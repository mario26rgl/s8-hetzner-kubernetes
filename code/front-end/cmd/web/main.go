package main

import (
	"embed"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

const brokerServiceURL = "http://broker-service.broker-service.svc.cluster.local"

var httpRequestDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
	Name:    "http_request_duration_seconds",
	Help:    "Duration of HTTP requests in seconds.",
	Buckets: prometheus.DefBuckets,
}, []string{"method", "status"})

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}

func observeDuration(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		recorder := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		started := time.Now()
		next.ServeHTTP(recorder, r)
		httpRequestDuration.WithLabelValues(r.Method, strconv.Itoa(recorder.status)).Observe(time.Since(started).Seconds())
	})
}

func main() {
	http.Handle("/", observeDuration(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		render(w, "auth.page.gohtml")
	})))

	http.Handle("/api/", observeDuration(apiProxyHandler()))
	http.Handle("/api", observeDuration(apiProxyHandler()))
	http.Handle("/metrics", promhttp.Handler())

	http.Handle("/test", observeDuration(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		render(w, "test.page.gohtml")
	})))

	fmt.Println("Starting front end service on port 80")
	err := http.ListenAndServe(":80", nil)
	if err != nil {
		log.Panic(err)
	}
}

func apiProxyHandler() http.Handler {
	targetURL, err := url.Parse(brokerServiceURL)
	if err != nil {
		panic(err)
	}

	proxy := httputil.NewSingleHostReverseProxy(targetURL)
	proxy.Director = func(request *http.Request) {
		originalHost := request.Host
		request.URL.Scheme = targetURL.Scheme
		request.URL.Host = targetURL.Host
		request.Host = targetURL.Host
		request.Header.Set("X-Forwarded-Host", originalHost)
		request.Header.Set("X-Forwarded-Proto", "http")
		request.URL.Path = strings.TrimPrefix(request.URL.Path, "/api")
		if request.URL.Path == "" {
			request.URL.Path = "/"
		}
	}

	return proxy
}

//go:embed templates
var templateFS embed.FS

func render(w http.ResponseWriter, t string) {

	partials := []string{
		"templates/base.layout.gohtml",
		"templates/header.partial.gohtml",
		"templates/footer.partial.gohtml",
	}

	var templateSlice []string
	templateSlice = append(templateSlice, fmt.Sprintf("templates/%s", t))

	for _, x := range partials {
		templateSlice = append(templateSlice, x)
	}

	tmpl, err := template.ParseFS(templateFS, templateSlice...)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	if err := tmpl.Execute(w, nil); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}
