package handlers

import (
	"log"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"

	"articulate-go/internal/utils"
	ws "articulate-go/internal/websocket"
)

var notificationUpgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

type NotificationHandler struct {
	Hub *ws.NotificationHub
}

func NewNotificationHandler(hub *ws.NotificationHub) *NotificationHandler {
	return &NotificationHandler{Hub: hub}
}

func (h *NotificationHandler) HandleUpgrade(c *gin.Context) {
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

	conn, err := notificationUpgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		log.Printf("notification websocket upgrade failed for user %s: %v", claims.UserID, err)
		return
	}

	client := &ws.NotificationClient{
		Conn:   conn,
		Hub:    h.Hub,
		UserID: claims.UserID,
		Send:   make(chan []byte, 16),
	}

	h.Hub.Register <- client

	go client.WritePump()
	go client.ReadPump()
}
