import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../api_config.dart';

const _ink    = Color(0xFF0F172A);
const _muted  = Color(0xFF94A3B8);
const _orange = Color(0xFFF97316);
const _bg     = Color(0xFFF8FAFC);

class BusinessDetailScreen extends StatefulWidget {
  final Map<String, dynamic> business;

  const BusinessDetailScreen({super.key, required this.business});

  @override
  State<BusinessDetailScreen> createState() => _BusinessDetailScreenState();
}

class _BusinessDetailScreenState extends State<BusinessDetailScreen> {
  List<dynamic> _packages = [];
  bool _isLoadingPkgs = true;
  bool _isFavorite = false;
  bool _isLoadingFav = true;
  String? _userEmail;
  String _bizId = '';

  List<dynamic> _reviews = [];
  double _avgRating = 0;
  int _reviewCount = 0;
  bool _isLoadingReviews = true;
  bool _hasReviewed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 'id' (search sonucu) veya 'business_id' (favoriler) her ikisini de destekle
    _bizId = ((widget.business['id'] ?? widget.business['business_id']) as String? ?? '');

    _userEmail = Supabase.instance.client.auth.currentSession?.user.email;
    if (_userEmail == null || _userEmail!.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      _userEmail = prefs.getString('user_email');
    }
    await Future.wait([_fetchPackages(), _checkFavorite(), _fetchReviews()]);
  }

  Future<void> _fetchReviews() async {
    final bizId = _bizId;
    if (bizId.isEmpty) { setState(() => _isLoadingReviews = false); return; }
    try {
      final res = await http.get(Uri.parse('$apiBaseUrl/api/v1/businesses/$bizId/reviews'));
      if (res.statusCode == 200 && mounted) {
        final data = json.decode(res.body);
        final reviewList = data['reviews'] as List? ?? [];
        setState(() {
          _reviews = reviewList;
          _avgRating = (data['avg_rating'] as num?)?.toDouble() ?? 0;
          _reviewCount = (data['count'] as num?)?.toInt() ?? 0;
          _isLoadingReviews = false;
          _hasReviewed = reviewList.any((r) => r['user_email'] == _userEmail);
        });
      } else {
        setState(() => _isLoadingReviews = false);
      }
    } catch (_) {
      setState(() => _isLoadingReviews = false);
    }
  }

  Future<void> _fetchPackages() async {
    final bizId = _bizId;
    try {
      final uri = Uri.parse('$apiBaseUrl/api/v1/packages').replace(
        queryParameters: {'business_id': bizId},
      );
      final res = await http.get(uri);
      if (res.statusCode == 200 && mounted) {
        final body = json.decode(res.body);
        final List<dynamic> list = (body is Map && body['data'] != null)
            ? body['data']
            : (body is List ? body : []);
        setState(() { _packages = list; _isLoadingPkgs = false; });
      } else {
        setState(() => _isLoadingPkgs = false);
      }
    } catch (_) {
      setState(() => _isLoadingPkgs = false);
    }
  }

  Future<void> _checkFavorite() async {
    if (_userEmail == null) { setState(() => _isLoadingFav = false); return; }
    final bizId = _bizId;
    try {
      final res = await http.get(Uri.parse('$apiBaseUrl/api/v1/favorites?email=$_userEmail'));
      if (res.statusCode == 200 && mounted) {
        final favs = json.decode(res.body) as List;
        setState(() {
          _isFavorite = favs.any((f) => f['business_id'] == bizId);
          _isLoadingFav = false;
        });
      } else {
        setState(() => _isLoadingFav = false);
      }
    } catch (_) { setState(() => _isLoadingFav = false); }
  }

  Future<void> _toggleFavorite() async {
    if (_userEmail == null) return;
    final prev = _isFavorite;
    setState(() => _isFavorite = !_isFavorite);
    try {
      final url = Uri.parse('$apiBaseUrl/api/v1/favorites');
      final body = json.encode({
        'user_email': _userEmail,
        'business_id': _bizId,
        'business_name': widget.business['name'] ?? '',
      });
      final headers = await authHeaders();
      final res = prev
          ? await http.delete(url, headers: headers, body: body)
          : await http.post(url, headers: headers, body: body);
      if ((res.statusCode != 200 && res.statusCode != 201) && mounted) {
        setState(() => _isFavorite = prev);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('İşlem başarısız, tekrar deneyin.')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isFavorite ? 'Favorilere eklendi ❤️' : 'Favorilerden kaldırıldı'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (_) { if (mounted) setState(() => _isFavorite = prev); }
  }

  void _showReviewSheet() {
    int rating = 5;
    final ctrl = TextEditingController();
    final bizId = _bizId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                const Text('İşletmeyi Değerlendir', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _ink)),
                const SizedBox(height: 4),
                const Text('Deneyiminizi paylaşın', style: TextStyle(fontSize: 13, color: _muted)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) => GestureDetector(
                    onTap: () => setSheet(() => rating = i + 1),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: const Color(0xFFFBBF24),
                        size: 38,
                      ),
                    ),
                  )),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 14, color: _ink),
                  decoration: InputDecoration(
                    hintText: 'Yorumunuz (isteğe bağlı)',
                    hintStyle: const TextStyle(color: _muted, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _orange, width: 1.5)),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      child: const Text('İptal', style: TextStyle(color: _muted)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final comment = ctrl.text;
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          final res = await http.post(
                            Uri.parse('$apiBaseUrl/api/v1/reviews'),
                            headers: await authHeaders(),
                            body: json.encode({
                              'business_id': bizId,
                              'user_email': _userEmail ?? '',
                              'order_id': '',
                              'rating': rating,
                              'comment': comment,
                            }),
                          );
                          if (!mounted) return;
                          if (res.statusCode == 201) {
                            await _fetchReviews();
                            messenger.showSnackBar(SnackBar(
                              content: const Text('Yorumunuz alındı 🎉'),
                              backgroundColor: const Color(0xFF10B981),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              margin: const EdgeInsets.all(16),
                            ));
                          } else if (res.statusCode == 409) {
                            messenger.showSnackBar(SnackBar(
                              content: const Text('Bu işletmeyi zaten değerlendirdiniz'),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              margin: const EdgeInsets.all(16),
                            ));
                          }
                        } catch (_) {}
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: const Text('Gönder', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _buy(Map<String, dynamic> pkg) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/v1/orders'),
        headers: await authHeaders(),
        body: json.encode({
          'package_id': pkg['id'],
          'buyer_email': _userEmail ?? '',
        }),
      );
      if (!mounted) return;
      if (res.statusCode == 201) {
        await _fetchPackages();
        messenger.showSnackBar(
          const SnackBar(content: Text('Siparişiniz alındı! Ödemeyi teslimatta yapabilirsiniz. 🎉'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating),
        );
      } else {
        String errMsg = 'Sipariş oluşturulamadı (${res.statusCode})';
        try { final d = json.decode(res.body); errMsg = d['error'] ?? errMsg; } catch (_) {}
        messenger.showSnackBar(SnackBar(content: Text(errMsg)));
      }
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text('Bağlantı hatası: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.business['name'] as String? ?? '';
    final address = widget.business['address'] as String? ?? '';
    final category = widget.business['category'] as String? ?? '';
    final logoUrl = widget.business['logo_url'] as String? ?? '';

    return Scaffold(
      backgroundColor: _bg,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ──
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: Colors.white,
            iconTheme: const IconThemeData(color: _ink),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: const Color(0xFFFFF7ED),
                child: Center(
                  child: logoUrl.isNotEmpty
                      ? Image.network(logoUrl, fit: BoxFit.cover, width: double.infinity,
                          errorBuilder: (_, __, ___) => const Icon(Icons.store_rounded, color: _orange, size: 64))
                      : const Icon(Icons.store_rounded, color: _orange, size: 64),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _isLoadingFav
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _orange)),
                      )
                    : IconButton(
                        icon: Icon(
                          _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: _isFavorite ? const Color(0xFFF43F5E) : _muted,
                        ),
                        onPressed: _toggleFavorite,
                        tooltip: _isFavorite ? 'Favorilerden çıkar' : 'Favorilere ekle',
                      ),
              ),
            ],
          ),

          // ── Business Info ──
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _ink, letterSpacing: -0.5)),
                  if (category.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(20)),
                      child: Text(category, style: const TextStyle(fontSize: 12, color: _orange, fontWeight: FontWeight.w600)),
                    ),
                  ],
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, size: 14, color: _muted),
                        const SizedBox(width: 4),
                        Expanded(child: Text(address, style: const TextStyle(fontSize: 13, color: _muted))),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ── Packages Header ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                'Mevcut Paketler',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _ink),
              ),
            ),
          ),

          // ── Packages List ──
          if (_isLoadingPkgs)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator(color: _orange, strokeWidth: 2)),
            )
          else if (_packages.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.lunch_dining_rounded, size: 48, color: Color(0xFFCBD5E1)),
                    SizedBox(height: 12),
                    Text('Şu an aktif paket yok', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                    SizedBox(height: 4),
                    Text('Daha sonra tekrar kontrol edin', style: TextStyle(fontSize: 13, color: _muted)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _PackageCard(
                      pkg: _packages[i],
                      onBuy: () => _buy(_packages[i]),
                    ),
                  ),
                  childCount: _packages.length,
                ),
              ),
            ),

          // ── Reviews Section ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  const Text('Yorumlar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _ink)),
                  if (!_isLoadingReviews && _reviewCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 14),
                          const SizedBox(width: 3),
                          Text(
                            '${_avgRating.toStringAsFixed(1)}  ($_reviewCount)',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _orange),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (!_isLoadingReviews)
                    OutlinedButton.icon(
                      onPressed: _hasReviewed ? null : _showReviewSheet,
                      icon: Icon(
                        _hasReviewed ? Icons.check_circle_rounded : Icons.star_outline_rounded,
                        size: 14,
                      ),
                      label: Text(
                        _hasReviewed ? 'Değerlendirildi ✓' : 'Yorum Yap',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _hasReviewed ? const Color(0xFF10B981) : _orange,
                        disabledForegroundColor: const Color(0xFF10B981),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        side: BorderSide(
                          color: _hasReviewed ? const Color(0xFFD1FAE5) : const Color(0xFFFFEDD5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          if (_isLoadingReviews)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(color: _orange, strokeWidth: 2)),
              ),
            )
          else if (_reviews.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 32),
                child: Text('Henüz yorum yok.', style: TextStyle(fontSize: 13, color: _muted)),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _ReviewCard(review: _reviews[i]),
                  ),
                  childCount: _reviews.length,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────── Review Card ────────────────────
