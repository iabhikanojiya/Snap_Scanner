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
      
      // Optimize images concurrently to save time
      final optimizedFiles = await Future.wait(
        images.map((img) => ImageUtils.optimizeImage(File(img.path)))
      );

      // Add pages in order
      for (int i = 0; i < images.length; i++) {
        provider.addPage(ScannedPage(
          id: const Uuid().v4(),
          originalPath: images[i].path,
          processedFile: optimizedFiles[i],
        ));
      }
      if (mounted) {
        Navigator.pop(context); // Hide loading
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 120), // Padding for bottom nav bar
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
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
          
          // Action Cards Grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: HomeActionCard(
                        title: 'Scan PDF',
                        icon: Icons.document_scanner,
                        color: Colors.blueAccent,
                        onTap: () => _openScanner(context),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: HomeActionCard(
                        title: 'Image to PDF',
                        icon: Icons.image_rounded,
                        color: Colors.green,
                        onTap: () => _pickImages(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: HomeActionCard(
                        title: 'Merge PDF',
                        icon: Icons.merge_type,
                        color: Colors.deepPurpleAccent,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const PdfMergeScreen()),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: HomeActionCard(
                        title: 'Split PDF',
                        icon: Icons.call_split,
                        color: Colors.teal,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const PdfSplitScreen()),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: HomeActionCard(
                        title: 'Compress PDF',
                        icon: Icons.compress,
                        color: Colors.orange,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const PdfCompressScreen()),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: HomeActionCard(
                        title: 'Lock PDF',
                        icon: Icons.lock,
                        color: Colors.blueGrey,
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Coming soon!')),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: HomeActionCard(
                        title: 'Signature',
                        icon: Icons.draw,
                        color: Colors.indigo,
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Coming soon!')),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: HomeActionCard(
                        title: 'Resize Image',
                        icon: Icons.photo_size_select_large,
                        color: Colors.pink,
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Coming soon!')),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
