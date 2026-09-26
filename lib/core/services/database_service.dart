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
      version: 3,
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
        await _createFolderAndSettingsTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE pdf_files ADD COLUMN toolType TEXT DEFAULT "unknown"');
        }
        if (oldVersion < 3) {
          await _createFolderAndSettingsTables(db);
          // Anyone upgrading already has a database, so they are not a new
          // user and should not see onboarding.
          await db.insert(
            'app_settings',
            {'key': 'onboarding_completed', 'value': '1'},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      },
    );
  }

  /// Folders, folder membership and simple key/value settings (v3).
  /// Default folders are seeded here so they are only ever created once.
  static Future<void> _createFolderAndSettingsTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS folders (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS folder_files (
        folderId TEXT NOT NULL,
        fileId TEXT NOT NULL,
        addedAt TEXT NOT NULL,
        PRIMARY KEY (folderId, fileId)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    final now = DateTime.now();
    const defaults = ['Important', 'Personal'];
    for (var i = 0; i < defaults.length; i++) {
      await db.insert(
        'folders',
        {
          'id': 'default_${defaults[i].toLowerCase()}',
          'name': defaults[i],
          'createdAt': now.add(Duration(milliseconds: i)).toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
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
