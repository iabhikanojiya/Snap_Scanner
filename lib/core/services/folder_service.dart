import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../models/folder_model.dart';
import '../models/pdf_file_model.dart';
import 'database_service.dart';

/// Folder organisation on top of the existing `pdf_files` table.
/// Membership lives in `folder_files`; PDF rows themselves are never touched.
class FolderService {
  static const Uuid _uuid = Uuid();

  /// Folders with the number of (still existing) files in each.
  static Future<List<FolderModel>> getFolders() async {
    final db = await DatabaseService.database;
    final maps = await db.rawQuery('''
      SELECT f.id, f.name, f.createdAt,
             COUNT(p.id) AS fileCount
      FROM folders f
      LEFT JOIN folder_files ff ON ff.folderId = f.id
      LEFT JOIN pdf_files p ON p.id = ff.fileId
      GROUP BY f.id
      ORDER BY f.createdAt ASC
    ''');
    return maps.map(FolderModel.fromMap).toList();
  }

  /// Returns null if a folder with the same name (case-insensitive) exists.
  static Future<FolderModel?> createFolder(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final db = await DatabaseService.database;
    final existing = await db.query(
      'folders',
      where: 'LOWER(name) = ?',
      whereArgs: [trimmed.toLowerCase()],
      limit: 1,
    );
    if (existing.isNotEmpty) return null;
    final folder = FolderModel(
      id: _uuid.v4(),
      name: trimmed,
      createdAt: DateTime.now(),
    );
    await db.insert('folders', {
      'id': folder.id,
      'name': folder.name,
      'createdAt': folder.createdAt.toIso8601String(),
    });
    return folder;
  }

  static Future<List<PdfFileModel>> getFilesInFolder(String folderId) async {
    final db = await DatabaseService.database;
    final maps = await db.rawQuery('''
      SELECT p.* FROM pdf_files p
      INNER JOIN folder_files ff ON ff.fileId = p.id
      WHERE ff.folderId = ?
      ORDER BY p.createdAt DESC
    ''', [folderId]);
    return maps.map(PdfFileModel.fromMap).toList();
  }

  /// Whether the file belongs to at least one folder.
  static Future<bool> isFileInAnyFolder(String fileId) async {
    final db = await DatabaseService.database;
    final rows = await db.query(
      'folder_files',
      columns: ['fileId'],
      where: 'fileId = ?',
      whereArgs: [fileId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static Future<void> addFileToFolder(String fileId, String folderId) async {
    final db = await DatabaseService.database;
    await db.insert(
      'folder_files',
      {
        'folderId': folderId,
        'fileId': fileId,
        'addedAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Removes the file from every other folder, then adds it to [folderId].
  static Future<void> moveFileToFolder(String fileId, String folderId) async {
    final db = await DatabaseService.database;
    await db.transaction((txn) async {
      await txn.delete(
        'folder_files',
        where: 'fileId = ? AND folderId != ?',
        whereArgs: [fileId, folderId],
      );
      await txn.insert(
        'folder_files',
        {
          'folderId': folderId,
          'fileId': fileId,
          'addedAt': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    });
  }

  static Future<void> removeFileFromFolder(String fileId, String folderId) async {
    final db = await DatabaseService.database;
    await db.delete(
      'folder_files',
      where: 'fileId = ? AND folderId = ?',
      whereArgs: [fileId, folderId],
    );
  }
}
