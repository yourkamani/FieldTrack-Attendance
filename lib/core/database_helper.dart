import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('locations.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT,
        session_id TEXT,
        lat REAL,
        lng REAL,
        timestamp TEXT
      )
    ''');
  }

  Future<void> insertLocation(Map<String, dynamic> data) async {
    final db = await instance.database;
    await db.insert('locations', data);
  }

  Future<List<Map<String, dynamic>>> getUnsyncedLocations() async {
    final db = await instance.database;
    return await db.query('locations');
  }

  Future<void> clearSyncedLocations(List<int> ids) async {
    final db = await instance.database;
    await db.delete('locations', where: 'id IN (${ids.join(',')})');
  }
}