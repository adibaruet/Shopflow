package catalog

import (
	"fmt"
	"strings"
	"time"
)

// Product is one thing for sale.
//
// Note PriceCents, not Price. Money is NEVER a float in commerce code.
// 0.1 + 0.2 == 0.30000000000000004 in float64, and a store that is off by
// a fraction of a cent on every order is a store with broken books.
// Store whole cents in an int64, divide by 100 only when you display it.
type Product struct {
	ID          int64     `json:"id"`
	Slug        string    `json:"slug"`
	Name        string    `json:"name"`
	Description string    `json:"description"`
	PriceCents  int64     `json:"price_cents"`
	Currency    string    `json:"currency"`
	Stock       int       `json:"stock"`
	Category    string    `json:"category"`
	ImageURL    string    `json:"image_url"`
	CreatedAt   time.Time `json:"created_at"`
}

// PriceString renders the price the way a human reads it: 2499 -> "24.99".
// A method is just a function with a receiver (the `p Product` part).
func (p Product) PriceString() string {
	return fmt.Sprintf("%d.%02d", p.PriceCents/100, p.PriceCents%100)
}

// ValidationError says which field was wrong and why.
//
// Implementing Error() string is the ONLY thing required to be an error in Go.
// There is no `throw`, no exception class to inherit from. An error is any
// value with that one method, and it travels back through normal return values.
type ValidationError struct {
	Field   string
	Message string
}

func (e ValidationError) Error() string {
	return fmt.Sprintf("%s: %s", e.Field, e.Message)
}

// Validate checks a product before it is allowed into the store.
// It returns nil when everything is fine. Returning nil for "no error"
// is the Go convention you will see everywhere.
func (p Product) Validate() error {
	if strings.TrimSpace(p.Name) == "" {
		return ValidationError{Field: "name", Message: "must not be empty"}
	}
	if len(p.Name) > 200 {
		return ValidationError{Field: "name", Message: "must be 200 characters or fewer"}
	}
	if p.PriceCents <= 0 {
		return ValidationError{Field: "price_cents", Message: "must be greater than zero"}
	}
	if p.Stock < 0 {
		return ValidationError{Field: "stock", Message: "must not be negative"}
	}
	if p.Currency == "" {
		return ValidationError{Field: "currency", Message: "must be set, e.g. USD"}
	}
	return nil
}

// Slugify turns "Hand-Roasted Coffee Beans!" into "hand-roasted-coffee-beans",
// which is what belongs in a URL.
func Slugify(name string) string {
	var b strings.Builder
	lastDash := true // true so a leading dash is never written
	for _, r := range strings.ToLower(name) {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			b.WriteRune(r)
			lastDash = false
		default:
			if !lastDash {
				b.WriteRune('-')
				lastDash = true
			}
		}
	}
	return strings.Trim(b.String(), "-")
}
