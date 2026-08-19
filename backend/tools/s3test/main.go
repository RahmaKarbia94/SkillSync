package main

import (
    "context"
    "fmt"
    "log"
    "strings"
    "time"

    "articulate-go/internal/storage"
)

func main() {
    ctx := context.Background()

    client, err := storage.NewS3Client(ctx)
    if err != nil {
        log.Fatalf("failed to init s3 client: %v", err)
    }
    fmt.Println("S3 client initialized")

    testContent := strings.NewReader("hello from articulate-go sprint 5 test")
    key := "test/connectivity-check.txt"

    _, err = client.UploadFile(ctx, key, testContent, "text/plain")
    if err != nil {
        log.Fatalf("upload failed: %v", err)
    }
    fmt.Println("Upload succeeded:", key)

    url, err := client.PresignGetURL(ctx, key, 5*time.Minute)
    if err != nil {
        log.Fatalf("presign failed: %v", err)
    }
    fmt.Println("Presigned URL:", url)
    fmt.Println("PASS: S3 connectivity confirmed")
}
