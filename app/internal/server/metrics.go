package server

import (
	"net/http"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// Metric names are part of the platform contract: the Grafana dashboard and
// the smoke tests query them.
const namespace = "hello"

type metrics struct {
	requests *prometheus.CounterVec
	duration *prometheus.HistogramVec
	inFlight prometheus.Gauge
}

func newMetrics(reg prometheus.Registerer, build BuildInfo) *metrics {
	f := promauto.With(reg)
	f.NewGauge(prometheus.GaugeOpts{
		Namespace:   namespace,
		Name:        "build_info",
		Help:        "Build information; always 1.",
		ConstLabels: prometheus.Labels{"version": build.Version, "revision": build.Revision, "goversion": build.GoVersion},
	}).Set(1)

	return &metrics{
		requests: f.NewCounterVec(prometheus.CounterOpts{
			Namespace: namespace,
			Name:      "http_requests_total",
			Help:      "HTTP requests by handler, method and status code.",
		}, []string{"handler", "method", "code"}),
		duration: f.NewHistogramVec(prometheus.HistogramOpts{
			Namespace: namespace,
			Name:      "http_request_duration_seconds",
			Help:      "HTTP request latency by handler and method.",
			Buckets:   []float64{.001, .0025, .005, .01, .025, .05, .1, .25, .5, 1},
		}, []string{"handler", "method"}),
		inFlight: f.NewGauge(prometheus.GaugeOpts{
			Namespace: namespace,
			Name:      "http_requests_in_flight",
			Help:      "HTTP requests currently being served.",
		}),
	}
}

// instrument wraps h with request count, latency and in-flight metrics,
// labelled with the given handler name.
// The GET/200 series start at zero, so rate() and increase() see the very first
// requests instead of a counter that appears already incremented.
func (m *metrics) instrument(handler string, h http.Handler) http.Handler {
	labels := prometheus.Labels{"handler": handler}
	m.requests.WithLabelValues(handler, "get", "200")
	m.duration.WithLabelValues(handler, "get")
	return promhttp.InstrumentHandlerInFlight(m.inFlight,
		promhttp.InstrumentHandlerDuration(m.duration.MustCurryWith(labels),
			promhttp.InstrumentHandlerCounter(m.requests.MustCurryWith(labels), h)))
}
