"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import Image from "next/image";
import { supabase } from "../../lib/supabaseClient";

const ERROR_MESSAGES: Record<string, string> = {
  invalid_credentials: "E-posta veya şifre hatalı. Lütfen kontrol edip tekrar deneyin.",
  email_not_confirmed: "E-posta adresiniz henüz doğrulanmamış. Lütfen gelen kutunuzu kontrol edin.",
  over_email_send_rate_limit: "Çok fazla deneme yaptınız. Lütfen biraz bekleyip tekrar deneyin.",
  user_not_found: "Bu e-posta adresiyle kayıtlı bir hesap bulunamadı.",
};

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (session) router.replace("/");
    });
  }, [router]);

  async function handleLogin(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    setLoading(false);
    if (error) {
      const code = (error as { code?: string }).code ?? "";
      setError(ERROR_MESSAGES[code] ?? error.message);
    } else {
      router.push("/");
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <form
        onSubmit={handleLogin}
        className="bg-white rounded-2xl border border-gray-100 p-8 w-full max-w-sm space-y-4 shadow-sm"
      >
        <div className="text-center mb-2">
          <div className="w-20 h-20 mx-auto mb-3 rounded-xl overflow-hidden shadow-md">
            <Image
              src="/yemekhane-logo.png"
              alt="Yemekhane Logo"
              width={80}
              height={80}
              priority
              className="w-full h-full object-cover"
            />
          </div>
          <h1 className="text-xl font-semibold text-gray-900">İşletme Girişi</h1>
          <p className="text-xs text-gray-400 mt-1">İşletme yönetim paneline giriş yapın</p>
        </div>
        {error && (
          <p className="text-sm text-red-600 bg-red-50 rounded-lg px-3 py-2">{error}</p>
        )}
        <div>
          <label className="block text-sm text-gray-600 mb-1">E-posta</label>
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            className="w-full bg-white border border-gray-300 rounded-xl px-4 py-3 text-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-orange-400 focus:border-transparent"
          />
        </div>
        <div>
          <label className="block text-sm text-gray-600 mb-1">Şifre</label>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            className="w-full bg-white border border-gray-300 rounded-xl px-4 py-3 text-sm text-gray-900 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-orange-400 focus:border-transparent"
          />
        </div>
        <button
          type="submit"
          disabled={loading}
          className="w-full bg-orange-500 text-white rounded-xl py-3 text-sm font-medium hover:bg-orange-600 disabled:opacity-50"
        >
          {loading ? "Giriş yapılıyor..." : "Giriş Yap"}
        </button>
        <p className="text-center text-sm text-gray-500">
          Hesabınız yok mu?{" "}
          <Link href="/signup" className="text-orange-500 font-medium hover:underline">
            Kayıt Ol
          </Link>
        </p>
      </form>
    </div>
  );
}
