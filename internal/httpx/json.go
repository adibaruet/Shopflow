// Package httpx holds the small helpers every handler needs, so that no
// handler has to repeat the plumbing of writing JSON or reporting an error.
package httpx

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
)

// WriteJSON sends v as JSON with the given status code.
//
// Order matters and is a classic Go bug: Header() changes must happen BEFORE
// WriteHeader, and WriteHeader before any Write. Once bytes go out you cannot
// take the status code back.
func WriteJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if v == nil {
		return
	}
	if err := json.NewEncoder(w).Encode(v); err != nil {
		// The client probably hung up. Nothing left to say to them, so just log.
		fmt.Printf("error encoding response: %v\n", err)
	}
}

// ErrorBody is the single shape every error from this API takes. Clients
// should never have to guess whether an error is a string, an object, or HTML.
type ErrorBody struct {
	Error struct {
		Message string `json:"message"`
		Field   string `json:"field,omitempty"`
	} `json:"error"`
}

// WriteError sends a structured error.
func WriteError(w http.ResponseWriter, status int, message, field string) {
	var body ErrorBody
	body.Error.Message = message
	body.Error.Field = field
	WriteJSON(w, status, body)
}

// DecodeJSON reads a JSON request body into dst.
//
// Two guards that matter in production:
//   - MaxBytesReader caps the body, so nobody can hand your server a 4GB
//     "product" and watch it run out of memory.
//   - DisallowUnknownFields makes a typo like {"nmae": "..."} a loud 400
//     instead of a product that silently gets created with an empty name.
func DecodeJSON(w http.ResponseWriter, r *http.Request, dst any) error {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20) // 1 MiB

	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()

	if err := dec.Decode(dst); err != nil {
		var syntaxErr *json.SyntaxError
		var typeErr *json.UnmarshalTypeError
		var tooLarge *http.MaxBytesError

		switch {
		case errors.As(err, &syntaxErr):
			return fmt.Errorf("body contains malformed JSON at position %d", syntaxErr.Offset)
		case errors.Is(err, io.ErrUnexpectedEOF):
			// A body that was cut off mid-object lands here, not in SyntaxError.
			return errors.New("body contains malformed JSON")
		case errors.As(err, &typeErr):
			return fmt.Errorf("field %q has the wrong type", typeErr.Field)
		case errors.Is(err, io.EOF):
			return errors.New("body must not be empty")
		case errors.As(err, &tooLarge):
			return fmt.Errorf("body must be smaller than %d bytes", tooLarge.Limit)
		default:
			return err
		}
	}

	// A second Decode must hit EOF, otherwise the caller sent two JSON objects.
	if err := dec.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return errors.New("body must contain a single JSON object")
	}
	return nil
}
