import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_config.dart';

const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF94A3B8);
const _orange = Color(0xFFF97316);
const _bg = Color(0xFFF8FAFC);

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
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Konum servisleri kapalı.')),
        );
      return;
    }
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied)
      perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) return;

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
      String url = '$apiBaseUrl/api/v1/packages?limit=50';
      if (userLocation != null) {
        url +=
            '&lat=${userLocation!.latitude}&lon=${userLocation!.longitude}&radius=${selectedRadius.toInt()}';
      }
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final body = json.decode(res.body);
        // Yeni paginated response: { data: [...], page: 1, limit: 50 }
        final List<dynamic> list = (body is Map && body['data'] != null)
            ? body['data']
            : (body is List ? body : []);
        setState(() {
          packages = list;
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('[MAP] Hata: $e');
      setState(() => isLoading = false);
    }
  }

  /// İşletme başına paketleri grupla — aynı konumda tek marker göster.
  /// 1000 pakette bile yalnızca N_işletme kadar marker oluşur.
  Map<String, List<dynamic>> _groupByBusiness() {
    final Map<String, List<dynamic>> groups = {};
    for (final pkg in packages) {
      final biz = pkg['business_id']?.toString() ?? '';
      if (biz.isEmpty) continue;
      groups.putIfAbsent(biz, () => []).add(pkg);
    }
    return groups;
  }

  List<Marker> _buildMarkers() {
    final List<Marker> markers = [];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (userLocation != null) {
      markers.add(Marker(
        point: userLocation!,
        width: 48,
        height: 48,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF3B82F6).withOpacity(0.4),
                  blurRadius: 12,
                  spreadRadius: 2)
            ],
          ),
          child:
              const Icon(Icons.person_rounded, color: Colors.white, size: 20),
        ),
      ));
    }

    // Grupla: her işletme için tek marker
    final groups = _groupByBusiness();
    for (final entry in groups.entries) {
      final pkgList = entry.value;
      final first = pkgList.first;
      final lat = (first['latitude'] as num?)?.toDouble() ?? 0.0;
      final lon = (first['longitude'] as num?)?.toDouble() ?? 0.0;
      if (lat == 0.0 && lon == 0.0) continue;
      final count = pkgList.length;

      markers.add(Marker(
        point: LatLng(lat, lon),
        width: 64,
        height: 76,
        child: GestureDetector(
          onTap: () =>
              count == 1 ? _showDetail(first) : _showBusinessPackages(pkgList),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _orange,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                            color: _orange.withValues(alpha: 0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 3))
                      ],
                    ),
                    child: const Icon(Icons.fastfood_rounded,
                        color: Colors.white, size: 22),
                  ),
                  if (count > 1)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                            color: Color(0xFF16A34A), shape: BoxShape.circle),
                        child: Text('$count',
                            style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF334155) : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.12), blurRadius: 4)
                  ],
                ),
                child: Text(
                  '₺${first['discounted_price']}',
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF16A34A)),
                ),
              ),
            ],
          ),
        ),
      ));
    }
    return markers;
  }

  void _showBusinessPackages(List<dynamic> pkgList) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pkgList.first['business_name'] ?? '',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : _ink)),
            const SizedBox(height: 12),
            ...pkgList.map((pkg) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.fastfood_rounded, color: _orange),
                  title: Text(pkg['name'] ?? '', style: TextStyle(color: isDark ? Colors.white : _ink)),
                  subtitle: Text('₺${pkg['discounted_price']}',
                      style: const TextStyle(
                          color: Color(0xFF16A34A),
                          fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.pop(context);
                    _showDetail(pkg);
                  },
                )),
          ],
        ),
      ),
    );
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final center = userLocation ?? const LatLng(41.0082, 28.9784);
    final validCount =
        packages.where((p) => (p['latitude'] ?? 0.0) != 0.0).length;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : _bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Container(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Yakınımdaki Paketler',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : _ink,
                                letterSpacing: -0.3)),
                        const SizedBox(height: 2),
                        Text(
                          '$validCount paket bulundu',
                          style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white70 : _muted,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _fetchPackages,
                    icon: Icon(Icons.refresh_rounded,
                        color: isDark ? Colors.white70 : const Color(0xFF64748B)),
                  ),
                ],
              ),
            ),

            // ── Radius Filter ──
            Container(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: radiusOptions.map((r) {
                    final selected = selectedRadius == r;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => selectedRadius = r);
                          _fetchPackages();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected
                                ? _orange
                                : (isDark
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFF1F5F9)),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${r.toInt()} km',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? Colors.white
                                  : (isDark
                                      ? Colors.white70
                                      : const Color(0xFF64748B)),
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
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: _orange, strokeWidth: 2))
                  : Stack(
                      children: [
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                              initialCenter: center, initialZoom: 13.0),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.yemekhane.mobile',
                              maxZoom: 19,
                            ),
                            MarkerLayer(markers: _buildMarkers()),
                          ],
                        ),
                        // Locate button
                        Positioned(
                          bottom: 16,
                          right: 16,
                          child: FloatingActionButton.small(
                            onPressed: () async {
                              await _getUserLocation();
                              _fetchPackages();
                            },
                            backgroundColor:
                                isDark ? const Color(0xFF1E293B) : Colors.white,
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
      setState(() => isLoadingFav = false);
      return;
    }
    try {
      final res = await http.get(
          Uri.parse('$apiBaseUrl/api/v1/favorites?email=${widget.userEmail}'));
      if (res.statusCode == 200) {
        final favs = json.decode(res.body) as List;
        setState(() {
          isFavorite =
              favs.any((f) => f['business_id'] == widget.pkg['business_id']);
          isLoadingFav = false;
        });
      } else {
        setState(() => isLoadingFav = false);
      }
    } catch (_) {
      setState(() => isLoadingFav = false);
    }
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
      final headers = await authHeaders();
      final res = prev
          ? await http.delete(url, headers: headers, body: body)
          : await http.post(url, headers: headers, body: body);
      if ((res.statusCode != 200 && res.statusCode != 201) && mounted) {
        setState(() => isFavorite = prev);
      }
    } catch (_) {
      if (mounted) setState(() => isFavorite = prev);
    }
  }

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
        Navigator.pop(context);
        widget.onPurchaseSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Siparişiniz alındı! Ödemeyi teslimatta yapabilirsiniz. 🎉'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        String errMsg = 'Sipariş oluşturulamadı (${res.statusCode})';
        try {
          final d = json.decode(res.body);
          errMsg = d['error'] ?? errMsg;
        } catch (_) {}
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errMsg)));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Bağlantı hatası: $e')));
    } finally {
      if (mounted) setState(() => isBuying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pkg = widget.pkg;
    final businessName = pkg['business_name'] ?? 'Dükkan';
    final distance = (pkg['distance_km'] as num?)?.toDouble() ?? 0.0;
    final rating = (pkg['rating'] as num?)?.toDouble() ?? 0.0;
    final category = pkg['category']?.toString() ?? '';
    final tags =
        (pkg['tags'] as List?)?.map((e) => e.toString()).toList() ?? [];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),

          // Shop info row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(12)),
                child:
                    const Icon(Icons.store_rounded, color: _orange, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(businessName,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : _ink)),
                    if (rating > 0)
                      Row(children: [
                        const Icon(Icons.star_rounded,
                            color: Color(0xFFFBBF24), size: 14),
                        const SizedBox(width: 3),
                        Text(rating.toStringAsFixed(1),
                            style: TextStyle(
                                fontSize: 12,
                                color: isDark ? Colors.white70 : _muted,
                                fontWeight: FontWeight.w600)),
                      ]),
                  ],
                ),
              ),
              if (distance > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.near_me_rounded,
                          size: 12, color: _muted),
                      const SizedBox(width: 4),
                      Text('${distance.toStringAsFixed(1)} km',
                          style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white70 : _muted,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              const SizedBox(width: 8),
              // Favorite
              GestureDetector(
                onTap: _toggleFavorite,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isFavorite
                        ? (isDark ? const Color(0xFF4C1D24) : const Color(0xFFFFF1F2))
                        : (isDark ? const Color(0xFF334155) : const Color(0xFFF8FAFC)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: isFavorite
                            ? (isDark ? const Color(0xFF991B1B) : const Color(0xFFFECACA))
                            : (isDark ? const Color(0xFF475569) : const Color(0xFFE2E8F0))),
                  ),
                  child: isLoadingFav
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFFF43F5E)))
                      : Icon(
                          isFavorite
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: const Color(0xFFF43F5E),
                          size: 18,
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9), height: 1),
          const SizedBox(height: 16),

          // Package detail row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: pkg['image_url'] != null && pkg['image_url'] != ''
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(pkg['image_url'],
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.fastfood_rounded,
                                color: _orange,
                                size: 36)))
                    : const Icon(Icons.fastfood_rounded,
                        color: _orange, size: 36),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pkg['name'] ?? '',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : _ink)),
                    if (category.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(category,
                          style: const TextStyle(
                              fontSize: 11,
                              color: _orange,
                              fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(height: 4),
                    Text(pkg['description'] ?? '',
                        style: TextStyle(
                            fontSize: 12, color: isDark ? Colors.white70 : _muted, height: 1.4),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    // Tags
                    if (tags.isNotEmpty)
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: tags
                            .map((t) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF4C1D24) : const Color(0xFFFFF1F2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(t,
                                      style: const TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFFE11D48))),
                                ))
                            .toList(),
                      ),
                    const SizedBox(height: 8),
                    // Price
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('₺${pkg['original_price']}',
                            style: TextStyle(
                                decoration: TextDecoration.lineThrough,
                                color: isDark ? Colors.white38 : _muted,
                                fontSize: 12)),
                        const SizedBox(width: 8),
                        Text('₺${pkg['discounted_price']}',
                            style: const TextStyle(
                                color: Color(0xFF16A34A),
                                fontWeight: FontWeight.bold,
                                fontSize: 22)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text('${pkg['stock']} adet',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF3B82F6),
                                  fontWeight: FontWeight.w600)),
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
                disabledBackgroundColor: const Color(0xFFD1FAE5),
              ),
              child: isBuying
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Hemen Al',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
