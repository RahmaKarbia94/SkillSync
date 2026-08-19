package webrtc

import (
	"fmt"
	"io"
	"log"
	"sync"

	"github.com/pion/webrtc/v3"
)

type PeerSession struct {
	SessionID      string
	UserID         string
	PeerConnection *webrtc.PeerConnection
}

type SFU struct {
	mu       sync.RWMutex
	peers    map[string]*PeerSession
	recorder *Recorder
}

func NewSFU(recorder *Recorder) *SFU {
	return &SFU{
		peers:    make(map[string]*PeerSession),
		recorder: recorder,
	}
}

func peerKey(sessionID, userID string) string {
	return sessionID + ":" + userID
}

func (s *SFU) CreatePeerConnection(sessionID, userID, offerSDP string, onConnected func()) (*webrtc.SessionDescription, error) {
	config := webrtc.Configuration{
		ICEServers: []webrtc.ICEServer{
			{URLs: []string{"stun:stun.l.google.com:19302"}},
		},
	}

	pc, err := webrtc.NewPeerConnection(config)
	if err != nil {
		return nil, fmt.Errorf("create peer connection: %w", err)
	}

	pc.OnTrack(func(track *webrtc.TrackRemote, receiver *webrtc.RTPReceiver) {
		go s.handleIncomingTrack(sessionID, userID, track)
	})

	pc.OnConnectionStateChange(func(state webrtc.PeerConnectionState) {
		log.Printf("session %s user %s connection state: %s", sessionID, userID, state.String())
		if state == webrtc.PeerConnectionStateConnected && onConnected != nil {
			onConnected()
		}
	})

	pc.OnICEConnectionStateChange(func(state webrtc.ICEConnectionState) {
		log.Printf("session %s user %s ice state: %s", sessionID, userID, state.String())
		switch state {
		case webrtc.ICEConnectionStateFailed, webrtc.ICEConnectionStateClosed, webrtc.ICEConnectionStateDisconnected:
			s.RemovePeer(sessionID, userID)
		}
	})

	offer := webrtc.SessionDescription{Type: webrtc.SDPTypeOffer, SDP: offerSDP}
	if err := pc.SetRemoteDescription(offer); err != nil {
		pc.Close()
		return nil, fmt.Errorf("set remote description: %w", err)
	}

	answer, err := pc.CreateAnswer(nil)
	if err != nil {
		pc.Close()
		return nil, fmt.Errorf("create answer: %w", err)
	}

	gatherComplete := webrtc.GatheringCompletePromise(pc)
	if err := pc.SetLocalDescription(answer); err != nil {
		pc.Close()
		return nil, fmt.Errorf("set local description: %w", err)
	}
	<-gatherComplete

	s.mu.Lock()
	s.peers[peerKey(sessionID, userID)] = &PeerSession{
		SessionID:      sessionID,
		UserID:         userID,
		PeerConnection: pc,
	}
	s.mu.Unlock()

	return pc.LocalDescription(), nil
}

func (s *SFU) AddICECandidate(sessionID, userID, candidate string, sdpMid *string, sdpMLineIndex *uint16) error {
	s.mu.RLock()
	peer, exists := s.peers[peerKey(sessionID, userID)]
	s.mu.RUnlock()

	if !exists {
		return fmt.Errorf("no active peer connection for session %s user %s", sessionID, userID)
	}

	return peer.PeerConnection.AddICECandidate(webrtc.ICECandidateInit{
		Candidate:     candidate,
		SDPMid:        sdpMid,
		SDPMLineIndex: sdpMLineIndex,
	})
}

func (s *SFU) handleIncomingTrack(sessionID, userID string, track *webrtc.TrackRemote) {
	writer, err := s.recorder.WriterFor(sessionID, userID, track.Kind())
	if err != nil {
		log.Printf("failed to create writer for session %s user %s: %v", sessionID, userID, err)
		return
	}

	for {
		packet, _, err := track.ReadRTP()
		if err != nil {
			if err != io.EOF {
				log.Printf("track read error (session %s user %s): %v", sessionID, userID, err)
			}
			break
		}

		if err := writer.WriteRTP(packet); err != nil {
			log.Printf("write rtp error (session %s user %s): %v", sessionID, userID, err)
			break
		}
	}

	s.recorder.CloseWriter(sessionID, userID, track.Kind())
}

func (s *SFU) RemovePeer(sessionID, userID string) {
	key := peerKey(sessionID, userID)

	s.mu.Lock()
	peer, exists := s.peers[key]
	if exists {
		delete(s.peers, key)
	}
	s.mu.Unlock()

	if !exists {
		return
	}

	peer.PeerConnection.Close()
	s.recorder.FinalizeSession(sessionID, userID)
}