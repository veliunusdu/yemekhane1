"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

// This page has been merged into the main business dashboard (/).
export default function OrdersRedirect() {
  const router = useRouter();
  useEffect(() => { router.replace("/"); }, [router]);
  return null;
}
