import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'login_screen.dart';
import 'api_config.dart';
import 'screens/payment_page.dart';
import 'screens/orders_screen.dart';
import 'screens/map_screen.dart';

// Ön plan bildirim kanalı (Android için)
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel fcmChannel = AndroidNotificationChannel(
  'yemekhane_high',
  'Yemekhane Bildirimi',
  description: 'Sipariş durumu ve paket bildirimleri',
  importance: Importance.high,
);

/// Arka planda gelen FCM mesajlarını işle (top-level fonksiyon olmalı)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!kIsWeb) {
    await Firebase.initializeApp();
    debugPrint('FCM arka plan mesajı: ${message.messageId}');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase başlat (google-services.json gerekir, Web'de options yoksa çöker)
  if (!kIsWeb) {
    await Firebase.initializeApp();

    // Arka plan FCM handler'ı kaydet
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Yerel bildirim kanalını oluştur (Android 8+)
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(fcmChannel);

    await _initLocalNotifications();
    await _setupFCM();
  }

  // Supabase başlat
  await Supabase.initialize(
    url: 'https://hnoskshrnactwcexwtjo.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imhub3Nrc2hybmFjdHdjZXh3dGpvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI2NDg1NzgsImV4cCI6MjA4ODIyNDU3OH0.8AbxhRwriiGhkNzWaKKfj39xSR8oulHSY2Q0gvPECeg',
  );

  runApp(const YemekhaneApp());
}

/// Yerel bildirim plugin başlatma
Future<void> _initLocalNotifications() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);
  await flutterLocalNotificationsPlugin.initialize(initSettings);
}

/// FCM izin + token alma + ön plan mesaj dinleyici
Future<void> _setupFCM() async {
  final messaging = FirebaseMessaging.instance;

  // Bildirim izni iste
  final settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  debugPrint('FCM izin durumu: ${settings.authorizationStatus}');

  // iOS ön plan bildirimleri için
  await messaging.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // FCM Token al ve backend'e kaydet
  final token = await messaging.getToken();
  if (token != null) {
    debugPrint('FCM Token: $token');
    await _saveFCMTokenToBackend(token);
  }

  // Token yenilenince tekrar kaydet
  messaging.onTokenRefresh.listen((newToken) {
    _saveFCMTokenToBackend(newToken);
  });

  // Uygulama açıkken gelen FCM → yerel bildirim göster
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final notification = message.notification;
    if (notification != null) {
      flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            fcmChannel.id,
            fcmChannel.name,
            channelDescription: fcmChannel.description,
            icon: '@mipmap/ic_launcher',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    }
  });
}

/// Backend'e FCM token'ı kaydet
Future<void> _saveFCMTokenToBackend(String token) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('user_email');
    if (email == null || email.isEmpty) return;
    await http.post(
      Uri.parse('$apiBaseUrl/api/v1/device-token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'fcm_token': token}),
    );
    debugPrint('FCM token backend\'e kaydedildi: $email');
  } catch (e) {
    debugPrint('FCM token kayıt hatası: $e');
  }
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
      home: const AuthGate(),
    );
  }
}

/// Uygulama açılışında kullanıcının giriş yapıp yapmadığını kontrol et
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('user_email');

    if (!mounted) return;

    if (email != null && email.isNotEmpty) {
      // Kayıtlı kullanıcı var → Ana sayfaya git
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
      );
    } else {
      // Kayıtlı kullanıcı yok → Giriş sayfasına git
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auth kontrol beklenirken loading göster
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.fastfood, size: 64, color: Colors.orange),
            SizedBox(height: 16),
            CircularProgressIndicator(color: Colors.orange),
          ],
        ),
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _widgetOptions = <Widget>[
    PackagesScreen(),
    OrdersScreen(),
    MapScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.fastfood),
            label: 'Menü',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long),
            label: 'Siparişlerim',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Harita',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.orange,
        onTap: _onItemTapped,
      ),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Çıkış Yap',
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              if (!context.mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
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