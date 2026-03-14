import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../api_config.dart';

class ImpactScreen extends StatefulWidget {
  const ImpactScreen({super.key});

  @override
  State<ImpactScreen> createState() => _ImpactScreenState();
}

class _ImpactScreenState extends State<ImpactScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  int _completedOrders = 0;
  double _savedFoodKg = 0;
  double _co2AvoidedKg = 0;
  double _moneySaved = 0;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  static const List<_Badge> _allBadges = [
    _Badge('🌱', 'İlk Adım', 'İlk siparişini tamamladın', 1),
    _Badge('🌿', 'Çevre Dostu', '5 siparişi tamamladın', 5),
    _Badge('🥗', 'Gıda Kurtarıcı', '10 siparişi tamamladın', 10),
    _Badge('🌍', 'Eko Savaşçı', '25 siparişi tamamladın', 25),
    _Badge('🦸', 'Süper Kahraman', '50 siparişi tamamladın', 50),
    _Badge('👑', 'Efsane', '100 siparişi tamamladın', 100),
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    String? email = Supabase.instance.client.auth.currentSession?.user.email;
    if (email == null || email.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      email = prefs.getString('user_email') ?? '';
    }
    if (email.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final headers = await authHeaders();
      final res = await http.get(
        Uri.parse(
            '$apiBaseUrl/api/v1/users/profile?email=${Uri.encodeComponent(email)}'),
        headers: headers,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _completedOrders = data['completed_orders'] ?? 0;
          _savedFoodKg = (data['saved_food_kg'] ?? 0.0).toDouble();
          _co2AvoidedKg = (data['co2_avoided_kg'] ?? 0.0).toDouble();
          _moneySaved = (data['money_saved'] ?? 0.0).toDouble();
        });
        _animController.forward(from: 0);
      }
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  _Badge? get _nextBadge {
    for (final b in _allBadges) {
      if (_completedOrders < b.threshold) return b;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF0FDF4);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_rounded,
              color: isDark ? Colors.white : const Color(0xFF14532D)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Katkım',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: isDark ? Colors.white : const Color(0xFF14532D),
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF16A34A)))
          : RefreshIndicator(
              color: const Color(0xFF16A34A),
              onRefresh: _load,
              child: FadeTransition(
                opacity: _fadeAnim,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    _buildHeroHeader(isDark),
                    const SizedBox(height: 20),
                    _buildStatCards(isDark),
                    const SizedBox(height: 24),
                    _buildNextMilestone(isDark),
                    const SizedBox(height: 24),
                    _buildBadgeGrid(isDark),
                    const SizedBox(height: 16),
                    _buildFootnote(isDark),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeroHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF16A34A), Color(0xFF15803D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF16A34A).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text('🌍', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text(
            'Gezegenimize Katkın',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$_completedOrders tamamlanan sipariş ile fark yaratıyorsun!',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCards(bool isDark) {
    final cards = [
      _StatData('🥗', '${_savedFoodKg.toStringAsFixed(1)} kg',
          'Kurtarılan Gıda', const Color(0xFF16A34A)),
      _StatData('☁️', '${_co2AvoidedKg.toStringAsFixed(1)} kg',
          'Önlenen CO₂', const Color(0xFF0284C7)),
      _StatData('💰', '₺${_moneySaved.toStringAsFixed(0)}',
          'Tasarruf Ettin', const Color(0xFFF97316)),
    ];

    return Column(
      children: [
        Row(
          children: [
            _statCard(cards[0], isDark),
            const SizedBox(width: 12),
            _statCard(cards[1], isDark),
          ],
        ),
        const SizedBox(height: 12),
        _statCardWide(cards[2], isDark),
      ],
    );
  }

  Widget _statCard(_StatData d, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(d.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 10),
            Text(
              d.value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: d.color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              d.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCardWide(_StatData d, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ],
      ),
      child: Row(
        children: [
          Text(d.emoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
              Text(
                d.value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: d.color,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: d.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'indirimli sipariş',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: d.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNextMilestone(bool isDark) {
    final next = _nextBadge;
    if (next == null) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Row(
          children: [
            Text('👑', style: TextStyle(fontSize: 32)),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Efsane Seviyeye Ulaştın!',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                  Text('Tüm rozetleri kazandın. Harikasın! 🎉',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final progress =
        (_completedOrders / next.threshold).clamp(0.0, 1.0);
    final remaining = next.threshold - _completedOrders;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                )
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(next.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sonraki Rozet: ${next.name}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? Colors.white
                            : const Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      '$remaining sipariş kaldı',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$_completedOrders/${next.threshold}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF16A34A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor:
                  isDark ? const Color(0xFF334155) : const Color(0xFFDCFCE7),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF16A34A)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeGrid(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rozetler',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.85,
          ),
          itemCount: _allBadges.length,
          itemBuilder: (_, i) => _buildBadgeTile(_allBadges[i], isDark),
        ),
      ],
    );
  }

  Widget _buildBadgeTile(_Badge badge, bool isDark) {
    final unlocked = _completedOrders >= badge.threshold;
    return Container(
      decoration: BoxDecoration(
        color: unlocked
            ? (isDark ? const Color(0xFF14532D) : const Color(0xFFDCFCE7))
            : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
        borderRadius: BorderRadius.circular(16),
        border: unlocked
            ? Border.all(color: const Color(0xFF16A34A), width: 1.5)
            : null,
        boxShadow: unlocked && !isDark
            ? [
                BoxShadow(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                )
              ]
            : [],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Text(
                badge.emoji,
                style: TextStyle(
                  fontSize: 36,
                  color: unlocked ? null : Colors.transparent,
                ),
              ),
              if (!unlocked)
                Text(
                  badge.emoji,
                  style: TextStyle(
                    fontSize: 36,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.1),
                  ),
                ),
              if (!unlocked)
                const Icon(Icons.lock_rounded,
                    size: 18, color: Color(0xFF94A3B8)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            badge.name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: unlocked
                  ? (isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D))
                  : const Color(0xFF94A3B8),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            '${badge.threshold} sipariş',
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFootnote(bool isDark) {
    return Text(
      '* Kurtarılan gıda: sipariş başına 0,5 kg ortalama. CO₂: 1 kg gıda = 2,5 kg CO₂ eşdeğeri.',
      style: TextStyle(
        fontSize: 10,
        color: isDark
            ? const Color(0xFF475569)
            : const Color(0xFF94A3B8),
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _Badge {
  final String emoji;
  final String name;
  final String description;
  final int threshold;
  const _Badge(this.emoji, this.name, this.description, this.threshold);
}

class _StatData {
  final String emoji;
  final String value;
  final String label;
  final Color color;
  const _StatData(this.emoji, this.value, this.label, this.color);
}
