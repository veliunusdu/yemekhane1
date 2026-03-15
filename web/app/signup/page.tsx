"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { Eye, EyeOff, Loader2, ArrowRight, CheckCircle2 } from "lucide-react";
import { supabase } from "../../lib/supabaseClient";

export default function SignupPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState(false);

  async function handleSignup(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError("");

    if (password.length < 6) {
      setError("Şifre en az 6 karakter olmalıdır.");
      setLoading(false);
      return;
    }

    const { error: signUpError } = await supabase.auth.signUp({
      email,
      password,
    });

    if (signUpError) {
      if (signUpError.message.includes("User already registered")) {
        setError("Bu e-posta adresiyle kayıtlı bir hesap zaten var.");
      } else {
        setError(signUpError.message || "Kayıt sırasında bir hata oluştu.");
      }
      setLoading(false);
    } else {
      setSuccess(true);
      setLoading(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-white p-4">
      <div className="w-full max-w-[360px] space-y-8">
        <div className="space-y-2">
          <div className="h-8 w-8 bg-orange-500 rounded-lg mb-6 shadow-sm flex items-center justify-center">
            <span className="text-white text-xs font-bold font-mono">YH</span>
          </div>
          <h1 className="text-2xl font-semibold tracking-tight text-gray-900">Create account</h1>
          <p className="text-sm text-gray-500">Enter your details to get started.</p>
        </div>

        {success ? (
          <div className="space-y-6">
            <div className="rounded-md border border-gray-200 p-4 flex gap-3 text-sm">
              <CheckCircle2 className="h-5 w-5 text-gray-900 shrink-0" />
              <div>
                <p className="font-medium text-gray-900">Account created</p>
                <p className="text-gray-500 mt-1">Your account has been successfully created. You can now log in to the dashboard.</p>
              </div>
            </div>
            <Link
              href="/login"
              className="flex w-full items-center justify-center gap-2 rounded-md bg-orange-500 px-4 py-2.5 text-sm font-medium text-white transition-opacity hover:bg-orange-600"
            >
              Go to login
            </Link>
          </div>
        ) : (
          <form onSubmit={handleSignup} className="space-y-5">
            <div className="space-y-4">
              <div className="space-y-1.5">
                <label htmlFor="email" className="text-sm font-medium text-gray-700">Email address</label>
                <input
                  id="email"
                  type="email"
                  required
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="w-full rounded-md border border-gray-200 bg-transparent px-3 py-2 text-sm text-gray-900 placeholder-gray-400 focus:border-orange-500 focus:outline-none focus:ring-1 focus:ring-orange-500 transition-colors"
                  placeholder="name@company.com"
                />
              </div>

              <div className="space-y-1.5">
                <label htmlFor="password" className="text-sm font-medium text-gray-700">Password</label>
                <div className="relative">
                  <input
                    id="password"
                    type={showPassword ? "text" : "password"}
                    required
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    className="w-full rounded-md border border-gray-200 bg-transparent px-3 py-2 text-sm text-gray-900 placeholder-gray-400 focus:border-orange-500 focus:outline-none focus:ring-1 focus:ring-orange-500 transition-colors pr-10"
                    placeholder="At least 6 characters"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-2 top-1/2 -translate-y-1/2 p-1 text-gray-400 hover:text-gray-900 transition-colors"
                  >
                    {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                  </button>
                </div>
              </div>
            </div>

            {error && (
              <div className="text-sm text-red-500">
                {error}
              </div>
            )}

            <button
              type="submit"
              disabled={loading}
              className="flex w-full items-center justify-center gap-2 rounded-md bg-orange-500 px-4 py-2.5 text-sm font-medium text-white transition-opacity hover:bg-orange-600 disabled:cursor-not-allowed disabled:opacity-50"
            >
              {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
              {loading ? "Creating..." : "Kayıt ol"} <ArrowRight className="h-4 w-4" />
            </button>
          </form>
        )}

        {!success && (
          <div className="text-sm text-gray-500">
            Already have an account?{" "}
            <Link href="/login" className="text-gray-900 font-medium hover:underline underline-offset-4">
              Log in
            </Link>
          </div>
        )}
      </div>
    </div>
  );
}
