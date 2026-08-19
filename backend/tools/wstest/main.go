package main

import (
    "encoding/json"
    "fmt"
    "log"
    "net/url"
    "os"
    "time"

    "github.com/gorilla/websocket"
)

func main() {
    if len(os.Args) < 2 {
        log.Fatal("usage: go run ./tools/wstest <jwt_token>")
    }
    token := os.Args[1]
    roomID := "test-room"

    u := url.URL{
        Scheme:   "ws",
        Host:     "localhost:8080",
        Path:     "/ws/signaling",
        RawQuery: fmt.Sprintf("token=%s&room_id=%s", token, roomID),
    }

    clientA, _, err := websocket.DefaultDialer.Dial(u.String(), nil)
    if err != nil {
        log.Fatalf("client A failed to connect: %v", err)
    }
    defer clientA.Close()
    fmt.Println("Client A connected")

    clientB, _, err := websocket.DefaultDialer.Dial(u.String(), nil)
    if err != nil {
        log.Fatalf("client B failed to connect: %v", err)
    }
    defer clientB.Close()
    fmt.Println("Client B connected")

    time.Sleep(500 * time.Millisecond)

    received := make(chan string, 1)
    go func() {
        _, msg, err := clientB.ReadMessage()
        if err != nil {
            log.Printf("client B read error: %v", err)
            return
        }
        received <- string(msg)
    }()

    offer := map[string]string{"type": "offer", "sdp": "v=0 test-sdp-payload"}
    payload, _ := json.Marshal(offer)

    if err := clientA.WriteMessage(websocket.TextMessage, payload); err != nil {
        log.Fatalf("client A failed to send: %v", err)
    }
    fmt.Println("Client A sent offer")

    select {
    case msg := <-received:
        fmt.Println("Client B received:", msg)
        fmt.Println("PASS: signaling relay works correctly")
    case <-time.After(5 * time.Second):
        fmt.Println("FAIL: client B did not receive the message within 5 seconds")
        os.Exit(1)
    }
}
