package server

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/testutil"
)

func newTestServer(t *testing.T) (*Server, *prometheus.Registry, *bytes.Buffer) {
	t.Helper()
	var logs bytes.Buffer
	reg := prometheus.NewRegistry()
	log := slog.New(slog.NewJSONHandler(&logs, &slog.HandlerOptions{Level: slog.LevelDebug}))
	s := New(log, BuildInfo{Version: "1.2.3", Revision: "abc123", GoVersion: "go1.27"}, "pod-1", reg)
	return s, reg, &logs
}

func get(t *testing.T, h http.Handler, method, path string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequestWithContext(t.Context(), method, path, nil))
	return rec
}

func TestEndpoints(t *testing.T) {
	s, _, _ := newTestServer(t)
	tests := []struct {
		method, path string
		code         int
		body         string
	}{
		{http.MethodGet, "/", http.StatusOK, `"message":"hello from golden-k8"`},
		{http.MethodGet, "/healthz", http.StatusOK, `"status":"ok"`},
		{http.MethodGet, "/readyz", http.StatusOK, `"status":"ready"`},
		{http.MethodGet, "/metrics", http.StatusOK, "hello_build_info"},
		{http.MethodGet, "/nope", http.StatusNotFound, ""},
		{http.MethodPost, "/", http.StatusMethodNotAllowed, ""},
	}
	for _, tt := range tests {
		t.Run(tt.method+" "+tt.path, func(t *testing.T) {
			rec := get(t, s.Handler(), tt.method, tt.path)
			if rec.Code != tt.code {
				t.Fatalf("status = %d, want %d", rec.Code, tt.code)
			}
			if !strings.Contains(rec.Body.String(), tt.body) {
				t.Fatalf("body %q does not contain %q", rec.Body.String(), tt.body)
			}
		})
	}
}

func TestHelloBody(t *testing.T) {
	s, _, _ := newTestServer(t)
	rec := get(t, s.Handler(), http.MethodGet, "/")

	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Fatalf("Content-Type = %q", ct)
	}
	var body struct {
		Pod   string    `json:"pod"`
		Build BuildInfo `json:"build"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if body.Pod != "pod-1" || body.Build.Version != "1.2.3" || body.Build.Revision != "abc123" {
		t.Fatalf("unexpected body: %+v", body)
	}
}

func TestReadinessFlips(t *testing.T) {
	s, _, _ := newTestServer(t)
	s.SetReady(false)
	if rec := get(t, s.Handler(), http.MethodGet, "/readyz"); rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("not ready: status = %d, want 503", rec.Code)
	}
	if rec := get(t, s.Handler(), http.MethodGet, "/healthz"); rec.Code != http.StatusOK {
		t.Fatalf("liveness must stay up during shutdown: status = %d", rec.Code)
	}
	s.SetReady(true)
	if rec := get(t, s.Handler(), http.MethodGet, "/readyz"); rec.Code != http.StatusOK {
		t.Fatalf("ready again: status = %d, want 200", rec.Code)
	}
}

func TestRequestMetrics(t *testing.T) {
	s, reg, _ := newTestServer(t)
	for range 3 {
		get(t, s.Handler(), http.MethodGet, "/")
	}
	get(t, s.Handler(), http.MethodGet, "/nope")

	want := `
# HELP hello_http_requests_total HTTP requests by handler, method and status code.
# TYPE hello_http_requests_total counter
hello_http_requests_total{code="200",handler="healthz",method="get"} 0
hello_http_requests_total{code="200",handler="hello",method="get"} 3
hello_http_requests_total{code="200",handler="other",method="get"} 0
hello_http_requests_total{code="200",handler="readyz",method="get"} 0
hello_http_requests_total{code="404",handler="other",method="get"} 1
`
	if err := testutil.GatherAndCompare(reg, strings.NewReader(want), "hello_http_requests_total"); err != nil {
		t.Fatal(err)
	}
	if n, err := testutil.GatherAndCount(reg, "hello_http_request_duration_seconds"); err != nil || n != 4 {
		t.Fatalf("duration series = %d (err %v), want 4 (one per handler)", n, err)
	}
}

func TestAccessLog(t *testing.T) {
	s, _, logs := newTestServer(t)
	get(t, s.Handler(), http.MethodGet, "/")
	get(t, s.Handler(), http.MethodGet, "/healthz")

	lines := strings.Split(strings.TrimSpace(logs.String()), "\n")
	if len(lines) != 2 {
		t.Fatalf("got %d log lines, want 2:\n%s", len(lines), logs.String())
	}
	var first, second map[string]any
	if err := json.Unmarshal([]byte(lines[0]), &first); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal([]byte(lines[1]), &second); err != nil {
		t.Fatal(err)
	}
	if first["level"] != "INFO" || first["path"] != "/" || first["status"] != float64(200) {
		t.Fatalf("hello log line: %v", first)
	}
	if second["level"] != "DEBUG" {
		t.Fatalf("probe requests should log at debug: %v", second)
	}
}

func TestMetricsEndpointServesRuntimeCollectors(t *testing.T) {
	s, _, _ := newTestServer(t)
	rec := get(t, s.Handler(), http.MethodGet, "/metrics")
	body, _ := io.ReadAll(rec.Body)
	for _, name := range []string{"go_goroutines", "process_resident_memory_bytes", "hello_build_info{"} {
		if !bytes.Contains(body, []byte(name)) {
			t.Errorf("/metrics is missing %s", name)
		}
	}
}
