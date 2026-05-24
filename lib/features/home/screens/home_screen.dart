import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:snap_scanner/core/utils/image_utils.dart';
import 'package:snap_scanner/core/models/scanned_page.dart';
import 'package:snap_scanner/core/models/pdf_file_model.dart';
import 'package:snap_scanner/core/services/database_service.dart';
import 'package:snap_scanner/core/services/storage_service.dart';
import 'package:snap_scanner/providers/scan_provider.dart';
import '../widgets/home_action_card.dart';
import 'package:snap_scanner/features/editor/screens/batch_crop_screen.dart';
import 'package:snap_scanner/features/scanner/screens/scanner_screen.dart';
import 'package:snap_scanner/features/settings/screens/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<PdfFileModel> _recentFiles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecentFiles();
  }

  Future<void> _loadRecentFiles() async {
    setState(() => _isLoading = true);
    final files = await DatabaseService.getAllFiles();
    setState(() {
      _recentFiles = files;
      _isLoading = false;
    });
  }

  Future<void> _pickImages(BuildContext context) async {
    final ImagePicker picker = ImagePicker();
    final provider = Provider.of<ScanProvider>(context, listen: false);
    provider.clearPages();

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
        ).then((_) => _loadRecentFiles());
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

  void _openScanner(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ScannerScreen()),
    ).then((_) => _loadRecentFiles());
  }

  void _showActionOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Create a PDF',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.document_scanner, color: Colors.blueAccent),
                ),
                title: const Text('Scan PDF', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Use camera to scan documents.'),
                onTap: () {
                  Navigator.pop(context);
                  _openScanner(context);
                },
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.image_rounded, color: Colors.green),
                ),
                title: const Text('Image to PDF', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Convert images into a PDF.'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImages(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFileActions(PdfFileModel file) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open'),
              onTap: () async {
                Navigator.pop(context);
                await OpenFilex.open(file.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share'),
              onTap: () async {
                Navigator.pop(context);
                await Share.shareXFiles([XFile(file.path)]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () async {
                Navigator.pop(context);
                _showRenameDialog(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(context);
                _showDeleteConfirmation(file);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(PdfFileModel file) {
    final controller = TextEditingController(text: file.name.replaceAll('.pdf', ''));
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename File'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(suffixText: '.pdf'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                final newPath = await StorageService.renameFile(file.path, newName);
                await DatabaseService.updateFileMetadata(file.id, newName, newPath);
                if (mounted) {
                  Navigator.pop(context);
                  _loadRecentFiles();
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(PdfFileModel file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete File'),
        content: Text('Are you sure you want to delete "${file.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              await StorageService.deleteFile(file.path);
              await DatabaseService.deleteFile(file.id);
              if (mounted) {
                Navigator.pop(context);
                _loadRecentFiles();
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor, // Light gray background or dark
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SnapScanner',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.titleLarge?.color,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                    child: const Icon(
                      Icons.settings,
                      color: Colors.black, // Changed from dull color to black
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
            
            // Action Cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Row(
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
            ),
            
            const SizedBox(height: 32),
            
            // Recent Files Header
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.0),
              child: Text(
                'Recent Files',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            
            const SizedBox(height: 16),

            // Recent Files List or Empty State
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : _recentFiles.isEmpty 
                  ? _buildEmptyState()
                  : _buildRecentFilesList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return GestureDetector(
      onTap: () => _showActionOptions(context),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Illustration placeholder
          Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Background paper shadow
              Transform.rotate(
                angle: -0.2,
                child: Container(
                  width: 120,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              // Background paper shadow
              Transform.rotate(
                angle: 0.2,
                child: Container(
                  width: 120,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              // Main Paper
              Container(
                width: 140,
                height: 180,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 40,
                      left: 20,
                      child: Container(width: 60, height: 4, color: Colors.grey.shade200),
                    ),
                    Positioned(
                      top: 60,
                      left: 20,
                      child: Container(width: 40, height: 4, color: Colors.grey.shade200),
                    ),
                     Positioned(
                      bottom: 30,
                      right: 20,
                      child: Icon(Icons.draw, color: Colors.grey.shade400, size: 40,),
                    ),
                  ],
                ),
              ),
              
              // Plus Button
              Positioned(
                bottom: -25,
                child: GestureDetector(
                  onTap: () => _showActionOptions(context),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF416C), Color(0xFFFF4B2B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF416C).withOpacity(0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 30),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 50),
          Text(
            'Create your first PDF',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Convert images into PDFs instantly',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
          // Move slightly up to center visually
          const SizedBox(height: 40),
        ],
      ),
    ));
  }

  Widget _buildRecentFilesList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: _recentFiles.length,
      itemBuilder: (context, index) {
        final file = _recentFiles[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.picture_as_pdf, color: Colors.red),
            ),
            title: Text(
              file.name,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${_formatSize(file.size)} • ${DateFormat('MMM dd, yyyy').format(file.createdAt)}',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),
            onTap: () => _showFileActions(file),
          ),
        );
      },
    );
  }
}
