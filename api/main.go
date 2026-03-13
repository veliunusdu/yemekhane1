package main

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math/big"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	jwtv4 "github.com/golang-jwt/jwt/v4"

	fire "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/messaging"
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/google/uuid"
	"github.com/joho/godotenv"
	_ "github.com/lib/pq"
	"github.com/redis/go-redis/v9"
	"google.golang.org/api/option"

	// Kendi modül adınla değiştirmeyi unutma!
	"github.com/veliunusdu/yemekhane1/internal/domain"
)

var ctx = context.Background()
var redisClient *redis.Client
var fcmClient *messaging.Client
var supabasePublicKey *ecdsa.PublicKey

// Supabase JWKS endpoint'inden ES256 public key'i çeker
func fetchSupabaseJWKS(supabaseURL string) (*ecdsa.PublicKey, error) {
	resp, err := http.Get(supabaseURL + "/auth/v1/.well-known/jwks.json")
	if err != nil {
		return nil, fmt.Errorf("JWKS fetch hatası: %v", err)
	}
	defer resp.Body.Close()

	var jwks struct {
		Keys []struct {
			Kty string `json:"kty"`
			Crv string `json:"crv"`
			X   string `json:"x"`
			Y   string `json:"y"`
		} `json:"keys"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&jwks); err != nil {
		return nil, fmt.Errorf("JWKS parse hatası: %v", err)
	}

	for _, key := range jwks.Keys {
		if key.Kty == "EC" && key.Crv == "P-256" {
			xBytes, err := base64.RawURLEncoding.DecodeString(key.X)
			if err != nil {
				continue
			}
			yBytes, err := base64.RawURLEncoding.DecodeString(key.Y)
			if err != nil {
				continue
			}
			return &ecdsa.PublicKey{
				Curve: elliptic.P256(),
				X:     new(big.Int).SetBytes(xBytes),
				Y:     new(big.Int).SetBytes(yBytes),
			}, nil
		}
	}
	return nil, fmt.Errorf("uygun EC P-256 key bulunamadı")
}

// FCM bildirim helper — tek bir token'a gönderir
func sendFCMNotification(token, title, body string) {
	if fcmClient == nil {
		log.Println("⚠️ FCM client hazır değil, bildirim atlandı.")
		return
	}
	message := &messaging.Message{
		Notification: &messaging.Notification{
			Title: title,
			Body:  body,
		},
		Token: token,
	}
	_, err := fcmClient.Send(ctx, message)
	if err != nil {
		log.Printf("❌ FCM gönderim hatası: %v", err)
	} else {
		log.Printf("🔔 FCM gönderildi → token: %s...%s", token[:6], token[len(token)-4:])
	}
}

// Kullanıcının email'ine göre FCM token'a bildirim gönderir
func sendFCMToEmail(db *sql.DB, email, title, body string) {
	var token string
	err := db.QueryRow("SELECT fcm_token FROM device_tokens WHERE user_email = $1", email).Scan(&token)
	if err != nil {
		log.Printf("⚠️ %s için FCM token bulunamadı", email)
		return
	}
	sendFCMNotification(token, title, body)
}

// Tüm kayıtlı kullanıcılara gönderir
func sendFCMToAll(db *sql.DB, title, body string) {
	rows, err := db.Query("SELECT fcm_token FROM device_tokens")
	if err != nil {
		log.Println("⚠️ device_tokens sorgu hatası:", err)
		return
	}
	defer rows.Close()
	for rows.Next() {
		var token string
		if err := rows.Scan(&token); err != nil {
			continue
		}
		sendFCMNotification(token, title, body)
	}
}

// rateLimiter, IP başına n istek / window süresi sınırını Redis'te uygular.
// Redis bağlı değilse şeffaf geçiş yapar (fail-open).
func rateLimiter(max int, window time.Duration) fiber.Handler {
	return func(c *fiber.Ctx) error {
		if redisClient == nil {
			return c.Next()
		}
		ip := c.IP()
		key := fmt.Sprintf("rl:%s:%s", c.Path(), ip)
		pipe := redisClient.Pipeline()
		incr := pipe.Incr(ctx, key)
		pipe.Expire(ctx, key, window)
		if _, err := pipe.Exec(ctx); err != nil {
			log.Printf("⚠️ Rate limiter Redis hatası: %v", err)
			return c.Next()
		}
		count := incr.Val()
		c.Set("X-RateLimit-Limit", fmt.Sprintf("%d", max))
		c.Set("X-RateLimit-Remaining", fmt.Sprintf("%d", max-int(count)))
		if count > int64(max) {
			return c.Status(429).JSON(fiber.Map{"error": "Çok fazla istek gönderdiniz. Lütfen bekleyin."})
		}
		return c.Next()
	}
}

// jwtMiddleware doğrulanmış Supabase JWT token'ını kontrol eder.
// Token geçerliyse kullanıcı e-postasını c.Locals("user_email") ile ileri handler'lara taşır.
func jwtMiddleware(c *fiber.Ctx) error {
	authHeader := c.Get("Authorization")
	if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer ") {
		return c.Status(401).JSON(fiber.Map{"error": "Yetkilendirme başlığı eksik"})
	}
	tokenStr := strings.TrimPrefix(authHeader, "Bearer ")

	if supabasePublicKey == nil {
		log.Println("⚠️ Supabase public key yüklenmemiş, JWT doğrulaması atlanıyor!")
		return c.Next()
	}

	token, err := jwtv4.Parse(tokenStr, func(token *jwtv4.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwtv4.SigningMethodECDSA); !ok {
			return nil, fmt.Errorf("beklenmedik imzalama yöntemi: %v", token.Header["alg"])
		}
		return supabasePublicKey, nil
	})

	if err != nil || !token.Valid {
		log.Printf("❌ JWT doğrulama hatası: %v | token başı: %.20s...", err, tokenStr)
		return c.Status(401).JSON(fiber.Map{"error": fmt.Sprintf("Geçersiz token: %v", err)})
	}

	claims, ok := token.Claims.(jwtv4.MapClaims)
	if !ok {
		return c.Status(401).JSON(fiber.Map{"error": "Token claims okunamadı"})
	}

	email, _ := claims["email"].(string)
	c.Locals("user_email", email)
	return c.Next()
}

func main() {
	// 0. Logları dosyaya da yaz
	logFile, _ := os.OpenFile("api.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0666)
	mw := io.MultiWriter(os.Stdout, logFile)
	log.SetOutput(mw)

	// .env dosyasını yükle
	err := godotenv.Load()
	if err != nil {
		log.Fatal(".env dosyası yüklenemedi!")
	}

	// Supabase JWKS (ES256 public key) yükle — başarısız olursa arka planda retry
	if supabaseURL := os.Getenv("SUPABASE_URL"); supabaseURL != "" {
		var jwksErr error
		supabasePublicKey, jwksErr = fetchSupabaseJWKS(supabaseURL)
		if jwksErr != nil {
			log.Printf("⚠️ Supabase JWKS yüklenemedi: %v — 30 saniyede bir retry yapılacak", jwksErr)
			go func() {
				for {
					time.Sleep(30 * time.Second)
					key, err := fetchSupabaseJWKS(supabaseURL)
					if err == nil {
						supabasePublicKey = key
						log.Println("✅ Supabase JWKS yüklendi (ES256) — retry başarılı")
						return
					}
					log.Printf("⚠️ JWKS retry başarısız: %v", err)
				}
			}()
		} else {
			log.Println("✅ Supabase JWKS yüklendi (ES256)")
		}
	}

	// 1. Veritabanına Bağlan (Environment variable'dan al)
	connStr := os.Getenv("DATABASE_URL")
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal("Veritabanına bağlanılamadı:", err)
	}
	defer db.Close()

	// 2. Tabloları Otomatik Oluştur (V2 Mimari)

	// A. Kullanıcılar (Users)
	db.Exec(`CREATE TABLE IF NOT EXISTS users (
		id UUID DEFAULT gen_random_uuid(),
		email VARCHAR(255) PRIMARY KEY,
		full_name VARCHAR(255),
		phone_number VARCHAR(50),
		profile_image_url TEXT,
		loyalty_points INT DEFAULT 0,
		preferences JSONB DEFAULT '{}',
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);`)

	// B. İşletmeler (Businesses)
	db.Exec(`CREATE TABLE IF NOT EXISTS businesses (
		id VARCHAR(255) PRIMARY KEY,
		owner_email VARCHAR(255),
		name VARCHAR(255) DEFAULT '',
		latitude FLOAT DEFAULT 0.0,
		longitude FLOAT DEFAULT 0.0,
		address TEXT,
		is_active BOOLEAN DEFAULT true,
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);`)

	// C. İşletme Çalışma Saatleri (Business Hours)
	db.Exec(`CREATE TABLE IF NOT EXISTS business_hours (
		id SERIAL PRIMARY KEY,
		business_id VARCHAR(255),
		day_of_week INT CHECK (day_of_week >= 0 AND day_of_week <= 6),
		open_time TIME,
		close_time TIME,
		is_closed BOOLEAN DEFAULT false,
		UNIQUE(business_id, day_of_week)
	);`)

	// D. Paketler (Packages V2)
	db.Exec(`CREATE TABLE IF NOT EXISTS packages (
		id UUID PRIMARY KEY,
		business_id VARCHAR(255),
		name VARCHAR(255),
		description TEXT,
		original_price DECIMAL(10,2),
		discounted_price DECIMAL(10,2),
		stock INT,
		is_active BOOLEAN,
		image_url TEXT,
		category VARCHAR(100) DEFAULT 'Diğer',
		tags JSONB DEFAULT '[]',
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);`)
	db.Exec("ALTER TABLE packages ADD COLUMN IF NOT EXISTS category VARCHAR(100) DEFAULT 'Diğer';")
	db.Exec("ALTER TABLE packages ADD COLUMN IF NOT EXISTS tags JSONB DEFAULT '[]';")
	db.Exec("ALTER TABLE businesses ADD COLUMN IF NOT EXISTS logo_url TEXT DEFAULT '';")
	db.Exec("ALTER TABLE businesses ADD COLUMN IF NOT EXISTS category VARCHAR(100) DEFAULT '';")
	db.Exec("ALTER TABLE businesses ADD COLUMN IF NOT EXISTS description TEXT DEFAULT '';")
	db.Exec("ALTER TABLE businesses ADD COLUMN IF NOT EXISTS phone VARCHAR(50) DEFAULT '';")
	db.Exec("ALTER TABLE businesses ADD COLUMN IF NOT EXISTS website TEXT DEFAULT '';")
	db.Exec("ALTER TABLE businesses ADD COLUMN IF NOT EXISTS email VARCHAR(255) DEFAULT '';")

	// E. Siparişler (Orders)
	db.Exec(`CREATE TABLE IF NOT EXISTS orders (
		id UUID PRIMARY KEY,
		package_id UUID,
		user_id VARCHAR(50),
		buyer_email VARCHAR(255),
		status VARCHAR(50),
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);`)
	db.Exec("ALTER TABLE orders ADD COLUMN IF NOT EXISTS buyer_email VARCHAR(255);")
	db.Exec("ALTER TABLE orders ALTER COLUMN status TYPE VARCHAR(50);")
	// 2.1: Snapshot & tracking columns
	db.Exec("ALTER TABLE orders ADD COLUMN IF NOT EXISTS total_price DECIMAL(10,2);")
	db.Exec("ALTER TABLE orders ADD COLUMN IF NOT EXISTS package_name VARCHAR(255);")
	db.Exec("ALTER TABLE orders ADD COLUMN IF NOT EXISTS package_image_url TEXT;")
	db.Exec("ALTER TABLE orders ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;")

	// 2.3: Performance indexes
	// Geçerli sipariş durumu sırası: 'Ödendi' → 'Hazırlanıyor' → 'Teslim Edilmeyi Bekliyor' → 'Teslim Edildi'
	//                                 'Ödendi' → 'İptal Edildi'  (5 dakika içinde)
	db.Exec("CREATE INDEX IF NOT EXISTS idx_orders_buyer_email ON orders(buyer_email);")
	db.Exec("CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);")
	db.Exec("CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at DESC);")
	db.Exec("CREATE INDEX IF NOT EXISTS idx_packages_is_active ON packages(is_active) WHERE is_active = true;")
	db.Exec("CREATE INDEX IF NOT EXISTS idx_device_tokens_email ON device_tokens(user_email);")

	// F. Sipariş Durum Geçmişi (Order Status History)
	db.Exec(`CREATE TABLE IF NOT EXISTS order_status_history (
		id SERIAL PRIMARY KEY,
		order_id UUID,
		status VARCHAR(50),
		changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);`)

	// G. Değerlendirmeler ve Yorumlar (Reviews)
	db.Exec(`CREATE TABLE IF NOT EXISTS reviews (
		id SERIAL PRIMARY KEY,
		order_id UUID,
		user_email VARCHAR(255),
		business_id VARCHAR(255),
		rating INT CHECK (rating >= 1 AND rating <= 5),
		comment TEXT,
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);`)

	// H. Favori Dükkanlar (Favorite Shops)
	db.Exec(`CREATE TABLE IF NOT EXISTS favorite_shops (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		user_email VARCHAR(255) NOT NULL,
		business_id VARCHAR(255),
		business_name VARCHAR(255),
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
		UNIQUE(user_email, business_name)
	);`)

	// I. FCM Token (Push Notification)
	db.Exec(`CREATE TABLE IF NOT EXISTS device_tokens (
		user_email VARCHAR(255) PRIMARY KEY,
		fcm_token  TEXT NOT NULL,
		updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);`)

	// Firebase App + FCM Client başlatma (service account varsa)
	serviceAccountPath := os.Getenv("GOOGLE_APPLICATION_CREDENTIALS")
	if serviceAccountPath == "" {
		serviceAccountPath = "./firebase-service-account.json"
	}
	if _, statErr := os.Stat(serviceAccountPath); statErr == nil {
		fireApp, fireErr := fire.NewApp(ctx, nil, option.WithCredentialsFile(serviceAccountPath))
		if fireErr != nil {
			log.Printf("⚠️ Firebase başlatma hatası: %v", fireErr)
		} else {
			fcmClient, _ = fireApp.Messaging(ctx)
			log.Println("🔥 Firebase FCM hazır!")
		}
	} else {
		log.Println("⚠️ firebase-service-account.json bulunamadı. Push bildirimler devre dışı.")
	}

	// Redis Bağlantısı (Upstash)
	redisURL := os.Getenv("REDIS_URL")
	if redisURL == "" {
		log.Println("UYARI: REDIS_URL bulunamadı. Rate limiting çalışmayacak!")
	} else {
		log.Printf("Connecting to Redis (Len: %d)...", len(redisURL))
		opt, err := redis.ParseURL(redisURL)
		if err != nil {
			log.Fatal("Redis URL hatası (Lütfen .env dosyasını kontrol et):", err)
		}

		log.Printf("Parsed Redis Opts -> Addr: %s, User: %s, TLS: %v", opt.Addr, opt.Username, opt.TLSConfig != nil)

		redisClient = redis.NewClient(opt)
		if err := redisClient.Ping(ctx).Err(); err != nil {
			log.Printf("⚠️ Redis bağlantı hatası: %v", err)
			log.Println("⚠️ Redis bağlantısı başarısız! Rate limiting devre dışı, API yine de çalışacak.")
			redisClient = nil // nil bırak ki rate limiting atlanabilsin
		} else {
			log.Println("Redis bağlantısı başarılı! 🚀")
		}
	}

	// 3. Fiber Uygulamasını Başlat
	app := fiber.New()

	// Logger (Hataları ve İstekleri Terminalden İzlemek İçin)
	app.Use(logger.New())

	// CORS Ayarı (Web ve Mobil'in API'ye erişebilmesi için)
	corsOrigins := os.Getenv("CORS_ORIGINS")
	if corsOrigins == "" {
		corsOrigins = "*"
	}
	app.Use(cors.New(cors.Config{
		AllowOrigins: corsOrigins,
		AllowMethods: "GET,POST,HEAD,PUT,DELETE,PATCH,OPTIONS",
		AllowHeaders: "Origin, Content-Type, Accept, Authorization",
	}))

	// API Rotası: İşletme Konumunu Kaydet/Güncelle
	app.Post("/api/v1/business/location", jwtMiddleware, func(c *fiber.Ctx) error {
		ownerEmail := c.Locals("user_email").(string)
		var businessID string
		if err := db.QueryRow("SELECT id FROM businesses WHERE owner_email = $1", ownerEmail).Scan(&businessID); err != nil {
			return c.Status(403).JSON(fiber.Map{"error": "Bu hesaba bağlı işletme bulunamadı"})
		}
		type LocationRequest struct {
			Name      string  `json:"name"`
			Latitude  float64 `json:"latitude"`
			Longitude float64 `json:"longitude"`
		}
		var req LocationRequest
		if err := c.BodyParser(&req); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Geçersiz veri"})
		}
		if req.Latitude == 0 || req.Longitude == 0 {
			return c.Status(400).JSON(fiber.Map{"error": "Geçerli koordinat gerekli"})
		}

		_, err := db.Exec(`
			INSERT INTO businesses (id, name, latitude, longitude, updated_at)
			VALUES ($1, $2, $3, $4, $5)
			ON CONFLICT (id) DO UPDATE SET
				name = EXCLUDED.name,
				latitude = EXCLUDED.latitude,
				longitude = EXCLUDED.longitude,
				updated_at = EXCLUDED.updated_at`,
			businessID, req.Name, req.Latitude, req.Longitude, time.Now())
		if err != nil {
			log.Println("Konum kaydetme hatası:", err)
			return c.Status(500).JSON(fiber.Map{"error": "Konum kaydedilemedi"})
		}
		log.Printf("📍 İşletme konumu güncellendi: %.6f, %.6f", req.Latitude, req.Longitude)
		return c.JSON(fiber.Map{"message": "Konum kaydedildi ✅", "latitude": req.Latitude, "longitude": req.Longitude})
	})

	// API Rotası: İşletmenin Kayıtlı Konumunu Çek (JWT ile owner'a göre)
	app.Get("/api/v1/business/location", jwtMiddleware, func(c *fiber.Ctx) error {
		ownerEmail := c.Locals("user_email").(string)
		var name string
		var lat, lon float64
		err := db.QueryRow(`SELECT name, latitude, longitude FROM businesses WHERE owner_email = $1`, ownerEmail).Scan(&name, &lat, &lon)
		if err != nil {
			return c.JSON(fiber.Map{"name": "", "latitude": 0, "longitude": 0})
		}
		return c.JSON(fiber.Map{"name": name, "latitude": lat, "longitude": lon})
	})

	// 4. API Rotasını Tanımla (İşletme Paket Ekler)
	app.Post("/api/v1/business/packages", rateLimiter(30, time.Hour), jwtMiddleware, func(c *fiber.Ctx) error {
		ownerEmail := c.Locals("user_email").(string)
		var businessID string
		if err := db.QueryRow("SELECT id FROM businesses WHERE owner_email = $1", ownerEmail).Scan(&businessID); err != nil {
			return c.Status(403).JSON(fiber.Map{"error": "Bu hesaba bağlı işletme bulunamadı"})
		}

		var dto domain.CreatePackageDTO

		// Gelen JSON verisini DTO'ya dönüştür
		if err := c.BodyParser(&dto); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Geçersiz veri formatı"})
		}

		log.Printf("📦 Yeni Paket Geldi: %+v\n", dto)

		// Koordinat verilmemişse işletmenin kayıtlı konumunu kullan
		if dto.Latitude == 0 || dto.Longitude == 0 {
			var bizLat, bizLon float64
			var bizName string
			dbErr := db.QueryRow(`SELECT name, latitude, longitude FROM businesses WHERE id = $1`, businessID).
				Scan(&bizName, &bizLat, &bizLon)
			if dbErr == nil && (bizLat != 0 || bizLon != 0) {
				dto.Latitude = bizLat
				dto.Longitude = bizLon
				if dto.BusinessName == "" {
					dto.BusinessName = bizName
				}
				log.Printf("📍 Koordinat eksik, işletme konumu kullanıldı: %.6f, %.6f", bizLat, bizLon)
			}
		}

		category := dto.Category
		if category == "" {
			category = "Diğer"
		}

		tagsJSON := "[]"
		if len(dto.Tags) > 0 {
			b, _ := json.Marshal(dto.Tags)
			tagsJSON = string(b)
		}

		// Veritabanı modelini (Entity) oluştur
		pkg := domain.Package{
			ID:              uuid.New().String(),
			BusinessID:      businessID,
			BusinessName:    dto.BusinessName,
			Latitude:        dto.Latitude,
			Longitude:       dto.Longitude,
			Name:            dto.Name,
			Description:     dto.Description,
			OriginalPrice:   dto.OriginalPrice,
			DiscountedPrice: dto.DiscountedPrice,
			Stock:           dto.Stock,
			IsActive:        true,
			ImageUrl:        dto.ImageUrl,
			Category:        category,
			Tags:            json.RawMessage(tagsJSON),
			CreatedAt:       time.Now(),
		}

		// V2 Mimarisi İçin Insert:
		insertQuery := `
			INSERT INTO packages (id, business_id, name, description, original_price, discounted_price, stock, is_active, created_at, image_url, category, tags, available_from, available_until)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)`

		availFrom := sql.NullString{String: dto.AvailableFrom, Valid: dto.AvailableFrom != ""}
		availUntil := sql.NullString{String: dto.AvailableUntil, Valid: dto.AvailableUntil != ""}
		_, err := db.Exec(insertQuery, pkg.ID, pkg.BusinessID, pkg.Name, pkg.Description, pkg.OriginalPrice, pkg.DiscountedPrice, pkg.Stock, pkg.IsActive, pkg.CreatedAt, pkg.ImageUrl, pkg.Category, tagsJSON, availFrom, availUntil)
		if err != nil {
			log.Println("Kaydetme hatası:", err)
			return c.Status(500).JSON(fiber.Map{"error": "Paket kaydedilemedi"})
		}

		// Push Bildirim: Tüm kullanıcılara yeni paket bildirimi gönder
		go sendFCMToAll(db,
			"Yakınında yeni bir paket! 🍱",
			pkg.Name+" — sadece ₺"+fmt.Sprintf("%.2f", pkg.DiscountedPrice),
		)

		// Başarılı yanıt dön (201 Created)
		return c.Status(201).JSON(pkg)
	})

	// API Rotası 2b: İşletmenin Kendi Paketlerini Listele (Dashboard)
	app.Get("/api/v1/business/packages", jwtMiddleware, func(c *fiber.Ctx) error {
		ownerEmail := c.Locals("user_email").(string)
		var businessID string
		if err := db.QueryRow("SELECT id FROM businesses WHERE owner_email = $1", ownerEmail).Scan(&businessID); err != nil {
			return c.Status(403).JSON(fiber.Map{"error": "Bu hesaba bağlı işletme bulunamadı"})
		}

		rows, err := db.Query(`
			SELECT id, name, description, original_price, discounted_price, stock, is_active, image_url, category, created_at
			FROM packages
			WHERE business_id = $1
			ORDER BY created_at DESC`, businessID)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": "Paketler getirilemedi"})
		}
		defer rows.Close()

		type PkgRow struct {
			ID              string    `json:"id"`
			Name            string    `json:"name"`
			Description     string    `json:"description"`
			OriginalPrice   float64   `json:"original_price"`
			DiscountedPrice float64   `json:"discounted_price"`
			Stock           int       `json:"stock"`
			IsActive        bool      `json:"is_active"`
			ImageUrl        string    `json:"image_url"`
			Category        string    `json:"category"`
			CreatedAt       time.Time `json:"created_at"`
		}
		pkgs := []PkgRow{}
		for rows.Next() {
			var p PkgRow
			var imgUrl sql.NullString
			if err := rows.Scan(&p.ID, &p.Name, &p.Description, &p.OriginalPrice, &p.DiscountedPrice, &p.Stock, &p.IsActive, &imgUrl, &p.Category, &p.CreatedAt); err != nil {
				continue
			}
			if imgUrl.Valid {
				p.ImageUrl = imgUrl.String
			}
			pkgs = append(pkgs, p)
		}
		return c.JSON(pkgs)
	})

	// API Rotası 2: Tüm Aktif Paketleri Listele (Kullanıcılar İçin - Konum Bazlı Filtrelenebilir)
	app.Get("/api/v1/packages", func(c *fiber.Ctx) error {
		// Konum parametrelerini al
		latStr := c.Query("lat")
		lonStr := c.Query("lon")
		radiusStr := c.Query("radius", "10") // Varsayılan 10 km
		bizFilter := c.Query("business_id")  // İsteğe bağlı işletme filtresi
		searchQ := c.Query("q")              // Kelime araması (paket adı / açıklama)
		catFilter := c.Query("category")     // Kategori filtresi

		var query string
		var rows *sql.Rows
		var err error

		if latStr != "" && lonStr != "" {
			// Konum varsa Haversine formülü ile hesapla ve filtrele
			lat, errLat := strconv.ParseFloat(latStr, 64)
			lon, errLon := strconv.ParseFloat(lonStr, 64)
			radius, errR := strconv.ParseFloat(radiusStr, 64)
			if errLat != nil || errLon != nil || errR != nil {
				return c.Status(400).JSON(fiber.Map{"error": "Geçersiz konum parametreleri"})
			}

			// Haversine Formülü — packages ve businesses JOIN işlemi
			bizClause := ""
			if bizFilter != "" {
				bizClause = " AND p.business_id = '" + strings.ReplaceAll(bizFilter, "'", "") + "'"
			}
			query = `
				SELECT * FROM (
					SELECT
						p.id, p.business_id, b.name as business_name, b.latitude, b.longitude, p.name,
						p.description, p.original_price, p.discounted_price, p.stock, p.is_active, p.image_url, p.category, p.tags,
						COALESCE(p.available_from::text, '') AS available_from,
						COALESCE(p.available_until::text, '') AS available_until,
						6371 * acos(
							LEAST(1.0,
								COS(RADIANS($1)) * COS(RADIANS(b.latitude)) *
								COS(RADIANS(b.longitude) - RADIANS($2)) +
								SIN(RADIANS($1)) * SIN(RADIANS(b.latitude))
							)
						) AS distance_km
					FROM packages p
					JOIN businesses b ON p.business_id = b.id
					WHERE p.is_active = true AND b.latitude != 0 AND b.longitude != 0
					  AND (p.available_from IS NULL OR p.available_until IS NULL
					       OR (CURRENT_TIME AT TIME ZONE 'Europe/Istanbul') BETWEEN p.available_from AND p.available_until)
					  AND ($4 = '' OR p.name ILIKE '%' || $4 || '%' OR p.description ILIKE '%' || $4 || '%')
					  AND ($5 = '' OR p.category = $5)` + bizClause + `
				) AS results
				WHERE results.distance_km <= $3
				ORDER BY results.distance_km ASC`
			rows, err = db.Query(query, lat, lon, radius, searchQ, catFilter)
		} else {
			// Konum yoksa tüm aktif paketleri getir
			if bizFilter != "" {
				query = `
					SELECT p.id, p.business_id, b.name as business_name, b.latitude, b.longitude, p.name, p.description, p.original_price, p.discounted_price, p.stock, p.is_active, p.image_url, p.category, p.tags,
					  COALESCE(p.available_from::text, '') AS available_from,
					  COALESCE(p.available_until::text, '') AS available_until,
					  0 AS distance_km
					FROM packages p
					JOIN businesses b ON p.business_id = b.id
					WHERE p.is_active = true AND p.business_id = $1
					  AND (p.available_from IS NULL OR p.available_until IS NULL
					       OR (CURRENT_TIME AT TIME ZONE 'Europe/Istanbul') BETWEEN p.available_from AND p.available_until)
					  AND ($2 = '' OR p.name ILIKE '%' || $2 || '%' OR p.description ILIKE '%' || $2 || '%')
					  AND ($3 = '' OR p.category = $3)`
				rows, err = db.Query(query, bizFilter, searchQ, catFilter)
			} else {
				query = `
					SELECT p.id, p.business_id, b.name as business_name, b.latitude, b.longitude, p.name, p.description, p.original_price, p.discounted_price, p.stock, p.is_active, p.image_url, p.category, p.tags,
					  COALESCE(p.available_from::text, '') AS available_from,
					  COALESCE(p.available_until::text, '') AS available_until,
					  0 AS distance_km
					FROM packages p
					JOIN businesses b ON p.business_id = b.id
					WHERE p.is_active = true
					  AND (p.available_from IS NULL OR p.available_until IS NULL
					       OR (CURRENT_TIME AT TIME ZONE 'Europe/Istanbul') BETWEEN p.available_from AND p.available_until)
					  AND ($1 = '' OR p.name ILIKE '%' || $1 || '%' OR p.description ILIKE '%' || $1 || '%')
					  AND ($2 = '' OR p.category = $2)`
				rows, err = db.Query(query, searchQ, catFilter)
			}
		}

		if err != nil {
			log.Println("Paket sorgulama hatası:", err)
			return c.Status(500).JSON(fiber.Map{"error": "Paketler getirilemedi"})
		}
		defer rows.Close()

		packages := []domain.Package{}
		for rows.Next() {
			var p domain.Package
			var tagsStr string
			if err := rows.Scan(&p.ID, &p.BusinessID, &p.BusinessName, &p.Latitude, &p.Longitude, &p.Name, &p.Description, &p.OriginalPrice, &p.DiscountedPrice, &p.Stock, &p.IsActive, &p.ImageUrl, &p.Category, &tagsStr, &p.AvailableFrom, &p.AvailableUntil, &p.DistanceKm); err != nil {
				log.Println("Satır okuma hatası:", err)
				continue
			}
			p.Tags = json.RawMessage(tagsStr)

			// V2 Ortalama Puan (Rating) Subquery
			db.QueryRow("SELECT COALESCE(AVG(rating), 0) FROM reviews WHERE business_id = $1", p.BusinessID).Scan(&p.Rating)

			packages = append(packages, p)
		}

		// Listeyi JSON olarak geri dön
		return c.JSON(packages)
	})

	// API Rotası 4: İşletme İçin Gelen Siparişleri Listele
	app.Get("/api/v1/business/orders", jwtMiddleware, func(c *fiber.Ctx) error {
		ownerEmail := c.Locals("user_email").(string)
		var businessID string
		if err := db.QueryRow("SELECT id FROM businesses WHERE owner_email = $1", ownerEmail).Scan(&businessID); err != nil {
			return c.Status(403).JSON(fiber.Map{"error": "Bu hesaba bağlı işletme bulunamadı"})
		}

		query := `
			SELECT o.id, p.name, o.buyer_email, o.status, o.created_at 
			FROM orders o 
			JOIN packages p ON o.package_id = p.id 
			WHERE p.business_id = $1
			ORDER BY o.created_at DESC`

		rows, err := db.Query(query, businessID)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": "Siparişler getirilemedi"})
		}
		defer rows.Close()

		type OrderInfo struct {
			ID         string    `json:"id"`
			Package    string    `json:"package_name"`
			BuyerEmail string    `json:"buyer_email"`
			Status     string    `json:"status"`
			CreatedAt  time.Time `json:"created_at"`
		}

		orders := []OrderInfo{}
		for rows.Next() {
			var o OrderInfo
			// Gelen boş String ihtimaline karşı sql.NullString de kullanılabilir ancak Go'da bos dize olarak maplenecek VARCHAR kullanılmış.
			var email sql.NullString
			if err := rows.Scan(&o.ID, &o.Package, &email, &o.Status, &o.CreatedAt); err != nil {
				continue
			}
			if email.Valid {
				o.BuyerEmail = email.String
			} else {
				o.BuyerEmail = "E-posta Eksik"
			}
			orders = append(orders, o)
		}

		return c.JSON(orders)
	})

	// API Rotası 5: Giriş Yap (Supabase Auth Proxy)
	app.Post("/api/v1/auth/login", func(c *fiber.Ctx) error {
		// 1. Gelen isteği oku
		body := c.Body()
		log.Printf("Incoming Login Request: %s", string(body))

		// 2. Supabase Auth API'sine yönlendir
		supabaseURL := os.Getenv("SUPABASE_URL") + "/auth/v1/token?grant_type=password"
		req, _ := http.NewRequest("POST", supabaseURL, bytes.NewBuffer(body))

		anonKey := os.Getenv("SUPABASE_ANON_KEY")
		req.Header.Set("apikey", anonKey)
		req.Header.Set("Authorization", "Bearer "+anonKey)
		req.Header.Set("Content-Type", "application/json")

		client := &http.Client{}
		resp, err := client.Do(req)
		if err != nil {
			log.Printf("Supabase Request Error: %v", err)
			return c.Status(500).JSON(fiber.Map{"error": "Supabase bağlantı hatası"})
		}
		defer resp.Body.Close()

		bodyBytes, _ := io.ReadAll(resp.Body)
		var result map[string]interface{}
		json.Unmarshal(bodyBytes, &result)

		log.Printf("Supabase Response [%d]: %s", resp.StatusCode, string(bodyBytes))
		return c.Status(resp.StatusCode).JSON(result)
	})

	// API Rotası 6: Kayıt Ol (Supabase Auth Signup Proxy)
	app.Post("/api/v1/auth/signup", func(c *fiber.Ctx) error {
		body := c.Body()
		supabaseURL := os.Getenv("SUPABASE_URL") + "/auth/v1/signup"
		req, _ := http.NewRequest("POST", supabaseURL, bytes.NewBuffer(body))

		anonKey := os.Getenv("SUPABASE_ANON_KEY")
		req.Header.Set("apikey", anonKey)
		req.Header.Set("Authorization", "Bearer "+anonKey)
		req.Header.Set("Content-Type", "application/json")

		client := &http.Client{}
		resp, err := client.Do(req)
		if err != nil {
			log.Printf("Supabase Signup Error: %v", err)
			return c.Status(500).JSON(fiber.Map{"error": "Supabase bağlantı hatası"})
		}
		defer resp.Body.Close()

		bodyBytes, _ := io.ReadAll(resp.Body)
		var result map[string]interface{}
		json.Unmarshal(bodyBytes, &result)
		return c.Status(resp.StatusCode).JSON(result)
	})

	// API Rotası 7: OTP Gönder (Hız Sınırlamalı)
	app.Post("/api/v1/auth/otp", func(c *fiber.Ctx) error {
		type OTPRequest struct {
			Email string `json:"email"`
		}
		var reqData OTPRequest
		if err := c.BodyParser(&reqData); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Geçersiz istek"})
		}

		// Redis ile Hız Sınırlama (Rate Limiting)
		// Aynı e-posta 1 dakikada en fazla 3 istek atabilir
		if redisClient != nil {
			key := "ratelimit:otp:" + reqData.Email
			count, _ := redisClient.Incr(ctx, key).Result()

			// İlk istekte 60 saniyelik temizlenme süresi (TTL) başlat
			if count == 1 {
				redisClient.Expire(ctx, key, 60*time.Second)
			}

			if count > 3 {
				return c.Status(429).JSON(fiber.Map{"error": "Çok fazla deneme! Lütfen 1 dakika sonra tekrar deneyin."})
			}
		}

		// Supabase OTP API'sine yönlendir
		supabaseURL := os.Getenv("SUPABASE_URL") + "/auth/v1/otp"
		bodyBytes, _ := json.Marshal(reqData)
		req, _ := http.NewRequest("POST", supabaseURL, bytes.NewBuffer(bodyBytes))

		anonKey := os.Getenv("SUPABASE_ANON_KEY")
		req.Header.Set("apikey", anonKey)
		req.Header.Set("Authorization", "Bearer "+anonKey)
		req.Header.Set("Content-Type", "application/json")

		client := &http.Client{}
		resp, err := client.Do(req)
		if err != nil {
			log.Printf("Supabase OTP Error: %v", err)
			return c.Status(500).JSON(fiber.Map{"error": "Supabase bağlantı hatası"})
		}
		defer resp.Body.Close()

		resBytes, _ := io.ReadAll(resp.Body)
		var result map[string]interface{}
		json.Unmarshal(resBytes, &result)
		return c.Status(resp.StatusCode).JSON(result)
	})

	// API Rotası 8: Direkt Sipariş Oluştur (Ödeme yüz yüze)
	app.Post("/api/v1/orders", rateLimiter(10, time.Minute), jwtMiddleware, func(c *fiber.Ctx) error {
		type OrderRequest struct {
			PackageID  string `json:"package_id"`
			BuyerEmail string `json:"buyer_email"`
		}
		var req OrderRequest
		if err := c.BodyParser(&req); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Geçersiz istek"})
		}
		userEmail, _ := c.Locals("user_email").(string)
		if userEmail == "" {
			userEmail = req.BuyerEmail
		}
		if req.PackageID == "" {
			return c.Status(400).JSON(fiber.Map{"error": "package_id gerekli"})
		}

		tx, txErr := db.Begin()
		if txErr != nil {
			return c.Status(500).JSON(fiber.Map{"error": "Sipariş oluşturulamadı"})
		}

		res, err := tx.Exec("UPDATE packages SET stock = stock - 1 WHERE id = $1 AND stock > 0", req.PackageID)
		if err != nil {
			tx.Rollback()
			return c.Status(500).JSON(fiber.Map{"error": "Stok güncellenemedi"})
		}
		rowsAffected, _ := res.RowsAffected()
		if rowsAffected == 0 {
			tx.Rollback()
			return c.Status(409).JSON(fiber.Map{"error": "Üzgünüz, ürün tükendi!"})
		}

		orderID := uuid.New().String()
		_, dbErr := tx.Exec(`
			INSERT INTO orders (id, package_id, user_id, buyer_email, status, created_at,
				total_price, package_name, package_image_url)
			SELECT $1, $2, $3, $4, $5, $6,
				discounted_price, name, image_url
			FROM packages WHERE id = $2`,
			orderID, req.PackageID, userEmail, userEmail, "Sipariş Alındı", time.Now())
		if dbErr != nil {
			tx.Rollback()
			log.Println("❌ Sipariş oluşturma hatası:", dbErr)
			return c.Status(500).JSON(fiber.Map{"error": "Sipariş kaydedilemedi"})
		}

		if commitErr := tx.Commit(); commitErr != nil {
			return c.Status(500).JSON(fiber.Map{"error": "Sipariş tamamlanamadı"})
		}

		go sendFCMToEmail(db, userEmail,
			"Siparişiniz Alındı! 🎉",
			"Siparişiniz işleme alındı. Ödemeyi teslimatta yapabilirsiniz.",
		)

		log.Printf("🛒 Yeni sipariş: %s → paket: %s, alıcı: %s", orderID, req.PackageID, userEmail)
		return c.Status(201).JSON(fiber.Map{"status": "success", "order_id": orderID})
	})

	// API Rotası 10: QR Okuma & Teslimat Onayı (Kantin Tarafı)
	app.Post("/api/v1/delivery/confirm", rateLimiter(10, time.Minute), jwtMiddleware, func(c *fiber.Ctx) error {
		var req struct {
			OrderID string `json:"order_id"`
		}

		if err := c.BodyParser(&req); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Geçersiz İstek Formatı"})
		}

		if req.OrderID == "" {
			return c.Status(400).JSON(fiber.Map{"error": "order_id eksik veya boş"})
		}

		// Veritabanında siparişin durumunu çekelim
		var status string
		err := db.QueryRow("SELECT status FROM orders WHERE id = $1", req.OrderID).Scan(&status)
		if err != nil {
			if err.Error() == "sql: no rows in result set" {
				return c.Status(404).JSON(fiber.Map{"error": "Sipariş bulunamadı"})
			}
			return c.Status(500).JSON(fiber.Map{"error": "Veritabanı okuma hatası"})
		}

		// Durum kontrolü
		if status == "Teslim Edildi" {
			return c.Status(400).JSON(fiber.Map{"error": "Bu paket zaten teslim alınmış/kullanılmış!"})
		}
		if status != "Ödendi" && status != "Teslim Edilmeyi Bekliyor" {
			return c.Status(400).JSON(fiber.Map{"error": "Bu sipariş teslim için hazır değil (Durum: " + status + ")"})
		}

		// Sipariş Ödenmiş, şimdi "Teslim Edildi" yapıyoruz
		_, updateErr := db.Exec("UPDATE orders SET status = 'Teslim Edildi', updated_at = NOW() WHERE id = $1", req.OrderID)
		if updateErr != nil {
			log.Println("❌ Teslimat güncelleme hatası:", updateErr)
			return c.Status(500).JSON(fiber.Map{"error": "Teslimat onaylanırken sistemsel bir hata oluştu"})
		}

		// (V2) Sipariş Durum Geçmişini Kaydet
		db.Exec("INSERT INTO order_status_history (order_id, status, changed_at) VALUES ($1, $2, $3)", req.OrderID, "Teslim Edildi", time.Now())

		// Sadakat puanı: teslimatta +10 puan + FCM bildirim
		var buyerEmail string
		if err := db.QueryRow("SELECT buyer_email FROM orders WHERE id = $1", req.OrderID).Scan(&buyerEmail); err == nil && buyerEmail != "" {
			db.Exec("UPDATE users SET loyalty_points = COALESCE(loyalty_points, 0) + 10 WHERE email = $1", buyerEmail)
			go sendFCMToEmail(db, buyerEmail,
				"Siparişiniz Teslim Edildi! ✅",
				"Afiyet olsun! +10 sadakat puanı kazandınız.",
			)
		}

		log.Printf("✅ Sipariş başarıyla teslim edildi. Sipariş ID: %s", req.OrderID)
		return c.Status(200).JSON(fiber.Map{"message": "Sipariş başarıyla teslim edildi ✅", "order_id": req.OrderID})
	})

	// API Rotası 10.1: Sipariş İptal Et (Kullanıcı — sadece "Ödendi" durumunda ve 5 dakika içinde)
	app.Post("/api/v1/orders/:id/cancel", jwtMiddleware, func(c *fiber.Ctx) error {
		orderID := c.Params("id")
		if orderID == "" {
			return c.Status(400).JSON(fiber.Map{"error": "Sipariş ID gerekli"})
		}

		var status string
		var createdAt time.Time
		err := db.QueryRow("SELECT status, created_at FROM orders WHERE id = $1", orderID).Scan(&status, &createdAt)
		if err != nil {
			return c.Status(404).JSON(fiber.Map{"error": "Sipariş bulunamadı"})
		}

		if status != "Ödendi" {
			return c.Status(400).JSON(fiber.Map{"error": "Yalnızca 'Ödendi' durumundaki siparişler iptal edilebilir"})
		}

		if time.Since(createdAt) > 5*time.Minute {
			return c.Status(400).JSON(fiber.Map{"error": "İptal süresi doldu (5 dakika geçti)"})
		}

		// Stoğu geri yükle
		var packageID string
		db.QueryRow("SELECT package_id FROM orders WHERE id = $1", orderID).Scan(&packageID)
		if packageID != "" {
			db.Exec("UPDATE packages SET stock = stock + 1 WHERE id = $1", packageID)
		}

		// Durumu güncelle
		_, updateErr := db.Exec("UPDATE orders SET status = 'İptal Edildi', updated_at = NOW() WHERE id = $1", orderID)
		if updateErr != nil {
			return c.Status(500).JSON(fiber.Map{"error": "İptal işlemi gerçekleştirilemedi"})
		}

		db.Exec("INSERT INTO order_status_history (order_id, status, changed_at) VALUES ($1, $2, $3)", orderID, "İptal Edildi", time.Now())

		// FCM: alıcıya iptal bildirimi
		var cancelBuyerEmail string
		if err := db.QueryRow("SELECT buyer_email FROM orders WHERE id = $1", orderID).Scan(&cancelBuyerEmail); err == nil && cancelBuyerEmail != "" {
			go sendFCMToEmail(db, cancelBuyerEmail,
				"Siparişiniz İptal Edildi 🚫",
				"Siparişiniz başarıyla iptal edildi. Ödemeniz iade sürecine alındı.",
			)
		}

		log.Printf("🚫 Sipariş iptal edildi: %s", orderID)
		return c.JSON(fiber.Map{"message": "Sipariş iptal edildi", "order_id": orderID})
	})

	// API Rotası 12: İşletme Sipariş Durumunu Güncelle (PATCH)
	app.Patch("/api/v1/orders/:id/status", jwtMiddleware, func(c *fiber.Ctx) error {
		orderID := c.Params("id")
		if orderID == "" {
			return c.Status(400).JSON(fiber.Map{"error": "Sipariş ID gerekli"})
		}

		type StatusRequest struct {
			Status string `json:"status"`
		}
		var req StatusRequest
		if err := c.BodyParser(&req); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Geçersiz istek"})
		}

		log.Printf("📋 Durum güncelleme isteği: order=%s, yeni_durum='%s' (len=%d)", orderID, req.Status, len(req.Status))

		// İzin verilen durumlar (switch ile — encoding problemi olmaz)
		switch req.Status {
		case "Hazırlanıyor", "Teslim Edilmeyi Bekliyor":
			// geçerli, devam et
		default:
			log.Printf("❌ Geçersiz durum reddedildi: '%s'", req.Status)
			return c.Status(400).JSON(fiber.Map{"error": "Geçersiz durum: " + req.Status})
		}

		// Mevcut durumu kontrol et (Teslim Edilmiş veya İptal Edilmiş siparişi geri çevirmeyi engelle)
		var currentStatus string
		err := db.QueryRow("SELECT status FROM orders WHERE id = $1", orderID).Scan(&currentStatus)
		if err != nil {
			return c.Status(404).JSON(fiber.Map{"error": "Sipariş bulunamadı"})
		}
		if currentStatus == "Teslim Edildi" {
			return c.Status(400).JSON(fiber.Map{"error": "Teslim edilmiş siparişin durumu değiştirilemez"})
		}
		if currentStatus == "İptal Edildi" {
			return c.Status(400).JSON(fiber.Map{"error": "İptal edilmiş siparişin durumu değiştirilemez"})
		}

		_, updateErr := db.Exec("UPDATE orders SET status = $1, updated_at = $3 WHERE id = $2", req.Status, orderID, time.Now())
		if updateErr != nil {
			log.Println("Durum güncelleme hatası:", updateErr)
			return c.Status(500).JSON(fiber.Map{"error": "Durum güncellenemedi"})
		}

		// (V2) Sipariş Durum Geçmişini Kaydet
		_, histErr := db.Exec("INSERT INTO order_status_history (order_id, status, changed_at) VALUES ($1, $2, $3)", orderID, req.Status, time.Now())
		if histErr != nil {
			log.Println("Durum geçmişi kaydetme hatası:", histErr)
		}

		// Push Bildirim: Hazır olduysa müşteriye bildir
		if req.Status == "Teslim Edilmeyi Bekliyor" {
			var buyerEmail string
			if err := db.QueryRow("SELECT buyer_email FROM orders WHERE id = $1", orderID).Scan(&buyerEmail); err == nil {
				go sendFCMToEmail(db, buyerEmail,
					"Siparişiniz Hazır! 🎉",
					"QR kodunuzu göstererek teslim alabilirsiniz.",
				)
			}
		} else if req.Status == "Hazırlanıyor" {
			var buyerEmail string
			if err := db.QueryRow("SELECT buyer_email FROM orders WHERE id = $1", orderID).Scan(&buyerEmail); err == nil {
				go sendFCMToEmail(db, buyerEmail,
					"Siparişiniz Hazırlanıyor 👨‍🍳",
					"Siparışiniz şu anda hazırlanıyor, kısa sürede hazır olacak!",
				)
			}
		}

		log.Printf("✅ Sipariş durumu güncellendi: %s → %s", orderID, req.Status)
		return c.JSON(fiber.Map{"message": "Durum güncellendi", "order_id": orderID, "status": req.Status})
	})

	// API Rotası 13: FCM Token Kayıt (Flutter'dan tek seferlik)
	app.Post("/api/v1/device-token", jwtMiddleware, func(c *fiber.Ctx) error {
		type TokenRequest struct {
			Email    string `json:"email"`
			FCMToken string `json:"fcm_token"`
		}
		var req TokenRequest
		if err := c.BodyParser(&req); err != nil || req.Email == "" || req.FCMToken == "" {
			return c.Status(400).JSON(fiber.Map{"error": "email ve fcm_token gerekli"})
		}
		_, err := db.Exec(`
			INSERT INTO device_tokens (user_email, fcm_token, updated_at)
			VALUES ($1, $2, $3)
			ON CONFLICT (user_email) DO UPDATE SET fcm_token = EXCLUDED.fcm_token, updated_at = EXCLUDED.updated_at`,
			req.Email, req.FCMToken, time.Now())
		if err != nil {
			log.Println("Token kaydetme hatası:", err)
			return c.Status(500).JSON(fiber.Map{"error": "Token kaydedilemedi"})
		}
		log.Printf("🔔 FCM token kaydedildi: %s", req.Email)
		return c.JSON(fiber.Map{"message": "Token kaydedildi"})
	})

	// API Rotası 14: İşletme İstatistikleri (Gelişmiş Raporlama)
	app.Get("/api/v1/business/stats", jwtMiddleware, func(c *fiber.Ctx) error {
		ownerEmail := c.Locals("user_email").(string)
		var businessID string
		if err := db.QueryRow("SELECT id FROM businesses WHERE owner_email = $1", ownerEmail).Scan(&businessID); err != nil {
			return c.Status(403).JSON(fiber.Map{"error": "Bu hesaba bağlı işletme bulunamadı"})
		}

		// 1. KPI'lar: Toplam Kazanç, Satılan Paket Sayısı
		var totalRevenue float64
		var totalSold int

		err := db.QueryRow(`
			SELECT COALESCE(SUM(p.discounted_price), 0), COUNT(o.id)
			FROM orders o
			JOIN packages p ON o.package_id = p.id
			WHERE o.status = 'Teslim Edildi' AND p.business_id = $1
		`, businessID).Scan(&totalRevenue, &totalSold)

		if err != nil {
			log.Println("KPI sorgu hatası:", err)
			return c.Status(500).JSON(fiber.Map{"error": "İstatistikler alınamadı"})
		}

		// Kurtarılan Gıda (her 1 paket = 0.5 kg varsayalım)
		savedFoodKg := float64(totalSold) * 0.5

		// 2. Haftalık Kazanç Grafiği (Son 7 Gün)
		// PostgreSQL'de generate_series veya basitçe son 7 günü gruplama
		rows, err := db.Query(`
			SELECT TO_CHAR(o.created_at, 'YYYY-MM-DD') as day, SUM(p.discounted_price) as revenue
			FROM orders o
			JOIN packages p ON o.package_id = p.id
			WHERE o.status = 'Teslim Edildi' AND o.created_at >= NOW() - INTERVAL '7 days' AND p.business_id = $1
			GROUP BY day
			ORDER BY day ASC
		`, businessID)
		if err != nil {
			log.Println("Haftalık kazanç sorgu hatası:", err)
			return c.Status(500).JSON(fiber.Map{"error": "Haftalık kazanç alınamadı"})
		}
		defer rows.Close()

		type DailyRevenue struct {
			Date    string  `json:"date"`
			Revenue float64 `json:"revenue"`
		}
		var weeklyRevenue []DailyRevenue
		for rows.Next() {
			var dr DailyRevenue
			if err := rows.Scan(&dr.Date, &dr.Revenue); err == nil {
				weeklyRevenue = append(weeklyRevenue, dr)
			}
		}

		// 3. En Çok Satılan Paketler (Top 5)
		topRows, err := db.Query(`
			SELECT p.name, COUNT(o.id) as sales
			FROM orders o
			JOIN packages p ON o.package_id = p.id
			WHERE o.status = 'Teslim Edildi' AND p.business_id = $1
			GROUP BY p.name
			ORDER BY sales DESC
			LIMIT 5
		`, businessID)
		if err != nil {
			log.Println("Popüler paket sorgu hatası:", err)
			return c.Status(500).JSON(fiber.Map{"error": "Popüler paketler alınamadı"})
		}
		defer topRows.Close()

		type TopPackage struct {
			Name  string `json:"name"`
			Sales int    `json:"sales"`
		}
		var topPackages []TopPackage
		for topRows.Next() {
			var tp TopPackage
			if err := topRows.Scan(&tp.Name, &tp.Sales); err == nil {
				topPackages = append(topPackages, tp)
			}
		}

		return c.JSON(fiber.Map{
			"kpis": fiber.Map{
				"totalRevenue": totalRevenue,
				"totalSold":    totalSold,
				"savedFoodKg":  savedFoodKg,
			},
			"weekly_revenue": weeklyRevenue,
			"top_packages":   topPackages,
		})
	})

	// API Rotası 11: Kullanıcının Siparişlerini Çekme (Flutter Siparişlerim UI Kullanır)
	app.Get("/api/v1/orders/me", jwtMiddleware, func(c *fiber.Ctx) error {
		// Kullanıcının emailini query param'dan al
		buyerEmail := c.Query("email")
		if buyerEmail == "" {
			return c.Status(400).JSON(fiber.Map{"error": "email parametresi gerekli"})
		}

		rows, err := db.Query(`
			SELECT o.id, o.package_id,
				COALESCE(o.package_name, p.name, o.package_id::text) AS display_name,
				o.status, o.created_at,
				COALESCE(p.business_id, '') AS business_id,
				COALESCE(o.total_price, p.discounted_price, 0) AS total_price,
				COALESCE(o.package_image_url, p.image_url, '') AS image_url,
				EXISTS(SELECT 1 FROM reviews r WHERE r.order_id = o.id) AS has_review
			FROM orders o
			LEFT JOIN packages p ON o.package_id = p.id
			WHERE o.buyer_email = $1
			ORDER BY o.created_at DESC
		`, buyerEmail)

		if err != nil {
			log.Println("Siparişleri çekerken hata:", err)
			return c.Status(500).JSON(fiber.Map{"error": "Siparişler getirilemedi"})
		}
		defer rows.Close()

		var orders []map[string]interface{}
		for rows.Next() {
			var id, packageID, displayName, status, businessId, imageUrl string
			var totalPrice float64
			var createdAt time.Time
			var hasReview bool
			if err := rows.Scan(&id, &packageID, &displayName, &status, &createdAt, &businessId, &totalPrice, &imageUrl, &hasReview); err != nil {
				continue
			}
			orders = append(orders, map[string]interface{}{
				"id":           id,
				"package_id":   packageID,
				"package_name": displayName,
				"status":       status,
				"created_at":   createdAt,
				"business_id":  businessId,
				"total_price":  totalPrice,
				"image_url":    imageUrl,
				"has_review":   hasReview,
			})
		}

		if orders == nil {
			orders = []map[string]interface{}{} // null gitmesini önle
		}

		return c.Status(200).JSON(orders)
	})

	// API Rotası 15: Yorum ve Puan (Reviews) Ekleme
	app.Post("/api/v1/reviews", rateLimiter(5, time.Minute), jwtMiddleware, func(c *fiber.Ctx) error {
		type ReviewRequest struct {
			OrderID    string `json:"order_id"`
			UserEmail  string `json:"user_email"`
			BusinessID string `json:"business_id"`
			Rating     int    `json:"rating"`
			Comment    string `json:"comment"`
		}
		var req ReviewRequest
		if err := c.BodyParser(&req); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Geçersiz İstek"})
		}

		// Duplicate prevention: bir işletme için tek yorum
		var existing int
		db.QueryRow("SELECT COUNT(*) FROM reviews WHERE user_email = $1 AND business_id = $2", req.UserEmail, req.BusinessID).Scan(&existing)
		if existing > 0 {
			return c.Status(409).JSON(fiber.Map{"error": "Bu işletmeyi zaten değerlendirdiniz"})
		}

		_, err := db.Exec(`INSERT INTO reviews (order_id, user_email, business_id, rating, comment, created_at)
			VALUES ($1, $2, $3, $4, $5, $6)`, req.OrderID, req.UserEmail, req.BusinessID, req.Rating, req.Comment, time.Now())
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": "Değerlendirme gönderilemedi"})
		}
		return c.Status(201).JSON(fiber.Map{"message": "Değerlendirme başarıyla alındı!"})
	})

	// API Rotası 16: Favori Dükkanlara Ekle
	app.Post("/api/v1/favorites", jwtMiddleware, func(c *fiber.Ctx) error {
		type FavReq struct {
			UserEmail    string `json:"user_email"`
			BusinessID   string `json:"business_id"`
			BusinessName string `json:"business_name"`
		}
		var req FavReq
		if err := c.BodyParser(&req); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Geçersiz İstek"})
		}
		_, err := db.Exec(`INSERT INTO favorite_shops (user_email, business_id, business_name, created_at) 
			VALUES ($1, $2, $3, $4)`, req.UserEmail, req.BusinessID, req.BusinessName, time.Now())
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": "Favorilere eklenirken hata"})
		}
		return c.Status(201).JSON(fiber.Map{"message": "Favorilere eklendi"})
	})

	// API Rotası 17: Favori Dükkanlardan Çıkar
	app.Delete("/api/v1/favorites", jwtMiddleware, func(c *fiber.Ctx) error {
		type FavReq struct {
			UserEmail    string `json:"user_email"`
			BusinessName string `json:"business_name"`
		}
		var req FavReq
		if err := c.BodyParser(&req); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Geçersiz İstek"})
		}
		_, err := db.Exec(`DELETE FROM favorite_shops WHERE user_email=$1 AND business_name=$2`, req.UserEmail, req.BusinessName)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": "Favorilerden çıkarılamadı"})
		}
		return c.Status(200).JSON(fiber.Map{"message": "Favorilerden çıkarıldı"})
	})

	// API Rotası 18: Kullanıcının Favorilerini Getir
	app.Get("/api/v1/favorites", jwtMiddleware, func(c *fiber.Ctx) error {
		email := c.Query("email")
		if email == "" {
			return c.Status(400).JSON(fiber.Map{"error": "email parametresi gerekli"})
		}
		rows, err := db.Query(`
			SELECT f.business_id, f.business_name,
			       COALESCE(b.address,'') as address,
			       COALESCE(b.latitude, 0) as latitude,
			       COALESCE(b.longitude, 0) as longitude,
			       COALESCE(b.logo_url,'') as logo_url,
			       COALESCE(b.category,'') as category
			FROM favorite_shops f
			LEFT JOIN businesses b ON f.business_id::text = b.id::text
			WHERE f.user_email=$1`, email)
		if err != nil {
			log.Println("Favoriler çekilemedi:", err)
			return c.Status(500).JSON(fiber.Map{"error": "Favoriler çekilemedi"})
		}
		defer rows.Close()

		favs := []map[string]interface{}{}
		for rows.Next() {
			var bId, bName, addr, logo, cat sql.NullString
			var lat, lon sql.NullFloat64
			if err := rows.Scan(&bId, &bName, &addr, &lat, &lon, &logo, &cat); err == nil {
				favs = append(favs, map[string]interface{}{
					"id":            bId.String,
					"business_id":   bId.String,
					"business_name": bName.String,
					"name":          bName.String,
					"address":       addr.String,
					"latitude":      lat.Float64,
					"longitude":     lon.Float64,
					"logo_url":      logo.String,
					"category":      cat.String,
				})
			}
		}
		if favs == nil {
			favs = []map[string]interface{}{}
		}
		return c.JSON(favs)
	})

	// API Rotası 19: İşletmenin Aldığı Yorumlar (Reviews)
	app.Get("/api/v1/business/reviews", jwtMiddleware, func(c *fiber.Ctx) error {
		ownerEmail := c.Locals("user_email").(string)
		var businessID string
		if err := db.QueryRow("SELECT id FROM businesses WHERE owner_email = $1", ownerEmail).Scan(&businessID); err != nil {
			return c.Status(403).JSON(fiber.Map{"error": "Bu hesaba bağlı işletme bulunamadı"})
		}

		rows, err := db.Query(`
			SELECT r.id, r.order_id, r.user_email, r.rating, r.comment, r.created_at
			FROM reviews r
			WHERE r.business_id = $1
			ORDER BY r.created_at DESC
		`, businessID)
		if err != nil {
			log.Println("Reviews sorgu hatası:", err)
			return c.Status(500).JSON(fiber.Map{"error": "Değerlendirmeler getirilemedi"})
		}
		defer rows.Close()

		type Review struct {
			ID        int       `json:"id"`
			OrderID   string    `json:"order_id"`
			UserEmail string    `json:"user_email"`
			Rating    int       `json:"rating"`
			Comment   string    `json:"comment"`
			CreatedAt time.Time `json:"created_at"`
		}

		reviews := []Review{}
		for rows.Next() {
			var r Review
			var comment sql.NullString
			if err := rows.Scan(&r.ID, &r.OrderID, &r.UserEmail, &r.Rating, &comment, &r.CreatedAt); err != nil {
				continue
			}
			if comment.Valid {
				r.Comment = comment.String
			}
			reviews = append(reviews, r)
		}

		// Ortalama puan hesapla
		var avgRating float64
		db.QueryRow("SELECT COALESCE(AVG(rating), 0) FROM reviews WHERE business_id = $1", businessID).Scan(&avgRating)

		return c.JSON(fiber.Map{
			"reviews":    reviews,
			"avg_rating": avgRating,
			"count":      len(reviews),
		})
	})

	// API Rotası 20: Kullanıcı Profili (Sadakat Puanı vs.)
	app.Get("/api/v1/users/profile", jwtMiddleware, func(c *fiber.Ctx) error {
		email := c.Query("email")
		if email == "" {
			return c.Status(400).JSON(fiber.Map{"error": "email parametresi gerekli"})
		}

		var fullName, phone string
		var loyalty int
		err := db.QueryRow("SELECT COALESCE(full_name,''), COALESCE(phone_number,''), COALESCE(loyalty_points,0) FROM users WHERE email = $1", email).Scan(&fullName, &phone, &loyalty)
		if err != nil {
			fullName, phone, loyalty = "", "", 0
		}

		// Tamamlanan sipariş sayısı + kurtarılan gıda hesabı
		var totalOrders, completedOrders int
		db.QueryRow("SELECT COUNT(*) FROM orders WHERE buyer_email = $1", email).Scan(&totalOrders)
		db.QueryRow("SELECT COUNT(*) FROM orders WHERE buyer_email = $1 AND status = 'Teslim Edildi'", email).Scan(&completedOrders)
		savedFoodKg := float64(completedOrders) * 0.5

		return c.JSON(fiber.Map{
			"email":            email,
			"full_name":        fullName,
			"phone_number":     phone,
			"loyalty_points":   loyalty,
			"total_orders":     totalOrders,
			"completed_orders": completedOrders,
			"saved_food_kg":    savedFoodKg,
		})
	})

	// API Rotası 21: Kullanıcı Profili Güncelle
	app.Patch("/api/v1/users/profile", jwtMiddleware, func(c *fiber.Ctx) error {
		var body struct {
			Email       string `json:"email"`
			FullName    string `json:"full_name"`
			PhoneNumber string `json:"phone_number"`
		}
		if err := c.BodyParser(&body); err != nil || body.Email == "" {
			return c.Status(400).JSON(fiber.Map{"error": "geçersiz istek"})
		}
		_, err := db.Exec(
			`INSERT INTO users (email, full_name, phone_number)
			 VALUES ($1, $2, $3)
			 ON CONFLICT (email) DO UPDATE
			   SET full_name = EXCLUDED.full_name,
			       phone_number = EXCLUDED.phone_number`,
			body.Email, body.FullName, body.PhoneNumber,
		)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": "güncelleme başarısız"})
		}
		return c.JSON(fiber.Map{"message": "profil güncellendi"})
	})

	// API Rotası: İşletme Paket Düzenle (PATCH)
	app.Patch("/api/v1/business/packages/:id", jwtMiddleware, func(c *fiber.Ctx) error {
		ownerEmail := c.Locals("user_email").(string)
		packageID := c.Params("id")

		// Paketin bu işletmeye ait olduğunu doğrula
		var count int
		err := db.QueryRow(`
			SELECT COUNT(*) FROM packages p
			JOIN businesses b ON p.business_id = b.id
			WHERE p.id = $1 AND b.owner_email = $2`, packageID, ownerEmail).Scan(&count)
		if err != nil || count == 0 {
			return c.Status(403).JSON(fiber.Map{"error": "Bu paketi düzenleme yetkiniz yok"})
		}

		var body struct {
			Name            string   `json:"name"`
			Description     string   `json:"description"`
			OriginalPrice   float64  `json:"original_price"`
			DiscountedPrice float64  `json:"discounted_price"`
			Stock           int      `json:"stock"`
			IsActive        bool     `json:"is_active"`
			ImageUrl        string   `json:"image_url"`
			Category        string   `json:"category"`
			Tags            []string `json:"tags"`
			AvailableFrom   string   `json:"available_from"`
			AvailableUntil  string   `json:"available_until"`
		}
		if err := c.BodyParser(&body); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Geçersiz veri formatı"})
		}

		tagsJSON := "[]"
		if len(body.Tags) > 0 {
			b, _ := json.Marshal(body.Tags)
			tagsJSON = string(b)
		}

		if body.Category == "" {
			body.Category = "Diğer"
		}

		availFrom := sql.NullString{String: body.AvailableFrom, Valid: body.AvailableFrom != ""}
		availUntil := sql.NullString{String: body.AvailableUntil, Valid: body.AvailableUntil != ""}

		_, err = db.Exec(`
			UPDATE packages SET
				name = $1, description = $2, original_price = $3, discounted_price = $4,
				stock = $5, is_active = $6, image_url = $7, category = $8, tags = $9,
				available_from = $10, available_until = $11
			WHERE id = $12`,
			body.Name, body.Description, body.OriginalPrice, body.DiscountedPrice,
			body.Stock, body.IsActive, body.ImageUrl, body.Category, tagsJSON,
			availFrom, availUntil, packageID)
		if err != nil {
			log.Println("Paket güncelleme hatası:", err)
			return c.Status(500).JSON(fiber.Map{"error": "Paket güncellenemedi"})
		}

		return c.JSON(fiber.Map{"message": "Paket güncellendi"})
	})

	// API Rotası: İşletme Paket Sil (DELETE)
	app.Delete("/api/v1/business/packages/:id", jwtMiddleware, func(c *fiber.Ctx) error {
		ownerEmail := c.Locals("user_email").(string)
		packageID := c.Params("id")

		// Paketin bu işletmeye ait olduğunu doğrula
		var count int
		err := db.QueryRow(`
			SELECT COUNT(*) FROM packages p
			JOIN businesses b ON p.business_id = b.id
			WHERE p.id = $1 AND b.owner_email = $2`, packageID, ownerEmail).Scan(&count)
		if err != nil || count == 0 {
			return c.Status(403).JSON(fiber.Map{"error": "Bu paketi silme yetkiniz yok"})
		}

		_, err = db.Exec("DELETE FROM packages WHERE id = $1", packageID)
		if err != nil {
			log.Println("Paket silme hatası:", err)
			return c.Status(500).JSON(fiber.Map{"error": "Paket silinemedi"})
		}
		return c.Status(200).JSON(fiber.Map{"message": "Paket silindi"})
	})

	// API Rotası: İşletme Ara (Herkese Açık)
	app.Get("/api/v1/businesses/search", func(c *fiber.Ctx) error {
		q := c.Query("q")
		rows, err := db.Query(`
			SELECT id, COALESCE(name,'') as name, COALESCE(address,'') as address,
			       latitude, longitude,
			       COALESCE(logo_url,'') as logo_url, COALESCE(category,'') as category
			FROM businesses
			WHERE is_active = true AND ($1 = '' OR name ILIKE '%' || $1 || '%')
			ORDER BY name
			LIMIT 30`, q)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": "İşletmeler getirilemedi"})
		}
		defer rows.Close()

		type BizResult struct {
			ID        string  `json:"id"`
			Name      string  `json:"name"`
			Address   string  `json:"address"`
			Latitude  float64 `json:"latitude"`
			Longitude float64 `json:"longitude"`
			LogoUrl   string  `json:"logo_url"`
			Category  string  `json:"category"`
		}
		results := []BizResult{}
		for rows.Next() {
			var b BizResult
			if err := rows.Scan(&b.ID, &b.Name, &b.Address, &b.Latitude, &b.Longitude, &b.LogoUrl, &b.Category); err != nil {
				continue
			}
			results = append(results, b)
		}
		return c.JSON(results)
	})

	// API Rotası: İşletme Yorumları (Herkese Açık)
	app.Get("/api/v1/businesses/:id/reviews", func(c *fiber.Ctx) error {
		bizID := c.Params("id")
		rows, err := db.Query(`
			SELECT user_email, rating, COALESCE(comment,'') as comment, created_at
			FROM reviews
			WHERE business_id = $1
			ORDER BY created_at DESC
			LIMIT 20`, bizID)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": "Yorumlar getirilemedi"})
		}
		defer rows.Close()

		type ReviewItem struct {
			UserEmail string    `json:"user_email"`
			Rating    int       `json:"rating"`
			Comment   string    `json:"comment"`
			CreatedAt time.Time `json:"created_at"`
		}
		items := []ReviewItem{}
		for rows.Next() {
			var r ReviewItem
			if err := rows.Scan(&r.UserEmail, &r.Rating, &r.Comment, &r.CreatedAt); err != nil {
				continue
			}
			items = append(items, r)
		}

		var avgRating float64
		var count int
		db.QueryRow("SELECT COALESCE(AVG(rating),0), COUNT(*) FROM reviews WHERE business_id = $1", bizID).Scan(&avgRating, &count)

		return c.JSON(fiber.Map{
			"reviews":    items,
			"avg_rating": avgRating,
			"count":      count,
		})
	})

	// 5. Sunucuyu Dinlemeye Başla
	log.Println("Yemekhane API 3001 portunda başarıyla çalışıyor! 🚀")
	log.Fatal(app.Listen(":3001"))
}
