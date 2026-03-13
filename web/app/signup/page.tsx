"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "../../lib/supabaseClient";
import Link from "next/link";

export default function SignupPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [success, setSuccess] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (session) router.replace("/");
    });
  }, [router]);

  async function handleSignup(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);
    
    const { data, error } = await supabase.auth.signUp({ 
      email, 
      password,
      options: {
        emailRedirectTo: `${window.location.origin}/auth/callback`,
      },
    });

    setLoading(false);
    if (error) {
      setError(error.message);
    } else if (data.session) {
      // Email confirmation disabled — logged in immediately
      router.push("/");
    } else {
      setSuccess(true);
    }
  }

  if (success) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50 p-4">
        <div className="bg-white rounded-2xl border border-gray-100 p-8 w-full max-w-sm space-y-4 shadow-sm text-center">
          <div className="w-16 h-16 bg-green-50 text-green-500 rounded-full flex items-center justify-center mx-auto mb-4">
            <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M5 13l4 4L19 7" />
            </svg>
          </div>
          <h1 className="text-xl font-semibold text-gray-900">Kayıt Başarılı!</h1>
          <p className="text-sm text-gray-600">
            E-posta adresinize bir onay linki gönderdik. Lütfen kutunuzu kontrol edin.
          </p>
          <Link
            href="/login"
            className="block w-full bg-orange-500 text-white rounded-xl py-3 text-sm font-medium hover:bg-orange-600"
          >
            Giriş Sayfasına Dön
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 p-4">
      <form
        onSubmit={handleSignup}
        className="bg-white rounded-2xl border border-gray-100 p-8 w-full max-w-sm space-y-4 shadow-sm"
      >
        <div className="text-center mb-6">
          <div className="w-12 h-12 bg-orange-100 text-orange-600 rounded-xl flex items-center justify-center mx-auto mb-3 text-2xl">
            🍱
          </div>
          <h1 className="text-xl font-semibold text-gray-900">İşletme Hesabı Oluştur</h1>
          <p className="text-sm text-gray-500 mt-1">Yemekhane platformuna katılın</p>
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
            placeholder="ornek@isletme.com"
            className="w-full bg-gray-50 border border-gray-200 rounded-xl px-4 py-3 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
          />
        </div>
        
        <div>
          <label className="block text-sm text-gray-600 mb-1">Şifre</label>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            minLength={6}
            placeholder="••••••••"
            className="w-full bg-gray-50 border border-gray-200 rounded-xl px-4 py-3 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400"
          />
        </div>

        <button
          type="submit"
          disabled={loading}
          className="w-full bg-orange-500 text-white rounded-xl py-3 text-sm font-medium hover:bg-orange-600 disabled:opacity-50 transition-colors"
        >
          {loading ? "Hesap oluşturuluyor..." : "Kayıt Ol"}
        </button>

        <div className="text-center pt-2">
          <p className="text-xs text-gray-500">
            Zaten hesabınız var mı?{" "}
            <Link href="/login" className="text-orange-500 font-semibold hover:underline">
              Giriş Yap
            </Link>
          </p>
        </div>
      </form>
    </div>
  );
}
