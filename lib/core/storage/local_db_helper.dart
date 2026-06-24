import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDbHelper {
  static final LocalDbHelper instance = LocalDbHelper._init();
  static Database? _database;

  LocalDbHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('app_database.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE api_cache (
        endpoint TEXT PRIMARY KEY,
        response_data TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Tabel terpadu untuk antrian offline (check_in, check_out, izin)
    await db.execute('''
      CREATE TABLE offline_queue (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        office_id INTEGER NOT NULL,
        is_face_valid INTEGER NOT NULL DEFAULT 0,
        check_in_time TEXT,
        check_out_time TEXT,
        offline_date TEXT,
        latitude REAL,
        longitude REAL,
        jenis_izin TEXT,
        izin_keterangan TEXT,
        is_synced INTEGER NOT NULL DEFAULT 0,
        sync_status TEXT NOT NULL DEFAULT 'pending',
        error_message TEXT,
        created_at TEXT NOT NULL
      )
    ''');
  }

  /// Migrasi dari v1 ke v2:
  /// - Buat tabel offline_queue baru
  /// - Migrasi data lama dari offline_presence ke offline_queue (sebagai check_in)
  /// - Hapus tabel lama
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Buat tabel baru
      await db.execute('''
        CREATE TABLE offline_queue (
          id TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          office_id INTEGER NOT NULL,
          is_face_valid INTEGER NOT NULL DEFAULT 0,
          check_in_time TEXT,
          check_out_time TEXT,
          offline_date TEXT,
          latitude REAL,
          longitude REAL,
          jenis_izin TEXT,
          izin_keterangan TEXT,
          is_synced INTEGER NOT NULL DEFAULT 0,
          sync_status TEXT NOT NULL DEFAULT 'pending',
          error_message TEXT,
          created_at TEXT NOT NULL
        )
      ''');

      // Migrasi data lama dari offline_presence (jika ada) ke offline_queue sebagai check_in
      try {
        final oldData = await db.query('offline_presence');
        for (final row in oldData) {
          await db.insert('offline_queue', {
            'id': row['id'],
            'type': 'check_in',
            'office_id': row['office_id'],
            'is_face_valid': row['is_face_valid'],
            'check_in_time': row['timestamp'],
            'latitude': row['latitude'],
            'longitude': row['longitude'],
            'is_synced': row['is_synced'],
            'sync_status': (row['is_synced'] as int) == 1 ? 'synced' : 'pending',
            'created_at': row['timestamp'] ?? DateTime.now().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        await db.execute('DROP TABLE IF EXISTS offline_presence');
      } catch (_) {
        // Tabel lama mungkin tidak ada, abaikan
      }
    }
  }

  // --- API Cache Methods ---

  Future<void> saveCache(String endpoint, String responseData) async {
    final db = await instance.database;
    await db.insert(
      'api_cache',
      {
        'endpoint': endpoint,
        'response_data': responseData,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getCache(String endpoint) async {
    final db = await instance.database;
    final maps = await db.query(
      'api_cache',
      columns: ['response_data'],
      where: 'endpoint = ?',
      whereArgs: [endpoint],
    );

    if (maps.isNotEmpty) {
      return maps.first['response_data'] as String;
    }
    return null;
  }

  Future<void> clearCache() async {
    final db = await instance.database;
    await db.delete('api_cache');
  }

  // --- Offline Queue Methods (unified) ---

  /// Insert satu item ke antrian offline.
  Future<void> insertOfflineQueueItem(Map<String, dynamic> item) async {
    final db = await instance.database;
    await db.insert(
      'offline_queue',
      item,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Ambil semua item pending (belum di-sync) urut dari terlama.
  Future<List<Map<String, dynamic>>> getPendingQueueItems() async {
    final db = await instance.database;
    return await db.query(
      'offline_queue',
      where: 'sync_status IN (?, ?)',
      whereArgs: ['pending', 'failed'],
      orderBy: 'created_at ASC',
    );
  }

  /// Tandai item sebagai synced.
  Future<void> markQueueItemSynced(String id) async {
    final db = await instance.database;
    await db.update(
      'offline_queue',
      {'is_synced': 1, 'sync_status': 'synced'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Tandai item sebagai failed dengan pesan error.
  Future<void> markQueueItemFailed(String id, String errorMessage) async {
    final db = await instance.database;
    await db.update(
      'offline_queue',
      {'sync_status': 'failed', 'error_message': errorMessage},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Hapus item yang sudah synced.
  Future<void> deleteSyncedQueueItems() async {
    final db = await instance.database;
    await db.delete(
      'offline_queue',
      where: 'sync_status = ?',
      whereArgs: ['synced'],
    );
  }

  /// Hapus semua item dari antrian (saat logout).
  Future<void> clearAllQueueItems() async {
    final db = await instance.database;
    await db.delete('offline_queue');
  }

  // --- Legacy methods (backward-compat, dipetakan ke tabel baru) ---

  Future<void> insertOfflinePresence({
    required String id,
    required int officeId,
    required double latitude,
    required double longitude,
    required bool isFaceValid,
    required String timestamp,
  }) async {
    await insertOfflineQueueItem({
      'id': id,
      'type': 'check_in',
      'office_id': officeId,
      'is_face_valid': isFaceValid ? 1 : 0,
      'check_in_time': timestamp,
      'latitude': latitude,
      'longitude': longitude,
      'is_synced': 0,
      'sync_status': 'pending',
      'created_at': timestamp,
    });
  }

  Future<List<Map<String, dynamic>>> getUnsyncedPresences() async {
    return await getPendingQueueItems();
  }

  Future<void> markPresenceSynced(String id) async {
    await markQueueItemSynced(id);
  }

  Future<void> deleteSyncedPresences() async {
    await deleteSyncedQueueItems();
  }
}
