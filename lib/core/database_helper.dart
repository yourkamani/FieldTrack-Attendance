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
    return await openDatabase(path, version: 3, onCreate: _createDB, onUpgrade: _onUpgrade);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT, business_id TEXT, session_id TEXT,
        lat REAL, lng REAL, timestamp TEXT
      )
    ''');
    await _createSessionsTable(db);
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _createSessionsTable(db);
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE sessions ADD COLUMN business_id TEXT');
      await db.execute('ALTER TABLE locations ADD COLUMN business_id TEXT');
    }
  }

  Future _createSessionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        session_id TEXT PRIMARY KEY, user_id TEXT, business_id TEXT,
        start_time TEXT, end_time TEXT,
        start_selfie_path TEXT, stop_selfie_path TEXT,
        auto_stopped INTEGER DEFAULT 0, synced INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> insertLocation(Map<String, dynamic> data) async => (await database).insert('locations', data);
  Future<List<Map<String, dynamic>>> getUnsyncedLocations() async => (await database).query('locations');
  Future<void> clearSyncedLocations(List<int> ids) async => (await database).delete('locations', where: 'id IN (${ids.join(',')})');

  Future<void> insertSessionStart(Map<String, dynamic> data) async =>
      (await database).insert('sessions', data, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> updateSessionStop({required String sessionId, required String endTime, String? stopSelfiePath}) async {
    await (await database).update('sessions',
        {'end_time': endTime, 'stop_selfie_path': stopSelfiePath, 'synced': 0},
        where: 'session_id = ?', whereArgs: [sessionId]);
  }

  Future<void> updateSessionAutoStop({required String sessionId, required String endTime}) async {
    await (await database).update('sessions',
        {'end_time': endTime, 'auto_stopped': 1, 'synced': 0},
        where: 'session_id = ?', whereArgs: [sessionId]);
  }

  Future<List<Map<String, dynamic>>> getUnsyncedSessions() async => (await database).query('sessions', where: 'synced = 0');
  Future<void> markSessionSynced(String sessionId) async =>
      (await database).update('sessions', {'synced': 1}, where: 'session_id = ?', whereArgs: [sessionId]);
}