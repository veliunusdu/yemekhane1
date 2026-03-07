"use client";

import { useEffect, useState } from "react";

export default function OrdersPage() {
  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  const fetchOrders = async () => {
    setLoading(true);
    setError("");
    try {
      const res = await fetch("http://localhost:3001/api/v1/business/orders");
      if (res.ok) {
        const data = await res.json();
        setOrders(data);
      } else {
        setError("Siparişler getirilemedi.");
      }
    } catch (err) {
      setError("Bağlantı hatası: Go API çalışıyor mu?");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchOrders();
    // Otomatik yenileme: Her 15 saniyede bir siparişleri kontrol et
    const interval = setInterval(fetchOrders, 15000);
    return () => clearInterval(interval);
  }, []);

  return (
    <main className="min-h-screen bg-gray-100 p-8">
      <div className="max-w-6xl mx-auto bg-white rounded-xl shadow-md overflow-hidden">
        {/* Header */}
        <div className="p-6 border-b border-gray-200 flex justify-between items-center bg-gray-50">
          <div>
            <h1 className="text-3xl font-extrabold text-gray-800">
              Canlı Sipariş Paneli
            </h1>
            <p className="text-sm text-gray-500 mt-1">
              Gelen tüm siparişleri ve ödeme durumlarını buradan anlık olarak takip edebilirsiniz.
            </p>
          </div>
          <button
            onClick={fetchOrders}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition"
          >
            <span>🔄</span> Yenile
          </button>
        </div>

        {/* Content */}
        <div className="p-6">
          {error && (
            <div className="mb-4 p-4 bg-red-100 text-red-700 rounded-lg">
              {error}
            </div>
          )}

          {loading && orders.length === 0 ? (
            <div className="text-center py-10 text-gray-500">
              Yükleniyor...
            </div>
          ) : orders.length === 0 ? (
            <div className="text-center py-10 text-gray-500 text-lg">
              Henüz sipariş bulunmuyor.
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="bg-gray-100 text-gray-700 text-sm uppercase tracking-wider">
                    <th className="p-4 rounded-tl-lg">Sipariş ID</th>
                    <th className="p-4">Paket Adı</th>
                    <th className="p-4">Alıcı E-postası</th>
                    <th className="p-4">Durum</th>
                    <th className="p-4 rounded-tr-lg">Tarih</th>
                  </tr>
                </thead>
                <tbody className="text-gray-700">
                  {orders.map((order: any, index: number) => {
                    const isSuccess = order.status === "Ödendi" || order.status === "SUCCESS";
                    return (
                      <tr 
                        key={order.id} 
                        className={`border-b border-gray-100 hover:bg-gray-50 transition ${index % 2 === 0 ? 'bg-white' : 'bg-gray-50/50'}`}
                      >
                        <td className="p-4 font-mono text-xs text-gray-500" title={order.id}>
                          {order.id.split('-')[0]}...
                        </td>
                        <td className="p-4 font-semibold text-gray-900">
                          {order.package_name}
                        </td>
                        <td className="p-4">
                          <a href={`mailto:${order.buyer_email}`} className="text-blue-600 hover:underline">
                            {order.buyer_email}
                          </a>
                        </td>
                        <td className="p-4">
                          <span 
                            className={`px-3 py-1 rounded-full text-xs font-bold uppercase shadow-sm ${
                              isSuccess 
                                ? "bg-green-100 text-green-700 border border-green-200"
                                : "bg-orange-100 text-orange-700 border border-orange-200"
                            }`}
                          >
                            {order.status}
                          </span>
                        </td>
                        <td className="p-4 text-sm text-gray-600">
                          {new Date(order.created_at).toLocaleString("tr-TR")}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </main>
  );
}
