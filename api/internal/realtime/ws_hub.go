package realtime

import (
	"encoding/json"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true // Configurable origin check for extension/web
	},
}

type Client struct {
	Hub      *Hub
	Conn     *websocket.Conn
	UserID   string
	DeviceID string
	Send     chan []byte
}

type Message struct {
	Type      string      `json:"type"` // e.g. "PHASE_TRANSITION", "TAMPER_ALERT", "LOCKOUT_STATUS"
	UserID    string      `json:"user_id"`
	SessionID string      `json:"session_id,omitempty"`
	Payload   interface{} `json:"payload"`
	Timestamp int64       `json:"timestamp_epoch_ms"`
}

type Hub struct {
	mu         sync.RWMutex
	clients    map[*Client]bool
	userGroups map[string]map[*Client]bool
	broadcast  chan []byte
	register   chan *Client
	unregister chan *Client
}

func NewHub() *Hub {
	return &Hub{
		clients:    make(map[*Client]bool),
		userGroups: make(map[string]map[*Client]bool),
		broadcast:  make(chan []byte, 256),
		register:   make(chan *Client),
		unregister: make(chan *Client),
	}
}

func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			h.mu.Lock()
			h.clients[client] = true
			if h.userGroups[client.UserID] == nil {
				h.userGroups[client.UserID] = make(map[*Client]bool)
			}
			h.userGroups[client.UserID][client] = true
			h.mu.Unlock()

		case client := <-h.unregister:
			h.mu.Lock()
			if _, ok := h.clients[client]; ok {
				delete(h.clients, client)
				close(client.Send)
				if group, exists := h.userGroups[client.UserID]; exists {
					delete(group, client)
					if len(group) == 0 {
						delete(h.userGroups, client.UserID)
					}
				}
			}
			h.mu.Unlock()

		case message := <-h.broadcast:
			h.mu.RLock()
			for client := range h.clients {
				select {
				case client.Send <- message:
				default:
					close(client.Send)
					delete(h.clients, client)
				}
			}
			h.mu.RUnlock()
		}
	}
}

func (h *Hub) BroadcastToUser(userID string, msg Message) error {
	msg.Timestamp = time.Now().UnixMilli()
	data, err := json.Marshal(msg)
	if err != nil {
		return err
	}

	h.mu.RLock()
	defer h.mu.RUnlock()

	if group, exists := h.userGroups[userID]; exists {
		for client := range group {
			select {
			case client.Send <- data:
			default:
				// Buffer full
			}
		}
	}
	return nil
}

func (h *Hub) ServeWS(w http.ResponseWriter, r *http.Request, userID, deviceID string) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		return
	}

	client := &Client{
		Hub:      h,
		Conn:     conn,
		UserID:   userID,
		DeviceID: deviceID,
		Send:     make(chan []byte, 64),
	}

	h.register <- client

	go client.writePump()
	go client.readPump()
}

func (c *Client) readPump() {
	defer func() {
		c.Hub.unregister <- c
		c.Conn.Close()
	}()

	c.Conn.SetReadLimit(4096)
	c.Conn.SetReadDeadline(time.Now().Add(60 * time.Second))
	c.Conn.SetPongHandler(func(string) error {
		c.Conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})

	for {
		_, _, err := c.Conn.ReadMessage()
		if err != nil {
			break
		}
	}
}

func (c *Client) writePump() {
	ticker := time.NewTicker(30 * time.Second)
	defer func() {
		ticker.Stop()
		c.Conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.Send:
			c.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if !ok {
				c.Conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			w, err := c.Conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			w.Write(message)
			if err := w.Close(); err != nil {
				return
			}

		case <-ticker.C:
			c.Conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
			if err := c.Conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
