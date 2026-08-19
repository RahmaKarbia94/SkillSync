package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"

	"articulate-go/internal/ai"
	"articulate-go/internal/db"
	"articulate-go/internal/routes"
	"articulate-go/internal/services"
	"articulate-go/internal/storage"
	"articulate-go/internal/worker"
	ws "articulate-go/internal/websocket"
)

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	mongoURI := getEnv("MONGO_URI", "mongodb://localhost:27017")
	dbName := getEnv("MONGO_DB_NAME", "softskills_platform")
	port := getEnv("APP_PORT", "8080")
	appEnv := getEnv("APP_ENV", "development")

	client, err := db.Connect(ctx, mongoURI)
	if err != nil {
		log.Fatalf("failed to connect to mongodb: %v", err)
	}
	defer func() {
		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer shutdownCancel()
		if err := client.Disconnect(shutdownCtx); err != nil {
			log.Printf("error disconnecting mongodb client: %v", err)
		}
	}()

	database := client.Database(dbName)

	if err := db.EnsureIndexes(ctx, database); err != nil {
		log.Fatalf("failed to provision indexes: %v", err)
	}

	s3Client, err := storage.NewS3Client(ctx)
	if err != nil {
		log.Fatalf("failed to initialize s3 client: %v", err)
	}

	whisperClient, err := ai.NewWhisperClient()
	if err != nil {
		log.Fatalf("failed to initialize whisper client: %v", err)
	}

	llmClient, err := ai.NewLLMClient()
	if err != nil {
		log.Fatalf("failed to initialize llm client: %v", err)
	}

	notificationHub := ws.NewNotificationHub()
	go notificationHub.Run()

	transcriptionService := services.NewTranscriptionService(s3Client, whisperClient, database)
	evaluationService := services.NewEvaluationService(llmClient, database, notificationHub)

	workerCount := getEnvInt("WORKER_POOL_SIZE", 4)
	queueSize := getEnvInt("WORKER_QUEUE_SIZE", 100)
	dispatcher := worker.NewDispatcher(workerCount, queueSize, transcriptionService, evaluationService)

	if appEnv == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := routes.SetupRouter(client, database, notificationHub)

	srv := &http.Server{
		Addr:         ":" + port,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	go func() {
		log.Printf("server listening on :%s", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server error: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	log.Println("shutting down server...")
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("forced http server shutdown: %v", err)
	}

	log.Println("shutting down worker pool...")
	if err := dispatcher.Shutdown(20 * time.Second); err != nil {
		log.Printf("worker pool shutdown warning: %v", err)
	}

	log.Println("server exited cleanly")
}

func getEnv(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(v)
	if err != nil || parsed <= 0 {
		return fallback
	}
	return parsed
}