package handlers

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"

	"articulate-go/internal/models"
	"articulate-go/internal/storage"
)

type MediaHandler struct {
	Sessions *mongo.Collection
	S3       *storage.S3Client
}

func NewMediaHandler(database *mongo.Database, s3Client *storage.S3Client) *MediaHandler {
	return &MediaHandler{
		Sessions: database.Collection("sessions"),
		S3:       s3Client,
	}
}

func (h *MediaHandler) GetPlaybackURL(c *gin.Context) {
	sessionID, err := primitive.ObjectIDFromHex(c.Param("session_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid session id"})
		return
	}

	mediaType := c.DefaultQuery("type", string(models.MediaTypeVideo))

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	var session models.Session
	if err := h.Sessions.FindOne(ctx, bson.M{"_id": sessionID}).Decode(&session); err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			c.JSON(http.StatusNotFound, gin.H{"error": "session not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch session"})
		return
	}

	var targetAsset *models.MediaAsset
	for i := range session.MediaAssets {
		if string(session.MediaAssets[i].Type) == mediaType {
			targetAsset = &session.MediaAssets[i]
			break
		}
	}

	if targetAsset == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "requested media asset not found for this session"})
		return
	}

	presignedURL, err := h.S3.PresignGetURL(ctx, targetAsset.URL, 15*time.Minute)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to generate playback url"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"playback_url":       presignedURL,
		"expires_in_seconds": 900,
	})
}

type updateSessionStatusRequest struct {
	Status string `json:"status" binding:"required"`
}

func (h *MediaHandler) UpdateSessionStatus(c *gin.Context) {
	sessionID, err := primitive.ObjectIDFromHex(c.Param("session_id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid session id"})
		return
	}

	var req updateSessionStatusRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	status := models.SessionStatus(req.Status)
	switch status {
	case models.SessionStatusPending, models.SessionStatusInProgress, models.SessionStatusCompleted, models.SessionStatusFailed, models.SessionStatusExpired:
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid status value"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	now := time.Now().UTC()
	setFields := bson.M{"status": status, "updated_at": now}
	if status == models.SessionStatusInProgress {
		setFields["started_at"] = now
	}
	if status == models.SessionStatusCompleted {
		setFields["completed_at"] = now
	}

	result, err := h.Sessions.UpdateOne(ctx, bson.M{"_id": sessionID}, bson.M{"$set": setFields})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to update session status"})
		return
	}
	if result.MatchedCount == 0 {
		c.JSON(http.StatusNotFound, gin.H{"error": "session not found"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "session status updated", "status": status})
}