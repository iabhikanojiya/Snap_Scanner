import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/image_utils.dart';
import '../../../core/models/scanned_page.dart';
import '../../../providers/scan_provider.dart';
import '../widgets/home_action_card.dart';

import 'package:snap_scanner/features/editor/screens/batch_crop_screen.dart';
import 'package:snap_scanner/features/scanner/screens/scanner_screen.dart';
import 'package:snap_scanner/features/merge/screens/pdf_merge_screen.dart';
import 'package:snap_scanner/features/split/screens/pdf_split_screen.dart';
import 'package:snap_scanner/features/compress/screens/pdf_compress_screen.dart';
import 'package:snap_scanner/features/lock/screens/pdf_lock_screen.dart';
import 'package:snap_scanner/features/signature/screens/signature_screen.dart';
import 'package:snap_scanner/features/resize_image/screens/resize_image_screen.dart';

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  void _openScanner(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ScannerScreen()),
    );
  }

  Future<void> _pickImages(BuildContext context) async {
    final ImagePicker picker = ImagePicker();
    final provider = Provider.of<ScanProvider>(context, listen: false);
    provider.clearPages();
    provider.setToolType('image_to_pdf');

    final List<XFile> images = await picker.pickMultiImage();
    if (images.isNotEmpty) {
      if (mounted) _showLoading();

      final optimizedFiles = await Future.wait(
        images.map((img) => ImageUtils.optimizeImage(File(img.path))),
      );

      for (int i = 0; i < images.length; i++) {
        provider.addPage(ScannedPage(
          id: const Uuid().v4(),
          originalPath: images[i].path,
          processedFile: optimizedFiles[i],
        ));
      }
      if (mounted) {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const BatchCropScreen()),
        );
      }
    }
  }

  void _showLoading() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 14),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.blueAccent.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolsRow(List<Widget> cards) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: cards.map((c) => Expanded(child: Padding(
          padding: cards.indexOf(c) == 0
              ? const EdgeInsets.only(right: 8)
              : const EdgeInsets.only(left: 8),
          child: c,
        ))).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F9FA),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [


            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tools',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.titleLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'All your PDF utilities in one place',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),

            // Scan PDF Banner
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEF4444).withOpacity(0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: () => _openScanner(context),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(Icons.document_scanner, color: Colors.white, size: 36),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Scan PDF',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Scan documents using your camera',
                                  style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.85)),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // --- CREATE ---
            _sectionHeader('CREATE'),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _pickImages(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.image_rounded, color: Colors.green, size: 30),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Image to PDF',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Convert images to PDF documents',
                                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right, color: Colors.grey.shade400),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // --- DOCUMENT TOOLS ---
            _sectionHeader('DOCUMENT TOOLS'),

            _toolsRow([
              HomeActionCard(
                title: 'Merge PDF',
                icon: Icons.merge_type,
                color: Colors.deepPurpleAccent,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PdfMergeScreen()));
                },
              ),
              HomeActionCard(
                title: 'Split PDF',
                icon: Icons.call_split,
                color: Colors.teal,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PdfSplitScreen()));
                },
              ),
            ]),
            const SizedBox(height: 12),
            _toolsRow([
              HomeActionCard(
                title: 'Compress PDF',
                icon: Icons.compress,
                color: Colors.orange,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PdfCompressScreen()));
                },
              ),
              HomeActionCard(
                title: 'Lock PDF',
                icon: Icons.lock,
                color: Colors.blueGrey,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const PdfLockScreen()));
                },
              ),
            ]),

            // --- ANNOTATE ---
            _sectionHeader('ANNOTATE'),

            _toolsRow([
              HomeActionCard(
                title: 'Signature',
                icon: Icons.draw,
                color: Colors.indigo,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SignatureScreen()));
                },
              ),
              HomeActionCard(
                title: 'Resize Image',
                icon: Icons.photo_size_select_large,
                color: Colors.pink,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ResizeImageScreen()));
                },
              ),
            ]),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
