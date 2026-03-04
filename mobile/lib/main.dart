import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
      home: const PackagesScreen(),
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

  @override
  void initState() {
    super.initState();
    fetchPackages();
  }

  Future<void> fetchPackages() async {
    try {
      // DİKKAT: Eğer Android Emulator'de deneyecekseniz 'localhost' yerine '10.0.2.2' yazmanız gerekir!
      // Chrome (Web) üzerinde deniyorsak 'localhost' kusursuz çalışır.
      final response = await http.get(Uri.parse('http://localhost:3000/api/v1/packages'));
      
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
                            // Yemek İkonu
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.fastfood, color: Colors.orange, size: 30),
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
                                      final res = await http.post(
                                        Uri.parse('http://localhost:3000/api/v1/orders'),
                                        headers: {"Content-Type": "application/json"},
                                        body: json.encode({"package_id": pkg['id']}),
                                      );
                                      if (res.statusCode == 201) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text("✅ Sipariş Alındı! Afiyet olsun.")));
                                        fetchPackages(); // Listeyi yenileyip stoğun düştüğünü gör
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