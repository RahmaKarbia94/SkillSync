package ai

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"time"
)

type WhisperClient struct {
	apiKey     string
	httpClient *http.Client
	baseURL    string
}

func NewWhisperClient() (*WhisperClient, error) {
	apiKey := os.Getenv("GROQ_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("GROQ_API_KEY environment variable is required")
	}

	return &WhisperClient{
		apiKey:     apiKey,
		httpClient: &http.Client{Timeout: 5 * time.Minute},
		baseURL:    "https://api.groq.com/openai/v1/audio/transcriptions",
	}, nil
}

func (w *WhisperClient) TranscribeAudio(ctx context.Context, audio io.Reader, filename string) (string, error) {
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)

	part, err := writer.CreateFormFile("file", filename)
	if err != nil {
		return "", fmt.Errorf("create form file: %w", err)
	}
	if _, err := io.Copy(part, audio); err != nil {
		return "", fmt.Errorf("copy audio data: %w", err)
	}

	if err := writer.WriteField("model", "whisper-large-v3-turbo"); err != nil {
		return "", fmt.Errorf("write model field: %w", err)
	}
	if err := writer.WriteField("response_format", "json"); err != nil {
		return "", fmt.Errorf("write response_format field: %w", err)
	}

	if err := writer.Close(); err != nil {
		return "", fmt.Errorf("close multipart writer: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, w.baseURL, body)
	if err != nil {
		return "", fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+w.apiKey)
	req.Header.Set("Content-Type", writer.FormDataContentType())

	resp, err := w.httpClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("whisper api request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("read response body: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("whisper api error (status %d): %s", resp.StatusCode, string(respBody))
	}

	var result struct {
		Text string `json:"text"`
	}
	if err := json.Unmarshal(respBody, &result); err != nil {
		return "", fmt.Errorf("parse whisper response: %w", err)
	}

	return result.Text, nil
}