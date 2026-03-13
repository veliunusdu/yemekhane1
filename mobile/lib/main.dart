import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'login_screen.dart';
import 'api_config.dart';
import 'screens/orders_screen.dart';
import 'screens/map_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/business_search_screen.dart';

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
  await flutterLocalNotificationsPlugin.initialize(settings: initSettings);
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
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: NotificationDetails(
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
      headers: await authHeaders(),
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
    // İlk frame çizildikten sonra yönlendir (build sırasında navigation hatası önlenir)
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAuth());
  }

  Future<void> _checkAuth() async {
    final session = Supabase.instance.client.auth.currentSession;

    if (!mounted) return;

    if (session != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_email', session.user.email ?? '');
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
      );
    } else {
      if (!mounted) return;
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

  static const List<Widget> _screens = [
    PackagesScreen(),
    OrdersScreen(),
    MapScreen(),
    FavoritesScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFF1F5F9), width: 1)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                _NavItem(icon: Icons.fastfood_rounded,    label: 'Menü',        index: 0, selected: _selectedIndex, onTap: (i) => setState(() => _selectedIndex = i)),
                _NavItem(icon: Icons.receipt_long_rounded,label: 'Siparişlerim',index: 1, selected: _selectedIndex, onTap: (i) => setState(() => _selectedIndex = i)),
                _NavItem(icon: Icons.map_rounded,         label: 'Harita',      index: 2, selected: _selectedIndex, onTap: (i) => setState(() => _selectedIndex = i)),
                _NavItem(icon: Icons.favorite_rounded,    label: 'Favoriler',   index: 3, selected: _selectedIndex, onTap: (i) => setState(() => _selectedIndex = i)),
                _NavItem(icon: Icons.person_rounded,      label: 'Profil',      index: 4, selected: _selectedIndex, onTap: (i) => setState(() => _selectedIndex = i)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int selected;
  final void Function(int) onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = index == selected;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFFFF7ED) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: isActive ? const Color(0xFFF97316) : const Color(0xFF94A3B8)),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? const Color(0xFFF97316) : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
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

  final _searchCtrl = TextEditingController();
  String _searchQ = '';
  String _selectedCategory = '';
  Timer? _debounce;

  static const _categories = ['Tümü', 'Yemek', 'Tatlı', 'İçecek', 'Vegan', 'Kahvaltı'];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    userEmail = prefs.getString('user_email');
    await fetchPackages();
  }

  Future<void> fetchPackages() async {
    setState(() => isLoading = true);
    try {
      final uri = Uri.parse('$apiBaseUrl/api/v1/packages').replace(
        queryParameters: {
          if (_searchQ.isNotEmpty) 'q': _searchQ,
          if (_selectedCategory.isNotEmpty) 'category': _selectedCategory,
        },
      );
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        setState(() { packages = json.decode(res.body) ?? []; isLoading = false; });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('Packages error: $e');
      setState(() => isLoading = false);
    }
  }

  void _onSearchChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() => _searchQ = val.trim());
      fetchPackages();
    });
  }

  void _selectCategory(String cat) {
    setState(() => _selectedCategory = cat == 'Tümü' ? '' : cat);
    fetchPackages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Günün Fırsatları',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF0F172A), letterSpacing: -0.5)),
                        const SizedBox(height: 2),
                        Text(
                          isLoading ? 'Yükleniyor...' : '${packages.length} paket mevcut',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: fetchPackages,
                    icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.store_rounded, color: Color(0xFF64748B)),
                    tooltip: 'İşletme Ara',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BusinessSearchScreen()),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout_rounded, color: Color(0xFF94A3B8)),
                    tooltip: 'Çıkış Yap',
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.clear();
                      await Supabase.instance.client.auth.signOut();
                      if (!context.mounted) return;
                      Navigator.pushAndRemoveUntil(context,
                        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
                    },
                  ),
                ],
              ),
            ),

            // ── Arama Çubuğu ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  hintText: 'Paket ara...',
                  hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF94A3B8)),
                  suffixIcon: _searchQ.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF94A3B8)),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQ = '');
                            fetchPackages();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFF97316), width: 1.5)),
                ),
              ),
            ),

            // ── Kategori Chip'leri ──
            SizedBox(
              height: 38,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final cat = _categories[i];
                  final isSelected = (cat == 'Tümü' && _selectedCategory.isEmpty) || cat == _selectedCategory;
                  return GestureDetector(
                    onTap: () => _selectCategory(cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFF97316) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isSelected ? const Color(0xFFF97316) : const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        cat,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),

            // ── List ──
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFF97316), strokeWidth: 2))
                  : packages.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          color: const Color(0xFFF97316),
                          onRefresh: fetchPackages,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                            itemCount: packages.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) => _PackageCard(
                              pkg: packages[i],
                              userEmail: userEmail,
                              onSuccess: fetchPackages,
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.fastfood_rounded, size: 36, color: Color(0xFFF97316)),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQ.isNotEmpty || _selectedCategory.isNotEmpty
                ? 'Arama sonucu bulunamadı'
                : 'Aktif paket bulunamadı',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 6),
          Text(
            _searchQ.isNotEmpty || _selectedCategory.isNotEmpty
                ? 'Farklı bir arama veya kategori deneyin'
                : 'Yeni fırsatlar yakında eklenecek',
            style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }
}

