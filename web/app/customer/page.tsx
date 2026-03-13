"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

// Müşteri deneyimi mobil uygulama üzerinden yönetilir.
// Bu sayfa iş letme paneliyle çakışmasın diye login'e yönlendirir.
export default function CustomerRedirect() {
  const router = useRouter();
  useEffect(() => { router.replace("/login"); }, [router]);
  return null;
}
