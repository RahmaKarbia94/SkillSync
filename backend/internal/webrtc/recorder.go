package webrtc

import (
    "context"
    "fmt"
    "log"
    "os"
    "path/filepath"
    "sync"
    "time"

    "github.com/pion/rtp"
    "github.com/pion/webrtc/v3"
    "github.com/pion/webrtc/v3/pkg/media/ivfwriter"
    "github.com/pion/webrtc/v3/pkg/media/oggwriter"
    "go.mongodb.org/mongo-driver/bson"
    "go.mongodb.org/mongo-driver/bson/primitive"
    "go.mongodb.org/mongo-driver/mongo"

    "articulate-go/internal/models"
    "articulate-go/internal/storage"
)

type TrackWriter interface {
    WriteRTP(packet *rtp.Packet) error
    Close() error
}

type trackWriterEntry struct {
    writer   TrackWriter
    filePath string
}

type Recorder struct {
    mu       sync.Mutex
    writers  map[string]*trackWriterEntry
    tempDir  string
    s3Client *storage.S3Client
    sessions *mongo.Collection

    // OnAudioUploaded, if set, is invoked once a session's audio track has
    // been uploaded to storage and the session document updated — used to
    // automatically kick off transcription for the recording.
    OnAudioUploaded func(sessionID, s3Key string)
}

func NewRecorder(s3Client *storage.S3Client, database *mongo.Database, tempDir string) *Recorder {
    return &Recorder{
        writers:  make(map[string]*trackWriterEntry),
        tempDir:  tempDir,
        s3Client: s3Client,
        sessions: database.Collection("sessions"),
    }
}

func recordingKey(sessionID, userID string, kind webrtc.RTPCodecType) string {
    return fmt.Sprintf("%s:%s:%s", sessionID, userID, kind.String())
}

func mediaKindLabel(kind webrtc.RTPCodecType) string {
    if kind == webrtc.RTPCodecTypeAudio {
        return "audio"
    }
    return "video"
}

func (r *Recorder) WriterFor(sessionID, userID string, kind webrtc.RTPCodecType) (TrackWriter, error) {
    key := recordingKey(sessionID, userID, kind)

    r.mu.Lock()
    defer r.mu.Unlock()

    if entry, exists := r.writers[key]; exists {
        return entry.writer, nil
    }

    if err := os.MkdirAll(r.tempDir, 0o755); err != nil {
        return nil, fmt.Errorf("create temp dir: %w", err)
    }

    var writer TrackWriter
    var filePath string
    var err error

    switch kind {
    case webrtc.RTPCodecTypeVideo:
        filePath = filepath.Join(r.tempDir, fmt.Sprintf("%s_%s_video.ivf", sessionID, userID))
        writer, err = ivfwriter.New(filePath)
    case webrtc.RTPCodecTypeAudio:
        filePath = filepath.Join(r.tempDir, fmt.Sprintf("%s_%s_audio.ogg", sessionID, userID))
        writer, err = oggwriter.New(filePath, 48000, 2)
    default:
        return nil, fmt.Errorf("unsupported track kind: %s", kind.String())
    }

    if err != nil {
        return nil, fmt.Errorf("create media writer: %w", err)
    }

    r.writers[key] = &trackWriterEntry{writer: writer, filePath: filePath}

    return writer, nil
}

func (r *Recorder) CloseWriter(sessionID, userID string, kind webrtc.RTPCodecType) {
    key := recordingKey(sessionID, userID, kind)

    r.mu.Lock()
    entry, exists := r.writers[key]
    if exists {
        delete(r.writers, key)
    }
    r.mu.Unlock()

    if !exists {
        return
    }

    if err := entry.writer.Close(); err != nil {
        log.Printf("error closing writer for %s: %v", key, err)
    }
}

func (r *Recorder) FinalizeSession(sessionID, userID string) {
    for _, kind := range []webrtc.RTPCodecType{webrtc.RTPCodecTypeVideo, webrtc.RTPCodecTypeAudio} {
        r.CloseWriter(sessionID, userID, kind)
    }

    ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
    defer cancel()

    var assets []models.MediaAsset
    var audioObjectKey string

    for _, kind := range []webrtc.RTPCodecType{webrtc.RTPCodecTypeVideo, webrtc.RTPCodecTypeAudio} {
        label := mediaKindLabel(kind)
        ext := "ivf"
        mediaType := models.MediaTypeVideo
        contentType := "video/x-ivf"
        if kind == webrtc.RTPCodecTypeAudio {
            ext = "ogg"
            mediaType = models.MediaTypeAudio
            contentType = "audio/ogg"
        }

        filePath := filepath.Join(r.tempDir, fmt.Sprintf("%s_%s_%s.%s", sessionID, userID, label, ext))

        info, err := os.Stat(filePath)
        if err != nil {
            continue
        }

        file, err := os.Open(filePath)
        if err != nil {
            log.Printf("failed to open recorded file %s: %v", filePath, err)
            continue
        }

        objectKey := fmt.Sprintf("sessions/%s/%s_%s.%s", sessionID, userID, label, ext)

        _, uploadErr := r.s3Client.UploadFile(ctx, objectKey, file, contentType)
        file.Close()
        if uploadErr != nil {
            log.Printf("failed to upload %s to s3: %v", filePath, uploadErr)
            continue
        }

        if kind == webrtc.RTPCodecTypeAudio {
            audioObjectKey = objectKey
        }

        assets = append(assets, models.MediaAsset{
            Type:            mediaType,
            URL:             objectKey,
            StorageProvider: "s3",
            SizeBytes:       info.Size(),
            MimeType:        contentType,
            UploadedAt:      time.Now().UTC(),
        })

        _ = os.Remove(filePath)
    }

    if len(assets) == 0 {
        return
    }

    sessionObjectID, err := primitive.ObjectIDFromHex(sessionID)
    if err != nil {
        log.Printf("invalid session id %s: %v", sessionID, err)
        return
    }

    now := time.Now().UTC()
    update := bson.M{
        "$push": bson.M{"media_assets": bson.M{"$each": assets}},
        "$set": bson.M{
            "status":       models.SessionStatusCompleted,
            "completed_at": now,
            "updated_at":   now,
        },
    }

    if _, err := r.sessions.UpdateOne(ctx, bson.M{"_id": sessionObjectID}, update); err != nil {
        log.Printf("failed to update session %s with media assets: %v", sessionID, err)
        return
    }

    if audioObjectKey != "" && r.OnAudioUploaded != nil {
        go r.OnAudioUploaded(sessionID, audioObjectKey)
    }
}
