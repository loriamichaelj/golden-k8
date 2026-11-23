// Package server implements the golden-k8 sample HTTP service: a hello
// endpoint, liveness and readiness probes, and Prometheus metrics.
package server

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"sync/atomic"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// BuildInfo identifies the running binary.
type BuildInfo struct {
	Version   string `json:"version"`
	Revision  string `json:"revision"`
	GoVersion string `json:"goVersion"`
}

// Server holds the handler and the readiness state.
type Server struct {
	handler  http.Handler
	ready    atomic.Bool
	log      *slog.Logger
	build    BuildInfo
	hostname string
}

// New builds the service. Metrics are registered on reg, which /metrics
// serves together with the Go runtime and process collectors.
func New(log *slog.Logger, build BuildInfo, hostname string, reg *prometheus.Registry) *Server {
	s := &Server{log: log, build: build, hostname: hostname}
	s.ready.Store(true)

	reg.MustRegister(
		collectors.NewGoCollector(),
		collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}),
	)
	m := newMetrics(reg, build)

	mux := http.NewServeMux()
	mux.Handle("GET /{$}", m.instrument("hello", http.HandlerFunc(s.hello)))
	mux.Handle("GET /healthz", m.instrument("healthz", http.HandlerFunc(s.healthz)))
	mux.Handle("GET /readyz", m.instrument("readyz", http.HandlerFunc(s.readyz)))
	mux.Handle("GET /metrics", promhttp.HandlerFor(reg, promhttp.HandlerOpts{Registry: reg}))

	// Unmatched requests (404/405 from the mux) are counted as handler="other".
	other := m.instrument("other", mux)
	s.handler = s.accessLog(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, pattern := mux.Handler(r); pattern == "" {
			other.ServeHTTP(w, r)
			return
		}
		mux.ServeHTTP(w, r)
	}))
	return s
}

// Handler returns the root HTTP handler.
func (s *Server) Handler() http.Handler { return s.handler }

// SetReady flips the readiness probe. It is set to false at shutdown so
// endpoints stop routing traffic before the listener closes.
func (s *Server) SetReady(ready bool) { s.ready.Store(ready) }

func (s *Server) hello(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"message": "hello from golden-k8",
		"pod":     s.hostname,
		"build":   s.build,
	})
}

func (s *Server) healthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) readyz(w http.ResponseWriter, _ *http.Request) {
	if !s.ready.Load() {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "shutting down"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

func writeJSON(w http.ResponseWriter, code int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(body)
}

// accessLog logs every request as JSON. Probe and metrics requests are
// logged at debug level so they don't drown the useful lines.
func (s *Server) accessLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)

		level := slog.LevelInfo
		switch r.URL.Path {
		case "/healthz", "/readyz", "/metrics":
			level = slog.LevelDebug
		}
		s.log.LogAttrs(r.Context(), level, "request",
			slog.String("method", r.Method),
			slog.String("path", r.URL.Path),
			slog.Int("status", rec.status),
			slog.Duration("duration", time.Since(start)),
			slog.String("remote", r.RemoteAddr),
		)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func (r *statusRecorder) Unwrap() http.ResponseWriter { return r.ResponseWriter }
