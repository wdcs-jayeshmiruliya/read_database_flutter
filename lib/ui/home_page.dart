import 'dart:io' show Platform;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:window_manager/window_manager.dart';

import '../db/database_service.dart';
import 'data_table_view.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DatabaseService _db = DatabaseService();

  String? _selectedTable;
  List<String> _tables = const [];
  List<String> _columns = const [];

  // paging
  static const int _pageSize = 50;
  int _currentPage = 0;
  int _totalCount = 0;
  List<Map<String, Object?>> _rows = const [];

  bool _loading = false;
  String? _error;
  bool _isDragging = false;
  final TextEditingController _pathController = TextEditingController();

  @override
  void dispose() {
    _pathController.dispose();
    _db.close();
    super.dispose();
  }

  Future<void> _pickDb() async {
    setState(() {
      _error = null;
    });
    try {
      // Make sure the window is in front before opening a sheet/dialog
      try { await windowManager.focus(); } catch (_) {}
      // Small delay helps when triggered immediately from UI; avoids sheet focus issues
      await Future.delayed(const Duration(milliseconds: 100));
      
      XFile? file;
      
      // Use file_selector for macOS (native macOS file picker)
      if (Platform.isMacOS) {
        debugPrint('Opening macOS file picker (file_selector)...');
        const typeGroup = XTypeGroup(
          label: 'SQLite database',
          extensions: ['db', 'sqlite', 'sqlite3'],
        );
        file = await openFile(acceptedTypeGroups: [typeGroup]);
        // If no file selected with filter, try without filter
        if (file == null) {
          debugPrint('Retrying without file filter...');
          file = await openFile();
        }
      } else {
        // For other platforms, use file_selector with filter
        const typeGroup = XTypeGroup(
          label: 'SQLite database',
          extensions: ['db', 'sqlite', 'sqlite3'],
        );
        file = await openFile(acceptedTypeGroups: [typeGroup]);
        if (file == null) {
          file = await openFile();
        }
      }

      if (file == null) {
        debugPrint('No file selected.');
        return;
      }

      await _db.open(file.path);
      final tables = await _db.listTables();
      setState(() {
        _tables = tables;
        _selectedTable = tables.isNotEmpty ? tables.first : null;
      });

      if (_selectedTable != null) {
        await _loadTable(_selectedTable!);
      }
    } catch (e, st) {
      debugPrint('Picker/open error: $e\n$st');
      setState(() => _error = e.toString());
      _showSnack('Failed to open database: $e');
    }
  }

  Future<void> _loadTable(String table) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cols = await _db.getColumnNames(table);
      final total = await _db.getRowCount(table);
      _currentPage = 0;
      final rows = await _db.getRows(table, limit: _pageSize, offset: 0);
      setState(() {
        _columns = cols;
        _totalCount = total;
        _rows = rows;
        _selectedTable = table;
      });
    } catch (e) {
      setState(() => _error = e.toString());
      _showSnack('Failed to load table "$table": $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _goPrev() async {
    if (_selectedTable == null) return;
    if (_currentPage <= 0) return;
    await _gotoPage(_currentPage - 1);
  }

  Future<void> _goNext() async {
    if (_selectedTable == null) return;
    final totalPages = (_totalCount / _pageSize).ceil();
    if (_currentPage >= totalPages - 1) return;
    await _gotoPage(_currentPage + 1);
  }

  Future<void> _gotoPage(int page) async {
    if (_selectedTable == null) return;
    setState(() => _loading = true);
    try {
      final rows = await _db.getRows(
        _selectedTable!,
        limit: _pageSize,
        offset: page * _pageSize,
      );
      setState(() {
        _rows = rows;
        _currentPage = page;
      });
    } catch (e) {
      _showSnack('Failed to load page: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }


  @override
  Widget build(BuildContext context) {
    final dbFileName = _db.databasePath == null ? 'No file selected' : p.basename(_db.databasePath!);
    return Scaffold(
      appBar: AppBar(
        title: const Text('SQLite Viewer (Desktop)'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(child: Text(dbFileName)),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: FilledButton.icon(
              onPressed: _pickDb,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open DB'),
            ),
          ),
        ],
      ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _isDragging = true),
        onDragExited: (_) => setState(() => _isDragging = false),
        onDragDone: (detail) async {
          setState(() => _isDragging = false);
          final filePath = detail.files.firstOrNull?.path;
          if (filePath == null) return;
          try {
            await _db.open(filePath);
            final tables = await _db.listTables();
            setState(() {
              _tables = tables;
              _selectedTable = tables.isNotEmpty ? tables.first : null;
            });
            if (_selectedTable != null) {
              await _loadTable(_selectedTable!);
            }
          } catch (e) {
            setState(() => _error = e.toString());
            _showSnack('Failed to open database: $e');
            debugPrint('Failed to open database: $e');
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  const Text('Table:'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedTable,
                      hint: const Text('Select a table'),
                      items: _tables
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          _loadTable(value);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            // Manual path open fallback
            // Padding(
            //   padding: const EdgeInsets.symmetric(horizontal: 12.0),
            //   child: Row(
            //     children: [
            //       Expanded(
            //         child: TextField(
            //           controller: _pathController,
            //           decoration: const InputDecoration(
            //             labelText: 'Or paste a database path (e.g. /Users/you/Downloads/db.sqlite)',
            //           ),
            //         ),
            //       ),
            //       const SizedBox(width: 8),
            //       FilledButton(
            //         onPressed: () async {
            //           final path = _pathController.text.trim();
            //           if (path.isEmpty) return;
            //           try {
            //             if (!await File(path).exists()) {
            //               _showSnack('File not found: $path');
            //               return;
            //             }
            //             _db.open(path);
            //             final tables = _db.listTables();
            //             setState(() {
            //               _tables = tables;
            //               _selectedTable = tables.isNotEmpty ? tables.first : null;
            //             });
            //             if (_selectedTable != null) {
            //               await _loadTable(_selectedTable!);
            //             }
            //           } catch (e) {
            //             setState(() => _error = e.toString());
            //             _showSnack('Failed to open database: $e');
            //           }
            //         },
            //         child: const Text('Open path'),
            //       ),
            //     ],
            //   ),
            // ),
            if (_isDragging)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                ),
                child: const Text('Drop a .db file here to open'),
              ),
            Expanded(
              child: _buildBody(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)));
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_selectedTable == null) {
      return const Center(child: Text('Open a .db file to begin'));
    }
    if (_columns.isEmpty) {
      return const Center(child: Text('No columns to display'));
    }
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: DataTableView(
        headers: _columns,
        rows: _rows,
        totalCount: _totalCount,
        pageSize: _pageSize,
        currentPage: _currentPage,
        onPrev: _goPrev,
        onNext: _goNext,
      ),
    );
  }
}