// ── Package Card ──────────────────────────────────────────
class _PackageCard extends StatefulWidget {
  final dynamic pkg;
  final String? userEmail;
  final VoidCallback onSuccess;

  const _PackageCard({required this.pkg, required this.userEmail, required this.onSuccess});

  @override
  State<_PackageCard> createState() => _PackageCardState();
}

class _PackageCardState extends State<_PackageCard> {
  bool isBuying = false;

  Future<void> _buy() async {
    if (isBuying) return;
    setState(() => isBuying = true);
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/v1/orders'),
        headers: await authHeaders(),
        body: json.encode({
          'package_id': widget.pkg['id'],
          'buyer_email': widget.userEmail ?? '',
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Siparişiniz alındı! Ödemeyi teslimatta yapabilirsiniz. 🎉'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ));
        widget.onSuccess();
      } else {
        String errMsg = 'Sipariş oluşturulamadı (${res.statusCode})';
        try { final d = json.decode(res.body); errMsg = d['error'] ?? errMsg; } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errMsg)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bağlantı hatası: $e')));
    } finally {
      if (mounted) setState(() => isBuying = false);
    }
  }

  // Kalan süreyi hesaplar. Örn: "19:30:00" → "1 sa 15 dk kaldı"
  String? _remainingTime() {
    final untilStr = widget.pkg['available_until']?.toString() ?? '';
    if (untilStr.isEmpty) return null;
    final parts = untilStr.split(':');
    if (parts.length < 2) return null;
    final now = DateTime.now();
    final until = DateTime(now.year, now.month, now.day,
        int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0);
    final diff = until.difference(now);
    if (diff.isNegative || diff.inMinutes == 0) return null;
    if (diff.inMinutes < 60) return '⏰ ${diff.inMinutes} dk kaldı';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return '⏰ $h sa${m > 0 ? ' $m dk' : ''} kaldı';
  }

  @override
  Widget build(BuildContext context) {
    final pkg = widget.pkg;
    final hasImage = pkg['image_url'] != null && pkg['image_url'] != '';
    final category = pkg['category']?.toString() ?? '';
    final tags = (pkg['tags'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final discount = pkg['original_price'] != null && pkg['discounted_price'] != null
        ? (((pkg['original_price'] - pkg['discounted_price']) / pkg['original_price']) * 100).round()
        : 0;
    final remaining = _remainingTime();
    final isUrgent = () {
      final untilStr = pkg['available_until']?.toString() ?? '';
      if (untilStr.isEmpty) return false;
      final parts = untilStr.split(':');
      if (parts.length < 2) return false;
      final now = DateTime.now();
      final until = DateTime(now.year, now.month, now.day,
          int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0);
      return until.difference(now).inMinutes <= 30;
    }();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image or placeholder
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                child: hasImage
                    ? Image.network(pkg['image_url'], height: 140, width: double.infinity, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _imagePlaceholder())
                    : _imagePlaceholder(),
              ),
              // Discount badge
              if (discount > 0)
                Positioned(
                  top: 10, left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(20)),
                    child: Text('-%$discount', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              // Stock badge
              Positioned(
                top: 10, right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.92), borderRadius: BorderRadius.circular(20)),
                  child: Text('${pkg['stock']} adet', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF3B82F6))),
                ),
              ),
              // Countdown badge
              if (remaining != null)
                Positioned(
                  bottom: 8, left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isUrgent ? const Color(0xFFEF4444) : const Color(0xFFF59E0B),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(remaining, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + Category
                if (category.isNotEmpty)
                  Text(category, style: const TextStyle(fontSize: 11, color: Color(0xFFF97316), fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(pkg['name'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                const SizedBox(height: 4),
                Text(pkg['description'] ?? '', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8), height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),

                // Rating
                if ((pkg['rating'] as num?)?.toDouble() != null && (pkg['rating'] as num).toDouble() > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 14),
                      const SizedBox(width: 3),
                      Text(
                        (pkg['rating'] as num).toDouble().toStringAsFixed(1),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF78716C)),
                      ),
                    ],
                  ),
                ],

                // Tags
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4, runSpacing: 4,
                    children: tags.map((t) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFFFF1F2), borderRadius: BorderRadius.circular(6)),
                      child: Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFE11D48))),
                    )).toList(),
                  ),
                ],

                const SizedBox(height: 12),
                // Price + Button
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('₺${pkg['original_price']}',
                          style: const TextStyle(decoration: TextDecoration.lineThrough, color: Color(0xFF94A3B8), fontSize: 12)),
                        Text('₺${pkg['discounted_price']}',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF16A34A))),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 110,
                      child: ElevatedButton(
                        onPressed: isBuying ? null : _buy,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                          disabledBackgroundColor: const Color(0xFFD1FAE5),
                        ),
                        child: isBuying
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Hemen Al', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      height: 140, width: double.infinity,
      color: const Color(0xFFFFF7ED),
      child: const Center(child: Icon(Icons.fastfood_rounded, color: Color(0xFFF97316), size: 48)),
    );
  }
}