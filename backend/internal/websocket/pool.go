package websocket

import (
	"log"
	"sync"
)

type Message struct {
	RoomID string
	Sender *Client
	Data   []byte
}

type Pool struct {
	mu         sync.RWMutex
	rooms      map[string]map[*Client]bool
	Register   chan *Client
	Unregister chan *Client
	Broadcast  chan *Message
}

func NewPool() *Pool {
	return &Pool{
		rooms:      make(map[string]map[*Client]bool),
		Register:   make(chan *Client),
		Unregister: make(chan *Client),
		Broadcast:  make(chan *Message),
	}
}

func (p *Pool) Run() {
	for {
		select {
		case client := <-p.Register:
			p.mu.Lock()
			if p.rooms[client.RoomID] == nil {
				p.rooms[client.RoomID] = make(map[*Client]bool)
			}
			p.rooms[client.RoomID][client] = true
			size := len(p.rooms[client.RoomID])
			p.mu.Unlock()
			log.Printf("client %s joined room %s (participants: %d)", client.UserID, client.RoomID, size)

		case client := <-p.Unregister:
			p.removeClient(client)
			log.Printf("client %s left room %s", client.UserID, client.RoomID)

		case message := <-p.Broadcast:
			p.mu.RLock()
			clients := p.rooms[message.RoomID]
			recipients := make([]*Client, 0, len(clients))
			for c := range clients {
				if c != message.Sender {
					recipients = append(recipients, c)
				}
			}
			p.mu.RUnlock()

			for _, c := range recipients {
				select {
				case c.Send <- message.Data:
				default:
					p.removeClient(c)
				}
			}
		}
	}
}

func (p *Pool) removeClient(c *Client) {
	p.mu.Lock()
	defer p.mu.Unlock()

	clients, ok := p.rooms[c.RoomID]
	if !ok {
		return
	}
	if _, exists := clients[c]; exists {
		delete(clients, c)
		close(c.Send)
	}
	if len(clients) == 0 {
		delete(p.rooms, c.RoomID)
	}
}

func (p *Pool) RoomSize(roomID string) int {
	p.mu.RLock()
	defer p.mu.RUnlock()
	return len(p.rooms[roomID])
}