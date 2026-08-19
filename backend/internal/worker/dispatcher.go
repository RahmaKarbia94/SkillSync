package worker

import (
	"context"
	"log"
	"time"

	"articulate-go/internal/services"
)

type TranscriptionTask struct {
	SessionID  string
	S3Key      string
	Service    *services.TranscriptionService
	Dispatcher *Dispatcher
}

func (t *TranscriptionTask) Execute(ctx context.Context) {
	if err := t.Service.ProcessTranscription(ctx, t.SessionID, t.S3Key); err != nil {
		log.Printf("transcription task failed (session %s): %v", t.SessionID, err)
		return
	}

	if t.Dispatcher != nil {
		if err := t.Dispatcher.EnqueueEvaluationTask(t.SessionID); err != nil {
			log.Printf("failed to enqueue evaluation task for session %s: %v", t.SessionID, err)
		}
	}
}

type EvaluationTask struct {
	SessionID string
	Service   *services.EvaluationService
}

func (t *EvaluationTask) Execute(ctx context.Context) {
	if err := t.Service.ProcessEvaluation(ctx, t.SessionID); err != nil {
		log.Printf("evaluation task failed (session %s): %v", t.SessionID, err)
	}
}

type Dispatcher struct {
	pool                  *Pool
	transcriptionService  *services.TranscriptionService
	evaluationService     *services.EvaluationService
}

func NewDispatcher(workers, queueSize int, transcriptionService *services.TranscriptionService, evaluationService *services.EvaluationService) *Dispatcher {
	pool := NewPool(workers, queueSize)
	pool.Start()

	return &Dispatcher{
		pool:                  pool,
		transcriptionService:  transcriptionService,
		evaluationService:     evaluationService,
	}
}

func (d *Dispatcher) EnqueueTranscriptionTask(sessionID string, s3Key string) error {
	task := &TranscriptionTask{
		SessionID:  sessionID,
		S3Key:      s3Key,
		Service:    d.transcriptionService,
		Dispatcher: d,
	}
	return d.pool.Submit(task)
}

func (d *Dispatcher) EnqueueEvaluationTask(sessionID string) error {
	task := &EvaluationTask{
		SessionID: sessionID,
		Service:   d.evaluationService,
	}
	return d.pool.Submit(task)
}

func (d *Dispatcher) Shutdown(timeout time.Duration) error {
	return d.pool.Shutdown(timeout)
}