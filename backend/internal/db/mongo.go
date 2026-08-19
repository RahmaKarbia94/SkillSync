package db

import (
	"context"
	"fmt"
	"time"

	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"go.mongodb.org/mongo-driver/mongo/readpref"
)

const (
	defaultMaxPoolSize     = 100
	defaultMinPoolSize     = 10
	defaultMaxConnIdleTime = 5 * time.Minute
	defaultConnectTimeout  = 10 * time.Second
	defaultServerSelection = 10 * time.Second
)

// Connect establishes a pooled connection to MongoDB and verifies connectivity.
func Connect(ctx context.Context, uri string) (*mongo.Client, error) {
	clientOpts := options.Client().
		ApplyURI(uri).
		SetMaxPoolSize(defaultMaxPoolSize).
		SetMinPoolSize(defaultMinPoolSize).
		SetMaxConnIdleTime(defaultMaxConnIdleTime).
		SetConnectTimeout(defaultConnectTimeout).
		SetServerSelectionTimeout(defaultServerSelection).
		SetRetryWrites(true).
		SetRetryReads(true)

	connectCtx, cancel := context.WithTimeout(ctx, defaultConnectTimeout)
	defer cancel()

	client, err := mongo.Connect(connectCtx, clientOpts)
	if err != nil {
		return nil, fmt.Errorf("mongo connect: %w", err)
	}

	pingCtx, pingCancel := context.WithTimeout(ctx, defaultServerSelection)
	defer pingCancel()

	if err := client.Ping(pingCtx, readpref.Primary()); err != nil {
		return nil, fmt.Errorf("mongo ping: %w", err)
	}

	return client, nil
}