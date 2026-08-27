package websocket

import (
	"encoding/json"
	"log"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

type NotificationType string

const (
	NotificationTypeEvaluationCompleted NotificationType = "evaluation_completed"
)

type Notification struct {
	Type      NotificationType `json:"type"`
	SessionID string           `json:"session_id,omitempty"`
	Message   string           `json:"message,omitempty"`
	Timestamp time.Time        `json:"timestamp"`
}

const (
	notifWriteWait  = 10 * time.Second
	notifPongWait   = 60 * time.Second
	notifPingPeriod = (notifPongWait * 9) / 10
	notifMaxMessage = 4096
)

type NotificationClient struct {
	Conn   *websocket.Conn
	Hub    *NotificationHub
	UserID string
	Send   chan []byte
}

func (c *NotificationClient) ReadPump() {
	defer func() {
		c.Hub.Unregister <- c
		c.Conn.Close()
	}()

	c.Conn.SetReadLimit(notifMaxMessage)
	c.Conn.SetReadDeadline(time.Now().Add(notifPongWait))
	c.Conn.SetPongHandler(func(string) error {
		c.Conn.SetReadDeadline(time.Now().Add(notifPongWait))
		return nil
	})

	for {
		// Notifications are server-to-client only. This loop exists purely
		// to detect disconnects and service ping/pong keepalive frames.
		if _, _, err := c.Conn.ReadMessage(); err != nil {
			break
		}
	}
}

func (c *NotificationClient) WritePump() {
	ticker := time.NewTicker(notifPingPeriod)
	defer func() {
		ticker.Stop()
		c.Conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.Send:
			c.Conn.SetWriteDeadline(time.Now().Add(notifWriteWait))
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
			c.Conn.SetWriteDeadline(time.Now().Add(notifWriteWait))
			if err := c.Conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

type NotificationHub struct {
	mu         sync.RWMutex
	clients    map[string]map[*NotificationClient]bool
	Register   chan *NotificationClient
	Unregister chan *NotificationClient
}

func NewNotificationHub() *NotificationHub {
	return &NotificationHub{
		clients:    make(map[string]map[*NotificationClient]bool),
		Register:   make(chan *NotificationClient),
		Unregister: make(chan *NotificationClient),
	}
}

func (h *NotificationHub) Run() {
	for {
		select {
		case client := <-h.Register:
			h.mu.Lock()
			if h.clients[client.UserID] == nil {
				h.clients[client.UserID] = make(map[*NotificationClient]bool)
			}
			h.clients[client.UserID][client] = true
			h.mu.Unlock()
			log.Printf("notification client connected: user %s", client.UserID)

		case client := <-h.Unregister:
			h.removeClient(client)
			log.Printf("notification client disconnected: user %s", client.UserID)
		}
	}
}

func (h *NotificationHub) removeClient(client *NotificationClient) {
	h.mu.Lock()
	defer h.mu.Unlock()

	clients, ok := h.clients[client.UserID]
	if !ok {
		return
	}
	if _, exists := clients[client]; exists {
		delete(clients, client)
		close(client.Send)
	}
	if len(clients) == 0 {
		delete(h.clients, client.UserID)
	}
}

// Notify delivers a notification to every active connection belonging to
// userID. Safe to call from any goroutine, including background workers.
func (h *NotificationHub) Notify(userID string, notification Notification) {
	payload, err := json.Marshal(notification)
	if err != nil {
		log.Printf("failed to marshal notification for user %s: %v", userID, err)
		return
	}

	h.mu.RLock()
	clients := h.clients[userID]
	recipients := make([]*NotificationClient, 0, len(clients))
	for c := range clients {
		recipients = append(recipients, c)
	}
	h.mu.RUnlock()
	log.Printf("notification hub: attempting delivery to user %s, %d active client(s)", userID, len(recipients))

	for _, c := range recipients {
		select {
		case c.Send <- payload:
		default:
			h.removeClient(c)
		}
	}
}
