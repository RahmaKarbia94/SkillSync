package handlers

import (
	"log"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"

	"articulate-go/internal/utils"
	"articulate-go/internal/webrtc"
	ws "articulate-go/internal/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  4096,
	WriteBufferSize: 4096,
	CheckOrigin: func(r *http.Request) bool {
		// TODO: restrict to trusted frontend origins before production release
		return true
	},
}

type SignalingHandler struct {
	Pool    *ws.Pool
	Manager *webrtc.Manager
}

func NewSignalingHandler(pool *ws.Pool, manager *webrtc.Manager) *SignalingHandler {
	return &SignalingHandler{Pool: pool, Manager: manager}
}

func (h *SignalingHandler) HandleUpgrade(c *gin.Context) {
	token := c.Query("token")
	if token == "" {
		authHeader := c.GetHeader("Authorization")
		if strings.HasPrefix(authHeader, "Bearer ") {
			token = strings.TrimPrefix(authHeader, "Bearer ")
		}
	}

	if token == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing authentication token"})
		return
	}

	claims, err := utils.ParseToken(token)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
		return
	}

	roomID := c.Query("room_id")
	if roomID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "room_id is required"})
		return
	}

	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("websocket upgrade failed for user %s: %v", claims.UserID, err)
		return
	}

	userID := claims.UserID

	client := &ws.Client{
		Conn:    conn,
		Pool:    h.Pool,
		Manager: h.Manager,
		RoomID:  roomID,
		UserID:  userID,
		Role:    string(claims.Role),
		Send:    make(chan []byte, 256),
		OnConnected: func() {
			log.Printf("session %s user %s: peer connection established, recording sequence started", roomID, userID)
		},
	}

	h.Pool.Register <- client

	go client.WritePump()
	go client.ReadPump()
}