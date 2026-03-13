import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey      = GlobalKey<FormState>();

  bool _isLoading     = false;
  bool _obscurePass   = true;
  bool _isSignupMode  = false;

  // ── Auth logic ────────────────────────────────────────
  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    try {
      if (_isSignupMode) {
        await Supabase.instance.client.auth.signUp(
          email: email,
          password: password,
        );
        if (!mounted) return;
        _showSnack(
          'Kayıt başarılı! Giriş yapabilirsiniz.',
          color: const Color(0xFF10B981),
        );
        setState(() => _isSignupMode = false);
      } else {
        final response = await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_email', response.user?.email ?? email);

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
        );
      }
    } on AuthException catch (e) {
      String msg = _isSignupMode ? 'Kayıt olunamadı.' : 'Giriş başarısız.';
      if (e.message.contains('Email not confirmed')) {
        msg = 'E-posta adresinizi onaylayın.';
      } else if (e.message.contains('Invalid login credentials')) {
        msg = 'E-posta veya şifre hatalı.';
      } else {
        msg = e.message;
      }
      if (mounted) _showSnack(msg);
    } catch (e) {
      if (mounted) _showSnack('Bağlantı hatası: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, {Color color = const Color(0xFFEF4444)}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w500)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 56),

                // ── Brand ──
                Center(
                  child: Column(
                    children: [
                      // Logo
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFF97316).withOpacity(0.2),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text('🍱', style: TextStyle(fontSize: 40)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Yemekhane',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Günün fırsatlarını kaçırma',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 48),

                // ── Heading ──
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Column(
                    key: ValueKey(_isSignupMode),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isSignupMode ? 'Hesap Oluştur' : 'Hoş Geldin',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isSignupMode
                            ? 'Yeni bir hesap oluşturmak için bilgilerini gir'
                            : 'Devam etmek için giriş yap',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── Email field ──
                _FieldLabel('E-posta'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  style: const TextStyle(fontSize: 15, color: Color(0xFF0F172A)),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'E-posta gerekli';
                    if (!v.contains('@')) return 'Geçerli bir e-posta girin';
                    return null;
                  },
                  decoration: _inputDecoration(
                    hint: 'ornek@email.com',
                    icon: Icons.mail_outline_rounded,
                  ),
                ),

                const SizedBox(height: 16),

                // ── Password field ──
                _FieldLabel('Şifre'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePass,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  style: const TextStyle(fontSize: 15, color: Color(0xFF0F172A)),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Şifre gerekli';
                    if (v.length < 6) return 'En az 6 karakter';
                    return null;
                  },
                  decoration: _inputDecoration(
                    hint: '••••••••',
                    icon: Icons.lock_outline_rounded,
                    suffix: IconButton(
                      icon: Icon(
                        _obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 20,
                        color: const Color(0xFF94A3B8),
                      ),
                      onPressed: () => setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Primary button ──
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF97316),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFFFEDD5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                        : Text(
                            _isSignupMode ? 'Kayıt Ol' : 'Giriş Yap',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Toggle mode ──
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isSignupMode ? 'Hesabın var mı? ' : 'Hesabın yok mu? ',
                        style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                      ),
                      GestureDetector(
                        onTap: _isLoading ? null : () {
                          setState(() {
                            _isSignupMode = !_isSignupMode;
                            _formKey.currentState?.reset();
                          });
                        },
                        child: Text(
                          _isSignupMode ? 'Giriş Yap' : 'Kayıt Ol',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFF97316),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
      prefixIcon: Padding(
        padding: const EdgeInsets.only(left: 14, right: 10),
        child: Icon(icon, size: 20, color: const Color(0xFF94A3B8)),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
        borderSide: const BorderSide(color: Color(0xFFF97316), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEF4444)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
      ),
      errorStyle: const TextStyle(fontSize: 12),
    );
  }
}

// ── Field label widget ────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF475569),
      ),
    );
  }
}
