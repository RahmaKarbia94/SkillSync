package db

import (
	"context"
	"fmt"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

// EnsureIndexes provisions all required indexes across collections at startup.
func EnsureIndexes(ctx context.Context, database *mongo.Database) error {
	if err := ensureUserIndexes(ctx, database); err != nil {
		return fmt.Errorf("user indexes: %w", err)
	}
	if err := ensureSessionIndexes(ctx, database); err != nil {
		return fmt.Errorf("session indexes: %w", err)
	}
	if err := ensureEvaluationIndexes(ctx, database); err != nil {
		return fmt.Errorf("evaluation indexes: %w", err)
	}
	return nil
}

func ensureUserIndexes(ctx context.Context, database *mongo.Database) error {
	coll := database.Collection("users")
	models := []mongo.IndexModel{
		{
			Keys:    bson.D{{Key: "email", Value: 1}},
			Options: options.Index().SetUnique(true).SetName("uniq_email"),
		},
		{
			Keys:    bson.D{{Key: "role", Value: 1}},
			Options: options.Index().SetName("idx_role"),
		},
		{
			Keys:    bson.D{{Key: "created_at", Value: -1}},
			Options: options.Index().SetName("idx_created_at"),
		},
	}
	_, err := coll.Indexes().CreateMany(ctx, models)
	return err
}

func ensureSessionIndexes(ctx context.Context, database *mongo.Database) error {
	coll := database.Collection("sessions")
	models := []mongo.IndexModel{
		{
			Keys:    bson.D{{Key: "candidate_id", Value: 1}},
			Options: options.Index().SetName("idx_candidate_id"),
		},
		{
			Keys:    bson.D{{Key: "candidate_id", Value: 1}, {Key: "status", Value: 1}},
			Options: options.Index().SetName("idx_candidate_status"),
		},
		{
			Keys:    bson.D{{Key: "created_at", Value: -1}},
			Options: options.Index().SetName("idx_created_at"),
		},
		{
			Keys:    bson.D{{Key: "status", Value: 1}},
			Options: options.Index().SetName("idx_status"),
		},
	}
	_, err := coll.Indexes().CreateMany(ctx, models)
	return err
}

func ensureEvaluationIndexes(ctx context.Context, database *mongo.Database) error {
	coll := database.Collection("evaluations")
	models := []mongo.IndexModel{
		{
			Keys:    bson.D{{Key: "candidate_id", Value: 1}},
			Options: options.Index().SetName("idx_candidate_id"),
		},
		{
			Keys:    bson.D{{Key: "session_id", Value: 1}},
			Options: options.Index().SetUnique(true).SetName("uniq_session_id"),
		},
		{
			Keys:    bson.D{{Key: "created_at", Value: -1}},
			Options: options.Index().SetName("idx_created_at"),
		},
		{
			Keys:    bson.D{{Key: "processing_status", Value: 1}},
			Options: options.Index().SetName("idx_processing_status"),
		},
	}
	_, err := coll.Indexes().CreateMany(ctx, models)
	return err
}