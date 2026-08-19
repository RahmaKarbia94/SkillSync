package main

import (
    "context"
    "fmt"
    "log"
    "os"

    "articulate-go/internal/ai"
    "articulate-go/internal/storage"
)

func main() {
    if len(os.Args) < 2 {
        log.Fatal("usage: go run ./tools/transcribetest <s3_key>")
    }
    key := os.Args[1]
    ctx := context.Background()

    s3Client, err := storage.NewS3Client(ctx)
    if err != nil {
        log.Fatalf("failed to init s3 client: %v", err)
    }
    fmt.Println("S3 client initialized")

    body, err := s3Client.DownloadObject(ctx, key)
    if err != nil {
        log.Fatalf("download failed: %v", err)
    }
    defer body.Close()
    fmt.Println("Downloaded audio from storage:", key)

    whisperClient, err := ai.NewWhisperClient()
    if err != nil {
        log.Fatalf("failed to init whisper client: %v", err)
    }
    fmt.Println("Whisper (Groq) client initialized")

    transcript, err := whisperClient.TranscribeAudio(ctx, body, key)
    if err != nil {
        log.Fatalf("transcription failed: %v", err)
    }

    fmt.Println("Transcript:", transcript)
    fmt.Println("PASS: transcription pipeline confirmed")
}
