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
    setState(
        () => favorites.removeWhere((f) => f['business_name'] == businessName));

    try {
      final res = await http.delete(
        Uri.parse('$apiBaseUrl/api/v1/favorites'),
        headers: {'Content-Type': 'application/json'},
        body: json
            .encode({'user_email': userEmail, 'business_name': businessName}),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Favorilerim',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    favorites.isEmpty && !isLoading
                        ? 'Henüz favori eklenmedi'
                        : '${favorites.length} favori dükkan',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),

            // ── Content ──
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFF97316), strokeWidth: 2))
                  : RefreshIndicator(
                      color: const Color(0xFFF97316),
                      onRefresh: _fetchFavorites,
                      child: favorites.isEmpty
                          ? Stack(children: [ListView(), _buildEmpty(isDark)])
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: favorites.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final fav = favorites[index];
                                return _FavoriteCard(
                                  businessName: fav['business_name'] ?? 'Bilinmeyen',
                                  onRemove: () => _removeFavorite(fav['business_name']),
                                  isDark: isDark,
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

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite_border, size: 48, color: isDark ? Colors.white24 : Colors.grey),
          const SizedBox(height: 16),
          Text('Favori dükkanın yok', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white70 : Colors.black87)),
        ],
      ),
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  final String businessName;
  final VoidCallback onRemove;
  final bool isDark;

  const _FavoriteCard(
      {required this.businessName, required this.onRemove, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
        boxShadow: isDark
            ? []
            : [
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
                color: isDark ? const Color(0xFF334155) : const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.storefront_rounded,
                  color: Color(0xFFF97316), size: 24),
            ),
            const SizedBox(width: 14),
            // Name
            Expanded(
              child: Text(
                businessName,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF1E293B)),
              ),
            ),
            // Action
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.favorite_rounded,
                  color: Color(0xFFEF4444), size: 22),
              tooltip: 'Favorilerden Kaldır',
            ),
          ],
        ),
      ),
    );
  }
}

