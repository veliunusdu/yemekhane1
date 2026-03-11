import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_config.dart';
import '../screens/payment_page.dart';

const _ink    = Color(0xFF0F172A);
const _muted  = Color(0xFF94A3B8);
const _orange = Color(0xFFF97316);
const _bg     = Color(0xFFF8FAFC);

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<dynamic> packages = [];
  bool isLoading = true;
  LatLng? userLocation;
  double selectedRadius = 10.0;
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
    bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konum servisleri kapalı.')),
      );
      return;
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      setState(() => userLocation = LatLng(pos.latitude, pos.longitude));
    } catch (e) {
      debugPrint('[MAP] Konum alınamadı: $e');
    }
  }

  Future<void> _fetchPackages() async {
    setState(() => isLoading = true);
    try {
      String url = '$apiBaseUrl/api/v1/packages';
      if (userLocation != null) {
        url += '?lat=${userLocation!.latitude}&lon=${userLocation!.longitude}&radius=${selectedRadius.toInt()}';
      }
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        setState(() { packages = json.decode(res.body) ?? []; isLoading = false; });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('[MAP] Hata: $e');
      setState(() => isLoading = false);
    }
  }

  List<Marker> _buildMarkers() {
    final List<Marker> markers = [];

    if (userLocation != null) {
      markers.add(Marker(
        point: userLocation!,
        width: 48, height: 48,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [BoxShadow(color: const Color(0xFF3B82F6).withOpacity(0.4), blurRadius: 12, spreadRadius: 2)],
          ),
          child: const Icon(Icons.person_rounded, color: Colors.white, size: 20),
        ),
      ));
    }

    for (final pkg in packages) {
      final lat = (pkg['latitude'] as num?)?.toDouble() ?? 0.0;
      final lon = (pkg['longitude'] as num?)?.toDouble() ?? 0.0;
      if (lat == 0.0 && lon == 0.0) continue;

      markers.add(Marker(
        point: LatLng(lat, lon),
        width: 64, height: 72,
        child: GestureDetector(
          onTap: () => _showDetail(pkg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: _orange,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [BoxShadow(color: _orange.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 3))],
                ),
                child: const Icon(Icons.fastfood_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 4)],
                ),
                child: Text(
                  '₺${pkg['discounted_price']}',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF16A34A)),
                ),
              ),
            ],
          ),
        ),
      ));
    }
    return markers;
  }

  void _showDetail(dynamic pkg) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PackageBottomSheet(
        pkg: pkg,
        userEmail: userEmail,
        onPurchaseSuccess: _fetchPackages,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final center = userLocation ?? const LatLng(41.0082, 28.9784);
    final validCount = packages.where((p) => (p['latitude'] ?? 0.0) != 0.0).length;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Yakınımdaki Paketler',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _ink, letterSpacing: -0.3)),
                        const SizedBox(height: 2),
                        Text(
                          isLoading ? 'Yükleniyor...' :
                            userLocation != null
                              ? '$validCount dükkan bulundu · ${selectedRadius.toInt()} km içinde'
                              : '${packages.length} paket listeleniyor',
                          style: const TextStyle(fontSize: 12, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _fetchPackages,
                    icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),

            // ── Radius Filter ──
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: radiusOptions.map((r) {
                    final selected = selectedRadius == r;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () { setState(() => selectedRadius = r); _fetchPackages(); },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? _orange : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${r.toInt()} km',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected ? Colors.white : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // ── Map ──
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(color: _orange, strokeWidth: 2))
                  : Stack(
                      children: [
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(initialCenter: center, initialZoom: 13.0),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.yemekhane.mobile',
                              maxZoom: 19,
                            ),
                            MarkerLayer(markers: _buildMarkers()),
                          ],
                        ),
                        // Locate button
                        Positioned(
                          bottom: 16, right: 16,
                          child: FloatingActionButton.small(
                            onPressed: () async { await _getUserLocation(); _fetchPackages(); },
                            backgroundColor: Colors.white,
                            foregroundColor: _orange,
                            elevation: 4,
                            child: const Icon(Icons.my_location_rounded),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════
// Package Bottom Sheet
// ════════════════════════════════════════════════════════
class _PackageBottomSheet extends StatefulWidget {
  final dynamic pkg;
  final String? userEmail;
  final VoidCallback onPurchaseSuccess;

  const _PackageBottomSheet({
    required this.pkg,
    required this.userEmail,
    required this.onPurchaseSuccess,
  });

  @override
  State<_PackageBottomSheet> createState() => _PackageBottomSheetState();
}

class _PackageBottomSheetState extends State<_PackageBottomSheet> {
  bool isFavorite = false;
  bool isLoadingFav = true;
  bool isBuying = false;

  @override
  void initState() {
    super.initState();
    _checkFavorite();
  }

  Future<void> _checkFavorite() async {
    if (widget.userEmail == null || widget.pkg['business_id'] == null) {
      setState(() => isLoadingFav = false); return;
    }
    try {
      final res = await http.get(Uri.parse('$apiBaseUrl/api/v1/favorites?email=${widget.userEmail}'));
      if (res.statusCode == 200) {
        final favs = json.decode(res.body) as List;
        setState(() {
          isFavorite = favs.any((f) => f['business_id'] == widget.pkg['business_id']);
          isLoadingFav = false;
        });
      } else { setState(() => isLoadingFav = false); }
    } catch (_) { setState(() => isLoadingFav = false); }
  }

  Future<void> _toggleFavorite() async {
    if (widget.userEmail == null || widget.pkg['business_id'] == null) return;
    final prev = isFavorite;
    setState(() => isFavorite = !isFavorite);
    try {
      final url = Uri.parse('$apiBaseUrl/api/v1/favorites');
      final body = json.encode({
        'user_email': widget.userEmail,
        'business_id': widget.pkg['business_id'],
        'business_name': widget.pkg['business_name'] ?? 'Mekan',
      });
      final res = prev
          ? await http.delete(url, headers: {'Content-Type': 'application/json'}, body: body)
          : await http.post(url,   headers: {'Content-Type': 'application/json'}, body: body);
      if ((res.statusCode != 200 && res.statusCode != 201) && mounted) {
        setState(() => isFavorite = prev);
      }
    } catch (_) { if (mounted) setState(() => isFavorite = prev); }
  }

  Future<void> _buy() async {
    if (isBuying) return;
    setState(() => isBuying = true);
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/v1/payments/initialize'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'package_id': widget.pkg['id'],
          'price': widget.pkg['discounted_price'].toString(),
          'email': widget.userEmail ?? 'bilinmeyen@kullanici.com',
          'name': 'Kullanici',
          'surname': 'Siparisci',
        }),
      );
      if (res.statusCode == 200 && mounted) {
        final data = json.decode(res.body);
        final paymentUrl = (data['paymentPageUrl'] as String?)?.trim();
        if (paymentUrl != null && paymentUrl.isNotEmpty) {
          Navigator.pop(context);
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => PaymentPage(paymentUrl: paymentUrl)),
          );
          if (result == true) widget.onPurchaseSuccess();
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ödeme başlatılamadı!')),
        );
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bağlantı hatası!')),
      );
    } finally { if (mounted) setState(() => isBuying = false); }
  }

  @override
  Widget build(BuildContext context) {
    final pkg = widget.pkg;
    final businessName = pkg['business_name'] ?? 'Dükkan';
    final distance     = (pkg['distance_km'] as num?)?.toDouble() ?? 0.0;
    final rating       = (pkg['rating'] as num?)?.toDouble() ?? 0.0;
    final category     = pkg['category']?.toString() ?? '';
    final tags         = (pkg['tags'] as List?)?.map((e) => e.toString()).toList() ?? [];

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),

          // Shop info row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.store_rounded, color: _orange, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(businessName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _ink)),
                    if (rating > 0)
                      Row(children: [
                        const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 14),
                        const SizedBox(width: 3),
                        Text(rating.toStringAsFixed(1), style: const TextStyle(fontSize: 12, color: _muted, fontWeight: FontWeight.w600)),
                      ]),
                  ],
                ),
              ),
              if (distance > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.near_me_rounded, size: 12, color: _muted),
                      const SizedBox(width: 4),
                      Text('${distance.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 11, color: _muted, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
              // Favorite
              GestureDetector(
                onTap: _toggleFavorite,
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: isFavorite ? const Color(0xFFFFF1F2) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isFavorite ? const Color(0xFFFECACA) : const Color(0xFFE2E8F0)),
                  ),
                  child: isLoadingFav
                      ? const Padding(padding: EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF43F5E)))
                      : Icon(
                          isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: const Color(0xFFF43F5E),
                          size: 18,
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: const Color(0xFFF1F5F9), height: 1),
          const SizedBox(height: 16),

          // Package detail row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: pkg['image_url'] != null && pkg['image_url'] != ''
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(pkg['image_url'], fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.fastfood_rounded, color: _orange, size: 36)))
                    : const Icon(Icons.fastfood_rounded, color: _orange, size: 36),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pkg['name'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _ink)),
                    if (category.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(category, style: const TextStyle(fontSize: 11, color: _orange, fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(height: 4),
                    Text(pkg['description'] ?? '', style: const TextStyle(fontSize: 12, color: _muted, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    // Tags
                    if (tags.isNotEmpty)
                      Wrap(
                        spacing: 4, runSpacing: 4,
                        children: tags.map((t) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1F2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFE11D48))),
                        )).toList(),
                      ),
                    const SizedBox(height: 8),
                    // Price
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('₺${pkg['original_price']}',
                          style: const TextStyle(decoration: TextDecoration.lineThrough, color: _muted, fontSize: 12)),
                        const SizedBox(width: 8),
                        Text('₺${pkg['discounted_price']}',
                          style: const TextStyle(color: Color(0xFF16A34A), fontWeight: FontWeight.bold, fontSize: 22)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(6)),
                          child: Text('${pkg['stock']} adet', style: const TextStyle(fontSize: 11, color: Color(0xFF3B82F6), fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Buy button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isBuying ? null : _buy,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
                disabledBackgroundColor: const Color(0xFFD1FAE5),
              ),
              child: isBuying
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Hemen Al', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
