import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'login_screen.dart';
import 'api_config.dart';
import 'screens/payment_page.dart';

void main() {
  runApp(const YemekhaneApp());
}

class YemekhaneApp extends StatelessWidget {
  const YemekhaneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yemekhane',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

class PackagesScreen extends StatefulWidget {
  const PackagesScreen({super.key});

  @override
  State<PackagesScreen> createState() => _PackagesScreenState();
}

class _PackagesScreenState extends State<PackagesScreen> {
  List<dynamic> packages = [];
  bool isLoading = true;
  String? userEmail;

  @override
  void initState() {
    super.initState();
    _loadLocalData();
    fetchPackages();
  }

  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userEmail = prefs.getString('user_email');
    });
  }

  Future<void> fetchPackages() async {
    try {
      final response = await http.get(Uri.parse('$apiBaseUrl/api/v1/packages'));
      
      if (response.statusCode == 200) {
        setState(() {
          var decodedData = json.decode(response.body);
          packages = decodedData ?? []; // Null gelirse boş liste yap
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      print("API Hatası: $e");
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Günün Fırsatları', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : packages.isEmpty
              ? const Center(child: Text('Şu an aktif fırsat paketi yok 😔'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: packages.length,
                  itemBuilder: (context, index) {
                    final pkg = packages[index];
                    return Card(
                      elevation: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                             // Yemek Fotoğrafı veya İkonu
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: pkg['image_url'] != null && pkg['image_url'] != ""
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        pkg['image_url'],
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) =>
                                            const Icon(Icons.fastfood, color: Colors.orange, size: 30),
                                      ),
                                    )
                                  : const Icon(Icons.fastfood, color: Colors.orange, size: 30),
                            ),
                            const SizedBox(width: 16),
                            
                            // Yemek Bilgileri
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(pkg['name'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(pkg['description'] ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[600]), maxLines: 2, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 8),
                                  Text('Stok: ${pkg['stock']} adet', style: const TextStyle(fontSize: 12, color: Colors.blue)),
                                  const SizedBox(height: 8),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white),
                                    onPressed: () async {
                                      // 1. Backend'den Payment URL iste
                                      final res = await http.post(
                                        Uri.parse('$apiBaseUrl/api/v1/payments/initialize'),
                                        headers: {"Content-Type": "application/json"},
                                        body: json.encode({
                                          "package_id": pkg['id'],
                                          "price": pkg['discounted_price'].toString(),
                                          "email": userEmail ?? "bilinmeyen@kullanici.com",
                                          "name": "Kullanici",
                                          "surname": "Siparisci"
                                        }),
                                      );

                                      if (res.statusCode == 200) {
                                        final data = json.decode(res.body);
                                        final String? paymentUrl = (data['paymentPageUrl'] as String?)?.trim();
                                        final String token = (data['token'] as String?) ?? '';
                                        
                                        if (paymentUrl == null || paymentUrl.isEmpty) {
                                           ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text("Ödeme linki alınamadı, lütfen tekrar deneyin.")));
                                           return;
                                        }

                                        // 2. Web'te yeni sekmede aç, mobilde WebView kullan
                                        bool? result = false;
                                        if (kIsWeb) {
                                          if (!await launchUrl(Uri.parse(paymentUrl), mode: LaunchMode.externalApplication)) {
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ödeme sayfası açılamadı')));
                                            return;
                                          }
                                          // Kullanıcı ödemeyi yeni sekmede yapıp dönünce onaylaması için dialog göster
                                          result = await showDialog<bool>(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (context) => AlertDialog(
                                              title: const Text("Ödeme İşlemi"),
                                              content: const Text("Açılan yeni sekmede (Iyzico) 3D Secure işleminizi tamamlayın. 'Siparişiniz Başarıyla Alındı' mesajını gördükten veya sayfa yönlendirmesi bittikten sonra buradaki 'İşlemi Kontrol Et' butonuna tıklayın.\n\nEğer sekme açılmadıysa tarayıcınızın pop-up engelleyicisini kontrol edin."),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(context, false),
                                                  child: const Text("İptal", style: TextStyle(color: Colors.red)),
                                                ),
                                                ElevatedButton(
                                                  onPressed: () => Navigator.pop(context, true),
                                                  child: const Text("İşlemi Kontrol Et"),
                                                ),
                                              ],
                                            ),
                                          );
                                        } else {
                                          result = await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => PaymentPage(paymentUrl: paymentUrl),
                                            ),
                                          );
                                        }

                                        // 3. Başarı veya Hata Senaryosu
                                        if (result == true) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text("Ödeme kontrol ediliyor... Lütfen bekleyin."))
                                          );

                                          // 4. Backend'e token ile durum sorgusu yap
                                          try {
                                            final checkRes = await http.post(
                                              Uri.parse('$apiBaseUrl/api/v1/payments/check'),
                                              headers: {"Content-Type": "application/json"},
                                              body: json.encode({
                                                "token": token,
                                                "package_id": pkg['id'],
                                                "buyer_email": userEmail ?? "bilinmeyen@kullanici.com"
                                              }),
                                            );

                                            if (checkRes.statusCode == 200) {
                                              final checkData = json.decode(checkRes.body);
                                              if (checkData['status'] == 'success') {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text("✅ Sipariş Alındı! Afiyet olsun."))
                                                );
                                                fetchPackages();
                                              } else {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text("❌ Ödeme başarısız veya iptal edildi."))
                                                );
                                              }
                                            } else {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text("❌ Ödeme doğrulanamadı. Lütfen destekle iletişime geçin."))
                                                );
                                            }
                                          } catch(e) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text("❌ Bağlantı hatası: Ödeme durumu doğrulanamadı!"))
                                              );
                                          }
                                          
                                        } else {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text("❌ Ödeme işlemi yarım kaldı."))
                                          );
                                        }
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text("Ödeme başlatılamadı!")));
                                      }
                                    },
                                    child: const Text("Hemen Al"),
                                  ),
                                ],
                              ),
                            ),
                            
                            // Fiyat Kısmı
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '₺${pkg['original_price']}',
                                  style: const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey, fontSize: 12),
                                ),
                                Text(
                                  '₺${pkg['discounted_price']}',
                                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 18),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}