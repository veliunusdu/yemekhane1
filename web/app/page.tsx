"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import { useRouter } from "next/navigation";
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
  Plus, ShoppingBag, BarChart2, MessageCircle, Store,
} from "lucide-react";

const API_URL = "http://localhost:3001";

type Order = { id: string; package_name: string; buyer_email: string; status: string; created_at: string };
type Review = { id: number; order_id: string; user_email: string; rating: number; comment: string; created_at: string };
type Tab = "orders" | "stats" | "reviews" | "business";
type MyPkg = { id: string; name: string; description: string; original_price: number; discounted_price: number; stock: number; is_active: boolean; image_url: string; category: string; created_at: string };

const TABS: { id: Tab; label: string; Icon: React.ElementType }[] = [
  { id: "orders",   label: "Siparişler",    Icon: ShoppingBag },
  { id: "stats",    label: "İstatistikler", Icon: BarChart2 },
  { id: "reviews",  label: "Yorumlar",      Icon: MessageCircle },
  { id: "business", label: "İşletme",       Icon: Store },
];

const STATUS: Record<string, { dot: string; badge: string }> = {
  "Sipariş Alındı":                   { dot: "bg-emerald-500", badge: "bg-emerald-50 text-emerald-700" },
  "Hazırlanıyor":             { dot: "bg-orange-500",  badge: "bg-orange-50 text-orange-700"  },
  "Teslim Edilmeyi Bekliyor": { dot: "bg-violet-500",  badge: "bg-violet-50 text-violet-700"  },
  "Teslim Edildi":            { dot: "bg-gray-300",    badge: "bg-gray-100 text-gray-400"     },
  "\u0130ptal Edildi":            { dot: "bg-red-400",     badge: "bg-red-50 text-red-600"        },
};

const INPUT = "w-full bg-gray-50 border border-gray-200 rounded-xl px-4 py-3 text-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-orange-400 focus:bg-white transition-colors";
const CARD  = "bg-white rounded-2xl border border-gray-100 p-5";

