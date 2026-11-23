// Command hello is the golden-k8 sample service.
//
// Configuration (environment):
//
//	PORT              listen port (default 8080)
//	LOG_LEVEL         debug | info | warn | error (default info)
//	SHUTDOWN_DELAY    time to report not-ready before closing the listener,
//	                  so endpoints drop the pod first (default 5s)
//	SHUTDOWN_TIMEOUT  time allowed for in-flight requests (default 10s)
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"runtime/debug"
	"strconv"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"

	"golden-k8/app/internal/server"
)

// Set at build time: -ldflags "-X main.version=... -X main.revision=...".
var (
	version  = "dev"
	revision = ""
)

type config struct {
	port            int
	logLevel        slog.Level
	shutdownDelay   time.Duration
	shutdownTimeout time.Duration
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	err := run(ctx, os.Getenv, os.Stdout, nil)
	stop()
	if err != nil {
		fmt.Fprintln(os.Stderr, "hello:", err)
		os.Exit(1)
	}
}

// run serves until ctx is cancelled, then shuts down gracefully. When ready
// is not nil, the bound address is sent on it once the listener is open.
func run(ctx context.Context, getenv func(string) string, stdout io.Writer, ready chan<- string) error {
	cfg, err := loadConfig(getenv)
	if err != nil {
		return err
	}
	log := slog.New(slog.NewJSONHandler(stdout, &slog.HandlerOptions{Level: cfg.logLevel}))

	hostname, _ := os.Hostname()
	build := buildInfo()
	srv := server.New(log, build, hostname, prometheus.NewRegistry())

	var lc net.ListenConfig
	ln, err := lc.Listen(ctx, "tcp", net.JoinHostPort("", strconv.Itoa(cfg.port)))
	if err != nil {
		return fmt.Errorf("listen: %w", err)
	}
	httpSrv := &http.Server{
		Handler:           srv.Handler(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() { errCh <- httpSrv.Serve(ln) }()
	log.Info("listening", slog.String("addr", ln.Addr().String()),
		slog.String("version", build.Version), slog.String("revision", build.Revision))
	if ready != nil {
		ready <- ln.Addr().String()
	}

	select {
	case err := <-errCh:
		return fmt.Errorf("serve: %w", err)
	case <-ctx.Done():
	}

	log.Info("shutting down", slog.Duration("delay", cfg.shutdownDelay))
	srv.SetReady(false)
	time.Sleep(cfg.shutdownDelay)

	shutdownCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), cfg.shutdownTimeout)
	defer cancel()
	if err := httpSrv.Shutdown(shutdownCtx); err != nil {
		return fmt.Errorf("shutdown: %w", err)
	}
	if err := <-errCh; !errors.Is(err, http.ErrServerClosed) {
		return fmt.Errorf("serve: %w", err)
	}
	log.Info("stopped")
	return nil
}

func loadConfig(getenv func(string) string) (config, error) {
	cfg := config{port: 8080, logLevel: slog.LevelInfo, shutdownDelay: 5 * time.Second, shutdownTimeout: 10 * time.Second}

	if v := getenv("PORT"); v != "" {
		p, err := strconv.Atoi(v)
		if err != nil || p < 1 || p > 65535 {
			return cfg, fmt.Errorf("PORT: invalid port %q", v)
		}
		cfg.port = p
	}
	if v := getenv("LOG_LEVEL"); v != "" {
		if err := cfg.logLevel.UnmarshalText([]byte(v)); err != nil {
			return cfg, fmt.Errorf("LOG_LEVEL: %w", err)
		}
	}
	for name, dst := range map[string]*time.Duration{
		"SHUTDOWN_DELAY":   &cfg.shutdownDelay,
		"SHUTDOWN_TIMEOUT": &cfg.shutdownTimeout,
	} {
		if v := getenv(name); v != "" {
			d, err := time.ParseDuration(v)
			if err != nil || d < 0 {
				return cfg, fmt.Errorf("%s: invalid duration %q", name, v)
			}
			*dst = d
		}
	}
	return cfg, nil
}

// buildInfo reports the ldflags version, falling back to the VCS revision
// Go embeds when building from a checkout.
func buildInfo() server.BuildInfo {
	b := server.BuildInfo{Version: version, Revision: revision, GoVersion: runtime.Version()}
	if b.Revision == "" {
		b.Revision = "unknown"
		if info, ok := debug.ReadBuildInfo(); ok {
			for _, s := range info.Settings {
				if s.Key == "vcs.revision" && len(s.Value) >= 12 {
					b.Revision = s.Value[:12]
				}
			}
		}
	}
	return b
}
