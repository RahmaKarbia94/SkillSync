package services

import (
	"context"
	"fmt"
	"log"
	"path/filepath"
	"time"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"

	"articulate-go/internal/ai"
	"articulate-go/internal/storage"
)

type TranscriptionService struct {
	s3Client      *storage.S3Client
	whisperClient *ai.WhisperClient
	sessions      *mongo.Collection
}

func NewTranscriptionService(s3Client *storage.S3Client, whisperClient *ai.WhisperClient, database *mongo.Database) *TranscriptionService {
	return &TranscriptionService{
		s3Client:      s3Client,
		whisperClient: whisperClient,
		sessions:      database.Collection("sessions"),
	}
}

func (s *TranscriptionService) ProcessTranscription(ctx context.Context, sessionID string, s3Key string) error {
	log.Printf("starting transcription for session %s (key: %s)", sessionID, s3Key)

	body, err := s.s3Client.DownloadObject(ctx, s3Key)
	if err != nil {
		return fmt.Errorf("download audio from s3: %w", err)
	}
	defer body.Close()

	transcript, err := s.whisperClient.TranscribeAudio(ctx, body, filepath.Base(s3Key))
	if err != nil {
		return fmt.Errorf("transcribe audio: %w", err)
	}

	sessionObjectID, err := primitive.ObjectIDFromHex(sessionID)
	if err != nil {
		return fmt.Errorf("invalid session id %s: %w", sessionID, err)
	}

	now := time.Now().UTC()
	update := bson.M{
		"$set": bson.M{
			"transcript":     transcript,
			"transcribed_at": now,
			"updated_at":     now,
		},
	}

	updateCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()

	result, err := s.sessions.UpdateOne(updateCtx, bson.M{"_id": sessionObjectID}, update)
	if err != nil {
		return fmt.Errorf("update session %s with transcript: %w", sessionID, err)
	}
	if result.MatchedCount == 0 {
		return fmt.Errorf("session %s not found", sessionID)
	}

	log.Printf("transcription completed for session %s (%d characters)", sessionID, len(transcript))
	return nil
}