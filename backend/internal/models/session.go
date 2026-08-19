package models

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

type SessionStatus string

const (
	SessionStatusPending    SessionStatus = "pending"
	SessionStatusInProgress SessionStatus = "in_progress"
	SessionStatusCompleted  SessionStatus = "completed"
	SessionStatusFailed     SessionStatus = "failed"
	SessionStatusExpired    SessionStatus = "expired"
)

type MediaType string

const (
	MediaTypeVideo MediaType = "video"
	MediaTypeAudio MediaType = "audio"
)

type MediaAsset struct {
	Type            MediaType `bson:"type" json:"type"`
	URL             string    `bson:"url" json:"url"`
	StorageProvider string    `bson:"storage_provider" json:"storage_provider"`
	SizeBytes       int64     `bson:"size_bytes" json:"size_bytes"`
	MimeType        string    `bson:"mime_type" json:"mime_type"`
	DurationSeconds float64   `bson:"duration_seconds" json:"duration_seconds"`
	Checksum        string    `bson:"checksum,omitempty" json:"checksum,omitempty"`
	UploadedAt      time.Time `bson:"uploaded_at" json:"uploaded_at"`
}

type Session struct {
	ID              primitive.ObjectID `bson:"_id,omitempty" json:"id"`
	CandidateID     primitive.ObjectID `bson:"candidate_id" json:"candidate_id"`
	AssessmentID    primitive.ObjectID `bson:"assessment_id,omitempty" json:"assessment_id,omitempty"`
	Status          SessionStatus      `bson:"status" json:"status"`
	MediaAssets     []MediaAsset       `bson:"media_assets,omitempty" json:"media_assets,omitempty"`
	QuestionCount   int                `bson:"question_count" json:"question_count"`
	Transcript      string             `bson:"transcript,omitempty" json:"transcript,omitempty"`
	TranscribedAt   *time.Time         `bson:"transcribed_at,omitempty" json:"transcribed_at,omitempty"`
	StartedAt       *time.Time         `bson:"started_at,omitempty" json:"started_at,omitempty"`
	CompletedAt     *time.Time         `bson:"completed_at,omitempty" json:"completed_at,omitempty"`
	DurationSeconds int64              `bson:"duration_seconds,omitempty" json:"duration_seconds,omitempty"`
	CreatedAt       time.Time          `bson:"created_at" json:"created_at"`
	UpdatedAt       time.Time          `bson:"updated_at" json:"updated_at"`
}