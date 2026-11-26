import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_notifier.dart';

/// Layar login: form NIK + password dengan validasi 16 digit dan loading state.
/// Rute: /login (standalone, tanpa bottom navigation)
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nipController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _nipError;

  @override
  void dispose() {
    _nipController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    setState(() => _nipError = null);
    if (!_formKey.currentState!.validate()) return;

    final nip = _nipController.text.trim();
    if (!RegExp(r'^\d{16}$').hasMatch(nip)) {
      setState(() => _nipError = 'NIK harus terdiri dari 16 digit angka');
      return;
    }

    await ref.read(authProvider.notifier).login(nip, _passwordController.text);

    if (!mounted) return;

    // Tampilkan error sebagai snackbar atau inline error
    final authState = ref.read(authProvider);
    if (authState.errorMessage != null) {
      final msg = authState.errorMessage!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red.shade700,
        ),
      );
      setState(() => _nipError = msg);
    }
    // Jika sukses, ProfileScreen akan otomatis rebuild karena authProvider berubah
  }

  @override
  Widget build(BuildContext context) {
    // Hanya watch isLoading agar tidak rebuild saat status auth berubah
    final isLoading = ref.watch(authProvider.select((s) => s.isLoading));

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo / Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.fingerprint,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Presensi',
                  style: TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Masuk untuk melanjutkan',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 40),

                // Form
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // NIK field
                      _buildLabel('NIK'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _nipController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(16),
                        ],
                        style: const TextStyle(color: Color(0xFF1F2937)),
                        decoration: _inputDecoration(
                          hint: 'Masukkan 16 digit NIK Anda',
                          icon: Icons.badge_outlined,
                          errorText: _nipError,
                        ),
                        validator: (v) {
                          final trimmed = v?.trim() ?? '';
                          if (trimmed.isEmpty) {
                            return 'NIK tidak boleh kosong';
                          }
                          if (!RegExp(r'^\d{16}$').hasMatch(trimmed)) {
                            return 'NIK harus terdiri dari 16 digit angka';
                          }
                          return null;
                        },
                        onChanged: (_) {
                          setState(() {
                            if (_nipError != null) _nipError = null;
                          });
                        },
                      ),
                      if (_nipController.text.isNotEmpty &&
                          _nipController.text.length < 16 &&
                          _nipError == null) ...[
                        const SizedBox(height: 6),
                        Text(
                          '*NIK tidak valid (wajib 16 digit angka, ${_nipController.text.length}/16)',
                          style: const TextStyle(
                            color: Color(0xFFD97706),
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (_nipError != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _nipError!,
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),

                      // Password field
                      _buildLabel('Password'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: const TextStyle(color: Color(0xFF1F2937)),
                        decoration: _inputDecoration(
                          hint: 'Masukkan password',
                          icon: Icons.lock_outlined,
                        ).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Color(0xFF9CA3AF),
                            ),
                            onPressed: () {
                              setState(
                                  () => _obscurePassword = !_obscurePassword);
                            },
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Password tidak boleh kosong';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 32),

                      // Submit button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : _handleLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF22C55E),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Masuk',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
        ),
      ),
    )));
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF374151),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    String? errorText,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Color(0xFF9CA3AF)),
      prefixIcon: Icon(icon, color: Color(0xFF9CA3AF), size: 20),
      filled: true,
      fillColor: const Color(0xFFF0FDF4),
      errorText: errorText,
      errorStyle: const TextStyle(color: Color(0xFFEF4444)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFBBF7D0), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF22C55E), width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    );
  }
}
