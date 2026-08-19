package webrtc

import "fmt"

type Manager struct {
	sfu *SFU
}

func NewManager(sfu *SFU) *Manager {
	return &Manager{sfu: sfu}
}

func (m *Manager) HandleOffer(sessionID, userID, offerSDP string, onConnected func()) (string, error) {
	answer, err := m.sfu.CreatePeerConnection(sessionID, userID, offerSDP, onConnected)
	if err != nil {
		return "", fmt.Errorf("create peer connection: %w", err)
	}
	return answer.SDP, nil
}

func (m *Manager) HandleICECandidate(sessionID, userID, candidate string, sdpMid *string, sdpMLineIndex *uint16) error {
	return m.sfu.AddICECandidate(sessionID, userID, candidate, sdpMid, sdpMLineIndex)
}

func (m *Manager) RemovePeer(sessionID, userID string) {
	m.sfu.RemovePeer(sessionID, userID)
}