"use client";

import { useState, useEffect } from "react";
import Link from "next/link";

const API_URL = "http://localhost:3001";

export default function Home() {
  const [formData, setFormData] = useState({
    name: "",
    description: "",
    original_price: "",
    discounted_price: "",
    stock: "",
  });
  const [status, setStatus] = useState("");
  const [orders, setOrders] = useState<any[]>([]);
  const [imageUrl, setImageUrl] = useState<string>("");
  const [isUploading, setIsUploading] = useState(false);

  // --- Dükkan Konum State ---
  const [businessName, setBusinessName] = useState("");
  const [locationLat, setLocationLat] = useState<string>("");
  const [locationLon, setLocationLon] = useState<string>("");
  const [locationStatus, setLocationStatus] = useState("");
  const [isLocating, setIsLocating] = useState(false);
  const [isSavingLocation, setIsSavingLocation] = useState(false);

  // Sayfa yüklendiğinde kayıtlı konumu çek
  useEffect(() => {
    fetchOrders();
    fetchSavedLocation();
    const interval = setInterval(fetchOrders, 30000);
    return () => clearInterval(interval);
  }, []);

  const fetchSavedLocation = async () => {
    try {
      const res = await fetch(`${API_URL}/api/v1/business/location`);
      if (res.ok) {
        const data = await res.json();
        if (data.latitude !== 0 || data.longitude !== 0) {
          setLocationLat(data.latitude.toString());
          setLocationLon(data.longitude.toString());
          setBusinessName(data.name || "");
          setLocationStatus("✅ Kayıtlı konum yüklendi.");
        }
      }
    } catch (e) {
      console.error("Konum çekilemedi:", e);
    }
  };

  // Tarayıcı GPS'ini kullan
  const handleGetCurrentLocation = () => {
    if (!navigator.geolocation) {
      setLocationStatus("❌ Tarayıcınız konum desteklemiyor.");
      return;
    }
    setIsLocating(true);
    setLocationStatus("📡 Konum alınıyor...");
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setLocationLat(pos.coords.latitude.toFixed(6));
        setLocationLon(pos.coords.longitude.toFixed(6));
        setLocationStatus("✅ Konum alındı! Kaydetmek için 'Konumu Kaydet' butonuna tıklayın.");
        setIsLocating(false);
      },
      (err) => {
        setLocationStatus("❌ Konum alınamadı: " + err.message);
        setIsLocating(false);
      },
      { timeout: 10000 }
    );
  };

  // Konumu backend'e kaydet
  const handleSaveLocation = async () => {
    const lat = parseFloat(locationLat);
    const lon = parseFloat(locationLon);
    if (isNaN(lat) || isNaN(lon) || lat === 0 || lon === 0) {
      setLocationStatus("❌ Geçerli koordinat girin.");
      return;
    }
    setIsSavingLocation(true);
    try {
      const res = await fetch(`${API_URL}/api/v1/business/location`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: businessName, latitude: lat, longitude: lon }),
      });
      if (res.ok) {
        setLocationStatus("✅ Konum kaydedildi! Artık tüm paketler bu konumu kullanacak.");
      } else {
        const err = await res.json();
        setLocationStatus("❌ Hata: " + (err.error || "Bilinmeyen hata"));
      }
    } catch (e) {
      setLocationStatus("❌ API'ye bağlanılamadı.");
    } finally {
      setIsSavingLocation(false);
    }
  };

  const fetchOrders = async () => {
    try {
      const res = await fetch(`${API_URL}/api/v1/business/orders`);
      if (res.ok) {
        const data = await res.json();
        setOrders(data || []);
      }
    } catch (error) {
      console.error("Siparişler çekilemedi:", error);
    }
  };

  const handleImageUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setIsUploading(true);
    console.log("☁️ Cloudinary'ye Yükleme Başlıyor...", file.name);

    const uploadData = new FormData();
    uploadData.append("file", file);
    uploadData.append("upload_preset", "yemekhane-preset");

    try {
      const res = await fetch(
        "https://api.cloudinary.com/v1_1/ddymvjxhw/image/upload",
        { method: "POST", body: uploadData }
      );
      const data = await res.json();
      if (data.secure_url) {
        setImageUrl(data.secure_url);
      } else {
        alert("Yükleme başarısız: " + (data.error?.message || "Bilinmeyen hata"));
      }
    } catch (error) {
      alert("Cloudinary'ye bağlanılamadı!");
    } finally {
      setIsUploading(false);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setStatus("⏳ Yükleniyor...");

    try {
      const res = await fetch(`${API_URL}/api/v1/business/packages`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: formData.name,
          description: formData.description,
          original_price: parseFloat(formData.original_price),
          discounted_price: parseFloat(formData.discounted_price),
          stock: parseInt(formData.stock),
          image_url: imageUrl,
          business_name: businessName,
          // Koordinatlar backend'de işletme profil tablosundan otomatik doldurulur
          // Ama yine de göndererek override edilebilir hale getiriyoruz
          latitude: locationLat ? parseFloat(locationLat) : 0,
          longitude: locationLon ? parseFloat(locationLon) : 0,
        }),
      });

      if (res.ok) {
        setStatus("✅ Paket başarıyla eklendi!");
        setFormData({ name: "", description: "", original_price: "", discounted_price: "", stock: "" });
        setImageUrl("");
        fetchOrders();
      } else {
        setStatus("❌ Bir hata oluştu.");
      }
    } catch (error) {
      setStatus("❌ API'ye bağlanılamadı. Go Backend (3001 portu) çalışıyor mu?");
    }
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    setFormData({ ...formData, [e.target.name]: e.target.value });
  };

  return (
    <main className="min-h-screen bg-gray-50 flex items-center justify-center p-4">
      <div className="bg-white p-8 rounded-xl shadow-lg w-full max-w-md">
        {/* Başlık */}
        <div className="flex justify-between items-center mb-6">
          <h1 className="text-2xl font-bold text-gray-800">İşletme Paneli</h1>
          <Link
            href="/scanner"
            className="bg-orange-500 hover:bg-orange-600 text-white px-4 py-2 rounded-lg font-bold text-sm transition-colors flex items-center gap-2"
          >
            📸 QR Oku
          </Link>
        </div>

        {/* ─── Dükkan Konumu Bölümü ─── */}
        <div className="bg-orange-50 border border-orange-200 rounded-xl p-4 mb-6">
          <h2 className="text-base font-bold text-orange-700 mb-3 flex items-center gap-2">
            📍 Dükkan Konumum
          </h2>
          <p className="text-xs text-orange-500 mb-3">
            Konumunuzu bir kez kaydedin — tüm paketlerde otomatik kullanılır.
          </p>

          <input
            type="text"
            placeholder="Dükkan / İşletme Adı"
            value={businessName}
            onChange={(e) => setBusinessName(e.target.value)}
            className="border p-2 rounded-lg text-black text-sm w-full mb-2 focus:ring-2 focus:ring-orange-400 outline-none"
          />

          <div className="flex gap-2 mb-2">
            <input
              type="number"
              step="0.000001"
              placeholder="Enlem (Lat)"
              value={locationLat}
              onChange={(e) => setLocationLat(e.target.value)}
              className="border p-2 rounded-lg text-black text-sm w-full focus:ring-2 focus:ring-orange-400 outline-none"
            />
            <input
              type="number"
              step="0.000001"
              placeholder="Boylam (Lon)"
              value={locationLon}
              onChange={(e) => setLocationLon(e.target.value)}
              className="border p-2 rounded-lg text-black text-sm w-full focus:ring-2 focus:ring-orange-400 outline-none"
            />
          </div>

          <div className="flex gap-2">
            <button
              type="button"
              onClick={handleGetCurrentLocation}
              disabled={isLocating}
              className="flex-1 bg-white border border-orange-400 text-orange-600 hover:bg-orange-50 text-sm font-semibold py-2 rounded-lg transition-colors disabled:opacity-50"
            >
              {isLocating ? "📡 Alınıyor..." : "📡 Mevcut Konumumu Kullan"}
            </button>
            <button
              type="button"
              onClick={handleSaveLocation}
              disabled={isSavingLocation || !locationLat || !locationLon}
              className="flex-1 bg-orange-500 hover:bg-orange-600 text-white text-sm font-semibold py-2 rounded-lg transition-colors disabled:opacity-50"
            >
              {isSavingLocation ? "Kaydediliyor..." : "💾 Konumu Kaydet"}
            </button>
          </div>

          {locationStatus && (
            <p className="text-xs mt-2 text-orange-700 font-medium">{locationStatus}</p>
          )}
        </div>

        {/* ─── Paket Ekleme Formu ─── */}
        <p className="text-gray-500 mb-4 text-sm">
          Satışa sunmak istediğiniz indirimli paketi ekleyin.
        </p>

        <form onSubmit={handleSubmit} className="flex flex-col gap-4">
          <input
            required
            name="name"
            value={formData.name}
            onChange={handleChange}
            placeholder="Paket Adı (Örn: 3'lü Karışık Poğaça)"
            className="border p-3 rounded-lg text-black focus:ring-2 focus:ring-blue-500 outline-none"
          />
          <textarea
            required
            name="description"
            value={formData.description}
            onChange={handleChange}
            placeholder="Paket Açıklaması"
            className="border p-3 rounded-lg text-black focus:ring-2 focus:ring-blue-500 outline-none resize-none h-24"
          />

          <div className="flex gap-4">
            <input
              required
              name="original_price"
              type="number"
              step="0.01"
              value={formData.original_price}
              onChange={handleChange}
              placeholder="Normal Fiyat (₺)"
              className="border p-3 rounded-lg text-black w-full focus:ring-2 focus:ring-blue-500 outline-none"
            />
            <input
              required
              name="discounted_price"
              type="number"
              step="0.01"
              value={formData.discounted_price}
              onChange={handleChange}
              placeholder="İndirimli (₺)"
              className="border p-3 rounded-lg text-black w-full focus:ring-2 focus:ring-blue-500 outline-none"
            />
          </div>

          <input
            required
            name="stock"
            type="number"
            value={formData.stock}
            onChange={handleChange}
            placeholder="Kaç Adet Var? (Stok)"
            className="border p-3 rounded-lg text-black focus:ring-2 focus:ring-blue-500 outline-none"
          />

          {/* Fotoğraf Yükleme */}
          <div className="mb-2">
            <label className="block text-gray-700 text-sm font-bold mb-2">
              Paket Fotoğrafı
            </label>
            <input
              type="file"
              accept="image/*"
              onChange={handleImageUpload}
              className="block w-full text-sm text-gray-500 file:mr-4 file:py-2 file:px-4 file:rounded file:border-0 file:text-sm file:font-semibold file:bg-orange-50 file:text-orange-700 hover:file:bg-orange-100 cursor-pointer"
            />
            {isUploading && (
              <p className="text-sm text-blue-500 mt-2">⏳ Fotoğraf yükleniyor...</p>
            )}
            {imageUrl && (
              <div className="mt-4">
                <p className="text-sm text-green-600 mb-1">✅ Fotoğraf Hazır!</p>
                <img src={imageUrl} alt="Önizleme" className="w-32 h-32 object-cover rounded shadow" />
              </div>
            )}
          </div>

          {/* Konum özet bilgisi */}
          {locationLat && locationLon && (
            <div className="text-xs text-gray-500 bg-gray-50 rounded-lg p-2 flex items-center gap-1">
              <span>📍</span>
              <span>Konum: {parseFloat(locationLat).toFixed(4)}, {parseFloat(locationLon).toFixed(4)}</span>
            </div>
          )}

          <button
            type="submit"
            disabled={isUploading}
            className={`p-3 rounded-lg font-bold transition-colors mt-2 text-white ${
              isUploading ? "bg-gray-400 cursor-not-allowed" : "bg-blue-600 hover:bg-blue-700"
            }`}
          >
            {isUploading ? "Fotoğraf Yükleniyor..." : "Paketi Yayınla"}
          </button>
        </form>

        {status && (
          <p className="mt-4 text-center font-semibold text-gray-700">{status}</p>
        )}

        {/* ─── Gelen Siparişler ─── */}
        <div className="mt-12 border-t pt-8">
          <div className="flex justify-between items-center mb-4">
            <h2 className="text-xl font-bold text-gray-800">Gelen Siparişler</h2>
            <button onClick={fetchOrders} className="text-sm text-blue-600 hover:underline">
              Yenile 🔄
            </button>
          </div>

          <div className="flex flex-col gap-3">
            {orders.length === 0 ? (
              <p className="text-gray-400 text-sm">Henüz sipariş gelmedi.</p>
            ) : (
              orders.map((order: any) => (
                <div
                  key={order.id}
                  className="bg-gray-100 p-4 rounded-lg flex justify-between items-center border-l-4 border-green-500"
                >
                  <div>
                    <p className="font-bold text-gray-800">{order.package_name}</p>
                    <p className="text-xs text-gray-500">
                      {new Date(order.created_at).toLocaleTimeString()}
                    </p>
                  </div>
                  <span className="bg-green-100 text-green-700 px-3 py-1 rounded-full text-xs font-bold uppercase">
                    {order.status}
                  </span>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </main>
  );
}