// ─────────────────────── COMPONENT ───────────────────────
export default function Home() {
  const router = useRouter();
  const [authChecked, setAuthChecked] = useState(false);
  const [userEmail, setUserEmail] = useState("");

  const [formData, setFormData] = useState({ name:"", description:"", original_price:"", discounted_price:"", stock:"", category:"", tags:"", available_from:"", available_until:"" });
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

  const [bizInfo, setBizInfo] = useState({ name:"", address:"", phone:"", email:"", description:"", logo_url:"", category:"", website:"" });
  const [bizInfoLoading, setBizInfoLoading] = useState(false);
  const [bizInfoSaving, setBizInfoSaving] = useState(false);
  const [bizInfoStatus, setBizInfoStatus] = useState("");
  const [bizId, setBizId] = useState<string|null>(null);

  const [myPackages, setMyPackages] = useState<MyPkg[]>([]);
  const [editingPkg, setEditingPkg] = useState<MyPkg|null>(null);
  const [editData, setEditData] = useState({ name:"", description:"", original_price:"", discounted_price:"", stock:"", category:"", is_active:true });
  const [editStatus, setEditStatus] = useState("");

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

  // ── Auth token helper ──
  const getToken = useCallback(async (): Promise<string> => {
    const { data: { session } } = await supabase.auth.getSession();
    return session?.access_token ?? "";
  }, []);

  const authFetch = useCallback(async (url: string, opts: RequestInit = {}): Promise<Response> => {
    const token = await getToken();
    return fetch(url, {
      ...opts,
      headers: { "Content-Type": "application/json", ...(opts.headers ?? {}), "Authorization": `Bearer ${token}` },
    });
  }, [getToken]);

  // ── Fetchers ──
  const fetchOrders = useCallback(async () => {
    try { const r = await authFetch(`${API_URL}/api/v1/business/orders`); if (r.ok) { const d = await r.json(); setOrders(Array.isArray(d) ? d : (d.data || [])); } } catch { /* */ }
  }, [authFetch]);

  const fetchLocation = useCallback(async () => {
    try {
      const r = await authFetch(`${API_URL}/api/v1/business/location`);
      if (r.ok) { const d = await r.json(); if (d.latitude !== 0 || d.longitude !== 0) { setLocLat(d.latitude.toString()); setLocLon(d.longitude.toString()); setBizName(d.name || ""); setLocStatus("Kayıtlı konum yüklendi."); } }
    } catch { /* */ }
  }, [authFetch]);

  const fetchStats = useCallback(async () => {
    setStatsLoading(true);
    try { const r = await authFetch(`${API_URL}/api/v1/business/stats`); if (r.ok) setStats(await r.json()); } catch { /* */ }
    finally { setStatsLoading(false); }
  }, [authFetch]);

  const fetchReviews = useCallback(async () => {
    setReviewsLoading(true);
    try { const r = await authFetch(`${API_URL}/api/v1/business/reviews`); if (r.ok) { const d = await r.json(); setReviews(d.reviews||[]); setAvgRating(d.avg_rating||0); setReviewCount(d.count||0); } } catch { /* */ }
    finally { setReviewsLoading(false); }
  }, [authFetch]);

  const fetchMyPackages = useCallback(async () => {
    try { const r = await authFetch(`${API_URL}/api/v1/business/packages`); if (r.ok) setMyPackages((await r.json()) || []); } catch { /* */ }
  }, [authFetch]);

  const openEdit = (pkg: MyPkg) => {
    setEditingPkg(pkg);
    setEditData({ name: pkg.name, description: pkg.description, original_price: pkg.original_price.toString(), discounted_price: pkg.discounted_price.toString(), stock: pkg.stock.toString(), category: pkg.category, is_active: pkg.is_active });
    setEditStatus("");
  };

  const deletePackage = async (id: string) => {
    if (!confirm("Bu paketi silmek istediğinizden emin misiniz?")) return;
    const r = await authFetch(`${API_URL}/api/v1/business/packages/${id}`, { method: "DELETE" });
    if (r.ok) setMyPackages(p => p.filter(pkg => pkg.id !== id));
    else alert("Paket silinemedi.");
  };

  const handleEditSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!editingPkg) return;
    setEditStatus("Kaydediliyor...");
    try {
      const r = await authFetch(`${API_URL}/api/v1/business/packages/${editingPkg.id}`, {
        method: "PATCH",
        body: JSON.stringify({ name: editData.name, description: editData.description, original_price: parseFloat(editData.original_price), discounted_price: parseFloat(editData.discounted_price), stock: parseInt(editData.stock), category: editData.category, is_active: editData.is_active }),
      });
      if (r.ok) { setEditStatus("Kaydedildi!"); fetchMyPackages(); setTimeout(() => setEditingPkg(null), 800); }
      else { const e = await r.json(); setEditStatus("Hata: " + (e.error || "?")); }
    } catch { setEditStatus("API'ye bağlanılamadı."); }
  };

  const fetchBizInfo = useCallback(async () => {
    setBizInfoLoading(true);
    try {
      const { data: { session } } = await supabase.auth.getSession();
      const currentEmail = session?.user.email ?? "";
      if (!currentEmail) return;
      const { data } = await supabase
        .from("businesses")
        .select("*")
        .eq("owner_email", currentEmail)
        .maybeSingle();
      if (data) {
        setBizId(data.id);
        setBizInfo({
          name:        data.name        || "",
          address:     data.address     || "",
          phone:       data.phone       || "",
          email:       data.email       || "",
          description: data.description || "",
          logo_url:    data.logo_url    || "",
          category:    data.category    || "",
          website:     data.website     || "",
        });
      } else {
        // İşletme henüz oluşturulmamış — onboarding'e yönlendir
        router.replace("/onboarding");
      }
    } catch { /* */ } finally { setBizInfoLoading(false); }
  }, [router]);

  const saveBizInfo = async () => {
    if (!bizId) return;
    setBizInfoSaving(true); setBizInfoStatus("");
    const { error } = await supabase.from("businesses").update({
      name:        bizInfo.name,
      address:     bizInfo.address,
      phone:       bizInfo.phone,
      email:       bizInfo.email,
      description: bizInfo.description,
      logo_url:    bizInfo.logo_url,
      category:    bizInfo.category,
      website:     bizInfo.website,
      updated_at:  new Date().toISOString(),
    }).eq("id", bizId);
    setBizInfoStatus(error ? "Hata: " + error.message : "Bilgiler kaydedildi!");
    setBizInfoSaving(false);
  };

  // ── Effects ──
  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (!session) { router.replace("/login"); } else { setAuthChecked(true); setUserEmail(session.user.email ?? ""); }
    });
  }, [router]);

  useEffect(() => {
    if (!authChecked) return;
    fetchOrders(); fetchLocation(); fetchStats(); fetchReviews(); fetchBizInfo(); fetchMyPackages();
    const ch = supabase.channel("biz-orders")
      .on("postgres_changes", { event:"INSERT", schema:"public", table:"orders",
        ...(bizId ? { filter: `business_id=eq.${bizId}` } : {}) },
        () => { fetchOrders(); showToast("Yeni sipariş geldi!"); })
      .subscribe();
    return () => { supabase.removeChannel(ch); if (toastTimer.current) clearTimeout(toastTimer.current); };
  }, [authChecked, bizId, authFetch, fetchOrders, fetchLocation, fetchStats, fetchReviews, fetchBizInfo, fetchMyPackages, showToast]);

  useEffect(() => {
    if (activeTab === "stats")    fetchStats();
    if (activeTab === "reviews")  fetchReviews();
    if (activeTab === "business") fetchBizInfo();
  }, [activeTab, fetchStats, fetchReviews, fetchBizInfo]);

  const handleLogout = async () => {
    await supabase.auth.signOut();
    router.replace("/login");
  };

  // ── Actions ──
  const updateStatus = async (id: string, s: string) => {
    setUpdatingId(id);
    try {
      const r = await authFetch(`${API_URL}/api/v1/orders/${id}/status`, { method:"PATCH", body:JSON.stringify({status:s}) });
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
      const r = await authFetch(`${API_URL}/api/v1/business/location`, { method:"POST", body:JSON.stringify({name:bizName,latitude:lat,longitude:lon}) });
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
      const r = await authFetch(`${API_URL}/api/v1/business/packages`, {
        method:"POST",
        body:JSON.stringify({ name:formData.name, description:formData.description, original_price:parseFloat(formData.original_price), discounted_price:parseFloat(formData.discounted_price), stock:parseInt(formData.stock), category:formData.category, tags:formData.tags.split(",").map(t=>t.trim()).filter(Boolean), image_url:imageUrl, business_name:bizName, latitude:locLat?parseFloat(locLat):0, longitude:locLon?parseFloat(locLon):0, available_from:formData.available_from||undefined, available_until:formData.available_until||undefined }),
      });
      if (r.ok) { setSubmitStatus("Paket başarıyla eklendi!"); setFormData({name:"",description:"",original_price:"",discounted_price:"",stock:"",category:"",tags:"",available_from:"",available_until:""}); setImageUrl(""); fetchOrders(); fetchStats(); }
      else { const e = await r.json(); setSubmitStatus("Hata: " + (e.error || "Paket eklenemedi.")); }
    } catch { setSubmitStatus("API'ye bağlanılamadı."); }
  };

  const fc = (e: React.ChangeEvent<HTMLInputElement|HTMLTextAreaElement>) => setFormData({...formData,[e.target.name]:e.target.value});

  const terminal = ["Teslim Edildi", "\u0130ptal Edildi"];
  const activeOrders    = orders.filter(o => !terminal.includes(o.status));
  const pastOrders      = orders.filter(o => o.status === "Teslim Edildi");
  const cancelledOrders = orders.filter(o => o.status === "\u0130ptal Edildi");
  const pendingCount    = orders.filter(o => o.status === "Sipariş Alındı").length;

  // ═══════════════ RENDER ═══════════════
  if (!authChecked) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="w-10 h-10 border-4 border-orange-500 border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

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
                {id==="orders" && pendingCount > 0 && (
                  <span className="ml-auto bg-orange-500 text-white text-[10px] font-bold w-5 h-5 rounded-full flex items-center justify-center">{pendingCount}</span>
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
            <div className="pt-1 border-t border-gray-100">
              <div className="flex items-center gap-2 px-2 py-1.5 mb-1">
                <div className="w-7 h-7 bg-orange-100 rounded-full flex items-center justify-center shrink-0">
                  <span className="text-xs font-bold text-orange-600">{userEmail ? userEmail[0].toUpperCase() : "?"}</span>
                </div>
                <p className="text-xs text-gray-500 truncate">{userEmail}</p>
              </div>
              <button onClick={handleLogout}
                className="flex items-center justify-center gap-2 w-full py-2 bg-gray-50 hover:bg-red-50 hover:text-red-600 text-gray-500 border border-gray-200 hover:border-red-200 rounded-xl text-xs font-medium transition-colors">
                Çıkış Yap
              </button>
            </div>
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
                {activeTab==="orders" ? "Siparişler" : activeTab==="stats" ? "İstatistikler & Raporlar" : activeTab==="reviews" ? "Müşteri Yorumları" : "İşletme Bilgileri"}
              </h1>
              <p className="text-xs text-gray-400 mt-0.5">
                {activeTab==="orders"   ? `${activeOrders.length} aktif · ${pastOrders.length} tamamlanan · ${cancelledOrders.length} iptal` :
                 activeTab==="stats"    ? "Satış performansı ve analiz" :
                 activeTab==="reviews"  ? `${reviewCount} değerlendirme · ${avgRating.toFixed(1)} ortalama puan` :
                 "İşletme profil bilgilerini görüntüle ve düzenle"}
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
              <div className="max-w-5xl space-y-6">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">

                {/* LEFT: Form */}
                <div className="space-y-5">

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
                        <label className="block text-xs text-gray-500 font-medium mb-1.5">Geçerlilik Saati <span className="text-gray-400 font-normal">(isteğe bağlı)</span></label>
                        <div className="grid grid-cols-2 gap-2">
                          <div>
                            <span className="text-xs text-gray-400 block mb-1">Başlangıç</span>
                            <input name="available_from" type="time" value={formData.available_from} onChange={fc} className={INPUT}/>
                          </div>
                          <div>
                            <span className="text-xs text-gray-400 block mb-1">Bitiş</span>
                            <input name="available_until" type="time" value={formData.available_until} onChange={fc} className={INPUT}/>
                          </div>
                        </div>
                      </div>
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
                        const s = STATUS[order.status] ?? STATUS["Sipariş Alındı"];
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
                            {order.status==="Sipariş Alındı" && <button disabled={upd} onClick={()=>updateStatus(order.id,"Hazırlanıyor")} className="w-full bg-orange-500 hover:bg-orange-600 disabled:opacity-50 text-white text-xs font-semibold py-2.5 rounded-lg transition-colors">{upd?"Güncelleniyor...":"👨‍🍳 Hazırlanmaya Başla"}</button>}
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

                  {cancelledOrders.length > 0 && (
                    <div className="mt-4 pt-4 border-t border-gray-100">
                      <p className="text-xs text-red-400 font-medium mb-2">İptal Edilenler ({cancelledOrders.length})</p>
                      <div className="space-y-1">
                        {cancelledOrders.slice(0,3).map(o=>(
                          <div key={o.id} className="flex items-center justify-between px-3 py-2 rounded-lg bg-red-50">
                            <span className="text-xs text-red-500 truncate">{o.package_name}</span>
                            <span className="text-xs text-red-400 shrink-0 ml-2">{o.buyer_email}</span>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              </div>{/* end grid */}

              {/* Paketlerim */}
              <div className={CARD}>
                <div className="flex items-center justify-between mb-4">
                  <h2 className="text-sm font-bold text-gray-900">Paketlerim</h2>
                  <button onClick={fetchMyPackages} className="flex items-center gap-1 text-xs text-gray-400 hover:text-gray-600 transition-colors"><RefreshCw className="w-3 h-3"/>Yenile</button>
                </div>
                {myPackages.length === 0 ? (
                  <div className="flex flex-col items-center py-8 text-center">
                    <Package className="w-8 h-8 text-gray-300 mb-2"/>
                    <p className="text-sm text-gray-400">Henüz paket eklemediniz</p>
                  </div>
                ) : (
                  <div className="space-y-2">
                    {myPackages.map(pkg => (
                      <div key={pkg.id} className="flex items-center justify-between gap-3 border border-gray-100 rounded-xl px-4 py-3 hover:bg-gray-50 transition-colors">
                        <div className="min-w-0 flex-1">
                          <div className="flex items-center gap-2">
                            <p className="text-sm font-semibold text-gray-800 truncate">{pkg.name}</p>
                            <span className={`shrink-0 text-[10px] font-semibold px-2 py-0.5 rounded-full ${pkg.is_active ? "bg-emerald-50 text-emerald-700" : "bg-gray-100 text-gray-400"}`}>{pkg.is_active ? "Aktif" : "Pasif"}</span>
                          </div>
                          <p className="text-xs text-gray-400 mt-0.5">₺{pkg.discounted_price.toFixed(2)} · Stok: {pkg.stock} · {pkg.category}</p>
                        </div>
                        <div className="flex items-center gap-2 shrink-0">
                          <button onClick={() => openEdit(pkg)} className="text-xs text-orange-500 hover:text-orange-700 font-semibold border border-orange-200 hover:border-orange-400 rounded-lg px-3 py-1.5 transition-colors">Düzenle</button>
                          <button onClick={() => deletePackage(pkg.id)} className="text-xs text-red-400 hover:text-red-600 border border-red-100 hover:border-red-300 rounded-lg px-2 py-1.5 transition-colors" title="Paketi Sil">🗑️</button>
                        </div>
                      </div>
                    ))}
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

            {/* ══════ İŞLETME BİLGİLERİ ══════ */}
            {activeTab === "business" && (
              <div className="max-w-xl space-y-5">
                {bizInfoLoading ? (
                  <div className="flex justify-center py-20"><Activity className="w-6 h-6 text-orange-500 animate-spin"/></div>
                ) : (
                  <>
                  <div className={CARD}>
                    <h2 className="text-sm font-bold text-gray-900 mb-5">İşletme Profili</h2>
                    <div className="space-y-3">
                      <div>
                        <label className="block text-xs text-gray-500 font-medium mb-1">İşletme Adı</label>
                        <input value={bizInfo.name} onChange={e=>setBizInfo(p=>({...p,name:e.target.value}))} placeholder="İşletme adı" className={INPUT}/>
                      </div>
                      <div>
                        <label className="block text-xs text-gray-500 font-medium mb-1">Kategori</label>
                        <select value={bizInfo.category} onChange={e=>setBizInfo(p=>({...p,category:e.target.value}))} className={INPUT+" bg-gray-50"}>
                          <option value="">Kategori seçin</option>
                          <option>Restoran</option><option>Kafe</option><option>Pastane & Fırın</option>
                          <option>Fast Food</option><option>Yemekhane</option><option>Diğer</option>
                        </select>
                      </div>
                      <div>
                        <label className="block text-xs text-gray-500 font-medium mb-1">Adres</label>
                        <input value={bizInfo.address} onChange={e=>setBizInfo(p=>({...p,address:e.target.value}))} placeholder="Sokak, Mahalle, İlçe, Şehir" className={INPUT}/>
                      </div>
                      <div className="grid grid-cols-2 gap-2">
                        <div>
                          <label className="block text-xs text-gray-500 font-medium mb-1">Telefon</label>
                          <input value={bizInfo.phone} onChange={e=>setBizInfo(p=>({...p,phone:e.target.value}))} placeholder="+90 555 000 00 00" className={INPUT}/>
                        </div>
                        <div>
                          <label className="block text-xs text-gray-500 font-medium mb-1">E-posta</label>
                          <input type="email" value={bizInfo.email} onChange={e=>setBizInfo(p=>({...p,email:e.target.value}))} placeholder="info@isletme.com" className={INPUT}/>
                        </div>
                      </div>
                      <div>
                        <label className="block text-xs text-gray-500 font-medium mb-1">Web Sitesi</label>
                        <input value={bizInfo.website} onChange={e=>setBizInfo(p=>({...p,website:e.target.value}))} placeholder="https://www.isletme.com" className={INPUT}/>
                      </div>
                      <div>
                        <label className="block text-xs text-gray-500 font-medium mb-1">Açıklama</label>
                        <textarea value={bizInfo.description} onChange={e=>setBizInfo(p=>({...p,description:e.target.value}))} placeholder="İşletmeniz hakkında kısa bir tanıtım..." rows={3} className={INPUT+" resize-none"}/>
                      </div>
                      <div>
                        <label className="block text-xs text-gray-500 font-medium mb-1">Logo URL</label>
                        <input value={bizInfo.logo_url} onChange={e=>setBizInfo(p=>({...p,logo_url:e.target.value}))} placeholder="https://..." className={INPUT}/>
                        {bizInfo.logo_url && (
                          <div className="mt-2 flex items-center gap-3">
                            {/* eslint-disable-next-line @next/next/no-img-element */}
                            <img src={bizInfo.logo_url} alt="logo" className="w-14 h-14 object-cover rounded-xl border border-gray-100"/>
                            <p className="text-xs text-gray-400">Önizleme</p>
                          </div>
                        )}
                      </div>
                      <button onClick={saveBizInfo} disabled={bizInfoSaving||!bizId}
                        className="w-full py-3 bg-orange-500 hover:bg-orange-600 disabled:opacity-50 text-white rounded-xl font-semibold text-sm transition-colors">
                        {bizInfoSaving ? "Kaydediliyor..." : "Bilgileri Kaydet"}
                      </button>
                      {bizInfoStatus && (
                        <p className={`text-center text-sm font-medium ${bizInfoStatus.startsWith("Hata") ? "text-red-500" : "text-emerald-600"}`}>
                          {bizInfoStatus}
                        </p>
                      )}
                    </div>
                  </div>

                  {/* Konum */}
                  <div className="bg-white rounded-2xl border border-gray-100 overflow-hidden">
                    <button className="w-full flex items-center justify-between px-5 py-4" onClick={() => setLocExpanded(v=>!v)}>
                      <div className="flex items-center gap-3">
                        <div className="w-8 h-8 bg-orange-50 rounded-lg flex items-center justify-center"><MapPin className="w-4 h-4 text-orange-500"/></div>
                        <div className="text-left">
                          <p className="text-sm font-semibold text-gray-800">Harita Konumu</p>
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
                  </>
                )}
              </div>
            )}

          </main>
        </div>

        {/* ════════ EDIT PACKAGE MODAL ════════ */}
        {editingPkg && (
          <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onClick={e => { if (e.target === e.currentTarget) setEditingPkg(null); }}>
            <div className="bg-white rounded-2xl w-full max-w-md max-h-[90vh] overflow-y-auto p-6 shadow-2xl">
              <div className="flex items-center justify-between mb-5">
                <h2 className="text-base font-bold text-gray-900">Paketi Düzenle</h2>
                <button onClick={() => setEditingPkg(null)} className="text-gray-400 hover:text-gray-700 text-xl font-light leading-none">✕</button>
              </div>
              <form onSubmit={handleEditSubmit} className="space-y-3">
                <input required value={editData.name} onChange={e=>setEditData(p=>({...p,name:e.target.value}))} placeholder="Paket adı" className={INPUT}/>
                <textarea required value={editData.description} onChange={e=>setEditData(p=>({...p,description:e.target.value}))} placeholder="Açıklama" rows={3} className={INPUT+" resize-none"}/>
                <div className="grid grid-cols-2 gap-2">
                  <input required type="number" step="0.01" value={editData.original_price} onChange={e=>setEditData(p=>({...p,original_price:e.target.value}))} placeholder="Normal ₺" className={INPUT}/>
                  <input required type="number" step="0.01" value={editData.discounted_price} onChange={e=>setEditData(p=>({...p,discounted_price:e.target.value}))} placeholder="İndirimli ₺" className={INPUT}/>
                </div>
                <div className="grid grid-cols-2 gap-2">
                  <select required value={editData.category} onChange={e=>setEditData(p=>({...p,category:e.target.value}))} className={INPUT+" bg-gray-50"}>
                    <option value="">Kategori</option>
                    <option>Sıcak Yemek</option><option>Soğuk Sandviç</option><option>Tatlı & Pastane</option><option>Vegan/Vejetaryen</option><option>İçecek</option><option>Diğer</option>
                  </select>
                  <input required type="number" value={editData.stock} onChange={e=>setEditData(p=>({...p,stock:e.target.value}))} placeholder="Stok" className={INPUT}/>
                </div>
                <label className="flex items-center gap-2 cursor-pointer select-none">
                  <input type="checkbox" checked={editData.is_active} onChange={e=>setEditData(p=>({...p,is_active:e.target.checked}))} className="w-4 h-4 accent-orange-500"/>
                  <span className="text-sm text-gray-700">Aktif (müşterilere göster)</span>
                </label>
                <button type="submit" className="w-full py-3 bg-orange-500 hover:bg-orange-600 text-white rounded-xl font-semibold text-sm transition-colors">Kaydet</button>
                {editStatus && <p className={`text-center text-sm font-medium ${editStatus.startsWith("Hata") ? "text-red-500" : editStatus.includes("Kaydedildi") ? "text-emerald-600" : "text-gray-500"}`}>{editStatus}</p>}
              </form>
            </div>
          </div>
        )}

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
