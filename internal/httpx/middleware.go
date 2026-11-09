package httpx

import (
	"log"
	"net/http"
	"time"
)

// Middleware is a function that wraps a handler in another handler.
// This one type is the whole idea behind logging, auth, rate limiting,
// CORS, and panic recovery in Go. You will use it constantly.
type Middleware func(http.Handler) http.Handler

// Chain applies middleware so that Chain(h, a, b) runs a, then b, then h.
func Chain(h http.Handler, mw ...Middleware) http.Handler {
	for i := len(mw) - 1; i >= 0; i-- {
		h = mw[i](h)
	}
	return h
}

// statusRecorder remembers the status code on its way past.
// http.ResponseWriter is an interface, so embedding it here means this type
// already has every method the real writer has; we only override the one we
// care about. That is Go's answer to inheritance.
type statusRecorder struct {
	http.ResponseWriter
	status int
	bytes  int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

func (r *statusRecorder) Write(b []byte) (int, error) {
	if r.status == 0 {
		r.status = http.StatusOK // Write without WriteHeader implies 200
	}
	n, err := r.ResponseWriter.Write(b)
	r.bytes += n
	return n, err
}

// Logger prints one line per request: method, path, status, size, duration.
func Logger(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w}

		next.ServeHTTP(rec, r)

		if rec.status == 0 {
			rec.status = http.StatusOK
		}
		log.Printf("%s %s -> %d (%d bytes) in %s",
			r.Method, r.URL.RequestURI(), rec.status, rec.bytes, time.Since(start).Round(time.Microsecond))
	})
}

// Recoverer turns a panic in any handler into a 500 instead of a dead server.
//
// Without this, one nil pointer dereference in one handler takes down the whole
// process and every other customer with it.
func Recoverer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				log.Printf("PANIC on %s %s: %v", r.Method, r.URL.Path, rec)
				WriteError(w, http.StatusInternalServerError, "something went wrong on our end", "")
			}
		}()
		next.ServeHTTP(w, r)
	})
}
