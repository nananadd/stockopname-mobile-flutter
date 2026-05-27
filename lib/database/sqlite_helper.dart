import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('wms_sigma_local.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    // 1. Tabel Master Rak
    await db.execute('''
      CREATE TABLE racks (
        id INTEGER PRIMARY KEY,
        code TEXT NOT NULL,
        qr_code TEXT
      )
    ''');

    // 2. Tabel Master Barang (Items)
    await db.execute('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY,
        sku TEXT NOT NULL,
        name TEXT NOT NULL,
        system_stock INTEGER NOT NULL
      )
    ''');

    // 3. Tabel Lokasi Barang (Pivot)
    await db.execute('''
      CREATE TABLE item_rack (
        item_id INTEGER,
        rack_id INTEGER,
        stock_at_location INTEGER,
        PRIMARY KEY (item_id, rack_id)
      )
    ''');

    // 4. Tabel Header Cycle Count (Draft Offline)
    await db.execute('''
      CREATE TABLE cycle_counts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rack_id INTEGER NOT NULL,
        status TEXT NOT NULL,
        started_at TEXT NOT NULL,
        finished_at TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0 
      )
    ''');

    // 5. Tabel Detail Cycle Count (Draft Offline)
    await db.execute('''
      CREATE TABLE cycle_count_details (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cycle_count_id INTEGER NOT NULL,
        item_id INTEGER NOT NULL,
        system_stock_snapshot INTEGER NOT NULL,
        physical_stock INTEGER NOT NULL
      )
    ''');
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }

  /// Fungsi untuk menghapus data lama sebelum sinkronisasi
  Future<void> clearMasterData() async {
    final db = await instance.database;
    await db.delete('racks');
    await db.delete('items');
    await db.delete('item_rack'); // <-- BERSAHKAN JUGA TABEL PIVOT
  }

  /// Fungsi untuk menyimpan banyak Rak sekaligus
  Future<void> insertRacks(List<dynamic> racks) async {
    final db = await instance.database;
    Batch batch = db.batch();
    for (var rack in racks) {
      batch.insert('racks', {
        'id': rack['id'],
        'code': rack['code'] ?? '',
        'qr_code': rack['qr_code'] ?? '',
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // <-- TANGKAP HUBUNGAN RAK DAN BARANG DARI LARAVEL
      if (rack['items'] != null) {
        for (var item in rack['items']) {
          batch.insert('item_rack', {
            'rack_id': rack['id'],
            'item_id': item['id'],
            'stock_at_location': 0, // Nilai default sementara
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    }
    await batch.commit(noResult: true);
  }

  /// Fungsi untuk menyimpan banyak Item sekaligus
  Future<void> insertItems(List<dynamic> items) async {
    final db = await instance.database;
    Batch batch = db.batch();
    for (var item in items) {
      batch.insert('items', {
        'id': item['id'],
        'sku': item['sku'] ?? '',
        'name': item['name'] ?? '',
        'system_stock': item['system_stock'] ?? 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// FUNGSI BARU: Ambil Item khusus untuk Rak tertentu saja
  Future<List<Map<String, dynamic>>> getItemsByRack(int rackId) async {
    final db = await instance.database;
    return await db.rawQuery('''
      SELECT i.* FROM items i
      INNER JOIN item_rack ir ON i.id = ir.item_id
      WHERE ir.rack_id = ?
    ''', [rackId]);
  }

  /// Ambil semua Cycle Count yang statusnya masih 'pending' (belum dikirim)
  Future<List<Map<String, dynamic>>> getPendingCycleCounts() async {
    final db = await instance.database;
    
    // Ambil header yang pending
    final List<Map<String, dynamic>> pendingCounts = await db.query(
      'cycle_counts',
      where: 'status = ?',
      whereArgs: ['pending'],
    );

    List<Map<String, dynamic>> result = [];

    // Loop setiap header untuk mengambil detail barangnya
    for (var count in pendingCounts) {
      final details = await db.query(
        'cycle_count_details',
        where: 'cycle_count_id = ?',
        whereArgs: [count['id']],
      );

      // Rangkai sesuai format JSON yang diminta Laravel
      result.add({
        'id': count['id'], // Disimpan untuk update status nanti
        'rack_id': count['rack_id'],
        'started_at': count['started_at'],
        'finished_at': count['finished_at'],
        'details': details.map((d) => {
          'item_id': d['item_id'],
          'physical_stock': d['physical_stock'],
        }).toList(),
      });
    }

    return result;
  }

  /// Ubah status menjadi 'synced' agar tidak dikirim ulang
  Future<void> markAsSynced(List<int> cycleCountIds) async {
    final db = await instance.database;
    Batch batch = db.batch();
    
    for (int id in cycleCountIds) {
      batch.update(
        'cycle_counts',
        {'status': 'synced', 'is_synced': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Ambil Riwayat Hitungan untuk ditampilkan di UI
  Future<List<Map<String, dynamic>>> getHistory() async {
    final db = await instance.database;
    // Menggunakan rawQuery untuk JOIN tabel cycle_counts dan racks
    return await db.rawQuery('''
      SELECT c.*, r.code as rack_code 
      FROM cycle_counts c
      LEFT JOIN racks r ON c.rack_id = r.id
      ORDER BY c.started_at DESC
    ''');
  }
}