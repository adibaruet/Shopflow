// Command server runs the ShopFlow store.
//
// Layout note: cmd/server/main.go is a Go convention. Everything under cmd/ is
// a runnable program, everything under internal/ is library code that only this
// module can import. Later you can add cmd/seed or cmd/migrate beside this one.
package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"shopflow/internal/catalog"
	"shopflow/internal/httpx"
)

func main() {
	addr := os.Getenv("SHOPFLOW_ADDR")
	if addr == "" {
		addr = ":8080"
	}

	// Build the store, fill it with sample products.
	// In Stage 3 these two lines become a Postgres connection and nothing
	// else in the program has to change.
	store := catalog.NewMemStore()
	if err := catalog.Seed(store); err != nil {
		log.Fatalf("seeding failed: %v", err)
	}

	// Mount the API, then the static site at the root.
	mux := http.NewServeMux()
	mux.Handle("/api/", catalog.Handler{Store: store}.Routes())
	mux.Handle("/", http.FileServer(http.Dir("web")))

	handler := httpx.Chain(mux, httpx.Recoverer, httpx.Logger)

	// Always configure timeouts. http.ListenAndServe uses none, which means a
	// single slow client can hold a connection open forever.
	srv := &http.Server{
		Addr:              addr,
		Handler:           handler,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	// Graceful shutdown: on Ctrl-C, stop accepting new requests but let the
	// ones already in flight finish. A customer mid-checkout should not have
	// the connection cut because you deployed.
	shutdownDone := make(chan struct{})
	go func() {
		sigint := make(chan os.Signal, 1)
		signal.Notify(sigint, os.Interrupt, syscall.SIGTERM)
		<-sigint // blocks this goroutine until a signal arrives

		log.Println("shutting down...")
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		if err := srv.Shutdown(ctx); err != nil {
			log.Printf("shutdown error: %v", err)
		}
		close(shutdownDone)
	}()

	log.Printf("ShopFlow listening on http://localhost%s", addr)

	// ListenAndServe blocks until the server stops. It returns ErrServerClosed
	// on a clean shutdown, which is not a failure.
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("server error: %v", err)
	}

	<-shutdownDone
	log.Println("goodbye")
}
