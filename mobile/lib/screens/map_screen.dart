import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_config.dart';
import '../screens/payment_page.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<dynamic> packages = [];
  bool isLoading = true;
  LatLng? userLocation;
  double selectedRadius = 10.0; // km
  String? userEmail;
  final MapController _mapController = MapController();

  final List<double> radiusOptions = [2, 5, 10, 20, 50];

  @override
  void initState() {
    super.initState();
    _loadAndFetch();
  }

  Future<void> _loadAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    userEmail = prefs.getString('user_email');
    await _getUserLocation();
    await _fetchPackages();
  }

  Future<void> _getUserLocation() async {
    // Konum servisini kontrol et
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Konum servisleri kapalı. Lütfen açın.')),
        );
      }
      return;
    }

    // İzin kontrolü
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Konum izni reddedildi.')),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Konum izni kalıcı olarak reddedildi. Ayarlardan açın.')),
        );
      }
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10), // Emülatörde takılmayı önler
      );
      setState(() {
        userLocation = LatLng(position.latitude, position.longitude);
      });
      debugPrint('[MAP] Konum alındı: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      debugPrint('[MAP] Konum alınamadı: $e');
    }
  }

  Future<void> _fetchPackages() async {
    setState(() => isLoading = true);
    try {
      String url = '$apiBaseUrl/api/v1/packages';
      if (userLocation != null) {
        url +=
            '?lat=${userLocation!.latitude}&lon=${userLocation!.longitude}&radius=${selectedRadius.toInt()}';
      }
      debugPrint('[MAP] API isteği gönderiliyor: $url');

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        setState(() {
          var data = json.decode(response.body);
          packages = data ?? [];
          isLoading = false;
        });
        debugPrint('[MAP] ${packages.length} paket yüklendi.');
      } else {
        debugPrint('[MAP] API Hata kodu: ${response.statusCode}');
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('[MAP] API Hatası: $e');
      setState(() => isLoading = false);
    }
  }

  List<Marker> _buildMarkers() {
    List<Marker> markers = [];

    // Kullanıcı konumu marker
    if (userLocation != null) {
      markers.add(
        Marker(
          point: userLocation!,
          width: 48,
          height: 48,
          child: const Icon(Icons.my_location, color: Colors.blue, size: 36),
        ),
      );
    }

    // Dükkan pinleri
    for (final pkg in packages) {
      final lat = (pkg['latitude'] as num?)?.toDouble() ?? 0.0;
      final lon = (pkg['longitude'] as num?)?.toDouble() ?? 0.0;
      if (lat == 0.0 && lon == 0.0) continue; // Koordinatsız paketleri atla

      markers.add(
        Marker(
          point: LatLng(lat, lon),
          width: 56,
          height: 56,
          child: GestureDetector(
            onTap: () => _showPackageDetail(pkg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  padding: const EdgeInsets.all(6),
                  child: const Icon(Icons.fastfood, color: Colors.white, size: 20),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 2)
                    ],
                  ),
                  child: Text(
                    '₺${pkg['discounted_price']}',
                    style: const TextStyle(
                        fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return markers;
  }

  void _showPackageDetail(dynamic pkg) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PackageBottomSheet(
        pkg: pkg,
        userEmail: userEmail,
        onPurchaseSuccess: _fetchPackages,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = userLocation ?? const LatLng(41.0082, 28.9784); // Varsayılan: İstanbul

    return Scaffold(
      appBar: AppBar(
        title: const Text('Yakınımdaki Paketler', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Yenile',
            onPressed: _fetchPackages,
          ),
        ],
      ),
      body: Column(
        children: [
          // Mesafe Filtresi
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.radar, color: Colors.orange),
                const SizedBox(width: 8),
                const Text('Mesafe:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                ...radiusOptions.map((r) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text('${r.toInt()}km'),
                        selected: selectedRadius == r,
                        selectedColor: Colors.orange,
                        labelStyle: TextStyle(
                          color: selectedRadius == r ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => selectedRadius = r);
                            _fetchPackages();
                          }
                        },
                      ),
                    )),
              ],
            ),
          ),
          // Harita
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.orange))
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 13.0,
                    ),
                    children: [
                      // OpenStreetMap Tile Layer (Leaflet'in "yakıtı")
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.yemekhane.mobile',
                        maxZoom: 19,
                      ),
                      // Dükkan ve kullanıcı pinleri
                      MarkerLayer(markers: _buildMarkers()),
                    ],
                  ),
          ),
          // Alt bilgi şeridi
          if (!isLoading)
            Container(
              color: Colors.orange.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.store_mall_directory, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    userLocation != null
                        ? '${packages.where((p) => (p['latitude'] ?? 0.0) != 0.0).length} dükkan bulundu (${selectedRadius.toInt()}km içinde)'
                        : '${packages.length} paket listeleniyor (konum yok)',
                    style: const TextStyle(fontSize: 13, color: Colors.orange),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// Alt kısım detay paneli
class _PackageBottomSheet extends StatelessWidget {
  final dynamic pkg;
  final String? userEmail;
  final VoidCallback onPurchaseSuccess;

  const _PackageBottomSheet({
    required this.pkg,
    required this.userEmail,
    required this.onPurchaseSuccess,
  });

  @override
  Widget build(BuildContext context) {
    final businessName = pkg['business_name'] ?? 'Dükkan';
    final distanceKm = (pkg['distance_km'] as num?)?.toDouble() ?? 0.0;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          // Dükkan adı ve mesafe
          Row(
            children: [
              const Icon(Icons.store, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(businessName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              if (distanceKm > 0)
                Chip(
                  label: Text('${distanceKm.toStringAsFixed(1)} km'),
                  backgroundColor: Colors.orange.shade50,
                  labelStyle: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                  avatar: const Icon(Icons.directions_walk, color: Colors.orange, size: 16),
                ),
            ],
          ),
          const Divider(height: 20),
          // Paket bilgileri
          Row(
            children: [
              // Resim
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: pkg['image_url'] != null && pkg['image_url'] != ''
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(pkg['image_url'], fit: BoxFit.cover,
                            errorBuilder: (c, e, s) =>
                                const Icon(Icons.fastfood, color: Colors.orange, size: 36)))
                    : const Icon(Icons.fastfood, color: Colors.orange, size: 36),
              ),
              const SizedBox(width: 16),
              // Bilgiler
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pkg['name'] ?? '',
                        style:
                            const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(pkg['description'] ?? '',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('₺${pkg['original_price']}',
                            style: const TextStyle(
                                decoration: TextDecoration.lineThrough,
                                color: Colors.grey,
                                fontSize: 12)),
                        const SizedBox(width: 8),
                        Text('₺${pkg['discounted_price']}',
                            style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 18)),
                        const Spacer(),
                        Text('Stok: ${pkg['stock']}',
                            style: const TextStyle(fontSize: 12, color: Colors.blue)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Satın Al butonu
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.shopping_bag_outlined),
              label: const Text('Hemen Al', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              onPressed: () async {
                Navigator.pop(context);
                final res = await http.post(
                  Uri.parse('$apiBaseUrl/api/v1/payments/initialize'),
                  headers: {'Content-Type': 'application/json'},
                  body: json.encode({
                    'package_id': pkg['id'],
                    'price': pkg['discounted_price'].toString(),
                    'email': userEmail ?? 'bilinmeyen@kullanici.com',
                    'name': 'Kullanici',
                    'surname': 'Siparisci',
                  }),
                );
                if (res.statusCode == 200) {
                  final data = json.decode(res.body);
                  final String? paymentUrl =
                      (data['paymentPageUrl'] as String?)?.trim();
                  if (paymentUrl != null && paymentUrl.isNotEmpty && context.mounted) {
                    final result = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                          builder: (ctx) => PaymentPage(paymentUrl: paymentUrl)),
                    );
                    if (result == true) onPurchaseSuccess();
                  }
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ödeme başlatılamadı!')));
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
