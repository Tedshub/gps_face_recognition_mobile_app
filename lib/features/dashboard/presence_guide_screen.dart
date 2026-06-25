import 'package:flutter/material.dart';

class PresenceGuideScreen extends StatelessWidget {
  const PresenceGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text(
          'Panduan Presensi',
          style: TextStyle(
            color: Color(0xFF1F2937),
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF1F2937)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildImageSection(
              title: 'Persiapan',
              imagePath: 'assets/guide/persiapan.png',
            ),
            const SizedBox(height: 24),
            _buildImageSection(
              title: 'Presensi saat Online',
              imagePath: 'assets/guide/presensi online.png',
            ),
            const SizedBox(height: 24),
            _buildImageSection(
              title: 'Presensi saat Offline',
              imagePath: 'assets/guide/presensi offline.png',
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSection({required String title, required String imagePath}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            imagePath,
            width: double.infinity,
            fit: BoxFit.contain,
          ),
        ),
      ],
    );
  }
}
