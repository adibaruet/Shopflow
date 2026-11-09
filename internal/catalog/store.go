package catalog

import (
	"errors"
	"sort"
	"strings"
	"sync"
	"time"
)

// ErrNotFound is a sentinel error: one shared value that callers compare against
// with errors.Is(err, catalog.ErrNotFound). This is how you signal "the thing
// you asked for does not exist" without the caller having to match on a string.
var ErrNotFound = errors.New("product not found")

// Filter describes a product search. Zero values mean "do not filter by this".
type Filter struct {
	Query    string // matches name or description, case-insensitive
	Category string
	InStock  bool
}

// Store is the CONTRACT for anywhere products can live.
//
// This interface is the most important thing in this file. Today the only
// implementation is MemStore, holding products in a map. In Stage 3 we write a
// PostgresStore that satisfies the same interface, and every handler that uses
// a Store keeps working with zero changes. In Go you do not declare "MemStore
// implements Store" anywhere. If the methods match, it implements it.
type Store interface {
	List(f Filter) ([]Product, error)
	Get(id int64) (Product, error)
	GetBySlug(slug string) (Product, error)
	Create(p Product) (Product, error)
	Categories() ([]string, error)
}

// MemStore keeps products in memory. It disappears when the server stops.
// That is fine: it is a placeholder until Postgres arrives in Stage 3.
type MemStore struct {
	mu     sync.RWMutex // guards everything below
	byID   map[int64]Product
	nextID int64
}

// NewMemStore returns an empty store.
// Go has no constructors, so a New* function that returns the type is the
// convention. It returns *MemStore (a pointer) because a mutex must never
// be copied, and because Create modifies the struct.
func NewMemStore() *MemStore {
	return &MemStore{
		byID:   make(map[int64]Product),
		nextID: 1,
	}
}

// Why the mutex at all?
//
// net/http runs EVERY request in its own goroutine. Two customers hitting your
// server at the same moment are two goroutines touching this same map at the
// same moment. Concurrent map writes are not merely a race in Go, they are a
// hard runtime crash. RLock allows many simultaneous readers; Lock is exclusive
// for writers. Postgres will take over this job later, but the lesson holds:
// shared state needs a guard.

func (s *MemStore) Create(p Product) (Product, error) {
	if err := p.Validate(); err != nil {
		return Product{}, err
	}

	s.mu.Lock()
	defer s.mu.Unlock() // runs when the function returns, however it returns

	p.ID = s.nextID
	s.nextID++
	if p.Slug == "" {
		p.Slug = Slugify(p.Name)
	}
	if p.CreatedAt.IsZero() {
		p.CreatedAt = time.Now().UTC()
	}
	s.byID[p.ID] = p
	return p, nil
}

func (s *MemStore) Get(id int64) (Product, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	// The two-value map read: ok is false when the key is absent.
	p, ok := s.byID[id]
	if !ok {
		return Product{}, ErrNotFound
	}
	return p, nil
}

func (s *MemStore) GetBySlug(slug string) (Product, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	for _, p := range s.byID {
		if p.Slug == slug {
			return p, nil
		}
	}
	return Product{}, ErrNotFound
}

func (s *MemStore) List(f Filter) ([]Product, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	out := make([]Product, 0, len(s.byID))
	needle := strings.ToLower(strings.TrimSpace(f.Query))

	for _, p := range s.byID {
		if f.Category != "" && !strings.EqualFold(p.Category, f.Category) {
			continue
		}
		if f.InStock && p.Stock <= 0 {
			continue
		}
		if needle != "" {
			// Search across name, description AND category, so that typing
			// "coffee" finds the beans even though the word is not in their
			// names. Postgres full-text search replaces this in Stage 4.
			hay := strings.ToLower(p.Name + " " + p.Description + " " + p.Category)
			if !strings.Contains(hay, needle) {
				continue
			}
		}
		out = append(out, p)
	}

	// Map iteration order in Go is deliberately random, so an unsorted list
	// would shuffle on every request. Always sort what you return.
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out, nil
}

func (s *MemStore) Categories() ([]string, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	seen := make(map[string]bool)
	var out []string
	for _, p := range s.byID {
		if p.Category != "" && !seen[p.Category] {
			seen[p.Category] = true
			out = append(out, p.Category)
		}
	}
	sort.Strings(out)
	return out, nil
}

// Seed fills the store with sample products so there is something to look at.
func Seed(s Store) error {
	samples := []Product{
		{Name: "Ethiopian Yirgacheffe", Description: "Bright, floral single-origin beans. 250g whole bean.", PriceCents: 1850, Currency: "USD", Stock: 42, Category: "coffee", ImageURL: "/img/ethiopian-yirgacheffe.svg"},
		{Name: "Colombian Supremo", Description: "Balanced and nutty, the everyday cup. 250g whole bean.", PriceCents: 1450, Currency: "USD", Stock: 60, Category: "coffee", ImageURL: "/img/colombian-supremo.svg"},
		{Name: "Decaf Sumatra", Description: "Full-bodied and earthy, no caffeine. 250g whole bean.", PriceCents: 1650, Currency: "USD", Stock: 0, Category: "coffee", ImageURL: "/img/decaf-sumatra.svg"},
		{Name: "Gooseneck Kettle", Description: "1L stainless steel, precise pour control.", PriceCents: 5900, Currency: "USD", Stock: 12, Category: "equipment", ImageURL: "/img/gooseneck-kettle.svg"},
		{Name: "Burr Grinder", Description: "40mm conical burrs, 30 grind settings.", PriceCents: 12900, Currency: "USD", Stock: 7, Category: "equipment", ImageURL: "/img/burr-grinder.svg"},
		{Name: "Ceramic Dripper V60", Description: "Size 02, makes one to four cups.", PriceCents: 2400, Currency: "USD", Stock: 25, Category: "equipment", ImageURL: "/img/ceramic-dripper-v60.svg"},
		{Name: "Paper Filters (100)", Description: "Natural unbleached, size 02.", PriceCents: 800, Currency: "USD", Stock: 200, Category: "supplies", ImageURL: "/img/paper-filters-100.svg"},
		{Name: "Shop Mug", Description: "350ml stoneware, dishwasher safe.", PriceCents: 1900, Currency: "USD", Stock: 33, Category: "supplies", ImageURL: "/img/shop-mug.svg"},
	}

	for _, p := range samples {
		if _, err := s.Create(p); err != nil {
			return err
		}
	}
	return nil
}
