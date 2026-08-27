package routes

import (
    "context"
    "log"
    "net/http"
    "os"
    "time"

    "github.com/gin-gonic/gin"
    "go.mongodb.org/mongo-driver/mongo"

    "articulate-go/internal/handlers"
    "articulate-go/internal/middleware"
    "articulate-go/internal/models"
    "articulate-go/internal/storage"
    "articulate-go/internal/webrtc"
    "articulate-go/internal/worker"
    ws "articulate-go/internal/websocket"
)

func SetupRouter(client *mongo.Client, database *mongo.Database, notificationHub *ws.NotificationHub, dispatcher *worker.Dispatcher) *gin.Engine {
    router := gin.New()
    router.Use(gin.Logger(), gin.Recovery())

    router.GET("/healthz", func(c *gin.Context) {
        ctx, cancel := context.WithTimeout(c.Request.Context(), 2*time.Second)
        defer cancel()

        if err := client.Ping(ctx, nil); err != nil {
            c.JSON(http.StatusServiceUnavailable, gin.H{"status": "unhealthy"})
            return
        }
        c.JSON(http.StatusOK, gin.H{"status": "healthy"})
    })

    authHandler := handlers.NewAuthHandler(database)

    signalingPool := ws.NewPool()
    go signalingPool.Run()

    s3Client, err := storage.NewS3Client(context.Background())
    if err != nil {
        log.Fatalf("failed to initialize s3 client: %v", err)
    }

    recordingsTempDir := os.Getenv("RECORDINGS_TEMP_DIR")
    if recordingsTempDir == "" {
        recordingsTempDir = "/tmp/recordings"
    }

    recorder := webrtc.NewRecorder(s3Client, database, recordingsTempDir)
    recorder.OnAudioUploaded = func(sessionID, s3Key string) {
        if err := dispatcher.EnqueueTranscriptionTask(sessionID, s3Key); err != nil {
            log.Printf("failed to enqueue transcription for session %s: %v", sessionID, err)
        }
    }

    sfu := webrtc.NewSFU(recorder)
    webrtcManager := webrtc.NewManager(sfu)

    signalingHandler := handlers.NewSignalingHandler(signalingPool, webrtcManager)
    mediaHandler := handlers.NewMediaHandler(database, s3Client)
    evaluationHandler := handlers.NewEvaluationHandler(database)
    sessionHandler := handlers.NewSessionHandler(database)
    notificationHandler := handlers.NewNotificationHandler(notificationHub)

    v1 := router.Group("/api/v1")
    {
        auth := v1.Group("/auth")
        {
            auth.POST("/register", authHandler.Register)
            auth.POST("/login", authHandler.Login)
        }

        protected := v1.Group("/protected")
        protected.Use(middleware.AuthRequired())
        {
            protected.GET("/candidate", middleware.RequireRole(models.RoleCandidate), func(c *gin.Context) {
                c.JSON(http.StatusOK, gin.H{
                    "message": "candidate access granted",
                    "user_id": c.GetString(middleware.ContextUserID),
                })
            })

            protected.GET("/recruiter", middleware.RequireRole(models.RoleRecruiter), func(c *gin.Context) {
                c.JSON(http.StatusOK, gin.H{
                    "message": "recruiter access granted",
                    "user_id": c.GetString(middleware.ContextUserID),
                })
            })
        }

        media := v1.Group("/media")
        media.Use(middleware.AuthRequired())
        {
            media.GET("/sessions/:session_id/playback", mediaHandler.GetPlaybackURL)
            media.PATCH("/sessions/:session_id/status", mediaHandler.UpdateSessionStatus)
        }

        evaluations := v1.Group("/evaluations")
        evaluations.Use(middleware.AuthRequired())
        {
            evaluations.GET("/:sessionId", evaluationHandler.GetBySessionID)
        }

        sessions := v1.Group("/sessions")
        sessions.Use(middleware.AuthRequired())
        {
            sessions.POST("/start", sessionHandler.StartSession)
            sessions.GET("/candidate/:id", sessionHandler.ListByCandidate)
        }
    }

    router.GET("/ws/signaling", signalingHandler.HandleUpgrade)
    router.GET("/ws/notifications", notificationHandler.HandleUpgrade)

    return router
}
