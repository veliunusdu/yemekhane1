import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../api_config.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List<dynamic> orders = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchOrders();
  }

  Future<void> fetchOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('user_email');

      if (email == null || email.isEmpty) {
        setState(() => isLoading = false);
        return;
      }

      final uri = Uri.parse('$apiBaseUrl/api/v1/orders/me')
          .replace(queryParameters: {'email': email});

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        setState(() {
          var decodedData = json.decode(response.body);
          orders = decodedData ?? [];
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      print("Orders Fetch Error: $e");
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
                QrImageView(
                  data: orderId,
                  version: QrVersions.auto,
                  size: 200.0,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  errorStateBuilder: (cxt, err) {
                    return const Center(
                      child: Text(
                        "Kod oluşturulamadı",
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Aktif Siparişlerim', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        actions: [
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
              ? const Center(child: Text('Henüz aktif bir siparişiniz yok 😔'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    return Card(
                      elevation: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: const Icon(Icons.fastfood, color: Colors.orange, size: 40),
                        title: Text(
                          order['package_name'] ?? 'Paket ID: ${order['package_id']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Durum: ${order['status']}',
                              style: TextStyle(
                                color: order['status'] == 'Ödendi'
                                    ? Colors.green
                                    : order['status'] == 'Teslim Edildi'
                                        ? Colors.blue
                                        : Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (order['created_at'] != null)
                              Text(
                                'Tarih: ${DateTime.parse(order['created_at']).toLocal().toString().substring(0, 16)}',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                          ],
                        ),
                        trailing: order['status'] == 'Ödendi'
                            ? ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                onPressed: () => _showQRCode(context, order['id']),
                                child: const Icon(Icons.qr_code_2, color: Colors.white),
                              )
                            : null,
                      ),
                    );
                  },
                ),
    );
  }
}
