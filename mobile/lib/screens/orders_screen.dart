import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../api_config.dart';

// ── Renk + stil sabitleri ──────────────────────────────
const _bg     = Color(0xFFF8FAFC);
const _card   = Colors.white;
const _ink    = Color(0xFF0F172A);
const _muted  = Color(0xFF94A3B8);
const _orange = Color(0xFFF97316);

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<dynamic> orders = [];
  bool isLoading = true;
  String? _userEmail;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _initOrders();
  }

  Future<void> _initOrders() async {
    final prefs = await SharedPreferences.getInstance();
    _userEmail = prefs.getString('user_email');
    await fetchOrders();
    _subscribeToRealtime();
  }

  void _subscribeToRealtime() {
    if (_userEmail == null || _userEmail!.isEmpty) return;
    _channel = Supabase.instance.client
        .channel('orders-${_userEmail!.replaceAll(RegExp(r'[@.]'), '-')}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'buyer_email',
            value: _userEmail!,
          ),
          callback: (payload) => _handleRealtimeUpdate(payload.newRecord),
        )
        .subscribe();
  }

  void _handleRealtimeUpdate(Map<String, dynamic> updated) {
    if (!mounted) return;
    setState(() {
      final idx = orders.indexWhere((o) => o['id'] == updated['id']);
      if (idx != -1) orders[idx] = {...orders[idx], 'status': updated['status']};
    });

    final status = updated['status'] ?? '';
    final configs = {
      'Teslim Edilmeyi Bekliyor': (Icons.check_circle_rounded,    const Color(0xFF8B5CF6), '🎉 Siparişiniz hazır!'),
      'Teslim Edildi':            (Icons.done_all_rounded,        const Color(0xFF10B981), '✅ Teslim edildi'),
      'Hazırlanıyor':             (Icons.restaurant_menu_rounded, _orange,                 '👨‍🍳 Hazırlanıyor'),
    };
    final cfg = configs[status];
    if (cfg == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(cfg.$1, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(cfg.$3, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
        backgroundColor: cfg.$2,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> fetchOrders() async {
    try {
      if (_userEmail == null || _userEmail!.isEmpty) {
        setState(() => isLoading = false);
        return;
      }
      final uri = Uri.parse('$apiBaseUrl/api/v1/orders/me')
          .replace(queryParameters: {'email': _userEmail!});
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        setState(() { orders = json.decode(res.body) ?? []; isLoading = false; });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('Orders error: $e');
      setState(() => isLoading = false);
    }
  }

  // ── Review dialog ─────────────────────────────────────
  void _showReviewDialog(dynamic order) {
    int rating = 5;
    final ctrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheet) => Container(
          decoration: const BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            24, 16, 24, MediaQuery.of(context).viewInsets.bottom + 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 20),
              const Text('Siparişi Değerlendir', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _ink)),
              const SizedBox(height: 4),
              const Text('Deneyiminizi paylaşın', style: TextStyle(fontSize: 13, color: _muted)),
              const SizedBox(height: 20),
              // Stars
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
              // Comment field
              TextField(
                controller: ctrl,
                maxLines: 3,
                style: const TextStyle(fontSize: 14, color: _ink),
                decoration: InputDecoration(
                  hintText: 'Yorumunuz (isteğe bağlı)',
                  hintStyle: const TextStyle(color: _muted, fontSize: 13),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _orange, width: 1.5),
                  ),
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
                      await _submitReview(order, rating, ctrl.text);
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
    );
  }

  Future<void> _submitReview(dynamic order, int rating, String comment) async {
    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/v1/reviews'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'order_id': order['id'],
          'user_email': _userEmail,
          'business_id': order['business_id'] ?? '',
          'rating': rating,
          'comment': comment,
        }),
      );
      if (res.statusCode == 201 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Değerlendirmeniz alındı, teşekkürler!'),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ));
      }
    } catch (_) {}
  }

  // ── QR dialog ─────────────────────────────────────────
  void _showQR(String orderId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text('Teslimat QR Kodu', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _ink)),
            const SizedBox(height: 6),
            const Text(
              'Kantindeki görevliye bu kodu okutun',
              style: TextStyle(fontSize: 13, color: _muted),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: QrImageView(
                data: orderId,
                version: QrVersions.auto,
                size: 200,
                backgroundColor: Colors.transparent,
                errorStateBuilder: (_, __) => const Text('Kod oluşturulamadı'),
              ),
            ),
            const SizedBox(height: 12),
            Text(orderId, style: const TextStyle(fontSize: 10, color: _muted, letterSpacing: 0.5)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                child: const Text('Kapat', style: TextStyle(color: _muted)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Status config ─────────────────────────────────────
  static const _statusCfg = {
    'Ödendi':                   (Color(0xFF10B981), Color(0xFFECFDF5), Icons.check_circle_outline_rounded,  'Ödendi'),
    'Hazırlanıyor':             (Color(0xFFF97316), Color(0xFFFFF7ED), Icons.restaurant_menu_rounded,       'Hazırlanıyor'),
    'Teslim Edilmeyi Bekliyor': (Color(0xFF8B5CF6), Color(0xFFF5F3FF), Icons.delivery_dining_rounded,       'Teslim Bekliyor'),
    'Teslim Edildi':            (Color(0xFF94A3B8), Color(0xFFF8FAFC), Icons.done_all_rounded,              'Teslim Edildi'),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
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
                        const Text('Siparişlerim',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _ink, letterSpacing: -0.5)),
                        const SizedBox(height: 2),
                        Row(children: [
                          _LiveDot(),
                          const SizedBox(width: 6),
                          const Text('Canlı güncelleme', style: TextStyle(fontSize: 12, color: _muted)),
                        ]),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () { setState(() => isLoading = true); fetchOrders(); },
                    icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),

            // ── Content ──
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(color: _orange, strokeWidth: 2))
                  : orders.isEmpty
                      ? _buildEmpty()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: orders.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) => _OrderCard(
                            order: orders[i],
                            onShowQR: _showQR,
                            onReview: _showReviewDialog,
                            onUpdateStatus: (id, s) async {
                              await http.patch(
                                Uri.parse('$apiBaseUrl/api/v1/orders/$id/status'),
                                headers: {'Content-Type': 'application/json'},
                                body: json.encode({'status': s}),
                              );
                            },
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
            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.receipt_long_rounded, size: 36, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 16),
          const Text('Sipariş bulunamadı', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _ink)),
          const SizedBox(height: 6),
          const Text('Aktif siparişleriniz burada görünecek', style: TextStyle(fontSize: 13, color: _muted)),
        ],
      ),
    );
  }
}