class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final email = review['user_email'] as String? ?? '';
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = review['comment'] as String? ?? '';
    final avatar = email.isNotEmpty ? email[0].toUpperCase() : '?';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFFFF7ED),
            child: Text(avatar, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: _orange)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        email.length > 20 ? '${email.substring(0, 20)}…' : email,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _ink),
                      ),
                    ),
                    Row(
                      children: List.generate(5, (i) => Icon(
                        i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: const Color(0xFFFBBF24),
                        size: 13,
                      )),
                    ),
                  ],
                ),
                if (comment.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(comment, style: const TextStyle(fontSize: 13, color: _muted, height: 1.4)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────── Package Card ───────────────────
class _PackageCard extends StatelessWidget {
  final Map<String, dynamic> pkg;
  final VoidCallback onBuy;

  const _PackageCard({required this.pkg, required this.onBuy});

  @override
  Widget build(BuildContext context) {
    final name = pkg['name'] as String? ?? '';
    final description = pkg['description'] as String? ?? '';
    final originalPrice = (pkg['original_price'] as num?)?.toDouble() ?? 0;
    final discountedPrice = (pkg['discounted_price'] as num?)?.toDouble() ?? 0;
    final stock = (pkg['stock'] as num?)?.toInt() ?? 0;
    final imageUrl = pkg['image_url'] as String? ?? '';
    final category = pkg['category'] as String? ?? '';
    final discount = originalPrice > 0 ? (((originalPrice - discountedPrice) / originalPrice) * 100).round() : 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image + discount badge
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: imageUrl.isNotEmpty
                    ? Image.network(imageUrl, height: 140, width: double.infinity, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(height: 100, color: const Color(0xFFFFF7ED), child: const Center(child: Icon(Icons.lunch_dining_rounded, color: _orange, size: 40))))
                    : Container(height: 100, color: const Color(0xFFFFF7ED), child: const Center(child: Icon(Icons.lunch_dining_rounded, color: _orange, size: 40))),
              ),
              if (discount > 0)
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: _orange, borderRadius: BorderRadius.circular(8)),
                    child: Text('%$discount', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: stock > 0 ? const Color(0xFFDCFCE7) : const Color(0xFFFFEDED), borderRadius: BorderRadius.circular(8)),
                  child: Text('Stok: $stock', style: TextStyle(color: stock > 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626), fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (category.isNotEmpty)
                  Text(category, style: const TextStyle(fontSize: 11, color: _orange, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _ink)),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: _muted, height: 1.4)),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    // Prices
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (originalPrice > discountedPrice)
                          Text('₺${originalPrice.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 12, color: _muted, decoration: TextDecoration.lineThrough)),
                        Text('₺${discountedPrice.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _orange)),
                      ],
                    ),
                    const Spacer(),
                    // Buy button
                    GestureDetector(
                      onTap: stock > 0 ? onBuy : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          color: stock > 0 ? _orange : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          stock > 0 ? 'Hemen Al' : 'Tükendi',
                          style: TextStyle(
                            color: stock > 0 ? Colors.white : _muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
}
