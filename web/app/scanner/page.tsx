"use client";

import { useEffect, useState, useRef } from "react";
import { useRouter } from "next/navigation";
import { Html5QrcodeScanner } from "html5-qrcode";
import { supabase } from "../../lib/supabaseClient";
import { CheckCircle2, XCircle, ScanLine, Loader2, ArrowLeft } from "lucide-react";

export default function QRScanner() {
  const router = useRouter();
  const [scanResult, setScanResult] = useState<string | null>(null);
  const [statusMessage, setStatusMessage] = useState<string>("");
  const [isError, setIsError] = useState<boolean>(false);
  const [authChecked, setAuthChecked] = useState(false);
  const scannerRef = useRef<Html5QrcodeScanner | null>(null);

  const API_URL = `${process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:3001"}/api/v1/delivery/confirm`;

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (!session) {
        router.replace("/login");
      } else {
        setAuthChecked(true);
      }
    });

    return () => {
      if (scannerRef.current) {
        scannerRef.current.clear().catch(() => {});
      }
    };
  }, [router]);

  useEffect(() => {
    if (!authChecked) return;

    const scanner = new Html5QrcodeScanner(
      "qr-reader",
      { fps: 15, qrbox: { width: 320, height: 320 } },
      false
    );

    scannerRef.current = scanner;

    scanner.render(
      (decodedText) => {
        setScanResult((prev) => {
          if (prev === null) {
            handleScanSuccess(decodedText);
            return decodedText;
          }
          return prev;
        });
      },
      () => {} // Quiet down logs
    );

    return () => {
      scanner.clear().catch(() => {});
    };
  }, [authChecked]);

  const handleScanSuccess = async (decodedText: string) => {
    setStatusMessage("İşleniyor...");
    setIsError(false);

    try {
      scannerRef.current?.pause(true);
    } catch {}

    try {
      const { data: { session } } = await supabase.auth.getSession();
      const token = session?.access_token ?? "";

      const response = await fetch(API_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${token}`
        },
        body: JSON.stringify({ order_id: decodedText }),
      });

      const data = await response.json();

      if (response.ok) {
        setIsError(false);
        setStatusMessage(data.message || "Başarıyla Teslim Edildi!");
      } else {
        setIsError(true);
        setStatusMessage(data.error || "Geçersiz İşlem!");
      }
    } catch {
      setIsError(true);
      setStatusMessage("Bağlantı Hatası");
    }

    setTimeout(() => {
      setScanResult(null);
      setStatusMessage("");
      try {
        scannerRef.current?.resume();
      } catch {}
    }, 3000);
  };

  if (!authChecked) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-orange-500">
        <div className="flex flex-col items-center gap-3 text-white/50">
          <Loader2 className="w-8 h-8 animate-spin" />
          <span className="text-sm font-medium">Sistem Başlatılıyor</span>
        </div>
      </div>
    );
  }

  return (
    <div className="relative min-h-[100dvh] bg-orange-500 flex flex-col items-center justify-center overflow-hidden selection:bg-transparent">
      <button 
        onClick={() => router.push("/")}
        className="absolute top-6 left-6 z-50 p-3 bg-orange-500/40 hover:bg-orange-500/60 backdrop-blur-md rounded-full text-white transition-all shadow-lg active:scale-95 border border-white/10"
      >
        <ArrowLeft className="w-6 h-6" />
      </button>

      <div className="w-full h-[100dvh] absolute inset-0 flex items-center justify-center pointer-events-auto">
        <div
          id="qr-reader"
          className="w-full h-full [&_video]:object-cover border-none bg-orange-500"
        />
      </div>

      <div className="absolute inset-0 z-10 pointer-events-none shadow-[inset_0_0_200px_rgba(0,0,0,0.95)]" />

      {/* Floating Status Indicator Overlay */}
      {statusMessage && (
        <div className="absolute inset-0 z-50 flex items-center justify-center p-6 bg-orange-500/70 backdrop-blur-sm animate-in fade-in duration-200">
          <div className={`flex flex-col items-center justify-center w-full max-w-sm p-10 rounded-[2.5rem] shadow-2xl animate-in zoom-in-95 duration-200 text-center ${isError ? "bg-red-600/90 box-shadow-[0_0_100px_rgba(220,38,38,0.4)]" : statusMessage === "İşleniyor..." ? "bg-white/10" : "bg-green-600/90 box-shadow-[0_0_100px_rgba(22,163,74,0.4)]"}`}>
            {isError ? (
              <XCircle className="w-24 h-24 text-white mb-6 animate-in zoom-in" />
            ) : statusMessage === "İşleniyor..." ? (
              <Loader2 className="w-20 h-20 text-white mb-6 animate-spin" />
            ) : (
              <CheckCircle2 className="w-24 h-24 text-white mb-6 animate-in zoom-in" />
            )}
            <h2 className="text-white text-3xl font-extrabold tracking-tight leading-tight">
              {statusMessage}
            </h2>
          </div>
        </div>
      )}

      {/* Default Idle State */}
      {!statusMessage && (
        <div className="absolute bottom-16 z-20 pointer-events-none flex flex-col items-center gap-4">
          <ScanLine className="w-14 h-14 text-white/60 animate-pulse" />
          <div className="bg-orange-500/50 backdrop-blur-md px-10 py-5 rounded-full border border-white/10 shadow-2xl">
            <p className="text-white font-bold tracking-[0.25em] text-sm">QR OKUTUN</p>
          </div>
        </div>
      )}
    </div>
  );
}