"use client";

import { useEffect, useState, useRef } from "react";
import { useRouter } from "next/navigation";
import { Html5QrcodeScanner } from "html5-qrcode";
import { supabase } from "../../lib/supabaseClient";

export default function QRScanner() {
  const router = useRouter();
  const [scanResult, setScanResult] = useState<string | null>(null);
  const [statusMessage, setStatusMessage] = useState<string>("");
  const [isError, setIsError] = useState<boolean>(false);
  const [authChecked, setAuthChecked] = useState(false);
  const scannerRef = useRef<Html5QrcodeScanner | null>(null);

  const API_URL = "http://localhost:3001/api/v1/delivery/confirm";

  // Auth kontrolü — giriş yapılmamışsa login'e yönlendir
  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (!session) {
        router.replace("/login");
      } else {
        setAuthChecked(true);
      }
    });
  }, [router]);

  useEffect(() => {
    if (!authChecked) return;

    const scanner = new Html5QrcodeScanner(
      "qr-reader",
      { fps: 10, qrbox: { width: 250, height: 250 } },
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
      () => {}
    );

    return () => {
      scanner.clear().catch(() => {});
    };
  }, [authChecked]);

  const handleScanSuccess = async (decodedText: string) => {
    setStatusMessage("Doğrulanıyor... Lütfen bekleyin.");
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
          "Authorization": `Bearer ${token}`,
        },
        body: JSON.stringify({ order_id: decodedText }),
      });

      const data = await response.json();

      if (response.ok) {
        setIsError(false);
        setStatusMessage(data.message || "Paket Başarıyla Teslim Edildi! ✅");
      } else {
        setIsError(true);
        setStatusMessage(data.error || "Geçersiz veya kullanılmış barkod! ❌");
      }
    } catch {
      setIsError(true);
      setStatusMessage("Sunucuya bağlanılamadı. Lütfen internetinizi kontrol edin.");
    }

    setTimeout(() => {
      setScanResult(null);
      setStatusMessage("");
      try {
        scannerRef.current?.resume();
      } catch {}
    }, 3500);
  };

  if (!authChecked) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-gray-100">
        <div className="text-gray-500 text-sm">Yükleniyor...</div>
      </div>
    );
  }

  return (
    <div className="flex flex-col items-center justify-center min-h-screen bg-gray-100 p-6">
      <div className="w-full max-w-md bg-white rounded-2xl shadow-xl overflow-hidden">
        <div className="bg-orange-600 p-6 text-center">
          <h1 className="text-2xl font-bold text-white">Yemekhane Kantin Gişesi</h1>
          <p className="text-orange-100 text-sm mt-1">Sipariş Teslim Tarayıcısı</p>
        </div>

        <div className="p-6 flex flex-col items-center">
          <div
            id="qr-reader"
            className="w-full h-64 bg-gray-200 border-2 border-dashed border-gray-400 rounded-lg overflow-hidden flex items-center justify-center mb-6"
          />

          {statusMessage && (
            <div
              className={`w-full p-4 rounded-lg text-center font-bold animate-pulse ${
                isError
                  ? "bg-red-100 text-red-700 border border-red-300"
                  : "bg-green-100 text-green-700 border border-green-300"
              }`}
            >
              <span className="block text-3xl mb-2">{isError ? "❌" : "✅"}</span>
              {statusMessage}
              {scanResult && !isError && (
                <span className="block text-xs font-normal text-gray-500 mt-2">
                  Sipariş ID: {scanResult}
                </span>
              )}
            </div>
          )}

          {!statusMessage && (
            <p className="text-gray-500 text-center text-sm">
              Müşterinin telefonundaki sipariş QR kodunu kameraya okutun.
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
