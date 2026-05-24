import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snap_scanner/providers/scan_provider.dart';
import 'package:snap_scanner/features/pdf/screens/pdf_settings_screen.dart';
import 'package:snap_scanner/features/scanner/screens/scanner_screen.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  // Edit functionality moved to BatchCropScreen and BatchFilterScreen

  void _onNext() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PdfSettingsScreen(buttonText: 'Create PDF'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<ScanProvider>(
          builder: (context, provider, _) => Text('Review (${provider.pages.length})'),
        ),
        actions: [
          TextButton(
            onPressed: _onNext,
            child: const Text('Next', style: TextStyle(fontSize: 16)),
          )
        ],
      ),
      body: Consumer<ScanProvider>(
        builder: (context, provider, _) {
          if (provider.pages.isEmpty) {
            return const Center(child: Text("No pages scanned"));
          }

          return ReorderableListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: provider.pages.length,
            onReorder: provider.reorderPages,
            itemBuilder: (context, index) {
              final page = provider.pages[index];
              return Container(
                key: ValueKey(page.id),
                margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04), // Subtle shadow
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 50,
                      height: 70,
                      child: Image.file(
                        page.displayFile,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  title: Text(
                    "Page ${index + 1}",
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => provider.removePage(page.id),
                      ),
                      const SizedBox(width: 8),
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_indicator, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ScannerScreen()),
          );
        },
        label: const Text("Add Pages"),
        icon: const Icon(Icons.add_a_photo),
      ),
    );
  }
}
