package models

import (
	"time"

	"go.mongodb.org/mongo-driver/bson/primitive"
)

type ProcessingStatus string

const (
	ProcessingStatusQueued     ProcessingStatus = "queued"
	ProcessingStatusProcessing ProcessingStatus = "processing"
	ProcessingStatusCompleted  ProcessingStatus = "completed"
	ProcessingStatusFailed     ProcessingStatus = "failed"
)

type FillerWordAnalysis struct {
	Count              int      `bson:"count" json:"count"`
	DensityPer100Words float64  `bson:"density_per_100_words" json:"density_per_100_words"`
	Examples           []string `bson:"examples,omitempty" json:"examples,omitempty"`
}

type LogicPacingAnalysis struct {
	Score        float64  `bson:"score" json:"score"`
	Assessment   string   `bson:"assessment" json:"assessment"`
	PacingIssues []string `bson:"pacing_issues,omitempty" json:"pacing_issues,omitempty"`
}

type SentimentAnalysis struct {
	Overall       string  `bson:"overall" json:"overall"`
	Confidence    float64 `bson:"confidence" json:"confidence"`
	EmotionalTone string  `bson:"emotional_tone" json:"emotional_tone"`
}

type Evaluation struct {
	ID                 primitive.ObjectID  `bson:"_id,omitempty" json:"id,omitempty"`
	SessionID          primitive.ObjectID  `bson:"session_id" json:"-"`
	CandidateID        primitive.ObjectID  `bson:"candidate_id" json:"-"`
	ModelVersion       string              `bson:"model_version" json:"-"`
	FillerWords        FillerWordAnalysis  `bson:"filler_words" json:"filler_words"`
	LogicPacing        LogicPacingAnalysis `bson:"logic_pacing" json:"logic_pacing"`
	Sentiment          SentimentAnalysis   `bson:"sentiment" json:"sentiment"`
	OverallScore       float64             `bson:"overall_score" json:"overall_score"`
	Summary            string              `bson:"summary" json:"summary"`
	Flags              []string            `bson:"flags,omitempty" json:"flags,omitempty"`
	ProcessingStatus   ProcessingStatus    `bson:"processing_status" json:"-"`
	ProcessingErrorMsg string              `bson:"processing_error_msg,omitempty" json:"-"`
	EvaluatedAt        *time.Time          `bson:"evaluated_at,omitempty" json:"-"`
	CreatedAt          time.Time           `bson:"created_at" json:"-"`
	UpdatedAt          time.Time           `bson:"updated_at" json:"-"`
}