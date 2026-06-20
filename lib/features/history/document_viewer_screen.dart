import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class DocumentViewerScreen extends StatelessWidget {
  final String localPath;

  const DocumentViewerScreen({super.key, required this.localPath});

  @override
  Widget build(BuildContext context) {
    final isPdf = localPath.toLowerCase().endsWith('.pdf');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dokumen Izin'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F2937),
        elevation: 1,
      ),
      body: Center(
        child: isPdf
            ? SfPdfViewer.file(File(localPath))
            : InteractiveViewer(
                child: Image.file(
                  File(localPath),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Text('Gagal memuat gambar dokumen');
                  },
                ),
              ),
      ),
    );
  }
}
