package catalog

import (
	"errors"
	"testing"
)

// Go's testing is built in: no framework, no assertion library.
// A file ending in _test.go, a function starting with Test taking *testing.T,
// and `go test ./...` runs it.

func TestPriceString(t *testing.T) {
	// A table test: one slice of cases, one loop. This is THE Go testing idiom.
	cases := []struct {
		name  string
		cents int64
		want  string
	}{
		{"whole dollars", 2400, "24.00"},
		{"with cents", 1899, "18.99"},
		{"single digit cents", 1805, "18.05"},
		{"under a dollar", 75, "0.75"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := Product{PriceCents: tc.cents}.PriceString()
			if got != tc.want {
				t.Errorf("PriceString() = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestSlugify(t *testing.T) {
	cases := map[string]string{
		"Ethiopian Yirgacheffe": "ethiopian-yirgacheffe",
		"Paper Filters (100)":   "paper-filters-100",
		"  Shop  Mug  ":         "shop-mug",
		"V60!!!":                "v60",
	}

	for in, want := range cases {
		if got := Slugify(in); got != want {
			t.Errorf("Slugify(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestValidateRejectsBadProducts(t *testing.T) {
	cases := []struct {
		name      string
		product   Product
		wantField string
	}{
		{"no name", Product{PriceCents: 100, Currency: "USD"}, "name"},
		{"free product", Product{Name: "Mug", Currency: "USD"}, "price_cents"},
		{"negative price", Product{Name: "Mug", PriceCents: -1, Currency: "USD"}, "price_cents"},
		{"negative stock", Product{Name: "Mug", PriceCents: 100, Currency: "USD", Stock: -5}, "stock"},
		{"no currency", Product{Name: "Mug", PriceCents: 100}, "currency"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := tc.product.Validate()
			if err == nil {
				t.Fatalf("expected an error, got nil")
			}

			var ve ValidationError
			if !errors.As(err, &ve) {
				t.Fatalf("expected a ValidationError, got %T", err)
			}
			if ve.Field != tc.wantField {
				t.Errorf("error on field %q, want %q", ve.Field, tc.wantField)
			}
		})
	}
}

func TestMemStoreCreateAndGet(t *testing.T) {
	s := NewMemStore()

	created, err := s.Create(Product{Name: "Test Mug", PriceCents: 1900, Currency: "USD", Stock: 3})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	if created.ID == 0 {
		t.Error("expected the store to assign an ID")
	}
	if created.Slug != "test-mug" {
		t.Errorf("slug = %q, want %q", created.Slug, "test-mug")
	}

	got, err := s.Get(created.ID)
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	if got.Name != "Test Mug" {
		t.Errorf("name = %q, want %q", got.Name, "Test Mug")
	}

	// The sentinel error, checked the right way.
	if _, err := s.Get(9999); !errors.Is(err, ErrNotFound) {
		t.Errorf("Get(9999) error = %v, want ErrNotFound", err)
	}
}

func TestMemStoreListFilters(t *testing.T) {
	s := NewMemStore()
	if err := Seed(s); err != nil {
		t.Fatalf("Seed: %v", err)
	}

	all, _ := s.List(Filter{})
	if len(all) != 8 {
		t.Fatalf("seeded %d products, want 8", len(all))
	}

	coffee, _ := s.List(Filter{Category: "coffee"})
	if len(coffee) != 3 {
		t.Errorf("coffee category returned %d, want 3", len(coffee))
	}

	inStock, _ := s.List(Filter{InStock: true})
	if len(inStock) != 7 {
		t.Errorf("in-stock returned %d, want 7 (Decaf Sumatra is sold out)", len(inStock))
	}

	search, _ := s.List(Filter{Query: "GRINDER"}) // case-insensitive
	if len(search) != 1 {
		t.Errorf("search for grinder returned %d, want 1", len(search))
	}

	// The category is part of the searchable text too.
	byCat, _ := s.List(Filter{Query: "coffee"})
	if len(byCat) != 3 {
		t.Errorf("search for coffee returned %d, want 3", len(byCat))
	}

	// Filters combine.
	combined, _ := s.List(Filter{Category: "coffee", InStock: true})
	if len(combined) != 2 {
		t.Errorf("in-stock coffee returned %d, want 2", len(combined))
	}
}
