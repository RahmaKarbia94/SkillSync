package storage

import (
	"context"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/s3/manager"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

type S3Client struct {
	client   *s3.Client
	uploader *manager.Uploader
	presign  *s3.PresignClient
	bucket   string
	region   string
}

func NewS3Client(ctx context.Context) (*S3Client, error) {
	bucket := os.Getenv("AWS_S3_BUCKET")
	if bucket == "" {
		return nil, fmt.Errorf("AWS_S3_BUCKET environment variable is required")
	}

	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "us-east-1"
	}

	endpoint := os.Getenv("AWS_S3_ENDPOINT")

	cfg, err := config.LoadDefaultConfig(ctx, config.WithRegion(region))
	if err != nil {
		return nil, fmt.Errorf("load aws config: %w", err)
	}

	client := s3.NewFromConfig(cfg, func(o *s3.Options) {
		if endpoint != "" {
			o.BaseEndpoint = aws.String(endpoint)
			o.UsePathStyle = true
		}
	})

	return &S3Client{
		client:   client,
		uploader: manager.NewUploader(client),
		presign:  s3.NewPresignClient(client),
		bucket:   bucket,
		region:   region,
	}, nil
}

func (s *S3Client) UploadFile(ctx context.Context, key string, body io.Reader, contentType string) (string, error) {
	result, err := s.uploader.Upload(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(s.bucket),
		Key:         aws.String(key),
		Body:        body,
		ContentType: aws.String(contentType),
	})
	if err != nil {
		return "", fmt.Errorf("upload object %s: %w", key, err)
	}
	return result.Location, nil
}

func (s *S3Client) DownloadObject(ctx context.Context, key string) (io.ReadCloser, error) {
	result, err := s.client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	})
	if err != nil {
		return nil, fmt.Errorf("download object %s: %w", key, err)
	}
	return result.Body, nil
}

func (s *S3Client) PresignGetURL(ctx context.Context, key string, expiry time.Duration) (string, error) {
	request, err := s.presign.PresignGetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(s.bucket),
		Key:    aws.String(key),
	}, s3.WithPresignExpires(expiry))
	if err != nil {
		return "", fmt.Errorf("presign object %s: %w", key, err)
	}
	return request.URL, nil
}

func (s *S3Client) PublicURL(key string) string {
	return fmt.Sprintf("https://%s.s3.%s.amazonaws.com/%s", s.bucket, s.region, key)
}