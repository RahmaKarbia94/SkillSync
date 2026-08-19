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
)

type EvaluationHandler struct {
	Sessions    *mongo.Collection
	Evaluations *mongo.Collection
}

func NewEvaluationHandler(database *mongo.Database) *EvaluationHandler {
	return &EvaluationHandler{
		Sessions:    database.Collection("sessions"),
		Evaluations: database.Collection("evaluations"),
	}
}

type EvaluationResponse struct {
	SessionID    string                      `json:"session_id"`
	Transcript   string                      `json:"transcript"`
	FillerWords  models.FillerWordAnalysis   `json:"filler_words"`
	LogicPacing  models.LogicPacingAnalysis  `json:"logic_pacing"`
	Sentiment    models.SentimentAnalysis    `json:"sentiment"`
	OverallScore float64                     `json:"overall_score"`
	Summary      string                      `json:"summary"`
	Flags        []string                    `json:"flags"`
	EvaluatedAt  *time.Time                  `json:"evaluated_at,omitempty"`
}

func (h *EvaluationHandler) GetBySessionID(c *gin.Context) {
	sessionID, err := primitive.ObjectIDFromHex(c.Param("sessionId"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid session id"})
		return
	}

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

	var evaluation models.Evaluation
	if err := h.Evaluations.FindOne(ctx, bson.M{"session_id": sessionID}).Decode(&evaluation); err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			c.JSON(http.StatusNotFound, gin.H{"error": "evaluation not found for this session"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch evaluation"})
		return
	}

	response := EvaluationResponse{
		SessionID:    sessionID.Hex(),
		Transcript:   session.Transcript,
		FillerWords:  evaluation.FillerWords,
		LogicPacing:  evaluation.LogicPacing,
		Sentiment:    evaluation.Sentiment,
		OverallScore: evaluation.OverallScore,
		Summary:      evaluation.Summary,
		Flags:        evaluation.Flags,
		EvaluatedAt:  evaluation.EvaluatedAt,
	}

	c.JSON(http.StatusOK, response)
}