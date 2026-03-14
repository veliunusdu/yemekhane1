import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // kIsWeb için eklendi
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart'; // Web'de URL açmak için

class PaymentPage extends StatefulWidget {
  final String paymentUrl;

  const PaymentPage({super.key, required this.paymentUrl});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  WebViewController? _controller;
  bool _isLoading = true;

  // Extracts the Iyzico payment token from the callback redirect URL
  String _extractToken(String url) {
    try {
      return Uri.parse(url).queryParameters['token'] ?? '';
    } catch (_) {
      return '';
    }
  }

  bool _popped = false;
  void _popWithToken(String url) {
    if (_popped) return;
    _popped = true;
    final token = _extractToken(url);
    if (mounted) Navigator.pop(context, token);
  }

  @override
  void initState() {
    super.initState();

    // Web platformunda WebView başlatılmaz, çökmesini engelleriz
    if (!kIsWeb) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        // Standard mobile Chrome user-agent — improves Iyzico form compatibility
        ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 13; Pixel 6) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/120.0.0.0 Mobile Safari/537.36',
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (NavigationRequest request) {
              String url = request.url;
              if (url.contains('iyzico-callback') ||
                  url.contains('yemekhane_callback')) {
                _popWithToken(url);
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
            onPageStarted: (String url) {
              if (url.contains('iyzico-callback') ||
                  url.contains('yemekhane_callback')) {
                _popWithToken(url);
                return;
              }
              setState(() => _isLoading = true);
            },
            onPageFinished: (_) => setState(() => _isLoading = false),
            onWebResourceError: (WebResourceError error) {
              if (error.url?.contains('iyzico-callback') == true ||
                  error.url?.contains('yemekhane_callback') == true) {
                _popWithToken(error.url ?? '');
                return;
              }
              setState(() => _isLoading = false);
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.paymentUrl));
    }
  }

  @override
  Widget build(BuildContext context) {
    // WEB için alternatif UI (Yeni Sekmede açma ekranı)
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Güvenli Ödeme"),
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.payment, size: 80, color: Colors.orange),
              const SizedBox(height: 24),
              const Text(
                'Web tarayıcıda Güvenli Ödeme sayfasına\nyönlendirileceksiniz.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Ödeme Sayfasını Aç',
                    style: TextStyle(fontSize: 16)),
                onPressed: () async {
                  final uri = Uri.parse(widget.paymentUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, ''),
                child: const Text('Ödemeyi Tamamladım, Geri Dön'),
              ),
            ],
          ),
        ),
      );
    }

    // ANDROID/IOS İçin Orijinal WebView
    return Scaffold(
      appBar: AppBar(
        title: const Text("Güvenli Ödeme"),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          if (_controller != null) WebViewWidget(controller: _controller!),
          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
