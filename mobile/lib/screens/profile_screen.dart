import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../api_config.dart';
import '../login_screen.dart';
import '../main.dart';
import 'impact_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  String? _email;
  String _fullName = '';
  String _phone = '';
  int _loyaltyPoints = 0;
  int _totalOrders = 0;
  int _completedOrders = 0;
  double _savedFoodKg = 0.0;
  double _co2AvoidedKg = 0.0;
  double _moneySaved = 0.0;

  // Edit mode
  bool _isEditing = false;
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    _email = Supabase.instance.client.auth.currentSession?.user.email;
    if (_email == null || _email!.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      _email = prefs.getString('user_email') ?? '';
    }
    if (_email == null || _email!.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final headers = await authHeaders();
      final res = await http.get(
        Uri.parse(
            '$apiBaseUrl/api/v1/users/profile?email=${Uri.encodeComponent(_email!)}'),
        headers: headers,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _fullName = data['full_name'] ?? '';
          _phone = data['phone_number'] ?? '';
          _loyaltyPoints = data['loyalty_points'] ?? 0;
          _totalOrders = data['total_orders'] ?? 0;
          _completedOrders = data['completed_orders'] ?? 0;
          _savedFoodKg = (data['saved_food_kg'] ?? 0.0).toDouble();
          _co2AvoidedKg = (data['co2_avoided_kg'] ?? 0.0).toDouble();
          _moneySaved = (data['money_saved'] ?? 0.0).toDouble();
        });
      }
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      final headers = await authHeaders();
      final res = await http.patch(
        Uri.parse('$apiBaseUrl/api/v1/users/profile'),
        headers: headers,
        body: jsonEncode({
          'email': _email,
          'full_name': _nameCtrl.text.trim(),
          'phone_number': _phoneCtrl.text.trim(),
        }),
      );
      if (res.statusCode == 200) {
        setState(() {
          _fullName = _nameCtrl.text.trim();
          _phone = _phoneCtrl.text.trim();
          _isEditing = false;
        });
        if (mounted) _showSnack('Profil güncellendi ✓', Colors.green);
      } else {
        if (mounted) _showSnack('Güncelleme başarısız', Colors.red);
      }
    } catch (_) {
      if (mounted) _showSnack('Bağlantı hatası', Colors.red);
    }
    setState(() => _isSaving = false);
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(msg),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text('Hesabından çıkmak istiyor musun?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Çıkış Yap', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text('Profilim',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: isDark ? Colors.white : const Color(0xFF1E293B))),
        centerTitle: true,
        actions: [
          if (!_isEditing)
            IconButton(
              icon: Icon(
                  isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                  color: const Color(0xFFF97316)),
              onPressed: () {
                final provider = ThemeProvider.of(context);
                provider.setThemeMode(
                    isDark ? ThemeMode.light : ThemeMode.dark);
              },
            ),
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit_rounded, color: Color(0xFFF97316)),
              onPressed: () {
                _nameCtrl.text = _fullName;
                _phoneCtrl.text = _phone;
                setState(() => _isEditing = true);
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFF97316)))
          : RefreshIndicator(
              color: const Color(0xFFF97316),
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _buildAvatar(isDark),
                  const SizedBox(height: 24),
                  _buildThemeSelector(context, isDark),
                  const SizedBox(height: 16),
                  _isEditing ? _buildEditForm(isDark) : _buildInfoCard(isDark),
                  const SizedBox(height: 20),
                  _buildStatsRow(isDark),
                  const SizedBox(height: 20),
                  _buildImpactCard(isDark),
                  const SizedBox(height: 20),
                  _buildLoyaltyCard(isDark),
                  const SizedBox(height: 32),
                  _buildSignOutButton(),
                ],
              ),
            ),
    );
  }

  Widget _buildThemeSelector(BuildContext context, bool isDark) {
    final provider = ThemeProvider.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Karanlık Mod',
              style: TextStyle(fontWeight: FontWeight.w600)),
          Switch(
            value: isDark,
            activeColor: const Color(0xFFF97316),
            onChanged: (val) {
              provider.setThemeMode(val ? ThemeMode.dark : ThemeMode.light);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(bool isDark) {
    final initials = _fullName.isNotEmpty
        ? _fullName
            .trim()
            .split(' ')
            .map((w) => w.isNotEmpty ? w[0] : '')
            .take(2)
            .join()
            .toUpperCase()
        : (_email?.isNotEmpty == true ? _email![0].toUpperCase() : '?');
    return Center(
      child: Stack(
        children: [
          CircleAvatar(
            radius: 44,
            backgroundColor:
                isDark ? const Color(0xFF334155) : const Color(0xFFFFF7ED),
            child: Text(initials,
                style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFF97316))),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                  color: Color(0xFFF97316), shape: BoxShape.circle),
              child: const Icon(Icons.fastfood_rounded,
                  size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2))
              ],
      ),
      child: Column(
        children: [
          _infoRow(Icons.person_rounded, 'Ad Soyad', _fullName),
          const Divider(height: 24),
          _infoRow(Icons.email_rounded, 'E-posta', _email ?? ''),
          const Divider(height: 24),
          _infoRow(Icons.phone_rounded, 'Telefon', _phone),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_isLoading) {
      return Row(
        children: [
          Icon(icon, size: 24, color: isDark ? Colors.white24 : Colors.grey.shade300),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 60, height: 12, color: isDark ? Colors.white10 : Colors.grey.shade200),
              const SizedBox(height: 6),
              Container(width: 120, height: 16, color: isDark ? Colors.white10 : Colors.grey.shade200),
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        Icon(icon, size: 24, color: const Color(0xFFF97316)),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500)),
            Text(value.isEmpty ? 'Belirtilmedi' : value,
                style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }

  Widget _buildEditForm(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2))
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Profili Düzenle',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: isDark ? Colors.white : const Color(0xFF1E293B))),
          const SizedBox(height: 16),
          TextField(
            controller: _nameCtrl,
            decoration: _inputDeco('Ad Soyad', Icons.person_rounded, isDark),
            textCapitalization: TextCapitalization.words,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            decoration: _inputDeco('Telefon', Icons.phone_rounded, isDark),
            keyboardType: TextInputType.phone,
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving
                      ? null
                      : () => setState(() => _isEditing = false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: isDark ? const BorderSide(color: Colors.white24) : null,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Vazgeç',
                      style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF97316),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Kaydet',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDeco(String hint, IconData icon, bool isDark) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
      prefixIcon: Icon(icon, color: const Color(0xFFF97316), size: 20),
      filled: true,
      fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _buildStatsRow(bool isDark) {
    final items = [
      {
        'icon': Icons.receipt_long_rounded,
        'value': '$_totalOrders',
        'label': 'Toplam Sipariş'
      },
      {
        'icon': Icons.check_circle_rounded,
        'value': '$_completedOrders',
        'label': 'Tamamlanan'
      },
      {
        'icon': Icons.eco_rounded,
        'value': '${_savedFoodKg.toStringAsFixed(1)}kg',
        'label': 'Kurtarılan'
      },
    ];
    return Row(
      children: items.map((item) {
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(
              left: items.indexOf(item) == 0 ? 0 : 6,
              right: items.indexOf(item) == items.length - 1 ? 0 : 6,
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: isDark
                  ? []
                  : [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ],
            ),
            child: Column(
              children: [
                Icon(item['icon'] as IconData,
                    color: const Color(0xFFF97316), size: 22),
                const SizedBox(height: 6),
                Text(item['value'] as String,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: isDark ? Colors.white : const Color(0xFF1E293B))),
                Text(item['label'] as String,
                    style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildImpactCard(bool isDark) {
    return GestureDetector(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const ImpactScreen())),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF16A34A), Color(0xFF15803D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF16A34A).withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Text('🌍', style: TextStyle(fontSize: 36)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Katkım',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(
                    '${_savedFoodKg.toStringAsFixed(1)} kg gıda • ₺${_moneySaved.toStringAsFixed(0)} tasarruf',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white70, size: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildLoyaltyCard(bool isDark) {
    final level = _loyaltyPoints >= 200
        ? 'Altın'
        : _loyaltyPoints >= 100
            ? 'Gümüş'
            : 'Bronz';
    final levelColor = _loyaltyPoints >= 200
        ? const Color(0xFFD97706)
        : _loyaltyPoints >= 100
            ? const Color(0xFF64748B)
            : const Color(0xFFB45309);
    final nextThreshold = _loyaltyPoints >= 200
        ? 200
        : _loyaltyPoints >= 100
            ? 200
            : 100;
    final progress = (_loyaltyPoints / nextThreshold).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFFFFF7ED), const Color(0xFFFEF3C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sadakat Puanları',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF92400E),
                          fontWeight: FontWeight.w500)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$_loyaltyPoints',
                          style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFF97316))),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6, left: 4),
                        child: Text('puan',
                            style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF92400E),
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                    color: levelColor, borderRadius: BorderRadius.circular(20)),
                child: Text(level,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: const Color(0xFFFDE68A),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFFF97316)),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _loyaltyPoints >= nextThreshold
                ? 'Maksimum seviyeye ulaştın! 🎉'
                : '${nextThreshold - _loyaltyPoints} puan daha → $level${_loyaltyPoints >= 100 ? "" : " → Gümüş"} seviyesi',
            style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF92400E),
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          const Text(
            'Her teslim edilen siparişte +10 puan kazanırsın.',
            style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }

  Widget _buildSignOutButton() {
    return OutlinedButton.icon(
      onPressed: _signOut,
      icon: const Icon(Icons.logout_rounded, color: Colors.red),
      label: const Text('Çıkış Yap',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: Colors.red),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
