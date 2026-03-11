import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../api_config.dart';

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

  /// Supabase Realtime: orders tablosundaki UPDATE olaylarını dinle
  void _subscribeToRealtime() {
    if (_userEmail == null || _userEmail!.isEmpty) return;

    _channel = Supabase.instance.client
        .channel('orders-user-${_userEmail!.replaceAll('@', '-').replaceAll('.', '-')}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'buyer_email',
            value: _userEmail!,
          ),
          callback: (payload) {
            debugPrint('🔔 Realtime: Sipariş güncellendi! ${payload.newRecord}');
            _handleOrderUpdate(payload.newRecord);
          },
        )
        .subscribe();
  }

  /// Realtime'dan gelen güncellemeyi yerel listeye yansıt
  void _handleOrderUpdate(Map<String, dynamic> updatedOrder) {
    if (!mounted) return;
    setState(() {
      final idx = orders.indexWhere((o) => o['id'] == updatedOrder['id']);
      if (idx != -1) {
        orders[idx] = {
          ...orders[idx],
          'status': updatedOrder['status'],
        };
      }
    });

    // Durum değişim bildirimi
    final newStatus = updatedOrder['status'] ?? '';
    String emoji = '📦';
    Color color = Colors.orange;

    if (newStatus == 'Teslim Edilmeyi Bekliyor') {
      emoji = '🎉';
      color = Colors.blue;
    } else if (newStatus == 'Teslim Edildi') {
      emoji = '✅';
      color = Colors.green;
    } else if (newStatus == 'Hazırlanıyor') {
      emoji = '👨‍🍳';
      color = Colors.orange;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sipariş durumu güncellendi: $newStatus',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        setState(() {
          final decodedData = json.decode(response.body);
          orders = decodedData ?? [];
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('Orders Fetch Error: $e');
      setState(() => isLoading = false);
    }
  }

  void _showQRCode(BuildContext context, String orderId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Teslimat QR Kodu', textAlign: TextAlign.center),
          content: SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Bu kodu kantindeki görevliye okutarak teslim alabilirsiniz.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                QrImageView(
                  data: orderId,
                  version: QrVersions.auto,
                  size: 200.0,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  errorStateBuilder: (cxt, err) {
                    return const Center(
                      child: Text(
                        'Kod oluşturulamadı',
                        textAlign: TextAlign.center,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  orderId,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Kapat'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  /// Sipariş durumuna göre renk ve ikon
  Color _statusColor(String status) {
    switch (status) {
      case 'Ödendi':
        return Colors.green;
      case 'Hazırlanıyor':
        return Colors.orange;
      case 'Teslim Edilmeyi Bekliyor':
        return Colors.blue;
      case 'Teslim Edildi':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'Ödendi':
        return Icons.check_circle_outline;
      case 'Hazırlanıyor':
        return Icons.restaurant;
      case 'Teslim Edilmeyi Bekliyor':
        return Icons.delivery_dining;
      case 'Teslim Edildi':
        return Icons.done_all;
      default:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Aktif Siparişlerim',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
          // Canlı bağlantı göstergesi
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Center(
              child: Row(
                children: const [
                  _LiveDot(),
                  SizedBox(width: 4),
                  Text('Canlı', style: TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => isLoading = true);
              fetchOrders();
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : orders.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text(
                        'Henüz aktif bir siparişiniz yok 😔',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    final status = order['status'] ?? '';
                    final statusColor = _statusColor(status);
                    final statusIcon = _statusIcon(status);

                    return Card(
                      elevation: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Paket adı + ikon
                            Row(
                              children: [
                                Icon(Icons.fastfood,
                                    color: Colors.orange, size: 28),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    order['package_name'] ??
                                        'Paket ID: ${order['package_id']}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 8),

                            // Durum göstergesi (renkli satır)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: statusColor.withAlpha(25),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: statusColor.withAlpha(102)),
                              ),
                              child: Row(
                                children: [
                                  Icon(statusIcon,
                                      color: statusColor, size: 18),
                                  const SizedBox(width: 6),
                                  Text(
                                    status,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 6),

                            // Tarih
                            if (order['created_at'] != null)
                              Text(
                                'Tarih: ${DateTime.parse(order['created_at']).toLocal().toString().substring(0, 16)}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),

                            // QR butonu (Ödendi durumunda)
                            if (status == 'Ödendi')
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.qr_code_2),
                                    label: const Text('Teslimat QR Kodunu Göster'),
                                    onPressed: () =>
                                        _showQRCode(context, order['id']),
                                  ),
                                ),
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

/// Canlı bağlantı göstergesi (yeşil titreyen nokta)
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.greenAccent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
