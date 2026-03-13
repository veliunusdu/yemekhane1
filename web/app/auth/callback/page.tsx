"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { supabase } from "../../../lib/supabaseClient";

export default function AuthCallbackPage() {
  const router = useRouter();

  useEffect(() => {
    // Supabase client automatically detects the #access_token hash on load
    // and exchanges it for a session. We just wait for that to complete.
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      if (event === "SIGNED_IN" && session) {
        subscription.unsubscribe();
        router.replace("/");
      }
    });

    // Fallback: if already signed in (e.g. hash was processed before listener attached)
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (session) {
        subscription.unsubscribe();
        router.replace("/");
      }
    });

    return () => subscription.unsubscribe();
  }, [router]);

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="text-center space-y-3">
        <div className="w-12 h-12 border-4 border-orange-500 border-t-transparent rounded-full animate-spin mx-auto" />
        <p className="text-sm text-gray-500">Giriş yapılıyor...</p>
      </div>
    </div>
  );
}
