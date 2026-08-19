package handlers

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"articulate-go/internal/middleware"
	"articulate-go/internal/models"
)

type SessionHandler struct {
	Sessions *mongo.Collection
}

func NewSessionHandler(database *mongo.Database) *SessionHandler {
	return &SessionHandler{Sessions: database.Collection("sessions")}
}

type startSessionResponse struct {
	SessionID string               `json:"session_id"`
	Status    models.SessionStatus `json:"status"`
	CreatedAt time.Time            `json:"created_at"`
}

func (h *SessionHandler) StartSession(c *gin.Context) {
	userIDHex := c.GetString(middleware.ContextUserID)
	candidateID, err := primitive.ObjectIDFromHex(userIDHex)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid user identity"})
		return
	}

	now := time.Now().UTC()
	session := models.Session{
		CandidateID: candidateID,
		Status:      models.SessionStatusPending,
		CreatedAt:   now,
		UpdatedAt:   now,
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	result, err := h.Sessions.InsertOne(ctx, session)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to create session"})
		return
	}

	sessionID := result.InsertedID.(primitive.ObjectID)

	c.JSON(http.StatusCreated, startSessionResponse{
		SessionID: sessionID.Hex(),
		Status:    session.Status,
		CreatedAt: session.CreatedAt,
	})
}

type sessionSummary struct {
	SessionID   string               `json:"session_id"`
	Status      models.SessionStatus `json:"status"`
	CreatedAt   time.Time            `json:"created_at"`
	CompletedAt *time.Time           `json:"completed_at,omitempty"`
	HasMedia    bool                 `json:"has_media"`
}

func (h *SessionHandler) ListByCandidate(c *gin.Context) {
	candidateID, err := primitive.ObjectIDFromHex(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid candidate id"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	findOptions := options.Find().SetSort(bson.D{{Key: "created_at", Value: -1}})

	cursor, err := h.Sessions.Find(ctx, bson.M{"candidate_id": candidateID}, findOptions)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch sessions"})
		return
	}
	defer cursor.Close(ctx)

	var sessions []models.Session
	if err := cursor.All(ctx, &sessions); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to decode sessions"})
		return
	}

	summaries := make([]sessionSummary, 0, len(sessions))
	for _, s := range sessions {
		summaries = append(summaries, sessionSummary{
			SessionID:   s.ID.Hex(),
			Status:      s.Status,
			CreatedAt:   s.CreatedAt,
			CompletedAt: s.CompletedAt,
			HasMedia:    len(s.MediaAssets) > 0,
		})
	}

	c.JSON(http.StatusOK, gin.H{"sessions": summaries})
}