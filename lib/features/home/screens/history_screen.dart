import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/models/pdf_file_model.dart';
import '../../../core/services/database_service.dart';
import '../../../core/services/storage_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<PdfFileModel> _recentFiles = [];
  bool _isLoading = true;
  String _selectedFilter = 'all';
  final _searchController = TextEditingController();

  static const _filterOptions = [
    ('All', 'all'),
    ('Scan PDF', 'scan_pdf'),
    ('Image to PDF', 'image_to_pdf'),
    ('Merge PDF', 'merge_pdf'),
    ('Split PDF', 'split_pdf'),
    ('Compress PDF', 'compress_pdf'),
    ('Lock PDF', 'lock_pdf'),
    ('Signature', 'signature_pdf'),
    ('Resize Image', 'resize_image'),
  ];

  List<PdfFileModel> get _filteredFiles {
    var files = _recentFiles;
    if (_selectedFilter != 'all') {
      files = files.where((f) => f.toolType == _selectedFilter).toList();
    }
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      files = files.where((f) => f.name.toLowerCase().contains(query)).toList();
    }
    return files;
  }

  @override
  void initState() {
    super.initState();
    _loadRecentFiles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentFiles() async {
    setState(() => _isLoading = true);
    final files = await DatabaseService.getAllFiles();
    if (mounted) {
      setState(() {
        _recentFiles = files;
        _isLoading = false;
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatToolType(String toolType) {
    switch (toolType) {
      case 'scan_pdf':
        return 'Created with Scan PDF';
      case 'image_to_pdf':
        return 'Created with Image to PDF';
      case 'merge_pdf':
        return 'Created with Merge PDF';
      case 'split_pdf':
        return 'Created with Split PDF';
      case 'compress_pdf':
        return 'Created with Compress PDF';
      case 'lock_pdf':
        return 'Created with Lock PDF';
      case 'signature_pdf':
        return 'Created with Signature';
      case 'resize_image':
        return 'Created with Resize Image';
      default:
        return 'Created with SnapScanner';
    }
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
              leading: const Icon(Icons.download),
              title: const Text('Download'),
              onTap: () async {
                Navigator.pop(context);
                try {
                  final sourceFile = File(file.path);
                  final bytes = await sourceFile.readAsBytes();
                  final outputPath = await FilePicker.saveFile(
                    dialogTitle: 'Download PDF',
                    fileName: file.name,
                    type: FileType.custom,
                    allowedExtensions: ['pdf'],
                    bytes: bytes,
                  );
                  if (outputPath != null) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('File downloaded successfully!')),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error downloading file: $e')),
                    );
                  }
                }
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

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F9FA),
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
                  'History',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).textTheme.titleLarge?.color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Recently created and modified files',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search files...',
                prefixIcon: const Icon(Icons.search, size: 22),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Filter chips
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: _filterOptions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final label = _filterOptions[index].$1;
                final value = _filterOptions[index].$2;
                final isSelected = _selectedFilter == value;
                return GestureDetector(
                  onTap: () => setState(() => _selectedFilter = value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blueAccent : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? Colors.blueAccent : Colors.grey.shade200,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey.shade700,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _recentFiles.isEmpty
                    ? _buildEmptyState()
                    : _filteredFiles.isEmpty
                        ? _buildNoResultsState()
                        : _buildRecentFilesList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.history, size: 56, color: Colors.blueAccent),
          ),
          const SizedBox(height: 24),
          Text(
            'No files yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your created PDFs will appear here',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.search_off, size: 48, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          Text(
            'No matching files',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different search or filter',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentFilesList() {
    final files = _filteredFiles;
    return ListView.builder(
      padding: const EdgeInsets.only(left: 24, right: 24, bottom: 100),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final isImage = file.toolType == 'resize_image';
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
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
              onTap: () => _showFileActions(file),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isImage
                            ? Colors.pink.withOpacity(0.12)
                            : Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isImage ? Icons.image : Icons.picture_as_pdf,
                        color: isImage ? Colors.pink : Colors.red,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatToolType(file.toolType),
                            style: TextStyle(color: Colors.blueAccent.shade400, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_formatSize(file.size)} • ${DateFormat('MMM dd, yyyy').format(file.createdAt)}',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.grey.shade300, size: 22),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
