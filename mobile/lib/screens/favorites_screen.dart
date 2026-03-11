import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api_config.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<dynamic> favorites = [];
  bool isLoading = true;
  String? userEmail;

  @override
  void initState() {
    super.initState();
    _loadAndFetch();
  }

  Future<void> _loadAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    userEmail = prefs.getString('user_email');
    await _fetchFavorites();
  }

  Future<void> _fetchFavorites() async {
    if (userEmail == null) {
      setState(() => isLoading = false);
      return;
    }
    setState(() => isLoading = true);
    try {
      final res = await http.get(
        Uri.parse('$apiBaseUrl/api/v1/favorites?email=$userEmail'),
      );
      if (res.statusCode == 200) {
        setState(() {
          favorites = json.decode(res.body);
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (_) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _removeFavorite(String businessName) async {
    // Optimistic remove
    final backup = List.from(favorites);
    setState(() => favorites.removeWhere((f) => f['business_name'] == businessName));

    try {
      final res = await http.delete(
        Uri.parse('$apiBaseUrl/api/v1/favorites'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'user_email': userEmail, 'business_name': businessName}),
      );
      if (res.statusCode != 200 && mounted) {
        setState(() => favorites = backup);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kaldırılamadı, tekrar deneyin.')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Favorilerden kaldırıldı'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => favorites = backup);
    }
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
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Favorilerim',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          favorites.isEmpty && !isLoading
                              ? 'Henüz favori eklenmedi'
                              : '${favorites.length} favori dükkan',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _fetchFavorites,
                    icon: const Icon(Icons.refresh_rounded),
                    color: const Color(0xFF64748B),
                    tooltip: 'Yenile',
                  ),
                ],
              ),
            ),

            // ── Content ──
            Expanded(
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFF97316),
                        strokeWidth: 2,
                      ),
                    )
                  : favorites.isEmpty
                      ? _buildEmpty()
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: favorites.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final fav = favorites[index];
                            return _FavoriteCard(
                              businessName: fav['business_name'] ?? 'Bilinmeyen',
                              onRemove: () => _removeFavorite(fav['business_name']),
                            );
                          },
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
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.favorite_border_rounded,
              size: 36,
              color: Color(0xFFF43F5E),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Favori dükkanın yok',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Harita ekranından dükkanları\nfavorilerine ekleyebilirsin',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8), height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  final String businessName;
  final VoidCallback onRemove;

  const _FavoriteCard({required this.businessName, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.store_rounded,
                color: Color(0xFFF97316),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            // Name
            Expanded(
              child: Text(
                businessName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
            // Remove button
            GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Color(0xFFF43F5E),
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
