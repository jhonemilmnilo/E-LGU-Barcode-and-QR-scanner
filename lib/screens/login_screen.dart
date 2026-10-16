import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  String? _errorMessage;

  Color? _themeColor;
  String? _siteLogo;
  String? _municipalityName;

  @override
  void initState() {
    super.initState();
    _loadBrandingAndSavedCredentials();
  }

  Color? _hexToColor(String? hexString) {
    if (hexString == null || hexString.isEmpty) return null;
    final buffer = StringBuffer();
    if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
    buffer.write(hexString.replaceFirst('#', ''));
    try {
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadBrandingAndSavedCredentials() async {
    // 1. Load locally cached branding if available
    final cachedTheme = await ApiService.getCachedThemeColor();
    final cachedLogo = await ApiService.getCachedLogo();
    final cachedMuni = await ApiService.getCachedMunicipalityName();
    final creds = await ApiService.getSavedCredentials();

    if (mounted) {
      setState(() {
        if (cachedTheme != null) _themeColor = _hexToColor(cachedTheme);
        _siteLogo = cachedLogo;
        _municipalityName = cachedMuni;
        _rememberMe = creds['remember'] ?? false;
        if (_rememberMe && (creds['email'] as String).isNotEmpty) {
          _emailController.text = (creds['email'] as String).trim();
        }
      });
    }

    // 2. Fetch fresh dynamic settings from database
    final freshSettings = await ApiService.fetchPublicSettings();
    if (mounted) {
      setState(() {
        if (freshSettings['themeColor'] != null) {
          _themeColor = _hexToColor(freshSettings['themeColor']);
        }
        if (freshSettings['siteLogo'] != null && (freshSettings['siteLogo'] as String).isNotEmpty) {
          _siteLogo = freshSettings['siteLogo'];
        }
        if (freshSettings['municipalityName'] != null) {
          _municipalityName = freshSettings['municipalityName'];
        }
      });
    }
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please enter both email and password');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await ApiService.login(email, password);

    if (!mounted) return;

    if (result['success'] == true) {
      await ApiService.setRememberMe(remember: _rememberMe, email: email);

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = result['error'] ?? 'Authentication failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use dynamic themeColor, or primary theme from Context
    final activeThemeColor = _themeColor ?? Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Municipal Seal Logo / Dynamic Barcode Icon
                Container(
                  width: 96,
                  height: 96,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: activeThemeColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: activeThemeColor.withValues(alpha: 0.25), width: 2),
                  ),
                  child: ClipOval(
                    child: _siteLogo != null && _siteLogo!.isNotEmpty
                        ? Image.network(
                            _siteLogo!.startsWith('http')
                                ? _siteLogo!
                                : '${ApiService.defaultBaseUrl}$_siteLogo',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              Icons.qr_code_scanner_rounded,
                              size: 52,
                              color: activeThemeColor,
                            ),
                          )
                        : Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 52,
                            color: activeThemeColor,
                          ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _municipalityName ?? 'Municipal Front Desk',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Kiosk Check-In Terminal',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 32),
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Color(0xFFDC2626), fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Frontdesk Email',
                    hintText: 'frontdesk@mapandan.gov.ph',
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: Icon(Icons.email_outlined, color: activeThemeColor),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: activeThemeColor, width: 2),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: Icon(Icons.lock_outline_rounded, color: activeThemeColor),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: activeThemeColor, width: 2),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: Colors.grey,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Remember Me Row
                Row(
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: _rememberMe,
                        activeColor: activeThemeColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                        onChanged: (val) {
                          setState(() => _rememberMe = val ?? false);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _rememberMe = !_rememberMe),
                      child: const Text(
                        'Remember me',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Sign In Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: activeThemeColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Text(
                            'Sign In to Terminal',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
