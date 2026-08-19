package main

import (
    "context"
    "fmt"
    "log"
    "os"
    "time"

    "go.mongodb.org/mongo-driver/bson"
    "go.mongodb.org/mongo-driver/bson/primitive"

    "articulate-go/internal/ai"
    "articulate-go/internal/db"
    "articulate-go/internal/services"
)

func main() {
    ctx := context.Background()

    client, err := db.Connect(ctx, os.Getenv("MONGO_URI"))
    if err != nil {
        log.Fatalf("mongo connect failed: %v", err)
    }
    defer client.Disconnect(ctx)

    database := client.Database(os.Getenv("MONGO_DB_NAME"))
    sessions := database.Collection("sessions")

    testTranscript := "Um, so, like, I think the main challenge was, you know, communication between teams. We had to, um, basically restructure how we, like, shared updates daily."

    testSession := bson.M{
        "_id":          primitive.NewObjectID(),
        "candidate_id": primitive.NewObjectID(),
        "status":       "completed",
        "transcript":   testTranscript,
        "created_at":   time.Now().UTC(),
        "updated_at":   time.Now().UTC(),
    }

    result, err := sessions.InsertOne(ctx, testSession)
    if err != nil {
        log.Fatalf("failed to insert test session: %v", err)
    }
    sessionID := result.InsertedID.(primitive.ObjectID).Hex()
    fmt.Println("Created test session:", sessionID)

    llmClient, err := ai.NewLLMClient()
    if err != nil {
        log.Fatalf("failed to init llm client: %v", err)
    }
    fmt.Println("LLM client initialized")

    evaluationService := services.NewEvaluationService(llmClient, database)

    if err := evaluationService.ProcessEvaluation(ctx, sessionID); err != nil {
        log.Fatalf("evaluation failed: %v", err)
    }

    fmt.Println("PASS: evaluation pipeline confirmed")
}
