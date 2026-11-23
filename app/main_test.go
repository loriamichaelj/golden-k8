package main

import (
	"bytes"
	"context"
	"log/slog"
	"net/http"
	"strings"
	"testing"
	"time"
)

func env(kv map[string]string) func(string) string {
	return func(k string) string { return kv[k] }
}

func TestLoadConfig(t *testing.T) {
	cfg, err := loadConfig(env(nil))
	if err != nil {
		t.Fatal(err)
	}
	if cfg.port != 8080 || cfg.logLevel != slog.LevelInfo || cfg.shutdownDelay != 5*time.Second || cfg.shutdownTimeout != 10*time.Second {
		t.Fatalf("defaults: %+v", cfg)
	}

	cfg, err = loadConfig(env(map[string]string{"PORT": "9090", "LOG_LEVEL": "debug", "SHUTDOWN_DELAY": "0s", "SHUTDOWN_TIMEOUT": "2s"}))
	if err != nil {
		t.Fatal(err)
	}
	if cfg.port != 9090 || cfg.logLevel != slog.LevelDebug || cfg.shutdownDelay != 0 || cfg.shutdownTimeout != 2*time.Second {
		t.Fatalf("overrides: %+v", cfg)
	}

	for _, bad := range []map[string]string{
		{"PORT": "0"}, {"PORT": "http"}, {"LOG_LEVEL": "loud"}, {"SHUTDOWN_DELAY": "-1s"}, {"SHUTDOWN_TIMEOUT": "soon"},
	} {
		if _, err := loadConfig(env(bad)); err == nil {
			t.Errorf("%v: expected an error", bad)
		}
	}
}

// TestRunGracefulShutdown starts the real server, serves a request, cancels
// the context (as SIGTERM would) and expects readiness to drop before exit.
func TestRunGracefulShutdown(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())
	var logs bytes.Buffer
	ready := make(chan string, 1)
	done := make(chan error, 1)
	go func() {
		done <- run(ctx, env(map[string]string{"PORT": "18080", "SHUTDOWN_DELAY": "300ms"}), &logs, ready)
	}()

	var addr string
	select {
	case addr = <-ready:
	case err := <-done:
		t.Fatalf("run exited early: %v", err)
	case <-time.After(5 * time.Second):
		t.Fatal("server did not start")
	}
	url := "http://" + strings.Replace(addr, "[::]", "127.0.0.1", 1)

	if code := status(t, url+"/readyz"); code != http.StatusOK {
		t.Fatalf("readyz before shutdown = %d", code)
	}
	cancel()
	time.Sleep(100 * time.Millisecond)
	if code := status(t, url+"/readyz"); code != http.StatusServiceUnavailable {
		t.Fatalf("readyz during the shutdown delay = %d, want 503", code)
	}

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("run: %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("server did not stop")
	}
	if !strings.Contains(logs.String(), `"msg":"stopped"`) {
		t.Fatalf("missing stopped log line:\n%s", logs.String())
	}
}

func status(t *testing.T, url string) int {
	t.Helper()
	req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, url, nil)
	if err != nil {
		t.Fatal(err)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = resp.Body.Close() }()
	return resp.StatusCode
}
