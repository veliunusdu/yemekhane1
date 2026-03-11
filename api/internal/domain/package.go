package domain

import (
	"encoding/json"
	"time"
)

// Package, işletmelerin satışa sunduğu "İndirimli Paket" modelini temsil eder.
type Package struct {
	ID              string          `json:"id"`
	BusinessID      string          `json:"business_id"`
	BusinessName    string          `json:"business_name"`    // JOIN ile businesses tablosundan
	Latitude        float64         `json:"latitude"`         // JOIN ile businesses tablosundan
	Longitude       float64         `json:"longitude"`        // JOIN ile businesses tablosundan
	Name            string          `json:"name"`             // Örn: "3'lü Karışık Poğaça"
	Description     string          `json:"description"`      // Örn: "Sabah üretiminden taze poğaçalar"
	OriginalPrice   float64         `json:"original_price"`   // Örn: 150.00
	DiscountedPrice float64         `json:"discounted_price"` // Örn: 50.00
	Stock           int             `json:"stock"`            // Örn: 5
	IsActive        bool            `json:"is_active"`
	ImageUrl        string          `json:"image_url"`
	Category        string          `json:"category"`
	Tags            json.RawMessage `json:"tags"` // Alerjenler vb. ek etiketler JSON array
	CreatedAt       time.Time       `json:"created_at"`
	DistanceKm      float64         `json:"distance_km,omitempty"` // Hesaplanan mesafe
	Rating          float64         `json:"rating,omitempty"`      // Hesaplanan ortalama puan
}

// CreatePackageDTO, işletme web üzerinden paket eklerken API'ye gelecek veridir.
type CreatePackageDTO struct {
	Name            string   `json:"name"`
	Description     string   `json:"description"`
	OriginalPrice   float64  `json:"original_price"`
	DiscountedPrice float64  `json:"discounted_price"`
	Stock           int      `json:"stock"`
	ImageUrl        string   `json:"image_url"`
	Category        string   `json:"category"`
	Tags            []string `json:"tags"`
	// V1'den kalma uyumluluk:
	BusinessName    string  `json:"business_name"`
	Latitude        float64 `json:"latitude"`
	Longitude       float64 `json:"longitude"`
}
