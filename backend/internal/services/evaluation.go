package services

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"

	"articulate-go/internal/ai"
	"articulate-go/internal/models"
	ws "articulate-go/internal/websocket"
)

type EvaluationService struct {
	llmClient       *ai.LLMClient
	sessions        *mongo.Collection
	evaluations     *mongo.Collection
	notificationHub *ws.NotificationHub
}

func NewEvaluationService(llmClient *ai.LLMClient, database *mongo.Database, notificationHub *ws.NotificationHub) *EvaluationService {
	return &EvaluationService{
		llmClient:       llmClient,
		sessions:        database.Collection("sessions"),
		evaluations:     database.Collection("evaluations"),
		notificationHub: notificationHub,
	}
}

func (s *EvaluationService) ProcessEvaluation(ctx context.Context, sessionID string) error {
	log.Printf("starting evaluation for session %s", sessionID)

	sessionObjectID, err := primitive.ObjectIDFromHex(sessionID)
	if err != nil {
		return fmt.Errorf("invalid session id %s: %w", sessionID, err)
	}

	var session models.Session
	if err := s.sessions.FindOne(ctx, bson.M{"_id": sessionObjectID}).Decode(&session); err != nil {
		return fmt.Errorf("fetch session %s: %w", sessionID, err)
	}

	if session.Transcript == "" {
		return fmt.Errorf("session %s has no transcript to evaluate", sessionID)
	}

	rawResult, err := s.llmClient.AnalyzeTranscript(ctx, session.Transcript)
	if err != nil {
		s.markFailed(sessionObjectID, session.CandidateID, err)
		return fmt.Errorf("analyze transcript: %w", err)
	}

	var evaluation models.Evaluation
	if err := json.Unmarshal(rawResult, &evaluation); err != nil {
		s.markFailed(sessionObjectID, session.CandidateID, err)
		return fmt.Errorf("unmarshal llm evaluation result: %w", err)
	}

	now := time.Now().UTC()
	evaluation.ID = primitive.NewObjectID()
	evaluation.SessionID = sessionObjectID
	evaluation.CandidateID = session.CandidateID
	evaluation.ModelVersion = "llama-3.3-70b-versatile"
	evaluation.ProcessingStatus = models.ProcessingStatusCompleted
	evaluation.EvaluatedAt = &now
	evaluation.CreatedAt = now
	evaluation.UpdatedAt = now

	insertCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	if _, err := s.evaluations.InsertOne(insertCtx, evaluation); err != nil {
		return fmt.Errorf("insert evaluation for session %s: %w", sessionID, err)
	}

	log.Printf("evaluation completed for session %s (overall score: %.1f)", sessionID, evaluation.OverallScore)

	if s.notificationHub != nil {
		s.notificationHub.Notify(session.CandidateID.Hex(), ws.Notification{
			Type:      ws.NotificationTypeEvaluationCompleted,
			SessionID: sessionID,
			Message:   "Your assessment evaluation is ready.",
			Timestamp: time.Now().UTC(),
		})
	}

	return nil
}

func (s *EvaluationService) markFailed(sessionID, candidateID primitive.ObjectID, cause error) {
	now := time.Now().UTC()
	failed := models.Evaluation{
		ID:                 primitive.NewObjectID(),
		SessionID:          sessionID,
		CandidateID:        candidateID,
		ModelVersion:       "llama-3.3-70b-versatile",
		ProcessingStatus:   models.ProcessingStatusFailed,
		ProcessingErrorMsg: cause.Error(),
		CreatedAt:          now,
		UpdatedAt:          now,
	}

	insertCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if _, err := s.evaluations.InsertOne(insertCtx, failed); err != nil {
		log.Printf("failed to record failed evaluation for session %s: %v", sessionID.Hex(), err)
	}
}