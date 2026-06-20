import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/auth_notifier.dart';
import '../../features/auth/login_screen.dart';

import 'profile_notifier.dart';

/// ProfileScreen — Tab 2
/// Menampilkan: info karyawan, foto wajah terdaftar, logout.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(profileProvider.notifier).loadProfile(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ref.listen dipanggil di sini agar stabil dan tidak menyebabkan rebuild loop
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Logout', style: TextStyle(color: Color(0xFF1F2937))),
        content: const Text(
          'Apakah Anda yakin ingin keluar?',
          style: TextStyle(color: Color(0xFF6B7280)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Keluar',
              style: TextStyle(color: Color(0xFFEF4444)),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(authProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    final auth = ref.watch(authProvider);
    final user = profile.userData;

    // Pantau perubahan auth untuk me-reload data profil jika login berhasil
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.status == AuthStatus.authenticated &&
          previous?.status != AuthStatus.authenticated) {
        ref.read(profileProvider.notifier).loadProfile();
      } else if (next.status == AuthStatus.unauthenticated &&
          previous?.status == AuthStatus.authenticated) {
        ref.invalidate(profileProvider);
      }
    });

    final isAuth = auth.status == AuthStatus.authenticated;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          isAuth ? 'Profil' : 'Masuk',
          style: const TextStyle(color: Color(0xFF1F2937), fontWeight: FontWeight.bold),
        ),
        actions: [],
        elevation: 0,
      ),
      body: !isAuth
          ? const LoginScreen()
          : (profile.isLoading || user == null)
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF22C55E)),
                )
              : _buildProfileContent(user, profile),
    );
  }

  Widget _buildProfileContent(Map<String, dynamic> user, ProfileState profile) {
    return RefreshIndicator(
      onRefresh: () => ref.read(profileProvider.notifier).refresh(),
      color: const Color(0xFF22C55E),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User info card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Column(
              children: [
                // Avatar
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: Color(0xFF22C55E),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      (user['name'] as String? ?? 'K')
                          .substring(0, 1)
                          .toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  user['name'] as String? ?? '-',
                  style: const TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'NIP: ${user['nip'] ?? '-'}',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFFE5E7EB)),
                const SizedBox(height: 8),

                // Details
                _buildInfoRow(
                    Icons.work_outlined, user['jabatan'] as String? ?? '-'),
                _buildInfoRow(
                    Icons.email_outlined, user['email'] as String? ?? '-'),
                if (user['office'] != null)
                  _buildInfoRow(
                    Icons.business_outlined,
                    (user['office'] as Map)['office_name'] as String? ?? '-',
                  ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Foto wajah terdaftar
          const Text(
            'Foto Wajah Terdaftar',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),

          if (profile.facePhotosPaths.isEmpty)
            Text(
              'Belum ada foto wajah terdaftar, silahkan menghubungi admin desa untuk menambahkan foto wajah.',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 13,
              ),
            )
          else ...[
            Text(
              '${profile.facePhotosPaths.length} foto wajah terdaftar',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: profile.facePhotosPaths.length,
                itemBuilder: (context, index) {
                  final path = profile.facePhotosPaths[index];
                  return Container(
                    width: 90,
                    height: 90,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: const Color(0xFF22C55E), width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.file(
                        File(path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 20),
          const Divider(color: Color(0xFFE5E7EB)),

          // Logout
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout, color: Color(0xFFEF4444)),
            title: const Text(
              'Logout',
              style: TextStyle(color: Color(0xFFEF4444)),
            ),
            onTap: _handleLogout,
          ),
        ],
      ),
    ));
  }

  Widget _buildInfoRow(IconData icon, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Color(0xFF9CA3AF)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
