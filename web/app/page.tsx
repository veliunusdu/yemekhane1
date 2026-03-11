"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import Link from "next/link";
import { supabase } from "../lib/supabaseClient";

const API_URL = "http://localhost:3001";

type Order = {
  id: string;
  package_name: string;
  buyer_email: string;
  status: string;
  created_at: string;
};

export default function Home() {
  const [formData, setFormData] = useState({
    name: "",
    description: "",
    original_price: "",
    discounted_price: "",
    stock: "",
  });
  const [status, setStatus] = useState("");
  const [orders, setOrders] = useState<Order[]>([]);
  const [imageUrl, setImageUrl] = useState<string>("");
  const [isUploading, setIsUploading] = useState(false);
  const [updatingOrderId, setUpdatingOrderId] = useState<string | null>(null);

  // --- Dükkan Konum State ---
  const [businessName, setBusinessName] = useState("");
  const [locationLat, setLocationLat] = useState<string>("");
  const [locationLon, setLocationLon] = useState<string>("");
  const [locationStatus, setLocationStatus] = useState("");
  const [isLocating, setIsLocating] = useState(false);
  const [isSavingLocation, setIsSavingLocation] = useState(false);

  // --- Realtime Bildirim State ---
  const [newOrderAlert, setNewOrderAlert] = useState<string | null>(null);
  const alertTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Sesli bildirim (Web Audio API)
  const playDing = useCallback(() => {
    try {
      const AudioCtx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      const ctx = new AudioCtx();

      const osc1 = ctx.createOscillator();
      const gain1 = ctx.createGain();
      osc1.type = "sine";
      osc1.frequency.setValueAtTime(1046.5, ctx.currentTime);
      gain1.gain.setValueAtTime(0.5, ctx.currentTime);
      gain1.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.4);
      osc1.connect(gain1);
      gain1.connect(ctx.destination);
      osc1.start(ctx.currentTime);
      osc1.stop(ctx.currentTime + 0.4);

      const osc2 = ctx.createOscillator();
      const gain2 = ctx.createGain();
      osc2.type = "sine";
      osc2.frequency.setValueAtTime(880, ctx.currentTime + 0.2);
      gain2.gain.setValueAtTime(0.4, ctx.currentTime + 0.2);
      gain2.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.6);
      osc2.connect(gain2);
      gain2.connect(ctx.destination);
      osc2.start(ctx.currentTime + 0.2);
      osc2.stop(ctx.currentTime + 0.6);
    } catch {
      // ses çalınamadıysa sessizce geç
    }
  }, []);

  const triggerNewOrderAlert = useCallback(() => {
    playDing();
    setNewOrderAlert("🔔 Yeni Sipariş Geldi!");
    if (alertTimerRef.current) clearTimeout(alertTimerRef.current);
    alertTimerRef.current = setTimeout(() => setNewOrderAlert(null), 5000);
  }, [playDing]);

  const fetchOrders = useCallback(async () => {
    try {
      const res = await fetch(`${API_URL}/api/v1/business/orders`);
      if (res.ok) {
        const data = await res.json();
        setOrders(data || []);
      }
    } catch {
      // sessizce geç
    }
  }, []);

  // Sipariş durumunu güncelle (İşletme Paneli Aksiyonu)
  const updateOrderStatus = async (orderId: string, newStatus: string) => {
    setUpdatingOrderId(orderId);
    try {
      const res = await fetch(`${API_URL}/api/v1/orders/${orderId}/status`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ status: newStatus }),
      });
      if (res.ok) {
        // Optimistik UI güncellemesi
        setOrders((prev) =>
          prev.map((o) => (o.id === orderId ? { ...o, status: newStatus } : o))
        );
      } else {
        const err = await res.json();
        alert("Hata: " + (err.error || "Durum güncellenemedi"));
      }
    } catch {
      alert("API'ye bağlanılamadı.");
    } finally {
      setUpdatingOrderId(null);
    }
  };

  const fetchSavedLocation = useCallback(async () => {
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
    } catch {
      // sessizce geç
    }
  }, []);

  useEffect(() => {
    fetchOrders();
    fetchSavedLocation();

    const channel = supabase
      .channel("business-orders-realtime")
      .on(
        "postgres_changes",
        { event: "INSERT", schema: "public", table: "orders" },
        () => {
          fetchOrders();
          triggerNewOrderAlert();
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
      if (alertTimerRef.current) clearTimeout(alertTimerRef.current);
    };
  }, [fetchOrders, fetchSavedLocation, triggerNewOrderAlert]);

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
        setLocationStatus("✅ Konum kaydedildi!");
      } else {
        const err = await res.json();
        setLocationStatus("❌ Hata: " + (err.error || "Bilinmeyen hata"));
      }
    } catch {
      setLocationStatus("❌ API'ye bağlanılamadı.");
    } finally {
      setIsSavingLocation(false);
    }
  };

  const handleImageUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setIsUploading(true);
    const uploadData = new FormData();
    uploadData.append("file", file);
    uploadData.append("upload_preset", "yemekhane-preset");
    try {
      const res = await fetch("https://api.cloudinary.com/v1_1/ddymvjxhw/image/upload", {
        method: "POST",
        body: uploadData,
      });
      const data = await res.json();
      if (data.secure_url) {
        setImageUrl(data.secure_url);
      } else {
        alert("Yükleme başarısız: " + (data.error?.message || "Bilinmeyen hata"));
      }
    } catch {
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
    } catch {
      setStatus("❌ API'ye bağlanılamadı. Go Backend (3001 portu) çalışıyor mu?");
    }
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    setFormData({ ...formData, [e.target.name]: e.target.value });
  };

  return (
    <main className="min-h-screen bg-gray-50 flex items-center justify-center p-4">

      {/* ─── Yeni Sipariş Banner ─── */}
      {newOrderAlert && (
        <div
          className="fixed top-4 left-1/2 -translate-x-1/2 z-50 flex items-center gap-3 bg-green-600 text-white px-6 py-4 rounded-2xl shadow-2xl animate-bounce cursor-pointer"
          onClick={() => setNewOrderAlert(null)}
        >
          <span className="text-2xl">🔔</span>
          <div>
            <p className="font-bold text-base leading-tight">{newOrderAlert}</p>
            <p className="text-xs text-green-100">Sayfayı yenilemenize gerek yok!</p>
          </div>
          <span className="ml-2 text-green-200 text-lg">✕</span>
        </div>
      )}

      <div className="bg-white p-8 rounded-xl shadow-lg w-full max-w-md">
        {/* Başlık */}
        <div className="flex justify-between items-center mb-6">
          <div>
            <h1 className="text-2xl font-bold text-gray-800">İşletme Paneli</h1>
            <div className="flex items-center gap-1 mt-1">
              <span className="inline-block w-2 h-2 rounded-full bg-green-500 animate-pulse"></span>
              <span className="text-xs text-green-600 font-medium">Canlı Bağlantı Aktif</span>
            </div>
          </div>
          <Link
            href="/scanner"
            className="bg-orange-500 hover:bg-orange-600 text-white px-4 py-2 rounded-lg font-bold text-sm transition-colors flex items-center gap-2"
          >
            📸 QR Oku
          </Link>
        </div>

        {/* ─── Dükkan Konumu ─── */}
        <div className="bg-orange-50 border border-orange-200 rounded-xl p-4 mb-6">
          <h2 className="text-base font-bold text-orange-700 mb-3 flex items-center gap-2">📍 Dükkan Konumum</h2>
          <p className="text-xs text-orange-500 mb-3">Konumunuzu bir kez kaydedin — tüm paketlerde otomatik kullanılır.</p>
          <input
            type="text"
            placeholder="Dükkan / İşletme Adı"
            value={businessName}
            onChange={(e) => setBusinessName(e.target.value)}
            className="border p-2 rounded-lg text-black text-sm w-full mb-2 focus:ring-2 focus:ring-orange-400 outline-none"
          />
          <div className="flex gap-2 mb-2">
            <input type="number" step="0.000001" placeholder="Enlem (Lat)" value={locationLat}
              onChange={(e) => setLocationLat(e.target.value)}
              className="border p-2 rounded-lg text-black text-sm w-full focus:ring-2 focus:ring-orange-400 outline-none" />
            <input type="number" step="0.000001" placeholder="Boylam (Lon)" value={locationLon}
              onChange={(e) => setLocationLon(e.target.value)}
              className="border p-2 rounded-lg text-black text-sm w-full focus:ring-2 focus:ring-orange-400 outline-none" />
          </div>
          <div className="flex gap-2">
            <button type="button" onClick={handleGetCurrentLocation} disabled={isLocating}
              className="flex-1 bg-white border border-orange-400 text-orange-600 hover:bg-orange-50 text-sm font-semibold py-2 rounded-lg transition-colors disabled:opacity-50">
              {isLocating ? "📡 Alınıyor..." : "📡 Mevcut Konumumu Kullan"}
            </button>
            <button type="button" onClick={handleSaveLocation} disabled={isSavingLocation || !locationLat || !locationLon}
              className="flex-1 bg-orange-500 hover:bg-orange-600 text-white text-sm font-semibold py-2 rounded-lg transition-colors disabled:opacity-50">
              {isSavingLocation ? "Kaydediliyor..." : "💾 Konumu Kaydet"}
            </button>
          </div>
          {locationStatus && <p className="text-xs mt-2 text-orange-700 font-medium">{locationStatus}</p>}
        </div>

        {/* ─── Paket Ekleme Formu ─── */}
        <p className="text-gray-500 mb-4 text-sm">Satışa sunmak istediğiniz indirimli paketi ekleyin.</p>
        <form onSubmit={handleSubmit} className="flex flex-col gap-4">
          <input required name="name" value={formData.name} onChange={handleChange}
            placeholder="Paket Adı (Örn: 3'lü Karışık Poğaça)"
            className="border p-3 rounded-lg text-black focus:ring-2 focus:ring-blue-500 outline-none" />
          <textarea required name="description" value={formData.description} onChange={handleChange}
            placeholder="Paket Açıklaması"
            className="border p-3 rounded-lg text-black focus:ring-2 focus:ring-blue-500 outline-none resize-none h-24" />
          <div className="flex gap-4">
            <input required name="original_price" type="number" step="0.01" value={formData.original_price}
              onChange={handleChange} placeholder="Normal Fiyat (₺)"
              className="border p-3 rounded-lg text-black w-full focus:ring-2 focus:ring-blue-500 outline-none" />
            <input required name="discounted_price" type="number" step="0.01" value={formData.discounted_price}
              onChange={handleChange} placeholder="İndirimli (₺)"
              className="border p-3 rounded-lg text-black w-full focus:ring-2 focus:ring-blue-500 outline-none" />
          </div>
          <input required name="stock" type="number" value={formData.stock} onChange={handleChange}
            placeholder="Kaç Adet Var? (Stok)"
            className="border p-3 rounded-lg text-black focus:ring-2 focus:ring-blue-500 outline-none" />
          <div className="mb-2">
            <label className="block text-gray-700 text-sm font-bold mb-2">Paket Fotoğrafı</label>
            <input type="file" accept="image/*" onChange={handleImageUpload}
              className="block w-full text-sm text-gray-500 file:mr-4 file:py-2 file:px-4 file:rounded file:border-0 file:text-sm file:font-semibold file:bg-orange-50 file:text-orange-700 hover:file:bg-orange-100 cursor-pointer" />
            {isUploading && <p className="text-sm text-blue-500 mt-2">⏳ Fotoğraf yükleniyor...</p>}
            {imageUrl && (
              <div className="mt-4">
                <p className="text-sm text-green-600 mb-1">✅ Fotoğraf Hazır!</p>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={imageUrl} alt="Önizleme" className="w-32 h-32 object-cover rounded shadow" />
              </div>
            )}
          </div>
          {locationLat && locationLon && (
            <div className="text-xs text-gray-500 bg-gray-50 rounded-lg p-2 flex items-center gap-1">
              <span>📍</span>
              <span>Konum: {parseFloat(locationLat).toFixed(4)}, {parseFloat(locationLon).toFixed(4)}</span>
            </div>
          )}
          <button type="submit" disabled={isUploading}
            className={`p-3 rounded-lg font-bold transition-colors mt-2 text-white ${isUploading ? "bg-gray-400 cursor-not-allowed" : "bg-blue-600 hover:bg-blue-700"}`}>
            {isUploading ? "Fotoğraf Yükleniyor..." : "Paketi Yayınla"}
          </button>
        </form>

        {status && <p className="mt-4 text-center font-semibold text-gray-700">{status}</p>}

        {/* ─── Gelen Siparişler ─── */}
        <div className="mt-12 border-t pt-8">
          <div className="flex justify-between items-center mb-4">
            <div>
              <h2 className="text-xl font-bold text-gray-800">Gelen Siparişler</h2>
              <p className="text-xs text-gray-400 mt-0.5">Yeni siparişler otomatik görünür</p>
            </div>
            <button onClick={fetchOrders} className="text-sm text-blue-600 hover:underline">Yenile 🔄</button>
          </div>

          <div className="flex flex-col gap-3">
            {orders.length === 0 ? (
              <p className="text-gray-400 text-sm">Henüz sipariş gelmedi.</p>
            ) : (
              orders.map((order) => {
                const isUpdating = updatingOrderId === order.id;
                return (
                  <div
                    key={order.id}
                    className={`bg-white border rounded-xl p-4 shadow-sm ${
                      order.status === "Teslim Edildi"
                        ? "border-gray-200 opacity-60"
                        : order.status === "Teslim Edilmeyi Bekliyor"
                        ? "border-l-4 border-purple-400"
                        : order.status === "Hazırlanıyor"
                        ? "border-l-4 border-orange-400"
                        : "border-l-4 border-green-400"
                    }`}
                  >
                    {/* Sipariş Bilgisi */}
                    <div className="flex justify-between items-start">
                      <div>
                        <p className="font-bold text-gray-800 text-sm">{order.package_name}</p>
                        <p className="text-xs text-gray-400 mt-0.5">
                          {new Date(order.created_at).toLocaleTimeString("tr-TR")} • {order.buyer_email}
                        </p>
                      </div>
                      <span className={`px-2.5 py-1 rounded-full text-xs font-bold shrink-0 ml-2 ${
                        order.status === "Teslim Edildi" ? "bg-gray-100 text-gray-500"
                          : order.status === "Teslim Edilmeyi Bekliyor" ? "bg-purple-100 text-purple-700"
                          : order.status === "Hazırlanıyor" ? "bg-orange-100 text-orange-700"
                          : "bg-green-100 text-green-700"
                      }`}>
                        {order.status}
                      </span>
                    </div>

                    {/* Aksiyon Butonları */}
                    {order.status !== "Teslim Edildi" && (
                      <div className="flex gap-2 mt-3">
                        {order.status === "Ödendi" && (
                          <button
                            disabled={isUpdating}
                            onClick={() => updateOrderStatus(order.id, "Hazırlanıyor")}
                            className="flex-1 bg-orange-500 hover:bg-orange-600 disabled:opacity-50 text-white text-xs font-bold py-2 px-3 rounded-lg transition-colors"
                          >
                            {isUpdating ? "⏳ Güncelleniyor..." : "👨‍🍳 Hazırlanmaya Başla"}
                          </button>
                        )}
                        {order.status === "Hazırlanıyor" && (
                          <button
                            disabled={isUpdating}
                            onClick={() => updateOrderStatus(order.id, "Teslim Edilmeyi Bekliyor")}
                            className="flex-1 bg-purple-600 hover:bg-purple-700 disabled:opacity-50 text-white text-xs font-bold py-2 px-3 rounded-lg transition-colors"
                          >
                            {isUpdating ? "⏳ Güncelleniyor..." : "🚀 Hazır — Müşteriyi Bildir"}
                          </button>
                        )}
                        {order.status === "Teslim Edilmeyi Bekliyor" && (
                          <div className="flex-1 bg-purple-50 border border-purple-200 text-purple-600 text-xs font-semibold py-2 px-3 rounded-lg text-center">
                            📲 Müşteri QR kodu okutmayı bekliyor...
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                );
              })
            )}
          </div>
        </div>
      </div>
    </main>
  );
}
