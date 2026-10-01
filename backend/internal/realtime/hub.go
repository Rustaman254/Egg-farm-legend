// Package realtime is the Battle Arena's websocket push channel: a thin per-wallet connection
// registry so the backend can tell a specific player "someone wants to fight you" or "your
// challenge was just accepted" the moment it happens, instead of them finding out on the next
// poll (today's arena presence/open-challenges lists stay on their existing short-interval poll --
// this only replaces the "did anyone target *me*" and "did my challenge resolve" checks).
package realtime

import (
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	// The arena page is served across an ngrok tunnel while the API stays on localhost (see
	// api.go's Private-Network-Access middleware for the same tradeoff on plain HTTP requests) --
	// CORS's Origin allowlist doesn't apply to websocket upgrades at all, so this is the one place
	// that decides it, and it mirrors the REST API's own wide-open cors.Handler policy.
	CheckOrigin: func(r *http.Request) bool { return true },
}

// conn wraps one websocket connection with its own write mutex -- gorilla/websocket requires all
// writes to a given connection to be serialized, and a hub may want to push to the same
// connection from multiple goroutines (e.g. two different challenge events landing at once).
type conn struct {
	ws *websocket.Conn
	mu sync.Mutex
}

func (c *conn) writeJSON(v any) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	_ = c.ws.SetWriteDeadline(time.Now().Add(10 * time.Second))
	return c.ws.WriteJSON(v)
}

type Hub struct {
	mu    sync.RWMutex
	conns map[string]map[*conn]struct{} // lowercased wallet -> live connections (a wallet may have several tabs open)
}

func NewHub() *Hub {
	return &Hub{conns: make(map[string]map[*conn]struct{})}
}

// Event is the envelope every push over the socket uses; Payload is arbitrary event-specific JSON.
type Event struct {
	Type    string `json:"type"`
	Payload any    `json:"payload"`
}

// Notify pushes an event to every live connection for a wallet. A no-op if that wallet isn't
// currently connected (the REST endpoints remain the source of truth -- this is a convenience
// nudge, not a delivery guarantee, so callers must not depend on it for correctness).
func (h *Hub) Notify(wallet string, eventType string, payload any) {
	wallet = strings.ToLower(wallet)
	h.mu.RLock()
	conns := make([]*conn, 0, len(h.conns[wallet]))
	for c := range h.conns[wallet] {
		conns = append(conns, c)
	}
	h.mu.RUnlock()

	for _, c := range conns {
		if err := c.writeJSON(Event{Type: eventType, Payload: payload}); err != nil {
			slog.Warn("arena websocket push failed", "wallet", wallet, "type", eventType, "error", err)
		}
	}
}

// Broadcast pushes an event to every live connection across every wallet -- for events that
// matter to anyone browsing right now regardless of whose wallet triggered them (e.g. a
// marketplace listing/sale changing what's for sale for every viewer).
func (h *Hub) Broadcast(eventType string, payload any) {
	h.mu.RLock()
	conns := make([]*conn, 0)
	for _, wallet := range h.conns {
		for c := range wallet {
			conns = append(conns, c)
		}
	}
	h.mu.RUnlock()

	for _, c := range conns {
		if err := c.writeJSON(Event{Type: eventType, Payload: payload}); err != nil {
			slog.Warn("websocket broadcast failed", "type", eventType, "error", err)
		}
	}
}

// ConnectedWallets returns every wallet with at least one live connection right now (lowercased).
// Used by the Wallet Watcher service to only poll on-chain balance for players actually online,
// instead of every wallet that's ever played.
func (h *Hub) ConnectedWallets() []string {
	h.mu.RLock()
	defer h.mu.RUnlock()
	out := make([]string, 0, len(h.conns))
	for wallet := range h.conns {
		out = append(out, wallet)
	}
	return out
}

func (h *Hub) register(wallet string, c *conn) {
	wallet = strings.ToLower(wallet)
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.conns[wallet] == nil {
		h.conns[wallet] = make(map[*conn]struct{})
	}
	h.conns[wallet][c] = struct{}{}
}

func (h *Hub) unregister(wallet string, c *conn) {
	wallet = strings.ToLower(wallet)
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.conns[wallet], c)
	if len(h.conns[wallet]) == 0 {
		delete(h.conns, wallet)
	}
}

// ServeWS upgrades the request and blocks (reading, and discarding, any client frames -- the
// client never needs to send anything but pings) until the connection closes. Call it from an
// http.HandlerFunc with the wallet already resolved from the URL.
func (h *Hub) ServeWS(w http.ResponseWriter, r *http.Request, wallet string) {
	ws, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		slog.Warn("arena websocket upgrade failed", "wallet", wallet, "error", err)
		return
	}
	c := &conn{ws: ws}
	h.register(wallet, c)
	defer func() {
		h.unregister(wallet, c)
		_ = ws.Close()
	}()

	ws.SetReadLimit(1024)
	_ = ws.SetReadDeadline(time.Now().Add(70 * time.Second))
	ws.SetPongHandler(func(string) error {
		_ = ws.SetReadDeadline(time.Now().Add(70 * time.Second))
		return nil
	})

	pingDone := make(chan struct{})
	go func() {
		ticker := time.NewTicker(30 * time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				c.mu.Lock()
				_ = ws.SetWriteDeadline(time.Now().Add(10 * time.Second))
				err := ws.WriteMessage(websocket.PingMessage, nil)
				c.mu.Unlock()
				if err != nil {
					return
				}
			case <-pingDone:
				return
			}
		}
	}()
	defer close(pingDone)

	for {
		if _, _, err := ws.ReadMessage(); err != nil {
			return
		}
	}
}
