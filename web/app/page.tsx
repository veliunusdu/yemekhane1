"use client";

import { useState, useEffect } from "react";
import Link from "next/link";

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

  const fetchOrders = async () => {
    try {
      const res = await fetch("http://localhost:3001/api/v1/business/orders");
      if (res.ok) {
        const data = await res.json();
        setOrders(data || []);
      }
    } catch (error) {
      console.error("Siparişler çekilemedi:", error);
    }
  };

  useEffect(() => {
    fetchOrders();
    // Her 30 saniyede bir siparişleri otomatik yenile
    const interval = setInterval(fetchOrders, 30000);
    return () => clearInterval(interval);
  }, []);

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
        {
          method: "POST",
          body: uploadData,
        },
      );

      const data = await res.json();
      console.log("☁️ Cloudinary Yanıtı:", data);

      if (data.secure_url) {
        setImageUrl(data.secure_url);
        console.log("✅ Fotoğraf Linki Alındı:", data.secure_url);
      } else {
        console.error("❌ Cloudinary Hata Mesajı:", data.error?.message);
        alert("Yükleme başarısız: " + (data.error?.message || "Bilinmeyen hata"));
      }
    } catch (error) {
      console.error("❌ Bağlantı Hatası:", error);
      alert("Cloudinary'ye bağlanılamadı!");
    } finally {
      setIsUploading(false);
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setStatus("⏳ Yükleniyor...");

    console.log("🚀 API'ye Gönderilen Veri:", {
      ...formData,
      image_url: imageUrl,
    });

    try {
      // Go API'mize istek atıyoruz (Port 3001)
      const res = await fetch(
        "http://localhost:3001/api/v1/business/packages",
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            name: formData.name,
            description: formData.description,
            original_price: parseFloat(formData.original_price),
            discounted_price: parseFloat(formData.discounted_price),
            stock: parseInt(formData.stock),
            image_url: imageUrl,
          }),
        },
      );

      if (res.ok) {
        setStatus("✅ Paket başarıyla eklendi!");
        // Formu temizle
        setFormData({
          name: "",
          description: "",
          original_price: "",
          discounted_price: "",
          stock: "",
        });
        setImageUrl("");
        // Yeni bir paket eklendiğinde (stok güncellenebilir vb.) listeyi yenileyelim
        fetchOrders();
      } else {
        setStatus("❌ Bir hata oluştu.");
      }
    } catch (error) {
      setStatus(
        "❌ API'ye bağlanılamadı. Go Backend (3001 portu) çalışıyor mu?",
      );
    }
  };

  const handleChange = (
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>,
  ) => {
    setFormData({ ...formData, [e.target.name]: e.target.value });
  };

  return (
    <main className="min-h-screen bg-gray-50 flex items-center justify-center p-4">
      <div className="bg-white p-8 rounded-xl shadow-lg w-full max-w-md">
        <div className="flex justify-between items-center mb-6">
          <h1 className="text-2xl font-bold text-gray-800">
            İşletme Paneli
          </h1>
          <Link 
            href="/scanner" 
            className="bg-orange-500 hover:bg-orange-600 text-white px-4 py-2 rounded-lg font-bold text-sm transition-colors flex items-center gap-2"
          >
            📸 QR Oku
          </Link>
        </div>
        <p className="text-gray-500 mb-6 text-sm">
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
            placeholder="Paket Açıklaması (Örn: Sabah üretiminden kalan taze poğaçalar)"
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
          <div className="mb-4">
            <label className="block text-gray-700 text-sm font-bold mb-2">
              Paket Fotoğrafı
            </label>
            <input
              type="file"
              accept="image/*"
              onChange={handleImageUpload}
              className="block w-full text-sm text-gray-500 file:mr-4 file:py-2 file:px-4 file:rounded file:border-0 file:text-sm file:font-semibold file:bg-orange-50 file:text-orange-700 hover:file:bg-orange-100 cursor-pointer"
            />

            {/* Yükleniyor Uyarısı */}
            {isUploading && (
              <p className="text-sm text-blue-500 mt-2">
                ⏳ Fotoğraf yükleniyor, lütfen bekleyin...
              </p>
            )}

            {/* Yüklendiyse Önizleme Göster */}
            {imageUrl && (
              <div className="mt-4">
                <p className="text-sm text-green-600 mb-1">✅ Fotoğraf Hazır!</p>
                <img
                  src={imageUrl}
                  alt="Önizleme"
                  className="w-32 h-32 object-cover rounded shadow"
                />
              </div>
            )}
          </div>

          <button
            type="submit"
            disabled={isUploading}
            className={`p-3 rounded-lg font-bold transition-colors mt-2 text-white ${
              isUploading
                ? "bg-gray-400 cursor-not-allowed"
                : "bg-blue-600 hover:bg-blue-700"
            }`}
          >
            {isUploading ? "Fotoğraf Yükleniyor..." : "Paketi Yayınla"}
          </button>
        </form>

        {status && (
          <p className="mt-4 text-center font-semibold text-gray-700">
            {status}
          </p>
        )}

        <div className="mt-12 border-t pt-8">
          <div className="flex justify-between items-center mb-4">
            <h2 className="text-xl font-bold text-gray-800">
              Gelen Siparişler
            </h2>
            <button
              onClick={fetchOrders}
              className="text-sm text-blue-600 hover:underline"
            >
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
                    <p className="font-bold text-gray-800">
                      {order.package_name}
                    </p>
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
