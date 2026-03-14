const fs = require('fs');
const onboardingCode = `"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabaseClient";
import { Save, User, MapPin, Map, Loader2, Navigation } from "lucide-react";

export default function OnboardingPage() {
  const router = useRouter();
  const [userEmail, setUserEmail] = useState("");
  const [loading, setLoading] = useState(false);
  const [fetchLocationLoading, setFetchLocationLoading] = useState(false);
  const [locationStatus, setLocationStatus] = useState<"idle" | "success" | "error">("idle");
  const [formData, setFormData] = useState({
    restaurant_name: "",
    address: "",
    latitude: "",
    longitude: "",
  });

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (!session) {
        router.replace("/login");
      } else {
        setUserEmail(session.user.email || "");
      }
    });
  }, [router]);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    setFormData({ ...formData, [e.target.name]: e.target.value });
  };

  const handleFetchLocation = () => {
    if (!navigator.geolocation) {
      alert("Tarayıcınız konum servisini desteklemiyor.");
      return;
    }
    setFetchLocationLoading(true);
    setLocationStatus("idle");
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setFormData((prev) => ({
          ...prev,
          latitude: position.coords.latitude.toString(),
          longitude: position.coords.longitude.toString(),
        }));
        setFetchLocationLoading(false);
        setLocationStatus("success");
      },
      (error) => {
        alert("Konum alınamadı. Lütfen izinleri kontrol edin.");
        setFetchLocationLoading(false);
        setLocationStatus("error");
      }
    );
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    const { data: userData, error: userError } = await supabase.auth.getUser();
    if (userError || !userData?.user) {
      alert("Kullanıcı doğrulama hatası. Lütfen tekrar giriş yapın.");
      setLoading(false);
      return;
    }

    const payload = {
      restaurant_id: userData.user.id,
      restaurant_name: formData.restaurant_name,
      address: formData.address,
      latitude: parseFloat(formData.latitude) || 0,
      longitude: parseFloat(formData.longitude) || 0,
    };

    const { error } = await supabase.from("restaurants").insert([payload]);

    if (error) {
      console.error(error);
      alert("Kayıt oluşturulurken bir hata oluştu");
    } else {
      router.push("/");
    }
    setLoading(false);
  };

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col items-center py-12 px-4 sm:px-6 lg:px-8">
      <div className="w-full max-w-xl bg-white rounded-3xl shadow-[0_2px_12px_-4px_rgba(0,0,0,0.05)] border border-gray-100 overflow-hidden">
        <div className="border-b border-gray-100 bg-white p-8">
          <h1 className="text-2xl font-bold text-gray-900">İşletme Profili Oluştur</h1>
          <p className="text-sm text-gray-500 mt-2">Müşterilerinize işletmenizi tanıtın ({userEmail})</p>
        </div>

        <form onSubmit={handleSubmit} className="p-8 space-y-10 bg-gray-50/30">
          {/* Section: Basic Info */}
          <div>
            <div className="flex items-center gap-2 mb-6 text-gray-900 border-b border-gray-200 pb-3">
              <User className="w-5 h-5 text-orange-600" />
              <h2 className="font-semibold text-lg">Temel Bilgiler</h2>
            </div>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Restoran / İşletme Adı</label>
                <input
                  type="text"
                  name="restaurant_name"
                  required
                  value={formData.restaurant_name}
                  onChange={handleChange}
                  placeholder="Örn: Lezzet Dünyası"
                  className="w-full bg-white border border-gray-200 rounded-xl px-4 py-3 text-sm focus:border-orange-500 focus:ring-1 focus:ring-orange-500 outline-none transition-all shadow-sm"
                />
              </div>
            </div>
          </div>

          {/* Section: Location Info */}
          <div>
            <div className="flex items-center gap-2 mb-6 text-gray-900 border-b border-gray-200 pb-3">
              <MapPin className="w-5 h-5 text-orange-600" />
              <h2 className="font-semibold text-lg">Konum & İletişim</h2>
            </div>
            <div className="space-y-6">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Açık Adres</label>
                <textarea
                  name="address"
                  required
                  rows={3}
                  value={formData.address}
                  onChange={handleChange}
                  placeholder="Mahalle, Sokak, No..."
                  className="w-full bg-white border border-gray-200 rounded-xl px-4 py-3 text-sm focus:border-orange-500 focus:ring-1 focus:ring-orange-500 outline-none transition-all resize-none shadow-sm"
                />
              </div>

              <div className="bg-orange-50/50 border border-orange-100 rounded-2xl p-5">
                <label className="block text-sm font-medium text-gray-900 mb-3 flex items-center gap-2">
                  <Navigation className="w-4 h-4 text-orange-600" />
                  Harita Konumu
                </label>
                
                <div className="space-y-4">
                  <button
                    type="button"
                    onClick={handleFetchLocation}
                    disabled={fetchLocationLoading}
                    className="w-full inline-flex items-center justify-center gap-2 px-6 py-3.5 bg-orange-600 text-white hover:bg-orange-700 rounded-xl font-medium text-sm transition-all shadow-sm active:scale-[0.99] disabled:opacity-70"
                  >
                    {fetchLocationLoading ? <Loader2 className="w-5 h-5 animate-spin" /> : <Map className="w-5 h-5" />}
                    {fetchLocationLoading ? "Konum Bulunuyor..." : "Mevcut Konumumu Kullan"}
                  </button>

                  {locationStatus === "success" && (
                    <div className="text-center p-3 text-sm font-medium text-green-700 bg-green-50 rounded-lg border border-green-100 flex items-center justify-center gap-2">
                      <div className="w-2 h-2 rounded-full bg-green-500 animate-pulse" />
                      Konum başarıyla alındı
                    </div>
                  )}

                  {/* Hidden inputs to send with form */}
                  <input type="hidden" name="latitude" value={formData.latitude} required />
                  <input type="hidden" name="longitude" value={formData.longitude} required />
                  
                  <p className="text-xs text-center text-gray-500">
                    Müşterilerinizin sizi haritada kolayca bulabilmesi için cihazınızın konumunu paylaşmanız gerekir.
                  </p>
                </div>
              </div>
            </div>
          </div>

          <div className="pt-4 border-t border-gray-100">
            <button
              type="submit"
              disabled={loading || !formData.latitude}
              className="w-full bg-slate-900 text-white rounded-xl py-4 text-sm font-semibold hover:bg-slate-800 disabled:opacity-50 transition-all shadow-md hover:shadow-lg inline-flex items-center justify-center gap-2 active:scale-[0.99]"
            >
              {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : <Save className="w-5 h-5" />}
              {loading ? "Kaydediliyor..." : "Profili Tamamla ve Başla"}
            </button>
            {!formData.latitude && !loading && (
              <p className="text-center text-xs text-red-500 mt-3 font-medium">
                * Lütfen devam etmeden önce konumunuzu alın
              </p>
            )}
          </div>
        </form>
      </div>
    </div>
  );
}`;
fs.writeFileSync('app/onboarding/page.tsx', onboardingCode);
console.log('Onboarding modified');
