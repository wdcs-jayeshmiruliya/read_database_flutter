import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

// Minimal Drift database to execute raw SQL via customSelect/customStatement
class _RawDriftDb extends GeneratedDatabase {
  _RawDriftDb(QueryExecutor e) : super(e);
  @override
  int get schemaVersion => 1; // Avoid drift writing PRAGMA user_version
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];
}

class DatabaseService {
  _RawDriftDb? _db;
  QueryExecutor? _executor;
  String? _dbPath;

  String? get databasePath => _dbPath;
  bool get isOpen => _db != null;

  Future<void> open(String path) async {
    await close();
    _executor = NativeDatabase.createInBackground(File(path));
    _db = _RawDriftDb(_executor!);
    _dbPath = path;
  }

  Future<void> close() async {
    try {
      final exec = _executor;
      if (exec is NativeDatabase) {
        await exec.close();
      }
    } finally {
      _db = null;
      _executor = null;
      _dbPath = null;
    }
  }

  Future<List<String>> listTables() async {
    final db = _requireDb();
    final result = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ).get();
    return result.map((row) => row.data['name'] as String).toList();
  }

  Future<List<String>> getColumnNames(String tableName) async {
    final db = _requireDb();
    final result = await db.customSelect('PRAGMA table_info(\'$tableName\')').get();
    return result.map((row) => row.data['name'] as String).toList();
  }

  Future<int> getRowCount(String tableName) async {
    final db = _requireDb();
    final rs = await db.customSelect('SELECT COUNT(*) AS c FROM "${tableName}"').getSingle();
    final c = rs.data['c'];
    if (c is int) return c;
    if (c is BigInt) return c.toInt();
    return (c as num).toInt();
  }

  Future<List<Map<String, Object?>>> getRows(
    String tableName, {
    required int limit,
    required int offset,
  }) async {
    final db = _requireDb();
    final rs = await db
        .customSelect(
          'SELECT * FROM "${tableName}" LIMIT ? OFFSET ?',
          variables: [Variable.withInt(limit), Variable.withInt(offset)],
        )
        .get();
    return rs.map((row) => Map<String, Object?>.from(row.data)).toList();
  }

  static String formatCellValue(Object? value) {
    if (value == null) return 'NULL';
    if (value is Uint8List) return '[BLOB] (${value.lengthInBytes} bytes)';
    return value.toString();
  }

  _RawDriftDb _requireDb() {
    final db = _db;
    if (db == null) {
      throw StateError('Database is not open');
    }
    return db;
  }
}


