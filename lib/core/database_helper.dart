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
    return await openDatabase(
      path,
      version: 2, // bumped: v2 adds the `sessions` table
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
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
    await _createSessionsTable(db);
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createSessionsTable(db);
    }
  }

  Future _createSessionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        session_id TEXT PRIMARY KEY,
        user_id TEXT,
        start_time TEXT,
        end_time TEXT,
        start_selfie_path TEXT,
        stop_selfie_path TEXT,
        auto_stopped INTEGER DEFAULT 0,
        synced INTEGER DEFAULT 0
      )
    ''');
  }

  // -------------------------------------------------------------------
  // LOCATIONS (unchanged)
  // -------------------------------------------------------------------
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

  // -------------------------------------------------------------------
  // SESSIONS (new — one row per start/stop cycle, carries selfie paths)
  // -------------------------------------------------------------------
  Future<void> insertSessionStart(Map<String, dynamic> data) async {
    final db = await instance.database;
    await db.insert('sessions', data, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateSessionStop({
    required String sessionId,
    required String endTime,
    String? stopSelfiePath,
  }) async {
    final db = await instance.database;
    await db.update(
      'sessions',
      {
        'end_time': endTime,
        'stop_selfie_path': stopSelfiePath,
        'synced': 0, // force a re-sync now that end info is known
      },
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Used by the background service when a session hits the 12-hour cap.
  /// No selfie is recorded — that's the whole point of auto-stop.
  Future<void> updateSessionAutoStop({
    required String sessionId,
    required String endTime,
  }) async {
    final db = await instance.database;
    await db.update(
      'sessions',
      {
        'end_time': endTime,
        'auto_stopped': 1,
        'synced': 0,
      },
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedSessions() async {
    final db = await instance.database;
    return await db.query('sessions', where: 'synced = 0');
  }

  Future<void> markSessionSynced(String sessionId) async {
    final db = await instance.database;
    await db.update('sessions', {'synced': 1}, where: 'session_id = ?', whereArgs: [sessionId]);
  }
}