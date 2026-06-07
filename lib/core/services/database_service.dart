import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/pdf_file_model.dart';

class DatabaseService {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'pdf_tools.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE pdf_files (
            id TEXT PRIMARY KEY,
            name TEXT,
            path TEXT,
            size INTEGER,
            createdAt TEXT,
            toolType TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE pdf_files ADD COLUMN toolType TEXT DEFAULT "unknown"');
        }
      },
    );
  }

  static Future<void> insertFile(PdfFileModel file) async {
    final db = await database;
    await db.insert(
      'pdf_files',
      file.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<PdfFileModel>> getAllFiles() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('pdf_files', orderBy: 'createdAt DESC');
    return List.generate(maps.length, (i) {
      return PdfFileModel.fromMap(maps[i]);
    });
  }

  static Future<void> deleteFile(String id) async {
    final db = await database;
    await db.delete(
      'pdf_files',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<void> updateFileMetadata(String id, String newName, String newPath) async {
    final db = await database;
    await db.update(
      'pdf_files',
      {
        'name': newName.endsWith('.pdf') ? newName : '$newName.pdf',
        'path': newPath,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
