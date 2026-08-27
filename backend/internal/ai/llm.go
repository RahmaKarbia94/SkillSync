package ai

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"
)

const evaluationSystemPrompt = `You are an expert communication coach analyzing a job interview transcript for a soft-skills assessment platform.

Analyze the transcript and respond with ONLY a valid JSON object matching exactly this schema, with no additional text, markdown, or commentary:

{
  "filler_words": {
    "count": <integer, total number of filler words like "um", "uh", "like", "you know">,
    "density_per_100_words": <float, filler words per 100 words spoken>,
    "examples": [<up to 5 example filler phrases actually found in the transcript>]
  },
  "logic_pacing": {
    "score": <float 0-100, how clear and well-paced the reasoning was>,
    "assessment": <string, 1-2 sentence assessment of pacing and logical flow>,
    "pacing_issues": [<list of specific pacing or structure issues found, empty array if none>]
  },
  "sentiment": {
    "overall": <string, one of "positive", "neutral", "negative">,
    "confidence": <float 0-1, confidence in the sentiment classification>,
    "emotional_tone": <string, brief description of emotional tone, e.g. "confident and enthusiastic">
  },
  "overall_score": <float 0-100, holistic communication quality score>,
  "summary": <string, 2-3 sentence overall summary of the candidate's communication performance>,
  "flags": [<list of any concerning patterns, empty array if none>]
}

Respond with ONLY the JSON object. No preamble, no markdown code fences, no explanation.`

type LLMClient struct {
	apiKey     string
	httpClient *http.Client
	baseURL    string
	model      string
}

func NewLLMClient() (*LLMClient, error) {
	apiKey := os.Getenv("GROQ_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("GROQ_API_KEY environment variable is required")
	}

	model := os.Getenv("LLM_MODEL")
	if model == "" {
		model = "openai/gpt-oss-120b"
	}

	return &LLMClient{
		apiKey:     apiKey,
		httpClient: &http.Client{Timeout: 2 * time.Minute},
		baseURL:    "https://api.groq.com/openai/v1/chat/completions",
		model:      model,
	}, nil
}

type chatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type chatCompletionRequest struct {
	Model          string            `json:"model"`
	Messages       []chatMessage     `json:"messages"`
	ResponseFormat map[string]string `json:"response_format"`
	Temperature    float64           `json:"temperature"`
}

type chatCompletionResponse struct {
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
}

func (c *LLMClient) AnalyzeTranscript(ctx context.Context, transcript string) ([]byte, error) {
	reqBody := chatCompletionRequest{
		Model: c.model,
		Messages: []chatMessage{
			{Role: "system", Content: evaluationSystemPrompt},
			{Role: "user", Content: fmt.Sprintf("Transcript:\n\n%s", transcript)},
		},
		ResponseFormat: map[string]string{"type": "json_object"},
		Temperature:    0.2,
	}

	payload, err := json.Marshal(reqBody)
	if err != nil {
		return nil, fmt.Errorf("marshal request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL, bytes.NewReader(payload))
	if err != nil {
		return nil, fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+c.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("llm api request: %w", err)
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("read response body: %w", err)
	}

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("llm api error (status %d): %s", resp.StatusCode, string(respBody))
	}

	var completion chatCompletionResponse
	if err := json.Unmarshal(respBody, &completion); err != nil {
		return nil, fmt.Errorf("parse llm response: %w", err)
	}

	if len(completion.Choices) == 0 {
		return nil, fmt.Errorf("llm response contained no choices")
	}

	return []byte(completion.Choices[0].Message.Content), nil
}
