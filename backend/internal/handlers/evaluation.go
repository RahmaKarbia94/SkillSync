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
	Users       *mongo.Collection
}

func NewEvaluationHandler(database *mongo.Database) *EvaluationHandler {
	return &EvaluationHandler{
		Sessions:    database.Collection("sessions"),
		Evaluations: database.Collection("evaluations"),
		Users:       database.Collection("users"),
	}
}

type EvaluationResponse struct {
	SessionID    string                     `json:"session_id"`
	Transcript   string                     `json:"transcript"`
	FillerWords  models.FillerWordAnalysis  `json:"filler_words"`
	LogicPacing  models.LogicPacingAnalysis `json:"logic_pacing"`
	Sentiment    models.SentimentAnalysis   `json:"sentiment"`
	OverallScore float64                    `json:"overall_score"`
	Summary      string                     `json:"summary"`
	Flags        []string                   `json:"flags"`
	EvaluatedAt  *time.Time                 `json:"evaluated_at,omitempty"`
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

// ExportReportResponse extends the base evaluation payload with candidate
// identity and assessment timing — fields only the export flow needs, kept
// out of GetBySessionID's response to avoid over-fetching on every results
// screen load.
type ExportReportResponse struct {
	SessionID      string                     `json:"session_id"`
	CandidateName  string                     `json:"candidate_name"`
	CandidateEmail string                     `json:"candidate_email"`
	AssessmentDate time.Time                  `json:"assessment_date"`
	Transcript     string                     `json:"transcript"`
	FillerWords    models.FillerWordAnalysis  `json:"filler_words"`
	LogicPacing    models.LogicPacingAnalysis `json:"logic_pacing"`
	Sentiment      models.SentimentAnalysis   `json:"sentiment"`
	OverallScore   float64                    `json:"overall_score"`
	Summary        string                     `json:"summary"`
	Flags          []string                   `json:"flags"`
	GeneratedAt    time.Time                  `json:"generated_at"`
}

// ExportEvaluationReport compiles session, candidate, and evaluation data
// into a single export-ready JSON payload consumed by the Flutter client's
// PDF report generator. Missing evaluation sub-scores are never treated as
// fatal here — this endpoint 404s only if the session or evaluation itself
// doesn't exist; the PDF layer is responsible for "N/A" fallback labels.
func (h *EvaluationHandler) ExportEvaluationReport(c *gin.Context) {
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

	candidateName := "Unknown Candidate"
	candidateEmail := ""
	var candidate models.User
	if err := h.Users.FindOne(ctx, bson.M{"_id": session.CandidateID}).Decode(&candidate); err == nil {
		candidateName = candidate.FullName
		candidateEmail = candidate.Email
	}

	assessmentDate := session.CreatedAt
	if session.CompletedAt != nil {
		assessmentDate = *session.CompletedAt
	}

	response := ExportReportResponse{
		SessionID:      sessionID.Hex(),
		CandidateName:  candidateName,
		CandidateEmail: candidateEmail,
		AssessmentDate: assessmentDate,
		Transcript:     session.Transcript,
		FillerWords:    evaluation.FillerWords,
		LogicPacing:    evaluation.LogicPacing,
		Sentiment:      evaluation.Sentiment,
		OverallScore:   evaluation.OverallScore,
		Summary:        evaluation.Summary,
		Flags:          evaluation.Flags,
		GeneratedAt:    time.Now().UTC(),
	}

	c.JSON(http.StatusOK, response)
}