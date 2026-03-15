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
  LogOut, QrCode, ChefHat, Send, Trash2, Edit2, Loader2, Play,
  CheckCircle2, XCircle
} from "lucide-react";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001";

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
  "Sipariş Alındı":                   { dot: "bg-blue-500", badge: "bg-blue-50 text-blue-700 border-blue-200" },
  "Hazırlanıyor":             { dot: "bg-amber-500",  badge: "bg-amber-50 text-amber-700 border-amber-200"  },
  "Teslim Edilmeyi Bekliyor": { dot: "bg-purple-500",  badge: "bg-purple-50 text-purple-700 border-purple-200"  },
  "Teslim Edildi":            { dot: "bg-gray-400",    badge: "bg-gray-50 text-gray-600 border-gray-200"     },
  "İptal Edildi":            { dot: "bg-red-500",     badge: "bg-red-50 text-red-700 border-red-200"        },
};

const INPUT = "w-full bg-transparent border border-gray-200 rounded-md px-3 py-2 text-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:border-orange-500 focus:ring-1 focus:ring-orange-500 transition-colors";
const CARD  = "bg-white rounded-xl border border-gray-200 p-6";

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

  // Audio Helper
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
    } catch { /* silent */ }
  }, []);

  const showToast = useCallback((msg: string) => {
    playDing(); setToast(msg);
    if (toastTimer.current) clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToast(null), 5000);
  }, [playDing]);

  // Auth Helpers
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

  // Fetch Definitions
  const fetchOrders = useCallback(async () => {
    try { const r = await authFetch(`${API_URL}/api/v1/business/orders`); if (r.ok) { const d = await r.json(); setOrders(Array.isArray(d) ? d : (d.data || [])); } } catch { /* */ }
  }, [authFetch]);

  const fetchLocation = useCallback(async () => {
    try {
      const r = await authFetch(`${API_URL}/api/v1/business/location`);
      if (r.ok) { const d = await r.json(); if (d.latitude !== 0 || d.longitude !== 0) { setLocLat(d.latitude.toString()); setLocLon(d.longitude.toString()); setBizName(d.name || ""); setLocStatus("Saved location loaded."); } }
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
    if (!confirm("Bu ilanı silmek istediğinize emin misiniz?")) return;
    const r = await authFetch(`${API_URL}/api/v1/business/packages/${id}`, { method: "DELETE" });
    if (r.ok) setMyPackages(p => p.filter(pkg => pkg.id !== id));
    else alert("İlan silinemedi.");
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
      if (r.ok) { setEditStatus("Kaydedildi."); fetchMyPackages(); setTimeout(() => setEditingPkg(null), 800); }
      else { const e = await r.json(); setEditStatus("Hata: " + (e.error || "?")); }
    } catch { setEditStatus("Sunucu bağlantı hatası."); }
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
    setBizInfoStatus(error ? "Hata: " + error.message : "Bilgiler kaydedildi.");
    setBizInfoSaving(false);
  };

  // Lifecycle
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
        () => { fetchOrders(); showToast("Yeni sipariş alındı!"); })
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

  // Actions Let
  const updateStatus = async (id: string, s: string) => {
    setUpdatingId(id);
    try {
      const r = await authFetch(`${API_URL}/api/v1/orders/${id}/status`, { method:"PATCH", body:JSON.stringify({status:s}) });
      if (r.ok) setOrders(p => p.map(o => o.id===id ? {...o,status:s} : o));
      else { const e = await r.json(); alert("Hata: " + (e.error||"Durum güncellenemedi")); }
    } catch { alert("Sunucu bağlantı hatası."); } finally { setUpdatingId(null); }
  };

  const getGPS = () => {
    if (!navigator.geolocation) { setLocStatus("Tarayıcı konumu desteklemiyor."); return; }
    setIsLocating(true); setLocStatus("Konum bulunuyor...");
    navigator.geolocation.getCurrentPosition(
      p => { setLocLat(p.coords.latitude.toFixed(6)); setLocLon(p.coords.longitude.toFixed(6)); setLocStatus("Konum alındı."); setIsLocating(false); },
      e => { setLocStatus("Hata: "+e.message); setIsLocating(false); },
      { timeout: 10000 }
    );
  };

  const saveLocation = async () => {
    const lat=parseFloat(locLat), lon=parseFloat(locLon);
    if (isNaN(lat)||isNaN(lon)||lat===0||lon===0) { setLocStatus("Geçerli koordinatlar girin."); return; }
    setIsSavingLoc(true);
    try {
      const r = await authFetch(`${API_URL}/api/v1/business/location`, { method:"POST", body:JSON.stringify({name:bizName,latitude:lat,longitude:lon}) });
      if (r.ok) { setLocStatus("Konum kaydedildi."); setLocExpanded(false); }
      else { const e=await r.json(); setLocStatus("Hata: "+(e.error||"?")); }
    } catch { setLocStatus("Sunucu bağlantı hatası."); } finally { setIsSavingLoc(false); }
  };

  const uploadImage = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]; if (!file) return;
    setIsUploading(true);
    const fd = new FormData(); fd.append("file",file); fd.append("upload_preset","yemekhane-preset");
    try {
      const r = await fetch("https://api.cloudinary.com/v1_1/ddymvjxhw/image/upload",{method:"POST",body:fd});
      const d = await r.json();
      if (d.secure_url) setImageUrl(d.secure_url); else alert("Yükleme başarısız: "+(d.error?.message||"?"));
    } catch { alert("Resim sunucusu bağlantı hatası."); } finally { setIsUploading(false); }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault(); setSubmitStatus("Oluşturuluyor...");
    try {
      const r = await authFetch(`${API_URL}/api/v1/business/packages`, {
        method:"POST",
        body:JSON.stringify({ name:formData.name, description:formData.description, original_price:parseFloat(formData.original_price), discounted_price:parseFloat(formData.discounted_price), stock:parseInt(formData.stock), category:formData.category, tags:formData.tags.split(",").map(t=>t.trim()).filter(Boolean), image_url:imageUrl, business_name:bizName, latitude:locLat?parseFloat(locLat):0, longitude:locLon?parseFloat(locLon):0, available_from:formData.available_from||undefined, available_until:formData.available_until||undefined }),
      });
      if (r.ok) { setSubmitStatus("Paket başarıyla eklendi."); setFormData({name:"",description:"",original_price:"",discounted_price:"",stock:"",category:"",tags:"",available_from:"",available_until:""}); setImageUrl(""); fetchOrders(); fetchStats(); }
      else { const e = await r.json(); setSubmitStatus("Hata: " + (e.error || "Eklenemedi.")); }
    } catch { setSubmitStatus("Sunucu bağlantı hatası."); }
  };

  const fc = (e: React.ChangeEvent<HTMLInputElement|HTMLTextAreaElement>) => setFormData({...formData,[e.target.name]:e.target.value});

  const terminal = ["Teslim Edildi", "İptal Edildi"];
  const activeOrders    = orders.filter(o => !terminal.includes(o.status));
  const pastOrders      = orders.filter(o => o.status === "Teslim Edildi");
  const cancelledOrders = orders.filter(o => o.status === "İptal Edildi");
  const pendingCount    = orders.filter(o => o.status === "Sipariş Alındı").length;

  if (!authChecked) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-white">
        <Loader2 className="h-5 w-5 animate-spin text-gray-400" />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-[#FAFAFA] font-sans text-gray-900 selection:bg-orange-500 selection:text-white">

      {/* Toast Notification */}
      {toast && (
        <div onClick={() => setToast(null)} className="fixed bottom-4 right-4 z-50 flex items-center gap-3 bg-orange-500 text-white px-4 py-3 rounded-lg shadow-lg cursor-pointer animate-in slide-in-from-bottom-2">
          <Bell className="w-4 h-4"/>
          <div>
            <p className="text-sm font-medium">{toast}</p>
          </div>
          <span className="text-gray-400 ml-2 hover:text-white transition-colors">✕</span>
        </div>
      )}

      <div className="flex min-h-screen w-full overflow-hidden bg-[#FAFAFA]">

        {/* SIDEBAR */}
        {/* SIDEBAR - MODERNIZED */}
        <aside className="hidden md:flex flex-col w-[260px] fixed inset-y-0 left-0 z-20 bg-white border-r border-gray-100 shadow-[2px_0_24px_rgba(0,0,0,0.02)] pt-6">
          <div className="px-6 mb-10">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 bg-gradient-to-br from-orange-400 to-orange-600 rounded-xl shadow-sm flex items-center justify-center">
                <span className="text-white text-sm font-black tracking-tight font-mono">YH</span>
              </div>
              <div className="flex flex-col">
                <span className="font-bold text-[15px] text-gray-900 tracking-tight">Kurumsal Panel</span>
                <div className="flex items-center gap-1.5 mt-0.5">
                  <span className="relative flex h-2 w-2">
                    <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
                    <span className="relative inline-flex rounded-full h-2 w-2 bg-green-500"></span>
                  </span>
                  <span className="text-[10px] uppercase tracking-wider text-gray-500 font-bold">Sistem Devrede</span>
                </div>
              </div>
            </div>
          </div>

          <nav className="flex-1 px-4 space-y-1.5">
            {TABS.map(({id,label,Icon}) => (
              <button key={id} onClick={() => setActiveTab(id)}
                className={`w-full flex items-center gap-3 px-3.5 py-3 rounded-xl text-sm font-medium transition-all duration-200 ${activeTab===id ? "bg-orange-50 text-orange-600 shadow-[inset_0_1px_0_rgba(255,255,255,0.5)] ring-1 ring-orange-100/50" : "text-gray-500 hover:text-gray-900 hover:bg-gray-50"}`}>
                <Icon className={`${activeTab===id ? "text-orange-500 w-5 h-5" : "text-gray-400 w-5 h-5"} shrink-0`}/>
                {label}
                {id==="orders" && pendingCount > 0 && (
                  <span className="ml-auto bg-orange-500 text-white text-[10px] font-bold px-2 py-0.5 rounded-full shadow-sm">{pendingCount}</span>
                )}
                {id==="reviews" && reviewCount > 0 && (
                  <span className="ml-auto text-xs text-brand-dark/50 font-semibold">{avgRating.toFixed(1)}</span>
                )}
              </button>
            ))}
          </nav>

          <div className="p-5 space-y-3 mt-auto mb-4">
            <Link href="/scanner" className="flex items-center justify-center gap-2 w-full py-2.5 bg-gradient-to-r from-orange-500 to-orange-600 hover:from-orange-600 hover:to-orange-700 text-white rounded-xl text-sm font-semibold shadow-md shadow-orange-500/20 transition-all hover:scale-[1.02] active:scale-95">
              <QrCode className="w-4 h-4"/> QR Okuyucu
            </Link>
            {activeTab === "orders" && (
              <button onClick={() => document.getElementById("pkg-form")?.scrollIntoView({behavior:"smooth"})}
                className="flex items-center justify-center gap-2 w-full py-2.5 bg-white hover:bg-gray-50 text-gray-700 border border-gray-200 rounded-xl text-sm font-semibold shadow-sm transition-all hover:scale-[1.02] active:scale-95">
                <Plus className="w-4 h-4"/> Yeni Menü
              </button>
            )}
            
            <div className="pt-5 mt-4 border-t border-gray-100">
              <div className="flex items-center gap-3 px-1 mb-4">
                <div className="w-9 h-9 bg-orange-100 border border-orange-200 rounded-full flex items-center justify-center text-[13px] text-orange-700 font-bold shrink-0">
                  {userEmail ? userEmail[0].toUpperCase() : "?"}
                </div>
                <div className="flex flex-col min-w-0">
                  <span className="text-[10px] text-gray-400 font-bold uppercase tracking-wider">Yetkili Hesap</span>
                  <p className="text-xs text-gray-700 font-semibold truncate leading-tight">{userEmail}</p>
                </div>
              </div>
              <button onClick={handleLogout}
                className="flex items-center gap-2 w-full px-3 py-2.5 text-gray-500 hover:text-red-600 hover:bg-red-50 rounded-xl text-sm font-semibold transition-all group">
                <LogOut className="w-4 h-4 group-hover:-translate-x-0.5 transition-transform"/> Güvenli Çıkış
              </button>
            </div>
          </div>
        </aside>

        {/* MAIN AREA */}
        <div className="flex-1 flex flex-col min-h-screen bg-white md:border-l border-gray-200 md:ml-[260px]">

          {/* Mobile Header */}
          <header className="md:hidden sticky top-0 z-10 bg-white/80 backdrop-blur-md border-b border-gray-200 px-4 py-3 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <div className="w-7 h-7 bg-orange-500 rounded-md flex items-center justify-center"><span className="text-white text-[10px] font-bold font-mono">YH</span></div>
              <span className="text-sm font-semibold">Yönetim Paneli</span>
            </div>
            <Link href="/scanner" className="flex items-center gap-1.5 bg-orange-500 text-white px-2.5 py-1.5 rounded-md text-xs font-medium"><QrCode className="w-3.5 h-3.5"/></Link>
          </header>

          <header className="hidden md:flex items-center justify-between px-8 py-6 sticky top-0 z-10 bg-white/90 backdrop-blur-md border-b border-gray-100">
            <div>
              <h1 className="text-xl font-semibold tracking-tight text-gray-900">
                {activeTab==="orders" ? "Sipariş Yönetimi" : activeTab==="stats" ? "İstatistikler" : activeTab==="reviews" ? "Müşteri Yorumları" : "İşletme Ayarları"}
              </h1>
            </div>
            <div className="flex items-center gap-2">
              <button onClick={activeTab==="orders" ? fetchOrders : activeTab==="stats" ? fetchStats : fetchReviews}
                className="flex items-center justify-center w-8 h-8 border border-gray-200 rounded-md hover:bg-gray-50 text-gray-500 transition-colors">
                <RefreshCw className="w-4 h-4"/>
              </button>
            </div>
          </header>

          {/* Content */}
          <main className="flex-1 p-4 md:p-8 pb-24 md:pb-8">

            {/* REVIEWS */}
            {activeTab === "reviews" && (
              <div className="max-w-2xl space-y-6">
                {reviewsLoading ? (
                  <div className="flex py-10"><Loader2 className="w-5 h-5 text-gray-400 animate-spin"/></div>
                ) : (
                  <>
                    <div className="flex gap-10 border-b border-gray-200 pb-8">
                      <div>
                        <p className="text-sm text-gray-500 mb-1">Average rating</p>
                        <div className="flex items-end gap-2">
                          <span className="text-4xl font-semibold tracking-tight text-gray-900">{avgRating.toFixed(1)}</span>
                        </div>
                      </div>
                      <div>
                        <p className="text-sm text-gray-500 mb-1">Total reviews</p>
                        <div className="flex items-end gap-2">
                          <span className="text-4xl font-semibold tracking-tight text-gray-900">{reviewCount}</span>
                        </div>
                      </div>
                    </div>

                    {reviews.length === 0 ? (
                      <p className="text-sm text-gray-500">Henüz yorum yok.</p>
                    ) : (
                      <div className="space-y-4">
                        {reviews.map(r => (
                          <div key={r.id} className="py-4 border-b border-gray-100 last:border-0">
                            <div className="flex items-center gap-2 mb-2">
                              <span className="text-sm font-medium">{r.user_email}</span>
                              <span className="text-xs text-gray-400">· {new Date(r.created_at).toLocaleDateString()}</span>
                              <span className="flex items-center gap-1 text-xs font-medium ml-auto bg-gray-50 px-1.5 py-0.5 rounded text-gray-600"><Star className="w-3 h-3"/> {r.rating}</span>
                            </div>
                            {r.comment && <p className="text-sm text-gray-600 leading-relaxed">{r.comment}</p>}
                          </div>
                        ))}
                      </div>
                    )}
                  </>
                )}
              </div>
            )}

            {/* ORDERS */}
            {activeTab === "orders" && (
              <div className="max-w-5xl space-y-6">
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">

                {/* LEFT */}
                <div className="space-y-6">
                  {/* Create Package */}
                  <div id="pkg-form" className={CARD}>
                    <h2 className="text-sm font-semibold mb-4 text-gray-900">İlan Oluştur</h2>
                    <form onSubmit={handleSubmit} className="space-y-4">
                      <div className="space-y-3">
                        <input required name="name" value={formData.name} onChange={fc} placeholder="Ürün Adı" className={INPUT}/>
                        <textarea required name="description" value={formData.description} onChange={fc} placeholder="Kısa açıklama..." rows={2} className={INPUT+" resize-none"}/>
                        <div className="grid grid-cols-2 gap-3">
                          <input required name="original_price" type="number" step="0.01" value={formData.original_price} onChange={fc} placeholder="Orijinal Fiyat" className={INPUT}/>
                          <input required name="discounted_price" type="number" step="0.01" value={formData.discounted_price} onChange={fc} placeholder="İndirimli Fiyat" className={INPUT}/>
                        </div>
                        <div className="grid grid-cols-2 gap-3">
                          <select required name="category" value={formData.category} onChange={e=>setFormData({...formData,category:e.target.value})} className={INPUT}>
                            <option value="">Select Category</option>
                            <option>Sıcak Yemek</option><option>Soğuk Sandviç</option><option>Tatlı & Pastane</option><option>Vegan</option><option>İçecek</option><option>Diğer</option>
                          </select>
                          <input name="tags" value={formData.tags} onChange={fc} placeholder="Etiketler (virgülle ayırın)" className={INPUT}/>
                        </div>
                        <input required name="stock" type="number" value={formData.stock} onChange={fc} placeholder="Mevcut Stok" className={INPUT}/>
                      </div>

                      <div className="pt-2 border-t border-gray-100">
                        <div className="flex items-center gap-2">
                          <label className="flex-1 w-full bg-gray-50 hover:bg-gray-100 border border-gray-200 text-center py-2.5 rounded-md cursor-pointer transition-colors text-sm text-gray-600 font-medium tracking-tight">
                            <input type="file" accept="image/*" onChange={uploadImage} className="hidden"/>
                            {isUploading ? <Loader2 className="w-4 h-4 inline animate-spin" /> : "Görsel Yükle"}
                          </label>
                        </div>
                        {imageUrl && (
                          <div className="mt-3 flex items-center justify-between border border-gray-100 p-2 rounded-md">
                            <span className="text-xs text-green-600 font-medium px-2">Görsel Yüklendi</span>
                            <img src={imageUrl} alt="" className="w-8 h-8 object-cover rounded-sm"/>
                          </div>
                        )}
                      </div>

                      <button type="submit" disabled={isUploading} className={`w-full py-2.5 rounded-md font-medium text-sm transition-colors ${isUploading?"bg-gray-100 text-gray-400":"bg-orange-500 hover:bg-orange-600 text-white"}`}>
                        {isUploading ? "Yükleniyor..." : "İlanı Yayınla"}
                      </button>
                      {submitStatus && <p className={`text-xs text-center font-medium ${submitStatus.toLowerCase().includes("error") ? "text-red-500" : "text-gray-900"}`}>{submitStatus}</p>}
                    </form>
                  </div>
                </div>

                {/* RIGHT */}
                <div className="space-y-6">
                  {/* Orders Queue */}
                  <div>
                    <h2 className="text-sm font-semibold mb-4 text-gray-900">Aktif Siparişler</h2>
                    {activeOrders.length === 0 ? (
                      <p className="text-sm text-gray-500">Şu anda aktif sipariş yok.</p>
                    ) : (
                      <div className="space-y-3">
                        {activeOrders.map(order => {
                          const s = STATUS[order.status] ?? STATUS["Sipariş Alındı"];
                          const upd = updatingId === order.id;
                          return (
                            <div key={order.id} className="border border-gray-200 rounded-lg p-4 bg-white">
                              <div className="flex items-start justify-between gap-3 mb-4">
                                <div>
                                  <p className="text-sm font-medium text-gray-900">{order.package_name}</p>
                                  <p className="text-xs text-gray-500 mt-1">{new Date(order.created_at).toLocaleTimeString()} · {order.buyer_email}</p>
                                </div>
                                <span className={`shrink-0 border px-2 py-0.5 rounded text-[10px] font-medium uppercase tracking-wider ${s.badge}`}>
                                  {order.status}
                                </span>
                              </div>
                              {order.status==="Sipariş Alındı" && <button disabled={upd} onClick={()=>updateStatus(order.id,"Hazırlanıyor")} className="w-full flex items-center justify-center gap-2 bg-orange-500 hover:bg-orange-600 text-white text-xs font-medium py-2 rounded-md transition-colors"><Play className="w-3.5 h-3.5 fill-white"/> Start Prep</button>}
                              {order.status==="Hazırlanıyor" && <button disabled={upd} onClick={()=>updateStatus(order.id,"Teslim Edilmeyi Bekliyor")} className="w-full flex items-center justify-center gap-2 border border-orange-500 text-gray-900 hover:bg-gray-50 text-xs font-medium py-2 rounded-md transition-colors"><Send className="w-3.5 h-3.5"/> Notify Ready</button>}
                              {order.status==="Teslim Edilmeyi Bekliyor" && <div className="w-full bg-gray-50 text-gray-400 text-xs font-medium py-2 rounded-md text-center border border-gray-100 flex items-center justify-center gap-2"><QrCode className="w-3.5 h-3.5"/> Awaiting scan</div>}
                            </div>
                          );
                        })}
                      </div>
                    )}
                  </div>

                  {pastOrders.length > 0 && (
                    <div className="pt-4">
                      <p className="text-xs font-medium text-gray-400 uppercase tracking-widest mb-3">Geçmiş Siparişler ({pastOrders.length})</p>
                      <div className="space-y-2">
                        {pastOrders.slice(0,5).map(o=>(
                          <div key={o.id} className="flex items-center justify-between text-sm text-gray-500">
                            <span className="truncate">{o.package_name}</span>
                            <span className="shrink-0 text-xs ml-2">{new Date(o.created_at).toLocaleDateString()}</span>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              </div>

              {/* LISTINGS */}
              <div className="pt-6 mt-6 border-t border-gray-100">
                <h2 className="text-sm font-semibold mb-4 text-gray-900">Aktif İlanlar</h2>
                {myPackages.length === 0 ? (
                  <p className="text-sm text-gray-500">Kayıtlı ürününüz bulunmuyor.</p>
                ) : (
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                    {myPackages.map(pkg => (
                      <div key={pkg.id} className="flex items-center justify-between gap-4 border border-gray-200 rounded-lg px-4 py-3 bg-white">
                        <div className="min-w-0">
                          <div className="flex items-center gap-2 mb-0.5">
                            <p className="text-sm font-medium text-gray-900 truncate">{pkg.name}</p>
                            {!pkg.is_active && <span className="text-[10px] bg-gray-100 px-1.5 rounded text-gray-500 uppercase tracking-wide">Silinmiş</span>}
                          </div>
                          <p className="text-xs text-gray-500">₺{pkg.discounted_price.toFixed(2)} · Stock: {pkg.stock}</p>
                        </div>
                        <div className="flex items-center gap-1">
                          <button onClick={() => openEdit(pkg)} className="p-1.5 text-gray-400 hover:text-gray-900 rounded transition-colors"><Edit2 className="w-4 h-4"/></button>
                          <button onClick={() => deletePackage(pkg.id)} className="p-1.5 text-gray-400 hover:text-red-600 rounded transition-colors"><Trash2 className="w-4 h-4"/></button>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
              </div>
            )}

            {/* ANALYTICS */}
            {activeTab === "stats" && (
              <div className="max-w-4xl space-y-8">
                {statsLoading ? (
                  <div className="py-10"><Loader2 className="w-5 h-5 text-gray-400 animate-spin"/></div>
                ) : !stats ? (
                  <p className="text-sm text-gray-500">Data could not be loaded. Please ensure API is running.</p>
                ) : (
                  <>
                    <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                      {[
                        { label:"Toplam Gelir", value:`₺${stats.kpis.totalRevenue.toFixed(0)}` },
                        { label:"Satılan Ürün", value:`${stats.kpis.totalSold}` },
                        { label:"Önlenen İsraf", value:`${stats.kpis.savedFoodKg.toFixed(1)}kg` },
                      ].map(({label,value}) => (
                        <div key={label} className="bg-white border border-gray-200 rounded-lg p-5">
                          <p className="text-xs text-gray-500 font-medium uppercase tracking-wider mb-1">{label}</p>
                          <p className="text-3xl font-semibold tracking-tight text-gray-900">{value}</p>
                        </div>
                      ))}
                    </div>

                    <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                      {stats.weekly_revenue?.length > 0 && (
                        <div className="border border-gray-200 rounded-lg p-5">
                          <p className="text-sm font-semibold text-gray-900 mb-6">Gelir (7 Gün)</p>
                          <div className="h-48 text-xs">
                            <ResponsiveContainer width={100} height={100}>
                              <BarChart data={stats.weekly_revenue} margin={{top:0,right:0,left:-20,bottom:0}}>
                                <XAxis dataKey="date" tickFormatter={v=>v.substring(5,10)} tick={{fill:"#9ca3af"}} axisLine={false} tickLine={false} />
                                <YAxis tick={{fill:"#9ca3af"}} axisLine={false} tickLine={false} tickFormatter={v=>`₺${v}`} />
                                <RechartsTooltip cursor={{fill:"#f3f4f6"}} contentStyle={{borderRadius:8,border:"1px solid #e5e7eb",boxShadow:"0 1px 2px 0 rgba(0,0,0,0.05)",fontSize:12,color:"#f97316"}} formatter={(v:any)=>[`₺${Number(v).toFixed(2)}`,"Gelir"]} labelFormatter={l=>l}/>
                                <Bar dataKey="revenue" fill="#f97316" radius={[4,4,0,0]} barSize={32}/>
                              </BarChart>
                            </ResponsiveContainer>
                          </div>
                        </div>
                      )}

                      {stats.top_packages?.length > 0 && (
                        <div className="border border-gray-200 rounded-lg p-5">
                          <p className="text-sm font-semibold text-gray-900 mb-6">En İyi Satışlar</p>
                          <div className="h-48 text-xs">
                            <ResponsiveContainer width={100} height={100}>
                              <PieChart>
                                <Pie data={stats.top_packages} cx="50%" cy="50%" innerRadius={40} outerRadius={60} paddingAngle={2} dataKey="sales" stroke="none">
                                  {stats.top_packages.map((_:any,i:number)=><Cell key={i} fill={["#f97316","#374151","#6b7280","#9ca3af","#e5e7eb"][i%5]}/>)}
                                </Pie>
                                <RechartsTooltip contentStyle={{borderRadius:8,border:"1px solid #e5e7eb",fontSize:12,color:"#f97316"}} formatter={(v:any)=>[`${v}`,"Satıldı"]}/>
                                <Legend wrapperStyle={{fontSize:11,color:"#6b7280", paddingTop:10}} iconType="circle" iconSize={6}/>
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

            {/* BUSINESS */}
            {activeTab === "business" && (
              <div className="max-w-xl space-y-6">
                {bizInfoLoading ? (
                  <div className="py-10"><Loader2 className="w-5 h-5 text-gray-400 animate-spin"/></div>
                ) : (
                  <>
                  <div className={CARD}>
                    <h2 className="text-sm font-semibold text-gray-900 mb-5">Genel Bilgiler</h2>
                    <div className="space-y-4">
                      <div>
                        <label className="block text-xs font-medium text-gray-600 mb-1.5">İşletme Adı</label>
                        <input value={bizInfo.name} onChange={e=>setBizInfo(p=>({...p,name:e.target.value}))} className={INPUT}/>
                      </div>
                      <div className="grid grid-cols-2 gap-3">
                        <div>
                          <label className="block text-xs font-medium text-gray-600 mb-1.5">İrtibat</label>
                          <input value={bizInfo.phone} onChange={e=>setBizInfo(p=>({...p,phone:e.target.value}))} className={INPUT}/>
                        </div>
                        <div>
                          <label className="block text-xs font-medium text-gray-600 mb-1.5">Tür</label>
                          <select value={bizInfo.category} onChange={e=>setBizInfo(p=>({...p,category:e.target.value}))} className={INPUT}>
                            <option>Restoran</option><option>Kafe</option><option>Pastane</option><option>Diğer</option>
                          </select>
                        </div>
                      </div>
                      <div>
                        <label className="block text-xs font-medium text-gray-600 mb-1.5">Tam Adres</label>
                        <input value={bizInfo.address} onChange={e=>setBizInfo(p=>({...p,address:e.target.value}))} className={INPUT}/>
                      </div>
                      <button onClick={saveBizInfo} disabled={bizInfoSaving||!bizId}
                        className="w-full py-2.5 bg-orange-500 hover:bg-orange-600 disabled:opacity-50 text-white rounded-md text-sm font-medium transition-colors">
                        {bizInfoSaving ? "Kaydediliyor..." : "Değişiklikleri Kaydet"}
                      </button>
                      {bizInfoStatus && <p className="text-xs font-medium text-gray-500 text-center">{bizInfoStatus}</p>}
                    </div>
                  </div>

                  <div className="border border-gray-200 rounded-xl overflow-hidden bg-white">
                    <button className="w-full flex items-center justify-between px-6 py-4 hover:bg-gray-50 transition-colors" onClick={() => setLocExpanded(v=>!v)}>
                      <div>
                        <p className="text-sm font-semibold text-gray-900">Konum Ayarları</p>
                        <p className="text-xs text-gray-500 mt-1">{locLat&&locLon ? `${parseFloat(locLat).toFixed(4)}, ${parseFloat(locLon).toFixed(4)}` : "Ayarlanmadı"}</p>
                      </div>
                      {locExpanded ? <ChevronUp className="w-4 h-4 text-gray-400"/> : <ChevronDown className="w-4 h-4 text-gray-400"/>}
                    </button>
                    {locExpanded && (
                      <div className="px-6 pb-6 pt-2 border-t border-gray-100 space-y-3">
                        <div className="grid grid-cols-2 gap-3">
                          <input type="number" step="0.000001" placeholder="Enlem" value={locLat} onChange={e=>setLocLat(e.target.value)} className={INPUT}/>
                          <input type="number" step="0.000001" placeholder="Boylam" value={locLon} onChange={e=>setLocLon(e.target.value)} className={INPUT}/>
                        </div>
                        <div className="grid grid-cols-2 gap-3 pt-1">
                          <button onClick={getGPS} disabled={isLocating} className="bg-gray-50 hover:bg-gray-100 text-gray-700 text-xs font-medium py-2.5 rounded-md transition-colors border border-gray-200">{isLocating?"Konum Alınıyor...":"Mevcut Konumu Kullan"}</button>
                          <button onClick={saveLocation} disabled={isSavingLoc||!locLat||!locLon} className="bg-orange-500 text-white text-xs font-medium py-2.5 rounded-md hover:bg-orange-600 transition-colors">{isSavingLoc?"Kaydediliyor...":"Koordinatları Kaydet"}</button>
                        </div>
                        {locStatus && <p className="text-xs text-gray-500 text-center">{locStatus}</p>}
                      </div>
                    )}
                  </div>
                  </>
                )}
              </div>
            )}

          </main>
        </div>

        {/* MODAL */}
        {editingPkg && (
          <div className="fixed inset-0 z-50 flex items-center justify-center bg-orange-500/40 backdrop-blur-sm p-4 animate-in fade-in" onClick={e => { if (e.target === e.currentTarget) setEditingPkg(null); }}>
            <div className="bg-white rounded-xl w-full max-w-sm mx-4 overflow-hidden shadow-2xl animate-in fade-in zoom-in-95">
              <div className="flex items-center justify-between p-5 border-b border-gray-100">
                <h2 className="text-sm font-semibold text-gray-900">İlanı Düzenle</h2>
                <button onClick={() => setEditingPkg(null)} className="text-gray-400 hover:text-gray-900 transition-colors"><XCircle className="w-5 h-5"/></button>
              </div>
              <form onSubmit={handleEditSubmit} className="p-5 space-y-4">
                <div className="space-y-3">
                  <input required value={editData.name} onChange={e=>setEditData(p=>({...p,name:e.target.value}))} placeholder="Ürün Adı" className={INPUT}/>
                  <div className="grid grid-cols-2 gap-3">
                    <input required type="number" step="0.01" value={editData.original_price} onChange={e=>setEditData(p=>({...p,original_price:e.target.value}))} placeholder="Orijinal Fiyat ₺" className={INPUT}/>
                    <input required type="number" step="0.01" value={editData.discounted_price} onChange={e=>setEditData(p=>({...p,discounted_price:e.target.value}))} placeholder="İndirimli Fiyat ₺" className={INPUT}/>
                  </div>
                  <div className="grid grid-cols-2 gap-3">
                    <input required type="number" value={editData.stock} onChange={e=>setEditData(p=>({...p,stock:e.target.value}))} placeholder="Stok Adedi" className={INPUT}/>
                    <select required value={editData.category} onChange={e=>setEditData(p=>({...p,category:e.target.value}))} className={INPUT}>
                      <option>Sıcak Yemek</option><option>Soğuk Sandviç</option><option>Tatlı & Pastane</option><option>Vegan</option><option>İçecek</option><option>Diğer</option>
                    </select>
                  </div>
                  <label className="flex items-center gap-2.5 cursor-pointer mt-4 py-2">
                    <input type="checkbox" checked={editData.is_active} onChange={e=>setEditData(p=>({...p,is_active:e.target.checked}))} className="w-4 h-4 rounded border-gray-300 text-gray-900 focus:ring-orange-500 accent-orange-500"/>
                    <span className="text-sm text-gray-600">Aktif (Müşteriler sipariş verebilir)</span>
                  </label>
                </div>
                <button type="submit" className="w-full py-2.5 bg-orange-500 text-white hover:bg-orange-600 rounded-md text-sm font-medium transition-colors">Ayarları Kaydet</button>
                {editStatus && <p className="text-xs text-center text-gray-500">{editStatus}</p>}
              </form>
            </div>
          </div>
        )}

        {/* MOBILE NAV */}
        <nav className="md:hidden fixed bottom-0 inset-x-0 bg-white/95 backdrop-blur-md border-t border-gray-200 flex z-20 pb-safe">
          {TABS.map(({id,label,Icon}) => (
            <button key={id} onClick={()=>setActiveTab(id)}
              className={`flex-1 flex flex-col items-center gap-1 py-3 transition-colors ${activeTab===id?"text-gray-900":"text-gray-400 hover:text-gray-600"}`}>
              <Icon className="w-5 h-5"/>
              <span className="text-[10px] sm:text-[11px] font-medium truncate px-1 text-center w-full">{label}</span>
            </button>
          ))}
        </nav>

      </div>
    </div>
  );
}
