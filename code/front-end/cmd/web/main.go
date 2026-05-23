package main

import (
	"embed"
	"fmt"
	"html/template"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"

	"github.com/prometheus/client_golang/prometheus/promhttp"
)

const brokerServiceURL = "http://broker-service.broker-service.svc.cluster.local"

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		render(w, "auth.page.gohtml")
	})

	http.Handle("/api/", apiProxyHandler())
	http.Handle("/api", apiProxyHandler())
	http.Handle("/metrics", promhttp.Handler())

	http.HandleFunc("/test", func(w http.ResponseWriter, r *http.Request) {
		render(w, "test.page.gohtml")
	})

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
