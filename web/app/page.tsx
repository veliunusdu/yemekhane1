"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import Link from "next/link";
import { supabase } from "../lib/supabaseClient";
import {
  BarChart, Bar, XAxis, YAxis,
  Tooltip as RechartsTooltip,
  ResponsiveContainer, PieChart, Pie, Cell, Legend,
} from "recharts";
import {
  TrendingUp, Package, Leaf, Activity, Star,
  RefreshCw, Bell, MapPin, ChevronDown, ChevronUp,
  Plus, ShoppingBag, BarChart2, MessageCircle,
} from "lucide-react";

const API_URL = "http://localhost:3001";

type Order = { id: string; package_name: string; buyer_email: string; status: string; created_at: string };
type Review = { id: number; order_id: string; user_email: string; rating: number; comment: string; created_at: string };
type Tab = "orders" | "stats" | "reviews";

const TABS: { id: Tab; label: string; Icon: React.ElementType }[] = [
  { id: "orders",  label: "Siparişler",    Icon: ShoppingBag },
  { id: "stats",   label: "İstatistikler", Icon: BarChart2 },
  { id: "reviews", label: "Yorumlar",      Icon: MessageCircle },
];

const STATUS: Record<string, { dot: string; badge: string }> = {
  "Ödendi":                   { dot: "bg-emerald-500", badge: "bg-emerald-50 text-emerald-700" },
  "Hazırlanıyor":             { dot: "bg-orange-500",  badge: "bg-orange-50 text-orange-700"  },
  "Teslim Edilmeyi Bekliyor": { dot: "bg-violet-500",  badge: "bg-violet-50 text-violet-700"  },
  "Teslim Edildi":            { dot: "bg-gray-300",    badge: "bg-gray-100 text-gray-400"     },
};

const INPUT = "w-full bg-gray-50 border border-gray-200 rounded-xl px-4 py-3 text-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-orange-400 focus:bg-white transition-colors";
const CARD  = "bg-white rounded-2xl border border-gray-100 p-5";

