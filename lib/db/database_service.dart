import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart' as sq3;

class DatabaseService {
  sq3.Database? _db;
  String? _dbPath;

  String? get databasePath => _dbPath;
  bool get isOpen => _db != null;

  void open(String path) {
    close();
    _db = sq3.sqlite3.open(path);
    _dbPath = path;
  }

  void close() {
    try {
      _db?.dispose();
    } finally {
      _db = null;
      _dbPath = null;
    }
  }

  List<String> listTables() {
    final db = _requireDb();
    final result = db.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    return result.map((row) => row['name'] as String).toList();
  }

  List<String> getColumnNames(String tableName) {
    final db = _requireDb();
    final result = db.select("PRAGMA table_info('$tableName')");
    return result.map((row) => row['name'] as String).toList();
  }

  int getRowCount(String tableName) {
    final db = _requireDb();
    final rs = db.select('SELECT COUNT(*) AS c FROM "$tableName"');
    return (rs.first['c'] as int);
  }

  List<Map<String, Object?>> getRows(
    String tableName, {
    required int limit,
    required int offset,
  }) {
    final db = _requireDb();
    final rs = db.select('SELECT * FROM "$tableName" LIMIT ? OFFSET ?', [limit, offset]);
    return rs.map((row) => Map<String, Object?>.from(row)).toList();
  }

  static String formatCellValue(Object? value) {
    if (value == null) return 'NULL';
    if (value is Uint8List) return '[BLOB] (${value.lengthInBytes} bytes)';
    return value.toString();
  }

  sq3.Database _requireDb() {
    final db = _db;
    if (db == null) {
      throw StateError('Database is not open');
    }
    return db;
  }
}


