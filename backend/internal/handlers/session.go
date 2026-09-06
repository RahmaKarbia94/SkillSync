package handlers

import (
	"context"
	"fmt"
	"log"
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
	SessionID    string               `json:"session_id"`
	Status       models.SessionStatus `json:"status"`
	CreatedAt    time.Time            `json:"created_at"`
	CompletedAt  *time.Time           `json:"completed_at,omitempty"`
	HasMedia     bool                 `json:"has_media"`
	OverallScore *float64             `json:"overall_score,omitempty"`
}

// aggregatedSessionResult mirrors the shape produced by the $lookup pipeline
// in listWithEvaluations — a session document with its matching evaluation
// (if one exists yet) merged in as an optional nested field. The unique
// index on evaluations.session_id (Sprint 1) guarantees at most one match
// per session, so $unwind never fans a session out into duplicates.
type aggregatedSessionResult struct {
	ID          primitive.ObjectID   `bson:"_id"`
	Status      models.SessionStatus `bson:"status"`
	CreatedAt   time.Time            `bson:"created_at"`
	CompletedAt *time.Time           `bson:"completed_at,omitempty"`
	MediaAssets []models.MediaAsset  `bson:"media_assets,omitempty"`
	Evaluation  *struct {
		OverallScore float64 `bson:"overall_score"`
	} `bson:"evaluation,omitempty"`
}

func (h *SessionHandler) ListByCandidate(c *gin.Context) {
	candidateID, err := primitive.ObjectIDFromHex(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid candidate id"})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	summaries, err := h.listWithEvaluations(ctx, candidateID)
	if err != nil {
		log.Printf("evaluation-joined session list failed for candidate %s, falling back to base sessions: %v", candidateID.Hex(), err)

		summaries, err = h.listBaseSessions(ctx, candidateID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to fetch sessions"})
			return
		}
	}

	c.JSON(http.StatusOK, gin.H{"sessions": summaries})
}

// listWithEvaluations joins each session with its matching evaluation via
// $lookup on evaluations.session_id, so the dashboard can render a
// completed session's overall score in a single request.
func (h *SessionHandler) listWithEvaluations(ctx context.Context, candidateID primitive.ObjectID) ([]sessionSummary, error) {
	pipeline := mongo.Pipeline{
		{{Key: "$match", Value: bson.M{"candidate_id": candidateID}}},
		{{Key: "$sort", Value: bson.M{"created_at": -1}}},
		{{Key: "$lookup", Value: bson.M{
			"from":         "evaluations",
			"localField":   "_id",
			"foreignField": "session_id",
			"as":           "evaluation",
		}}},
		{{Key: "$unwind", Value: bson.M{
			"path":                       "$evaluation",
			"preserveNullAndEmptyArrays": true,
		}}},
		{{Key: "$project", Value: bson.M{
			"_id":                      1,
			"status":                   1,
			"created_at":               1,
			"completed_at":             1,
			"media_assets":             1,
			"evaluation.overall_score": 1,
		}}},
	}

	cursor, err := h.Sessions.Aggregate(ctx, pipeline)
	if err != nil {
		return nil, fmt.Errorf("aggregate sessions with evaluations: %w", err)
	}
	defer cursor.Close(ctx)

	var results []aggregatedSessionResult
	if err := cursor.All(ctx, &results); err != nil {
		return nil, fmt.Errorf("decode aggregated sessions: %w", err)
	}

	summaries := make([]sessionSummary, 0, len(results))
	for _, r := range results {
		summary := sessionSummary{
			SessionID:   r.ID.Hex(),
			Status:      r.Status,
			CreatedAt:   r.CreatedAt,
			CompletedAt: r.CompletedAt,
			HasMedia:    len(r.MediaAssets) > 0,
		}
		if r.Evaluation != nil {
			score := r.Evaluation.OverallScore
			summary.OverallScore = &score
		}
		summaries = append(summaries, summary)
	}

	return summaries, nil
}

// listBaseSessions is the fallback path used only if the $lookup
// aggregation itself errors — plain session data with no evaluation join,
// so the endpoint degrades gracefully instead of failing outright.
func (h *SessionHandler) listBaseSessions(ctx context.Context, candidateID primitive.ObjectID) ([]sessionSummary, error) {
	findOptions := options.Find().SetSort(bson.D{{Key: "created_at", Value: -1}})

	cursor, err := h.Sessions.Find(ctx, bson.M{"candidate_id": candidateID}, findOptions)
	if err != nil {
		return nil, fmt.Errorf("find sessions: %w", err)
	}
	defer cursor.Close(ctx)

	var sessions []models.Session
	if err := cursor.All(ctx, &sessions); err != nil {
		return nil, fmt.Errorf("decode sessions: %w", err)
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

	return summaries, nil
}