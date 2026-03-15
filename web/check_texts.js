const fs = require('fs');

const pageFile = 'app/page.tsx';
let content = fs.readFileSync(pageFile, 'utf-8');

// remove max-w-[1600px] and mx-auto
content = content.replace(/max-w-\[1600px\] mx-auto /g, 'w-full ');

// remove lg:left-[calc(50%-800px)] inside sidebar
content = content.replace(/lg:left-\[calc\(50%-800px\)\] /g, '');

// Also ensure text is correct

// Look for placeholders and standard UI text
const replacements = {
  '"Search"': '"Ara"',
  '"Cancel"': '"İptal"',
  '"Edit"': '"Düzenle"',
  '"Delete"': '"Sil"',
  '"Stock"': '"Stok"',
  '"Original Price"': '"Orijinal Fiyat"',
  '"Discounted Price"': '"İndirimli Fiyat"',
  '"Brief description..."': '"Kısa açıklama..."',
  '"Product Name"': '"Ürün Adı"',
  '>Orders Management<': '>Sipariş Yönetimi<',
  '>Customer Reviews<': '>Müşteri Yorumları<',
  '>Business Settings<': '>İşletme Ayarları<',
  '>Analytics<': '>İstatistikler<',
  '>Create Listing<': '>İlan Oluştur<',
  '>Active Orders<': '>Aktif Siparişler<',
  '>No active orders right now.<': '>Şu anda aktif sipariş yok.<',
  '>Active Listings<': '>Aktif İlanlar<',
  '>You don\\'t have any items listed.<': '>Listelenmiş herhangi bir ürününüz yok.<',
  '>General Information<': '>Genel Bilgiler<',
  '>Location Settings<': '>Konum Ayarları<',
  '>Edit Listing<': '>İlanı Düzenle<',
  '>Save Changes<': '>Değişiklikleri Kaydet<',
  'placeholder="Latitude"': 'placeholder="Enlem"',
  'placeholder="Longitude"': 'placeholder="Boylam"',
  'placeholder="Product Name"': 'placeholder="Ürün Adı"',
  'placeholder="Brief description..."': 'placeholder="Kısa açıklama..."',
  'placeholder="Orig ₺"': 'placeholder="Orijinal ₺"',
  'placeholder="Disc ₺"': 'placeholder="İndirimli ₺"',
  'placeholder="Stock"': 'placeholder="Stok"',
  'placeholder="Tags (comma sep)"': 'placeholder="Etiketler (virgülle ayırın)"',
  '>Upload Image<': '>Görsel Yükle<',
  '>Image attached<': '>Görsel eklendi<',
  '>Publish Listing<': '>İlanı Yayınla<',
  '>Start Prep<': '>Hazırlamaya Başla<',
  '>Notify Ready<': '>Hazır (Müşteriye Bildir)<',
  '>Completed (': '>Tamamlananlar (',
  '>Total Revenue<': '>Toplam Gelir<',
  '>Items Sold<': '>Satılan Ürün<',
  '>Waste Saved<': '>Önlenen İsraf<',
  '>Revenue (7 Days)<': '>Gelir (7 Gün)<',
  '>Top Items<': '>En Çok Satanlar<',
  '>Business Name<': '>İşletme Adı<',
  '>Phone<': '>Telefon<',
  '>Category<': '>Kategori<',
  '>Address<': '>Adres<',
  '>Use Current Location<': '>Mevcut Konumu Kullan<',
  '>Save Coordinates<': '>Koordinatları Kaydet<',
  '>Active (Visible to customers)<': '>Aktif (Müşterilere görünür)<',
  '>Dashboard<': '>Yönetim Paneli<',
  '>System Active<': '>Sistem Aktif<',
  '>Getting GPS...<': '>Konum Alınıyor...<',
  '>Saving...<': '>Kaydediliyor...<',
  '>Not configured<': '>Ayarlanmadı<',
  '>Hidden<': '>Gizli<'
};

for (const [k, v] of Object.entries(replacements)) {
  content = content.replace(new RegExp(k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g'), v);
}

fs.writeFileSync(pageFile, content);
console.log('Mobile view fixed and more text checked');