// ─────────────────────── COMPONENT ───────────────────────
export default function Home() {
  const [formData, setFormData] = useState({ name:"", description:"", original_price:"", discounted_price:"", stock:"", category:"", tags:"" });
  const [submitStatus, setSubmitStatus] = useState("");
  const [orders,  setOrders]  = useState<Order[]>([]);
  const [imageUrl, setImageUrl] = useState("");
  const [isUploading, setIsUploading] = useState(false);
  const [updatingId, setUpdatingId] = useState<string|null>(null);

  const [activeTab, setActiveTab] = useState<Tab>("orders");
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const [stats, setStats]   = useState<any>(null);
  const [statsLoading, setStatsLoading] = useState(false);

  const [reviews, setReviews]     = useState<Review[]>([]);
  const [avgRating, setAvgRating] = useState(0);
  const [reviewCount, setReviewCount] = useState(0);
  const [reviewsLoading, setReviewsLoading] = useState(false);

  const [bizName, setBizName]         = useState("");
  const [locLat,  setLocLat]          = useState("");
  const [locLon,  setLocLon]          = useState("");
  const [locStatus, setLocStatus]     = useState("");
  const [isLocating, setIsLocating]   = useState(false);
  const [isSavingLoc, setIsSavingLoc] = useState(false);
  const [locExpanded, setLocExpanded] = useState(false);

  const [toast, setToast] = useState<string|null>(null);
  const toastTimer = useRef<ReturnType<typeof setTimeout>|null>(null);

  // ── Audio ──
  const playDing = useCallback(() => {
    try {
      const AC = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
      const ctx = new AC();
      const mkBeep = (freq: number, start: number) => {
        const o = ctx.createOscillator(); const g = ctx.createGain();
        o.type = "sine"; o.frequency.setValueAtTime(freq, ctx.currentTime + start);
        g.gain.setValueAtTime(0.4, ctx.currentTime + start);
        g.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + start + 0.4);
        o.connect(g); g.connect(ctx.destination);
        o.start(ctx.currentTime + start); o.stop(ctx.currentTime + start + 0.4);
      };
      mkBeep(1046.5, 0); mkBeep(880, 0.2);
    } catch { /* sessiz */ }
  }, []);

  const showToast = useCallback((msg: string) => {
    playDing(); setToast(msg);
    if (toastTimer.current) clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToast(null), 5000);
  }, [playDing]);

  // ── Fetchers ──
  const fetchOrders = useCallback(async () => {
    try { const r = await fetch(`${API_URL}/api/v1/business/orders`); if (r.ok) setOrders((await r.json()) || []); } catch { /* */ }
  }, []);

  const fetchLocation = useCallback(async () => {
    try {
      const r = await fetch(`${API_URL}/api/v1/business/location`);
      if (r.ok) { const d = await r.json(); if (d.latitude !== 0 || d.longitude !== 0) { setLocLat(d.latitude.toString()); setLocLon(d.longitude.toString()); setBizName(d.name || ""); setLocStatus("Kayıtlı konum yüklendi."); } }
    } catch { /* */ }
  }, []);

  const fetchStats = useCallback(async () => {
    setStatsLoading(true);
    try { const r = await fetch(`${API_URL}/api/v1/business/stats`); if (r.ok) setStats(await r.json()); } catch { /* */ }
    finally { setStatsLoading(false); }
  }, []);

  const fetchReviews = useCallback(async () => {
    setReviewsLoading(true);
    try { const r = await fetch(`${API_URL}/api/v1/business/reviews`); if (r.ok) { const d = await r.json(); setReviews(d.reviews||[]); setAvgRating(d.avg_rating||0); setReviewCount(d.count||0); } } catch { /* */ }
    finally { setReviewsLoading(false); }
  }, []);

  // ── Effects ──
  useEffect(() => {
    fetchOrders(); fetchLocation(); fetchStats(); fetchReviews();
    const ch = supabase.channel("biz-orders")
      .on("postgres_changes", { event:"INSERT", schema:"public", table:"orders" }, () => { fetchOrders(); showToast("Yeni sipariş geldi!"); })
      .subscribe();
    return () => { supabase.removeChannel(ch); if (toastTimer.current) clearTimeout(toastTimer.current); };
  }, [fetchOrders, fetchLocation, fetchStats, fetchReviews, showToast]);

  useEffect(() => {
    if (activeTab === "stats")   fetchStats();
    if (activeTab === "reviews") fetchReviews();
  }, [activeTab, fetchStats, fetchReviews]);

  // ── Actions ──
  const updateStatus = async (id: string, s: string) => {
    setUpdatingId(id);
    try {
      const r = await fetch(`${API_URL}/api/v1/orders/${id}/status`, { method:"PATCH", headers:{"Content-Type":"application/json"}, body:JSON.stringify({status:s}) });
      if (r.ok) setOrders(p => p.map(o => o.id===id ? {...o,status:s} : o));
      else { const e = await r.json(); alert("Hata: " + (e.error||"Güncellenemedi")); }
    } catch { alert("API'ye bağlanılamadı."); } finally { setUpdatingId(null); }
  };

  const getGPS = () => {
    if (!navigator.geolocation) { setLocStatus("Konum desteklenmiyor."); return; }
    setIsLocating(true); setLocStatus("Konum alınıyor...");
    navigator.geolocation.getCurrentPosition(
      p => { setLocLat(p.coords.latitude.toFixed(6)); setLocLon(p.coords.longitude.toFixed(6)); setLocStatus("Konum alındı!"); setIsLocating(false); },
      e => { setLocStatus("Alınamadı: "+e.message); setIsLocating(false); },
      { timeout: 10000 }
    );
  };

  const saveLocation = async () => {
    const lat=parseFloat(locLat), lon=parseFloat(locLon);
    if (isNaN(lat)||isNaN(lon)||lat===0||lon===0) { setLocStatus("Geçerli koordinat girin."); return; }
    setIsSavingLoc(true);
    try {
      const r = await fetch(`${API_URL}/api/v1/business/location`, { method:"POST", headers:{"Content-Type":"application/json"}, body:JSON.stringify({name:bizName,latitude:lat,longitude:lon}) });
      if (r.ok) { setLocStatus("Konum kaydedildi!"); setLocExpanded(false); }
      else { const e=await r.json(); setLocStatus("Hata: "+(e.error||"?")); }
    } catch { setLocStatus("API'ye bağlanılamadı."); } finally { setIsSavingLoc(false); }
  };

  const uploadImage = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]; if (!file) return;
    setIsUploading(true);
    const fd = new FormData(); fd.append("file",file); fd.append("upload_preset","yemekhane-preset");
    try {
      const r = await fetch("https://api.cloudinary.com/v1_1/ddymvjxhw/image/upload",{method:"POST",body:fd});
      const d = await r.json();
      if (d.secure_url) setImageUrl(d.secure_url); else alert("Yükleme başarısız: "+(d.error?.message||"?"));
    } catch { alert("Cloudinary bağlantı hatası!"); } finally { setIsUploading(false); }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault(); setSubmitStatus("Yükleniyor...");
    try {
      const r = await fetch(`${API_URL}/api/v1/business/packages`, {
        method:"POST", headers:{"Content-Type":"application/json"},
        body:JSON.stringify({ name:formData.name, description:formData.description, original_price:parseFloat(formData.original_price), discounted_price:parseFloat(formData.discounted_price), stock:parseInt(formData.stock), category:formData.category, tags:formData.tags.split(",").map(t=>t.trim()).filter(Boolean), image_url:imageUrl, business_name:bizName, latitude:locLat?parseFloat(locLat):0, longitude:locLon?parseFloat(locLon):0 }),
      });
      if (r.ok) { setSubmitStatus("Paket başarıyla eklendi!"); setFormData({name:"",description:"",original_price:"",discounted_price:"",stock:"",category:"",tags:""}); setImageUrl(""); fetchOrders(); fetchStats(); }
      else { setSubmitStatus("Bir hata oluştu."); }
    } catch { setSubmitStatus("API'ye bağlanılamadı."); }
  };

  const fc = (e: React.ChangeEvent<HTMLInputElement|HTMLTextAreaElement>) => setFormData({...formData,[e.target.name]:e.target.value});

  const activeOrders = orders.filter(o => o.status !== "Teslim Edildi");
  const pastOrders   = orders.filter(o => o.status === "Teslim Edildi");

  // ═══════════════ RENDER ═══════════════
  return (
    <div className="min-h-screen bg-gray-50">

      {/* ── Toast ── */}
      {toast && (
        <div onClick={() => setToast(null)} className="fixed top-5 left-1/2 -translate-x-1/2 z-50 flex items-center gap-3 bg-gray-900 text-white px-4 py-3 rounded-2xl shadow-2xl cursor-pointer select-none w-max max-w-xs">
          <div className="w-8 h-8 bg-orange-500 rounded-full flex items-center justify-center shrink-0"><Bell className="w-4 h-4"/></div>
          <div><p className="text-sm font-semibold">{toast}</p><p className="text-xs text-gray-400 mt-0.5">Sayfayı yenilemenize gerek yok</p></div>
          <span className="text-gray-500 text-sm ml-1">✕</span>
        </div>
      )}

      <div className="flex min-h-screen">

        {/* ════════ SIDEBAR (Desktop) ════════ */}
        <aside className="hidden md:flex flex-col w-60 bg-white border-r border-gray-100 fixed inset-y-0 left-0 z-20">
          {/* Brand */}
          <div className="px-5 py-5 border-b border-gray-50">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 bg-orange-500 rounded-2xl flex items-center justify-center text-xl shadow-sm shadow-orange-200">🍱</div>
              <div>
                <p className="font-bold text-sm text-gray-900 leading-tight">İşletme Paneli</p>
                <div className="flex items-center gap-1.5 mt-1">
                  <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse"/>
                  <span className="text-xs text-emerald-600 font-medium">Canlı bağlantı</span>
                </div>
              </div>
            </div>
          </div>

          {/* Nav */}
          <nav className="flex-1 px-3 py-4 space-y-0.5">
            {TABS.map(({id,label,Icon}) => (
              <button key={id} onClick={() => setActiveTab(id)}
                className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm font-medium transition-all ${activeTab===id ? "bg-orange-50 text-orange-600" : "text-gray-500 hover:bg-gray-50 hover:text-gray-800"}`}>
                <Icon className="w-4 h-4 shrink-0"/>
                {label}
                {id==="orders" && activeOrders.length > 0 && (
                  <span className="ml-auto bg-orange-500 text-white text-[10px] font-bold w-5 h-5 rounded-full flex items-center justify-center">{activeOrders.length}</span>
                )}
                {id==="reviews" && reviewCount > 0 && (
                  <span className="ml-auto text-xs text-gray-400">{avgRating.toFixed(1)} ⭐</span>
                )}
              </button>
            ))}
          </nav>

          {/* Bottom */}
          <div className="p-3 border-t border-gray-100 space-y-2">
            <Link href="/scanner" className="flex items-center justify-center gap-2 w-full py-2.5 bg-orange-500 hover:bg-orange-600 text-white rounded-xl text-sm font-semibold transition-colors">
              📸 QR Oku
            </Link>
            {activeTab === "orders" && (
              <button onClick={() => document.getElementById("pkg-form")?.scrollIntoView({behavior:"smooth"})}
                className="flex items-center justify-center gap-2 w-full py-2.5 bg-gray-50 hover:bg-gray-100 text-gray-700 border border-gray-200 rounded-xl text-sm font-medium transition-colors">
                <Plus className="w-4 h-4"/> Paket Ekle
              </button>
            )}
          </div>
        </aside>

        {/* ════════ MAIN AREA ════════ */}
        <div className="flex-1 md:ml-60 flex flex-col min-h-screen">

          {/* Mobile Header */}
          <header className="md:hidden sticky top-0 z-10 bg-white border-b border-gray-100 px-4 py-3 flex items-center justify-between">
            <div className="flex items-center gap-2.5">
              <div className="w-8 h-8 bg-orange-500 rounded-xl flex items-center justify-center text-base">🍱</div>
              <div>
                <p className="text-sm font-bold text-gray-900 leading-tight">İşletme Paneli</p>
                <div className="flex items-center gap-1"><span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse"/><span className="text-xs text-emerald-600">Canlı</span></div>
              </div>
            </div>
            <Link href="/scanner" className="flex items-center gap-1.5 bg-orange-500 hover:bg-orange-600 text-white px-3 py-2 rounded-xl text-xs font-bold transition-colors">📸 QR</Link>
          </header>

          {/* Desktop Page Header */}
          <header className="hidden md:flex items-center justify-between px-8 py-5 bg-white border-b border-gray-100 sticky top-0 z-10">
            <div>
              <h1 className="text-lg font-bold text-gray-900">
                {activeTab==="orders" ? "Siparişler" : activeTab==="stats" ? "İstatistikler & Raporlar" : "Müşteri Yorumları"}
              </h1>
              <p className="text-xs text-gray-400 mt-0.5">
                {activeTab==="orders" ? `${activeOrders.length} aktif · ${pastOrders.length} tamamlanan` :
                 activeTab==="stats"  ? "Satış performansı ve analiz" :
                 `${reviewCount} değerlendirme · ${avgRating.toFixed(1)} ortalama puan`}
              </p>
            </div>
            <div className="flex items-center gap-3">
              {activeTab==="orders" && (
                <button onClick={() => document.getElementById("pkg-form")?.scrollIntoView({behavior:"smooth"})}
                  className="flex items-center gap-2 bg-orange-500 hover:bg-orange-600 text-white px-4 py-2 rounded-xl text-sm font-semibold transition-colors">
                  <Plus className="w-4 h-4"/> Paket Ekle
                </button>
              )}
              <button onClick={activeTab==="orders" ? fetchOrders : activeTab==="stats" ? fetchStats : fetchReviews}
                className="flex items-center gap-1.5 border border-gray-200 bg-white hover:bg-gray-50 text-gray-500 px-3 py-2 rounded-xl text-sm transition-colors">
                <RefreshCw className="w-3.5 h-3.5"/> Yenile
              </button>
            </div>
          </header>

          {/* ── Content ── */}
          <main className="flex-1 p-4 md:p-8 pb-24 md:pb-8">

            {/* ══════ YORUMLAR ══════ */}
            {activeTab === "reviews" && (
              <div className="max-w-2xl space-y-4">
                {reviewsLoading ? (
                  <div className="flex justify-center py-20"><Activity className="w-6 h-6 text-orange-500 animate-spin"/></div>
                ) : (
                  <>
                    <div className={CARD + " flex items-center justify-between"}>
                      <div>
                        <p className="text-xs text-gray-400 font-medium uppercase tracking-wider mb-1">Ortalama Puan</p>
                        <div className="flex items-baseline gap-1.5">
                          <span className="text-4xl font-bold text-gray-900">{avgRating.toFixed(1)}</span>
                          <span className="text-sm text-gray-400">/ 5</span>
                        </div>
                        <div className="flex gap-0.5 mt-2">
                          {[1,2,3,4,5].map(s=><Star key={s} className={`w-4 h-4 ${s<=Math.round(avgRating)?"text-amber-400 fill-amber-400":"text-gray-200 fill-gray-200"}`}/>)}
                        </div>
                      </div>
                      <div className="text-right">
                        <p className="text-3xl font-bold text-gray-900">{reviewCount}</p>
                        <p className="text-xs text-gray-400 mt-0.5">değerlendirme</p>
                      </div>
                    </div>

                    {reviews.length === 0 ? (
                      <div className={CARD + " flex flex-col items-center py-12 text-center"}>
                        <div className="w-12 h-12 bg-gray-100 rounded-full flex items-center justify-center mb-3"><Star className="w-5 h-5 text-gray-400"/></div>
                        <p className="text-sm font-medium text-gray-600">Henüz değerlendirme yok</p>
                        <p className="text-xs text-gray-400 mt-1">Müşteriler sipariş sonrası yorum yapabilir</p>
                      </div>
                    ) : (
                      <div className="space-y-2">
                        {reviews.map(r => (
                          <div key={r.id} className={CARD}>
                            <div className="flex items-start justify-between mb-2">
                              <div className="flex items-center gap-2.5">
                                <div className="w-8 h-8 bg-orange-100 rounded-full flex items-center justify-center shrink-0">
                                  <span className="text-xs font-bold text-orange-600">{r.user_email[0].toUpperCase()}</span>
                                </div>
                                <div>
                                  <p className="text-sm font-medium text-gray-800">{r.user_email}</p>
                                  <p className="text-xs text-gray-400">{new Date(r.created_at).toLocaleDateString("tr-TR")}</p>
                                </div>
                              </div>
                              <div className="flex items-center gap-1 bg-amber-50 px-2.5 py-1 rounded-lg">
                                <Star className="w-3 h-3 text-amber-500 fill-amber-500"/><span className="text-sm font-bold text-amber-700">{r.rating}</span>
                              </div>
                            </div>
                            {r.comment && <p className="text-sm text-gray-600 leading-relaxed pl-10">{r.comment}</p>}
                          </div>
                        ))}
                      </div>
                    )}
                  </>
                )}
              </div>
            )}

            {/* ══════ SİPARİŞLER ══════ */}
            {activeTab === "orders" && (
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6 max-w-5xl">

                {/* LEFT: Location + Form */}
                <div className="space-y-5">

                  {/* Location */}
                  <div className="bg-white rounded-2xl border border-gray-100 overflow-hidden">
                    <button className="w-full flex items-center justify-between px-5 py-4" onClick={() => setLocExpanded(v=>!v)}>
                      <div className="flex items-center gap-3">
                        <div className="w-8 h-8 bg-orange-50 rounded-lg flex items-center justify-center"><MapPin className="w-4 h-4 text-orange-500"/></div>
                        <div className="text-left">
                          <p className="text-sm font-semibold text-gray-800">Dükkan Konumu</p>
                          <p className="text-xs text-gray-400 mt-0.5">{locLat&&locLon ? `${parseFloat(locLat).toFixed(4)}, ${parseFloat(locLon).toFixed(4)}` : "Henüz ayarlanmadı"}</p>
                        </div>
                      </div>
                      {locExpanded ? <ChevronUp className="w-4 h-4 text-gray-400"/> : <ChevronDown className="w-4 h-4 text-gray-400"/>}
                    </button>
                    {locExpanded && (
                      <div className="px-5 pb-5 pt-1 border-t border-gray-50 space-y-2.5">
                        <input type="text" placeholder="Dükkan / İşletme Adı" value={bizName} onChange={e=>setBizName(e.target.value)} className={INPUT}/>
                        <div className="grid grid-cols-2 gap-2">
                          <input type="number" step="0.000001" placeholder="Enlem" value={locLat} onChange={e=>setLocLat(e.target.value)} className={INPUT}/>
                          <input type="number" step="0.000001" placeholder="Boylam" value={locLon} onChange={e=>setLocLon(e.target.value)} className={INPUT}/>
                        </div>
                        <div className="grid grid-cols-2 gap-2">
                          <button onClick={getGPS} disabled={isLocating} className="bg-gray-50 border border-gray-200 text-gray-700 text-xs font-semibold py-3 rounded-xl hover:bg-gray-100 disabled:opacity-50 transition-colors">{isLocating?"Alınıyor...":"📡 GPS"}</button>
                          <button onClick={saveLocation} disabled={isSavingLoc||!locLat||!locLon} className="bg-orange-500 text-white text-xs font-semibold py-3 rounded-xl hover:bg-orange-600 disabled:opacity-50 transition-colors">{isSavingLoc?"Kaydediliyor...":"Kaydet"}</button>
                        </div>
                        {locStatus && <p className="text-xs text-gray-500">{locStatus}</p>}
                      </div>
                    )}
                  </div>

                  {/* Package Form */}
                  <div id="pkg-form" className={CARD}>
                    <h2 className="text-sm font-bold text-gray-900 mb-4">Yeni Paket Ekle</h2>
                    <form onSubmit={handleSubmit} className="space-y-3">
                      <input required name="name" value={formData.name} onChange={fc} placeholder="Paket adı" className={INPUT}/>
                      <textarea required name="description" value={formData.description} onChange={fc} placeholder="Açıklama" rows={3} className={INPUT+" resize-none"}/>
                      <div className="grid grid-cols-2 gap-2">
                        <input required name="original_price" type="number" step="0.01" value={formData.original_price} onChange={fc} placeholder="Normal ₺" className={INPUT}/>
                        <input required name="discounted_price" type="number" step="0.01" value={formData.discounted_price} onChange={fc} placeholder="İndirimli ₺" className={INPUT}/>
                      </div>
                      <div className="grid grid-cols-2 gap-2">
                        <select required name="category" value={formData.category} onChange={e=>setFormData({...formData,category:e.target.value})} className={INPUT+" bg-gray-50"}>
                          <option value="">Kategori</option>
                          <option>Sıcak Yemek</option><option>Soğuk Sandviç</option><option>Tatlı & Pastane</option><option>Vegan/Vejetaryen</option><option>İçecek</option><option>Diğer</option>
                        </select>
                        <input name="tags" value={formData.tags} onChange={fc} placeholder="Etiketler (virgülle)" className={INPUT}/>
                      </div>
                      <input required name="stock" type="number" value={formData.stock} onChange={fc} placeholder="Stok adedi" className={INPUT}/>
                      <div>
                        <label className="block text-xs text-gray-500 font-medium mb-1.5">Fotoğraf</label>
                        <input type="file" accept="image/*" onChange={uploadImage} className="w-full text-xs text-gray-500 file:mr-3 file:py-2 file:px-3 file:rounded-lg file:border-0 file:text-xs file:font-semibold file:bg-orange-50 file:text-orange-600 hover:file:bg-orange-100 cursor-pointer"/>
                        {isUploading && <p className="text-xs text-blue-500 mt-1.5">Yükleniyor...</p>}
                        {imageUrl && (
                          <div className="flex items-center gap-3 mt-2">
                            {/* eslint-disable-next-line @next/next/no-img-element */}
                            <img src={imageUrl} alt="" className="w-14 h-14 object-cover rounded-xl"/>
                            <p className="text-xs text-emerald-600 font-medium">Fotoğraf hazır</p>
                          </div>
                        )}
                      </div>
                      {locLat && locLon && (
                        <div className="flex items-center gap-1.5 text-xs text-gray-400 bg-gray-50 rounded-lg px-3 py-2">
                          <MapPin className="w-3 h-3"/><span>{parseFloat(locLat).toFixed(4)}, {parseFloat(locLon).toFixed(4)}</span>
                        </div>
                      )}
                      <button type="submit" disabled={isUploading} className={`w-full py-3 rounded-xl font-semibold text-sm transition-colors ${isUploading?"bg-gray-200 text-gray-400 cursor-not-allowed":"bg-orange-500 hover:bg-orange-600 text-white"}`}>
                        {isUploading ? "Fotoğraf yükleniyor..." : "Paketi Yayınla"}
                      </button>
                      {submitStatus && <p className={`text-center text-sm font-medium ${submitStatus.includes("hata")||submitStatus.includes("bağlan") ? "text-red-500" : submitStatus.includes("başarı") ? "text-emerald-600" : "text-gray-500"}`}>{submitStatus}</p>}
                    </form>
                  </div>
                </div>

                {/* RIGHT: Orders */}
                <div className={CARD + " self-start"}>
                  <div className="flex items-center justify-between mb-5">
                    <div>
                      <h2 className="text-sm font-bold text-gray-900">Aktif Siparişler</h2>
                      <p className="text-xs text-gray-400 mt-0.5">Yeni siparişler otomatik güncellenir</p>
                    </div>
                    <button onClick={fetchOrders} className="flex items-center gap-1 text-xs text-gray-400 hover:text-gray-600 transition-colors"><RefreshCw className="w-3 h-3"/>Yenile</button>
                  </div>

                  {activeOrders.length === 0 ? (
                    <div className="flex flex-col items-center py-10 text-center">
                      <div className="w-12 h-12 bg-gray-100 rounded-2xl flex items-center justify-center mb-3"><Package className="w-5 h-5 text-gray-400"/></div>
                      <p className="text-sm text-gray-500 font-medium">Bekleyen sipariş yok</p>
                      <p className="text-xs text-gray-400 mt-1">Yeni siparişler burada görünecek</p>
                    </div>
                  ) : (
                    <div className="space-y-3">
                      {activeOrders.map(order => {
                        const s = STATUS[order.status] ?? STATUS["Ödendi"];
                        const upd = updatingId === order.id;
                        return (
                          <div key={order.id} className="border border-gray-100 rounded-xl p-4 bg-gray-50 hover:bg-white transition-colors">
                            <div className="flex items-start justify-between gap-2 mb-3">
                              <div className="min-w-0">
                                <p className="text-sm font-semibold text-gray-800 truncate">{order.package_name}</p>
                                <p className="text-xs text-gray-400 mt-0.5 truncate">{new Date(order.created_at).toLocaleTimeString("tr-TR")} · {order.buyer_email}</p>
                              </div>
                              <span className={`shrink-0 inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-semibold ${s.badge}`}>
                                <span className={`w-1.5 h-1.5 rounded-full ${s.dot}`}/>{order.status}
                              </span>
                            </div>
                            {order.status==="Ödendi" && <button disabled={upd} onClick={()=>updateStatus(order.id,"Hazırlanıyor")} className="w-full bg-orange-500 hover:bg-orange-600 disabled:opacity-50 text-white text-xs font-semibold py-2.5 rounded-lg transition-colors">{upd?"Güncelleniyor...":"👨‍🍳 Hazırlanmaya Başla"}</button>}
                            {order.status==="Hazırlanıyor" && <button disabled={upd} onClick={()=>updateStatus(order.id,"Teslim Edilmeyi Bekliyor")} className="w-full bg-violet-600 hover:bg-violet-700 disabled:opacity-50 text-white text-xs font-semibold py-2.5 rounded-lg transition-colors">{upd?"Güncelleniyor...":"🚀 Hazır — Müşteriyi Bildir"}</button>}
                            {order.status==="Teslim Edilmeyi Bekliyor" && <div className="w-full bg-violet-50 text-violet-600 text-xs font-medium py-2.5 rounded-lg text-center">📲 QR bekleniyor...</div>}
                          </div>
                        );
                      })}
                    </div>
                  )}

                  {pastOrders.length > 0 && (
                    <div className="mt-5 pt-4 border-t border-gray-100">
                      <p className="text-xs text-gray-400 font-medium mb-2">Tamamlananlar ({pastOrders.length})</p>
                      <div className="space-y-1">
                        {pastOrders.slice(0,5).map(o=>(
                          <div key={o.id} className="flex items-center justify-between px-3 py-2 rounded-lg">
                            <span className="text-xs text-gray-500 truncate">{o.package_name}</span>
                            <span className="text-xs text-gray-400 shrink-0 ml-2">{new Date(o.created_at).toLocaleDateString("tr-TR")}</span>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              </div>
            )}

            {/* ══════ İSTATİSTİKLER ══════ */}
            {activeTab === "stats" && (
              <div className="max-w-3xl space-y-5">
                {statsLoading ? (
                  <div className="flex justify-center py-20"><Activity className="w-6 h-6 text-orange-500 animate-spin"/></div>
                ) : !stats ? (
                  <div className={CARD+" flex flex-col items-center py-14 text-center"}>
                    <div className="w-12 h-12 bg-gray-100 rounded-full flex items-center justify-center mb-3"><Activity className="w-6 h-6 text-gray-400"/></div>
                    <p className="text-sm font-medium text-gray-600">Veriler alınamadı</p>
                    <p className="text-xs text-gray-400 mt-1">Go backend (3001 portu) çalışıyor mu?</p>
                    <button onClick={fetchStats} className="mt-4 text-orange-500 text-sm font-medium">Tekrar Dene</button>
                  </div>
                ) : (
                  <>
                    {/* KPI */}
                    <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
                      {[
                        { icon: TrendingUp, color: "orange", label:"Toplam Kazanç", value:`₺${stats.kpis.totalRevenue.toFixed(0)}` },
                        { icon: Package,    color: "blue",   label:"Satılan Paket", value:`${stats.kpis.totalSold} adet` },
                        { icon: Leaf,       color: "emerald",label:"Önlenen İsraf", value:`${stats.kpis.savedFoodKg.toFixed(1)} kg` },
                      ].map(({icon:Icon,color,label,value}) => (
                        <div key={label} className="bg-white rounded-2xl border border-gray-100 p-4">
                          <div className={`w-9 h-9 bg-${color}-50 rounded-xl flex items-center justify-center mb-3`}>
                            <Icon className={`w-4 h-4 text-${color}-500`}/>
                          </div>
                          <p className="text-xs text-gray-400 font-medium mb-0.5">{label}</p>
                          <p className="text-xl font-bold text-gray-900">{value}</p>
                        </div>
                      ))}
                    </div>

                    {/* Charts */}
                    <div className="grid grid-cols-1 md:grid-cols-2 gap-5">
                      {stats.weekly_revenue?.length > 0 && (
                        <div className={CARD}>
                          <p className="text-xs font-bold text-gray-700 uppercase tracking-wider mb-4">Son 7 Gün Kazanç</p>
                          <div className="h-48">
                            <ResponsiveContainer width="100%" height="100%">
                              <BarChart data={stats.weekly_revenue} margin={{top:0,right:0,left:-24,bottom:0}}>
                                <XAxis dataKey="date" tickFormatter={v=>v.substring(5,10)} tick={{fontSize:10,fill:"#9ca3af"}} axisLine={false} tickLine={false}/>
                                <YAxis tick={{fontSize:10,fill:"#9ca3af"}} axisLine={false} tickLine={false} tickFormatter={v=>`₺${v}`}/>
                                <RechartsTooltip contentStyle={{borderRadius:12,border:"none",boxShadow:"0 4px 20px rgba(0,0,0,0.08)",fontSize:12}}
                                  // eslint-disable-next-line @typescript-eslint/no-explicit-any
                                  formatter={(v:any)=>[`₺${Number(v).toFixed(2)}`,"Kazanç"]} labelFormatter={l=>`Tarih: ${l}`}/>
                                <Bar dataKey="revenue" fill="#f97316" radius={[6,6,0,0]}/>
                              </BarChart>
                            </ResponsiveContainer>
                          </div>
                        </div>
                      )}

                      {stats.top_packages?.length > 0 && (
                        <div className={CARD}>
                          <p className="text-xs font-bold text-gray-700 uppercase tracking-wider mb-4">En Çok Satılanlar</p>
                          <div className="h-48">
                            <ResponsiveContainer width="100%" height="100%">
                              <PieChart>
                                <Pie data={stats.top_packages} cx="50%" cy="50%" innerRadius={38} outerRadius={65} paddingAngle={3} dataKey="sales">
                                  {/* eslint-disable-next-line @typescript-eslint/no-explicit-any */}
                                  {stats.top_packages.map((_:any,i:number)=><Cell key={i} fill={["#f97316","#3b82f6","#10b981","#8b5cf6","#ec4899"][i%5]}/>)}
                                </Pie>
                                <RechartsTooltip contentStyle={{borderRadius:12,border:"none",boxShadow:"0 4px 20px rgba(0,0,0,0.08)",fontSize:12}}
                                  // eslint-disable-next-line @typescript-eslint/no-explicit-any
                                  formatter={(v:any)=>[`${v} adet`,"Satış"]}/>
                                <Legend wrapperStyle={{fontSize:10}}/>
                              </PieChart>
                            </ResponsiveContainer>
                          </div>
                        </div>
                      )}
                    </div>
                  </>
                )}
              </div>
            )}

          </main>
        </div>

        {/* ════════ MOBILE BOTTOM NAV ════════ */}
        <nav className="md:hidden fixed bottom-0 inset-x-0 bg-white border-t border-gray-100 flex z-20 safe-b">
          {TABS.map(({id,label,Icon}) => (
            <button key={id} onClick={()=>setActiveTab(id)}
              className={`flex-1 flex flex-col items-center gap-0.5 py-2.5 relative transition-colors ${activeTab===id?"text-orange-500":"text-gray-400"}`}>
              {activeTab===id && <span className="absolute top-0 left-1/2 -translate-x-1/2 w-10 h-0.5 bg-orange-500 rounded-b-full"/>}
              <Icon className="w-5 h-5"/>
              <span className="text-[11px] font-medium">{label}</span>
              {id==="orders" && activeOrders.length > 0 && (
                <span className="absolute top-1.5 right-1/4 bg-orange-500 text-white text-[9px] font-bold w-4 h-4 rounded-full flex items-center justify-center">{activeOrders.length}</span>
              )}
            </button>
          ))}
        </nav>

      </div>
    </div>
  );
}
