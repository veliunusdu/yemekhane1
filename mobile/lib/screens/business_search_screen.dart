import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api_config.dart';
import 'business_detail_screen.dart';

class BusinessSearchScreen extends StatefulWidget {
  const BusinessSearchScreen({super.key});

  @override
  State<BusinessSearchScreen> createState() => _BusinessSearchScreenState();
}

class _BusinessSearchScreenState extends State<BusinessSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  List<dynamic> _results = [];
  bool _isLoading = false;
  bool _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() { _isLoading = true; _searched = true; });
    try {
      final uri = Uri.parse('$apiBaseUrl/api/v1/businesses/search').replace(
        queryParameters: {'q': query},
      );
      final res = await http.get(uri);
      if (res.statusCode == 200 && mounted) {
        setState(() { _results = json.decode(res.body); _isLoading = false; });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'İşletme Ara',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                autofocus: true,
                style: const TextStyle(fontSize: 15, color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  hintText: 'İşletme adı ile ara...',
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF94A3B8), size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: Color(0xFF94A3B8), size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() { _results = []; _searched = false; });
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                ),
              ),
            ),
          ),

          // Results
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFF97316), strokeWidth: 2))
                : !_searched
                    ? _buildHint()
                    : _results.isEmpty
                        ? _buildEmpty()
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: _results.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final biz = _results[i];
                              return _BusinessCard(
                                biz: biz,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BusinessDetailScreen(business: biz),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildHint() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.store_rounded, size: 48, color: Color(0xFFCBD5E1)),
          SizedBox(height: 12),
          Text(
            'İşletme ara',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
          ),
          SizedBox(height: 4),
          Text(
            'Yukarıdaki arama kutusuna\nişletme adı yaz',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8), height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: Color(0xFFCBD5E1)),
          SizedBox(height: 12),
          Text(
            'Sonuç bulunamadı',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
          ),
          SizedBox(height: 4),
          Text(
            'Farklı bir arama terimi deneyin',
            style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }
}

class _BusinessCard extends StatelessWidget {
  final Map<String, dynamic> biz;
  final VoidCallback onTap;

  const _BusinessCard({required this.biz, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = biz['name'] as String? ?? '';
    final address = biz['address'] as String? ?? '';
    final category = biz['category'] as String? ?? '';
    final logoUrl = biz['logo_url'] as String? ?? '';

    return GestureDetector(
      onTap: onTap,
      child: Container(
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
              // Logo / Avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: logoUrl.isNotEmpty
                    ? Image.network(logoUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.store_rounded, color: Color(0xFFF97316), size: 24))
                    : const Icon(Icons.store_rounded, color: Color(0xFFF97316), size: 24),
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                    ),
                    if (category.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(category, style: const TextStyle(fontSize: 12, color: Color(0xFFF97316), fontWeight: FontWeight.w500)),
                    ],
                    if (address.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
