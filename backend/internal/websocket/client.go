package websocket

import (
	"encoding/json"
	"log"
	"time"

	"github.com/gorilla/websocket"

	"articulate-go/internal/webrtc"
)

type SignalMessageType string

const (
	MessageTypeOffer        SignalMessageType = "offer"
	MessageTypeAnswer       SignalMessageType = "answer"
	MessageTypeICECandidate SignalMessageType = "ice-candidate"
	MessageTypeError        SignalMessageType = "error"
)

type ICECandidate struct {
	Candidate     string  `json:"candidate"`
	SDPMid        string  `json:"sdpMid,omitempty"`
	SDPMLineIndex *uint16 `json:"sdpMLineIndex,omitempty"`
}

type SignalMessage struct {
	Type      SignalMessageType `json:"type"`
	RoomID    string            `json:"room_id,omitempty"`
	SenderID  string            `json:"sender_id,omitempty"`
	SDP       string            `json:"sdp,omitempty"`
	Candidate *ICECandidate     `json:"candidate,omitempty"`
}

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = (pongWait * 9) / 10
	maxMessageSize = 65536
)

type Client struct {
	Conn        *websocket.Conn
	Pool        *Pool
	Manager     *webrtc.Manager
	RoomID      string
	UserID      string
	Role        string
	Send        chan []byte
	OnConnected func()
}

func (c *Client) ReadPump() {
	defer func() {
		c.Pool.Unregister <- c
		if c.Manager != nil {
			c.Manager.RemovePeer(c.RoomID, c.UserID)
		}
		c.Conn.Close()
	}()

	c.Conn.SetReadLimit(maxMessageSize)
	c.Conn.SetReadDeadline(time.Now().Add(pongWait))
	c.Conn.SetPongHandler(func(string) error {
		c.Conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, rawMessage, err := c.Conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("unexpected close for client %s: %v", c.UserID, err)
			}
			break
		}

		var msg SignalMessage
		if err := json.Unmarshal(rawMessage, &msg); err != nil {
			c.sendError("invalid message format")
			continue
		}

		switch msg.Type {
		case MessageTypeOffer:
			c.handleOffer(msg)

		case MessageTypeICECandidate:
			c.handleICECandidate(msg)

		case MessageTypeAnswer:
			continue

		default:
			c.sendError("unsupported message type")
		}
	}
}

func (c *Client) handleOffer(msg SignalMessage) {
	if c.Manager == nil {
		c.sendError("server not ready to accept offers")
		return
	}

	onConnected := c.OnConnected
	if onConnected == nil {
		onConnected = func() {}
	}

	answerSDP, err := c.Manager.HandleOffer(c.RoomID, c.UserID, msg.SDP, onConnected)
	if err != nil {
		log.Printf("failed to handle offer (session %s user %s): %v", c.RoomID, c.UserID, err)
		c.sendError("failed to negotiate connection")
		return
	}

	c.sendAnswer(answerSDP)
}

func (c *Client) handleICECandidate(msg SignalMessage) {
	if c.Manager == nil || msg.Candidate == nil {
		return
	}

	var sdpMid *string
	if msg.Candidate.SDPMid != "" {
		sdpMid = &msg.Candidate.SDPMid
	}

	if err := c.Manager.HandleICECandidate(c.RoomID, c.UserID, msg.Candidate.Candidate, sdpMid, msg.Candidate.SDPMLineIndex); err != nil {
		log.Printf("failed to add ice candidate (session %s user %s): %v", c.RoomID, c.UserID, err)
	}
}

func (c *Client) sendAnswer(sdp string) {
	payload, err := json.Marshal(SignalMessage{
		Type:     MessageTypeAnswer,
		RoomID:   c.RoomID,
		SenderID: c.UserID,
		SDP:      sdp,
	})
	if err != nil {
		return
	}
	select {
	case c.Send <- payload:
	default:
	}
}

func (c *Client) sendError(reason string) {
	payload, err := json.Marshal(SignalMessage{Type: MessageTypeError, SDP: reason})
	if err != nil {
		return
	}
	select {
	case c.Send <- payload:
	default:
	}
}

func (c *Client) WritePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.Conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.Send:
			c.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := c.Conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			if _, err := w.Write(message); err != nil {
				return
			}
			if err := w.Close(); err != nil {
				return
			}

		case <-ticker.C:
			c.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.Conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}