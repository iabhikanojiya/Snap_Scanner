import 'dart:io';
import 'package:flutter/material.dart';
import '../core/models/scanned_page.dart';

class ScanProvider extends ChangeNotifier {
  List<ScannedPage> _pages = [];
  String _toolType = 'scan_pdf';
  String? _appendToPdfPath;

  List<ScannedPage> get pages => _pages;
  String get toolType => _toolType;

  /// When set, the generated PDF is this existing PDF followed by [pages]
  /// (saved as a new file; the original is left unchanged).
  String? get appendToPdfPath => _appendToPdfPath;

  void setAppendTarget(String? pdfPath) {
    _appendToPdfPath = pdfPath;
  }

  void setToolType(String type) {
    _toolType = type;
  }

  void addPage(ScannedPage page) {
    _pages.add(page);
    notifyListeners();
  }

  void removePage(String id) {
    _pages.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  void reorderPages(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final ScannedPage item = _pages.removeAt(oldIndex);
    _pages.insert(newIndex, item);
    notifyListeners();
  }

  void updatePageProcessedFile(String id, File file) {
    final index = _pages.indexWhere((p) => p.id == id);
    if (index != -1) {
      _pages[index].processedFile = file;
      notifyListeners();
    }
  }

  void clearPages() {
    _pages = [];
    _toolType = 'scan_pdf';
    _appendToPdfPath = null;
    notifyListeners();
  }
}
