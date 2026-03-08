"use client";

import { useEffect, useState, useRef } from "react";
import { Html5QrcodeScanner } from "html5-qrcode";

export default function QRScanner() {
  const [scanResult, setScanResult] = useState<string | null>(null);
  const [statusMessage, setStatusMessage] = useState<string>("");
  const [isError, setIsError] = useState<boolean>(false);
  const [isScanning, setIsScanning] = useState<boolean>(true);
  const scannerRef = useRef<Html5QrcodeScanner | null>(null);

  // Bu API URL'sini kendi sunucu adresinize veya public ngrok URL'inize çevirmeniz gerekebilir.
  const API_URL = "http://localhost:3001/api/v1/delivery/confirm";

  useEffect(() => {
    // Component yüklendiğinde scanner'ı saniyede 10 frame ile başlat
    const scanner = new Html5QrcodeScanner(
      "qr-reader",
      { fps: 10, qrbox: { width: 250, height: 250 } },
      false,
    );

    scannerRef.current = scanner;

    scanner.render(
      (decodedText) => {
        // Başarılı okuma
        if (isScanning) {
          setIsScanning(false);
          setScanResult(decodedText);
          verifyOrder(decodedText, scanner);
        }
      },
      (error) => {
        // Hata durumları (kameraları falan algılamadığında) çok log basar, burayı genelde boş bırakırız
      },
    );

    return () => {
      // Component unmount olduğunda kamerayı kapat
      scanner
        .clear()
        .catch((error) => console.error("Scanner kapatılırken hata:", error));
    };
  }, [isScanning]);

  const verifyOrder = async (orderId: string, scanner: Html5QrcodeScanner) => {
    setStatusMessage("Doğrulanıyor... Lütfen bekleyin.");
    setIsError(false);

    // Tarayıcıyı kısa süreliğine durdur
    scanner.pause(true);

    try {
      const response = await fetch(API_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          // 'Authorization': 'Bearer ADMIN_TOKEN', // Geliştirmede eklenecek
        },
        body: JSON.stringify({ order_id: orderId }),
      });

      const data = await response.json();

      if (response.ok) {
        setIsError(false);
        setStatusMessage(data.message || "Paket Başarıyla Teslim Edildi! ✅");
      } else {
        setIsError(true);
        setStatusMessage(data.error || "Geçersiz veya kullanılmış barkod! ❌");
      }
    } catch (error) {
      setIsError(true);
      setStatusMessage(
        "Sunucuya bağlanılamadı. Lütfen internetinizi kontrol edin.",
      );
    }

    // 3 saniye sonra tarayıcıyı tekrar aktif et
    setTimeout(() => {
      setScanResult(null);
      setStatusMessage("");
      setIsScanning(true);
      scanner.resume();
    }, 3500);
  };

  return (
    <div className="flex flex-col items-center justify-center min-h-screen bg-gray-100 p-6">
      <div className="w-full max-w-md bg-white rounded-2xl shadow-xl overflow-hidden">
        {/* Header */}
        <div className="bg-orange-600 p-6 text-center">
          <h1 className="text-2xl font-bold text-white">
            Yemekhane Kantin Gişesi
          </h1>
          <p className="text-orange-100 text-sm mt-1">Öğrenci Kodu Tarayıcı</p>
        </div>

        {/* Scanner Body */}
        <div className="p-6 flex flex-col items-center">
          {/* Kamera Divi */}
          <div
            id="qr-reader"
            className="w-full h-64 bg-gray-200 border-2 border-dashed border-gray-400 rounded-lg overflow-hidden flex items-center justify-center mb-6"
          ></div>

          {/* Sonuç Göstergesi */}
          {statusMessage && (
            <div
              className={`w-full p-4 rounded-lg text-center font-bold animate-pulse ${isError ? "bg-red-100 text-red-700 border border-red-300" : "bg-green-100 text-green-700 border border-green-300"}`}
            >
              <span className="block text-3xl mb-2">
                {isError ? "❌" : "✅"}
              </span>
              {statusMessage}

              {scanResult && !isError && (
                <span className="block text-xs font-normal text-gray-500 mt-2">
                  ID: {scanResult}
                </span>
              )}
            </div>
          )}

          {!statusMessage && (
            <p className="text-gray-500 text-center text-sm">
              Lütfen telefonunuzdan açtığınız sipariş karekodunu kameraya
              okutun.
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
