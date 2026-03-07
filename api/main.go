package main

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"time"

	iyzipay "github.com/JspBack/iyzipay-go"
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/google/uuid"
	"github.com/joho/godotenv"
	_ "github.com/lib/pq"
	"github.com/redis/go-redis/v9"
	"github.com/resend/resend-go/v2"

	// Kendi modül adınla değiştirmeyi unutma!
	"github.com/veliunusdu/yemekhane1/internal/domain"
)

var ctx = context.Background()
var redisClient *redis.Client

// Resend ile E-posta Gönder
func sendSuccessEmail(targetEmail string, paymentID string) {
	apiKey := os.Getenv("RESEND_API_KEY")
	if apiKey == "" {
		log.Println("UYARI: RESEND_API_KEY bulunamadı!")
		return
	}

	client := resend.NewClient(apiKey)

	params := &resend.SendEmailRequest{
		From:    "onboarding@resend.dev",
		To:      []string{targetEmail},
		Subject: "Siparişiniz Alındı! 🍲",
		Html:    "<strong>Siparişiniz başarıyla alındı.</strong><br>Ödeme ID: " + paymentID + "<br>Afiyet olsun!",
	}

	sent, err := client.Emails.Send(params)
	if err != nil {
		log.Println("E-posta gönderim hatası:", err)
		return
	}
	log.Println("E-posta başarıyla gönderildi! ID:", sent.Id)
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

	// 1. Veritabanına Bağlan (Environment variable'dan al)
	connStr := os.Getenv("DATABASE_URL")
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal("Veritabanına bağlanılamadı:", err)
	}
	defer db.Close()

	// 2. Tabloyu Otomatik Oluştur (Sadece MVP için tabloyu elle açmamak adına buraya ekliyoruz)
	createTableQuery := `
	CREATE TABLE IF NOT EXISTS packages (
		id UUID PRIMARY KEY,
		business_id VARCHAR(50),
		name VARCHAR(255),
		description TEXT,
		original_price DECIMAL(10,2),
		discounted_price DECIMAL(10,2),
		stock INT,
		is_active BOOLEAN,
		image_url TEXT,
		created_at TIMESTAMP
	);`
	if _, err := db.Exec(createTableQuery); err != nil {
		log.Fatal("Tablo oluşturulamadı:", err)
	}

	// Siparişler Tablosunu Oluştur
	createOrderTableQuery := `
	CREATE TABLE IF NOT EXISTS orders (
		id UUID PRIMARY KEY,
		package_id UUID,
		user_id VARCHAR(50),
		buyer_email VARCHAR(255),
		status VARCHAR(20),
		created_at TIMESTAMP
	);`
	db.Exec(createOrderTableQuery)
	// Gelecekteki veya mevcut migration'lar için safe bir ALTER:
	db.Exec("ALTER TABLE orders ADD COLUMN IF NOT EXISTS buyer_email VARCHAR(255);")

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
	app.Use(cors.New(cors.Config{
		AllowOrigins: "*",
		AllowMethods: "GET,POST,HEAD,PUT,DELETE,PATCH,OPTIONS",
		AllowHeaders: "Origin, Content-Type, Accept, Authorization",
	}))

	// 4. API Rotasını Tanımla (İşletme Paket Ekler)
	app.Post("/api/v1/business/packages", func(c *fiber.Ctx) error {
		var dto domain.CreatePackageDTO

		// Gelen JSON verisini DTO'ya dönüştür
		if err := c.BodyParser(&dto); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Geçersiz veri formatı"})
		}

		log.Printf("📦 Yeni Paket Geldi: %+v\n", dto)

		// Veritabanı modelini (Entity) oluştur
		pkg := domain.Package{
			ID:              uuid.New().String(),
			BusinessID:      "business-123", // Şimdilik MVP için sabit bir işletme hesabı
			Name:            dto.Name,
			Description:     dto.Description,
			OriginalPrice:   dto.OriginalPrice,
			DiscountedPrice: dto.DiscountedPrice,
			Stock:           dto.Stock,
			IsActive:        true,
			ImageUrl:        dto.ImageUrl,
			CreatedAt:       time.Now(),
		}

		// Veritabanına Kaydet
		insertQuery := `
			INSERT INTO packages (id, business_id, name, description, original_price, discounted_price, stock, is_active, created_at, image_url)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`

		_, err := db.Exec(insertQuery, pkg.ID, pkg.BusinessID, pkg.Name, pkg.Description, pkg.OriginalPrice, pkg.DiscountedPrice, pkg.Stock, pkg.IsActive, pkg.CreatedAt, pkg.ImageUrl)
		if err != nil {
			log.Println("Kaydetme hatası:", err)
			return c.Status(500).JSON(fiber.Map{"error": "Paket kaydedilemedi"})
		}

		// Başarılı yanıt dön (201 Created)
		return c.Status(201).JSON(pkg)
	})

	// API Rotası 2: Tüm Aktif Paketleri Listele (Kullanıcılar İçin)
	app.Get("/api/v1/packages", func(c *fiber.Ctx) error {
		rows, err := db.Query("SELECT id, business_id, name, description, original_price, discounted_price, stock, is_active, image_url FROM packages WHERE is_active = true")
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": "Paketler getirilemedi"})
		}
		defer rows.Close()

		packages := []domain.Package{}
		for rows.Next() {
			var p domain.Package
			if err := rows.Scan(&p.ID, &p.BusinessID, &p.Name, &p.Description, &p.OriginalPrice, &p.DiscountedPrice, &p.Stock, &p.IsActive, &p.ImageUrl); err != nil {
				continue
			}
			packages = append(packages, p)
		}

		// Listeyi JSON olarak geri dön
		return c.JSON(packages)
	})

	// API Rotası 3: Sipariş Ver (Kullanıcı İçin)
	app.Post("/api/v1/orders", func(c *fiber.Ctx) error {
		type OrderRequest struct {
			PackageID  string `json:"package_id"`
			BuyerEmail string `json:"buyer_email"`
		}
		var req OrderRequest
		if err := c.BodyParser(&req); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Geçersiz istek"})
		}

		if req.BuyerEmail == "" {
			req.BuyerEmail = "bilinmeyen@kullanici.com" // Fallback in case old client hits API
		}

		// 1. Stok kontrolü yap ve stoğu 1 azalt
		res, err := db.Exec("UPDATE packages SET stock = stock - 1 WHERE id = $1 AND stock > 0", req.PackageID)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": "Stok güncellenemedi"})
		}

		rowsAffected, _ := res.RowsAffected()
		if rowsAffected == 0 {
			return c.Status(400).JSON(fiber.Map{"error": "Üzgünüz, ürün tükendi!"})
		}

		// 2. Sipariş kaydı oluştur
		orderID := uuid.New().String()
		_, err = db.Exec("INSERT INTO orders (id, package_id, user_id, buyer_email, status, created_at) VALUES ($1, $2, $3, $4, $5, $6)",
			orderID, req.PackageID, "user-456", req.BuyerEmail, "Hazırlanıyor", time.Now())

		return c.Status(201).JSON(fiber.Map{"message": "Sipariş başarıyla alındı!", "order_id": orderID})
	})

	// API Rotası 4: İşletme İçin Gelen Siparişleri Listele
	app.Get("/api/v1/business/orders", func(c *fiber.Ctx) error {
		// Bu sorgu hem sipariş bilgilerini hem de hangi paketin satıldığını getirir (JOIN)
		query := `
			SELECT o.id, p.name, o.buyer_email, o.status, o.created_at 
			FROM orders o 
			JOIN packages p ON o.package_id = p.id 
			ORDER BY o.created_at DESC`

		rows, err := db.Query(query)
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

		req.Header.Set("apikey", os.Getenv("SUPABASE_ANON_KEY"))
		req.Header.Set("Content-Type", "application/json")

		client := &http.Client{}
		resp, err := client.Do(req)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": "Supabase bağlantı hatası"})
		}
		defer resp.Body.Close()

		// 3. Yanıtı oku ve geri dön
		var result map[string]interface{}
		bodyBytes, _ := io.ReadAll(resp.Body)
		json.Unmarshal(bodyBytes, &result)

		log.Printf("Supabase Response [%d]: %s", resp.StatusCode, string(bodyBytes))

		return c.Status(resp.StatusCode).JSON(result)
	})

	// API Rotası 6: Kayıt Ol (Supabase Auth Signup Proxy)
	app.Post("/api/v1/auth/signup", func(c *fiber.Ctx) error {
		body := c.Body()
		supabaseURL := os.Getenv("SUPABASE_URL") + "/auth/v1/signup"
		req, _ := http.NewRequest("POST", supabaseURL, bytes.NewBuffer(body))

		req.Header.Set("apikey", os.Getenv("SUPABASE_ANON_KEY"))
		req.Header.Set("Content-Type", "application/json")

		client := &http.Client{}
		resp, err := client.Do(req)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": "Supabase bağlantı hatası"})
		}
		defer resp.Body.Close()

		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
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

		req.Header.Set("apikey", os.Getenv("SUPABASE_ANON_KEY"))
		req.Header.Set("Content-Type", "application/json")

		client := &http.Client{}
		resp, err := client.Do(req)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": "Supabase bağlantı hatası"})
		}
		defer resp.Body.Close()

		var result map[string]interface{}
		json.NewDecoder(resp.Body).Decode(&result)
		return c.Status(resp.StatusCode).JSON(result)
	})

	// API Rotası 8: Iyzico Ödeme Başlat (Checkout Form)
	app.Post("/api/v1/payments/initialize", func(c *fiber.Ctx) error {
		type PaymentRequest struct {
			PackageID string `json:"package_id"`
			Price     string `json:"price"`
			Email     string `json:"email"`
			Name      string `json:"name"`
			Surname   string `json:"surname"`
		}
		var reqData PaymentRequest
		if err := c.BodyParser(&reqData); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Geçersiz istek"})
		}

		// 1. Iyzico İstemci Ayarları (.env'den çekiliyor)
		apiKey := os.Getenv("IYZICO_API_KEY")
		secretKey := os.Getenv("IYZICO_SECRET_KEY")

		client, err := iyzipay.New(apiKey, secretKey)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": "Iyzico client oluşturulamadı"})
		}

		// 2. Ödeme Formu İsteği Oluştur
		req := &iyzipay.CFRequest{
			InitPWIRequest: iyzipay.InitPWIRequest{
				Locale:              "tr",
				ConversationID:      uuid.New().String(),
				Price:               reqData.Price,
				BasketId:            "B" + uuid.New().String()[0:8],
				PaymentGroup:        "PRODUCT",
				CallbackUrl:         "https://example.com/yemekhane_callback", // Unique URL to intercept in WebView's onPageStarted (since Android ignores POSTs in onNavigationRequest)
				Currency:            "TRY",
				PaidPrice:           reqData.Price, // İndirim yoksa Price ile aynı
				EnabledInstallments: []string{"1", "2", "3", "6", "9"},
				Buyer: iyzipay.Buyer{
					ID:                  "BY123",
					Name:                reqData.Name,
					Surname:             reqData.Surname,
					GSMNumber:           "+905350000000",
					Email:               reqData.Email,
					IdentityNumber:      "74300864791",
					RegistrationAddress: "Nidakule Göztepe, Merdivenköy Mah. Bora Sok. No:1",
					IP:                  "85.34.78.112",
					City:                "Istanbul",
					Country:             "Turkey",
				},
				ShippingAddress: iyzipay.ShippingAddress{
					ContactName: reqData.Name + " " + reqData.Surname,
					City:        "Istanbul",
					Country:     "Turkey",
					Address:     "Nidakule Göztepe, Merdivenköy Mah. Bora Sok. No:1",
				},
				BillingAddress: iyzipay.BillingAddress{
					ContactName: reqData.Name + " " + reqData.Surname,
					City:        "Istanbul",
					Country:     "Turkey",
					Address:     "Nidakule Göztepe, Merdivenköy Mah. Bora Sok. No:1",
				},
				BasketItems: []iyzipay.BasketItem{
					{
						ID:        reqData.PackageID,
						Name:      "Yemek Paketi",
						Category1: "Food",
						ItemType:  "PHYSICAL",
						Price:     reqData.Price,
					},
				},
			},
			// PaymentSource kaldırıldı — sandbox'ta kısıtlamalara yol açıyordu
		}

		// 6. Iyzico'ya İsteği Gönder
		reqBytes, _ := json.MarshalIndent(req, "", "  ")
		log.Printf("Iyzico'ya giden istek: %s", string(reqBytes))

		res, err := client.CheckoutFormPaymentRequest(req, "popup") // popup = WebView'da tam ekran açılır, iframe gibi CSP kısıtlaması yok
		if err != nil {
			log.Printf("❌ Iyzico API isteği hata fırlattı: %v", err)
			return c.Status(500).JSON(fiber.Map{"error": "Iyzico bağlantı hatası: " + err.Error()})
		}

		resBytes, _ := json.Marshal(res)
		log.Printf("Iyzico'dan dönen cevap: %s", string(resBytes))

		if res.Status != "success" {
			log.Printf("❌ Iyzico başlatma başarısız: %s", string(resBytes))
			// we don't have ErrorMessage field exposed safely, let's just send the status string
			return c.Status(500).JSON(fiber.Map{"error": "Iyzico: " + res.Status})
		}

		return c.JSON(res)
	})
	// API Rotası 8.4: Iyzico Gerçek Webhook Callback (Iyzico 3D Onayı Sonrası Kendi Sunucularından İstek Atar)
	app.Post("/api/v1/payments/iyzico-callback", func(c *fiber.Ctx) error {
		// Iyzico'nun POST isteği attığı yer burası. 200 OK dönmezsek 3D işlemi iptal olur (mdStatus:0)
		log.Println("⚡ Iyzico'dan Webhook Geldi: Payment Callback!")
		// İçeriği okuyup detayları görebiliriz:
		log.Println("Webhook Body:", string(c.Body()))

		// Iyzico'ya "aldım tamam" diyoruz, işlemi onaylıyor
		return c.SendStatus(200)
	})

	// API Rotası 8.5: Iyzico Ödeme Durumu Manuel Kontrol (Mobil WebView kapandığında çağrılır)
	app.Post("/api/v1/payments/check", func(c *fiber.Ctx) error {
		type CheckRequest struct {
			Token      string `json:"token"`
			PackageID  string `json:"package_id"`
			BuyerEmail string `json:"buyer_email"`
		}
		var req CheckRequest
		if err := c.BodyParser(&req); err != nil {
			log.Printf("❌ BodyParser Hatası: %v", err)
			return c.Status(400).JSON(fiber.Map{"error": "Geçersiz istek"})
		}

		if req.Token == "" {
			log.Println("❌ Token bulunamadı isteğin içinde")
			return c.Status(400).JSON(fiber.Map{"error": "Token bulunamadı"})
		}

		apiKey := os.Getenv("IYZICO_API_KEY")
		secretKey := os.Getenv("IYZICO_SECRET_KEY")

		client, err := iyzipay.New(apiKey, secretKey)
		if err != nil {
			log.Printf("❌ Iyzico client oluşturma hatası: %v", err)
			return c.Status(500).JSON(fiber.Map{"error": "Iyzico client oluşturulamadı"})
		}

		inquiryReq := &iyzipay.CFInquiryRequest{
			Locale:         "tr",
			Token:          req.Token,
			ConversationId: "123456789",
		}

		inquiryResp, err := client.CheckoutFormPaymentInquiryRequest(inquiryReq)
		if err != nil {
			log.Printf("❌ Iyzico CheckoutFormPaymentInquiryRequest Hatası: %v", err)
			// Return 400 instead of 500 when inquiry fails (often due to expired tokens)
			return c.Status(400).JSON(fiber.Map{"error": "Ödeme sorgulanırken hata oluştu!"})
		}

		rawInquiry, _ := json.Marshal(inquiryResp)
		log.Printf("🔍 Iyzico Inquiry Status: %s, PaymentStatus: %s\n RAW DUMP: %s", inquiryResp.Status, inquiryResp.PaymentStatus, string(rawInquiry))

		if inquiryResp.Status == "success" && inquiryResp.PaymentStatus == "SUCCESS" {
			log.Printf("✅ Ödeme Manuel Teyit Edildi! PaymentID: %s\n", inquiryResp.PaymentID)

			if req.PackageID != "" && req.BuyerEmail != "" {
				// 1. Stok Düş
				res, err := db.Exec("UPDATE packages SET stock = stock - 1 WHERE id = $1 AND stock > 0", req.PackageID)
				if err != nil {
					log.Printf("❌ Veritabanı stok güncelleme hatası: %v", err)
				} else {
					rowsAffected, _ := res.RowsAffected()
					if rowsAffected == 0 {
						log.Printf("⚠️ Uyarı: Ödeme yapıldı ama stokta kalmamış! PackageID: %s", req.PackageID)
					}
				}

				// 2. Sipariş Oluştur (Artık doğrudan Ödendi olarak yazıyoruz)
				orderID := uuid.New().String()
				_, dbErr := db.Exec("INSERT INTO orders (id, package_id, user_id, buyer_email, status, created_at) VALUES ($1, $2, $3, $4, $5, $6)",
					orderID, req.PackageID, "user-456", req.BuyerEmail, "Ödendi", time.Now())
				if dbErr != nil {
					log.Println("❌ Sipariş oluşturma hatası:", dbErr)
				}
			} else {
				log.Println("⚠️ Uyarı: Ödeme başarılı ancak PackageID veya BuyerEmail eksik olduğu için sipariş kaydedilemedi.")
			}

			// E-posta gönderimi SADECE başarılı olduğunda çalışmalı
			log.Println("✉️ Resend e-posta gönderimi tetikleniyor...")
			sendSuccessEmail(req.BuyerEmail, inquiryResp.PaymentID)

			return c.JSON(fiber.Map{"status": "success", "message": "Ödeme başarılı! Sipariş onaylandı."})
		}

		return c.Status(400).JSON(fiber.Map{"status": "error", "message": "Ödeme başarısız veya tamamlanmadı."})
	})

	// API Rotası 9: Iyzico Ödeme Sonucu Callback
	app.Post("/api/v1/payments/callback", func(c *fiber.Ctx) error {
		// Iyzico POST isteği ile form verisi olarak 'token' gönderir
		token := c.FormValue("token")
		if token == "" {
			return c.Status(400).JSON(fiber.Map{"error": "Token bulunamadı"})
		}

		apiKey := os.Getenv("IYZICO_API_KEY")
		secretKey := os.Getenv("IYZICO_SECRET_KEY")

		client, err := iyzipay.New(apiKey, secretKey)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": "Iyzico client oluşturulamadı"})
		}

		// Ödeme sonucunu doğrulamak (Inquiry) için istek oluştur
		inquiryReq := &iyzipay.CFInquiryRequest{
			Locale:         "tr",
			Token:          token,
			ConversationId: "123456789", // İsteğe bağlı, güvenlik ve loglama için eklenebilir
		}

		inquiryResp, err := client.CheckoutFormPaymentInquiryRequest(inquiryReq)
		if err != nil {
			log.Println("Ödeme sorgulama hatası:", err)
			return c.Redirect("http://localhost:3000/payment/error", 302)
		}

		// Iyzico'dan dönen Status ve PaymentStatus'u kontrol et
		if inquiryResp.Status == "success" && inquiryResp.PaymentStatus == "SUCCESS" {
			log.Printf("🎉 Ödeme Başarılı! PaymentID: %s\n", inquiryResp.PaymentID)

			// 1. Veritabanında sipariş durumunu "Ödendi" olarak güncelle
			// BasketId içindeki sipariş ID'sini çekmeye çalışıyoruz (Bxxxxxxxx formatında yapmıştık)
			// Gerçek senaryoda ConversationId veya basketId içine order_id gömeriz.
			// Şimdilik en son bekleyen siparişi güncelle (MVP Mantığı)
			_, dbErr := db.Exec("UPDATE orders SET status = 'Ödendi' WHERE status = 'Hazırlanıyor' AND user_id = 'user-456'")
			if dbErr != nil {
				log.Println("❌ Veritabanı güncelleme hatası:", dbErr)
			}

			// 2. Kullanıcıya E-posta Gönder (Resend)
			// Iyzico inquiry response bu SDK'da Buyer bilgisini içermiyor.
			// Gerçek senaryoda ConversationId ile DB'den çekilir.
			targetEmail := "veliunusdu@gmail.com" // Şimdilik geliştirme amaçlı sabit
			sendSuccessEmail(targetEmail, inquiryResp.PaymentID)

			// Mobil uygulama WebView'ine "başarılı" mesajı gönderen bir URL'e yönlendir
			return c.Redirect("https://app.yemekhane.com/payment/success", 302)
		}

		log.Printf("❌ Ödeme Başarısız veya İptal Edildi! Status: %s\n", inquiryResp.Status)
		return c.Redirect("https://app.yemekhane.com/payment/error", 302)
	})

	// 5. Sunucuyu Dinlemeye Başla
	log.Println("Yemekhane API 3001 portunda başarıyla çalışıyor! 🚀")
	log.Fatal(app.Listen(":3001"))
}
