import 'dart:io';
import 'package:flutter/material.dart';
import '../core/models/scanned_page.dart';

class ScanProvider extends ChangeNotifier {
  List<ScannedPage> _pages = [];
  String _toolType = 'scan_pdf';

  List<ScannedPage> get pages => _pages;
  String get toolType => _toolType;

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
    notifyListeners();
  }
}
