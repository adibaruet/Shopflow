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
	"shopflow/internal/lab"
)

// listenAddr decides where the server binds.
//  1. SHOPFLOW_ADDR wins if set (explicit override).
//  2. PORT is set by hosts like Railway; bind all interfaces on that port.
//  3. Otherwise localhost only, because the SQL Lab runs real SQL.
func listenAddr() string {
	if a := os.Getenv("SHOPFLOW_ADDR"); a != "" {
		return a
	}
	if p := os.Getenv("PORT"); p != "" {
		return ":" + p
	}
	return "127.0.0.1:8080"
}

func main() {
	addr := listenAddr()

	// Build the store, fill it with sample products.
	// In Stage 3 these two lines become a Postgres connection and nothing
	// else in the program has to change.
	store := catalog.NewMemStore()
	if err := catalog.Seed(store); err != nil {
		log.Fatalf("seeding failed: %v", err)
	}

	// Connect to Postgres for the storefront views and the SQL Lab.
	// If it is not running the server still starts, and the pages explain why.
	db, err := lab.Open(context.Background())
	if err != nil {
		log.Printf("Postgres not connected (%v): the shop pages and SQL Lab are off", err)
	} else {
		defer db.Close()
	}

	// Mount the API, then the static site at the root.
	mux := http.NewServeMux()

	// The SQL Lab runs arbitrary SQL, so it is only mounted when explicitly
	// enabled. Never set SHOPFLOW_LAB=1 on a public deployment.
	if os.Getenv("SHOPFLOW_LAB") == "1" {
		lab.Register(mux, db)
		log.Println("SQL Lab ENABLED (local use only)")
	}

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

	// Graceful shutdown: on Ctrl-C or SIGTERM, stop accepting new requests but
	// let the ones already in flight finish. A customer mid-checkout should not
	// have the connection cut because you deployed.
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

	log.Printf("ShopFlow listening on %s", addr)

	// ListenAndServe blocks until the server stops. It returns ErrServerClosed
	// on a clean shutdown, which is not a failure.
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("server error: %v", err)
	}

	<-shutdownDone
	log.Println("goodbye")
}