// ── Order Card ────────────────────────────────────────────
class _OrderCard extends StatelessWidget {
  final dynamic order;
  final void Function(String) onShowQR;
  final void Function(dynamic) onReview;
  final Future<void> Function(String, String) onUpdateStatus;

  const _OrderCard({
    required this.order,
    required this.onShowQR,
    required this.onReview,
    required this.onUpdateStatus,
  });

  static const _statusCfg = {
    'Ödendi':                   (Color(0xFF10B981), Color(0xFFECFDF5), Icons.check_circle_outline_rounded),
    'Hazırlanıyor':             (Color(0xFFF97316), Color(0xFFFFF7ED), Icons.restaurant_menu_rounded),
    'Teslim Edilmeyi Bekliyor': (Color(0xFF8B5CF6), Color(0xFFF5F3FF), Icons.delivery_dining_rounded),
    'Teslim Edildi':            (Color(0xFF94A3B8), Color(0xFFF8FAFC), Icons.done_all_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final status = order['status'] ?? '';
    final cfg = _statusCfg[status] ?? _statusCfg['Ödendi']!;
    final color = cfg.$1;
    final bgColor = cfg.$2;
    final icon = cfg.$3;
    final isDelivered = status == 'Teslim Edildi';

    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Opacity(
        opacity: isDelivered ? 0.65 : 1.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.fastfood_rounded, color: Color(0xFFF97316), size: 22),
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order['package_name'] ?? 'Paket',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _ink),
                        ),
                        const SizedBox(height: 2),
                        if (order['created_at'] != null)
                          Text(
                            _formatDate(order['created_at']),
                            style: const TextStyle(fontSize: 11, color: _muted),
                          ),
                      ],
                    ),
                  ),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: color, size: 13),
                        const SizedBox(width: 4),
                        Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Divider + Action ──
            if (!isDelivered) ...[
              Divider(height: 1, color: const Color(0xFFF1F5F9)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: _buildAction(context, status),
              ),
            ] else
              const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildAction(BuildContext context, String status) {
    if (status == 'Teslim Edilmeyi Bekliyor') {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => onShowQR(order['id']),
          icon: const Icon(Icons.qr_code_2_rounded, size: 18),
          label: const Text('Teslimat QR Kodunu Göster', style: TextStyle(fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF8B5CF6),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
        ),
      );
    }

    if (status == 'Teslim Edildi') {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => onReview(order),
          icon: const Icon(Icons.star_outline_rounded, size: 16),
          label: const Text('Değerlendir', style: TextStyle(fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFF97316),
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            side: const BorderSide(color: Color(0xFFFFEDD5)),
          ),
        ),
      );
    }

    // Ödendi: bilgi satırı
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF10B981), size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Ödeme alındı, dükkan siparişi işleme alacak',
              style: TextStyle(fontSize: 12, color: Color(0xFF059669), fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.day}.${dt.month}.${dt.year}  ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    } catch (_) {
      return raw;
    }
  }
}

// ── Animated Live Dot ─────────────────────────────────────
class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _anim,
    child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
  );
}
