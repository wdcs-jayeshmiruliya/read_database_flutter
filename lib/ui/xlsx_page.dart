import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:excel/excel.dart';
import 'package:watcher/watcher.dart';

import 'data_table_view.dart';

class XlsxPage extends StatefulWidget {
  const XlsxPage({super.key});

  @override
  State<XlsxPage> createState() => _XlsxPageState();
}

class _XlsxPageState extends State<XlsxPage> {
  Excel? _workbook;
  String? _fileName;
  String? _filePath;
  List<String> _sheetNames = const [];
  String? _selectedSheet;

  // Data for current sheet
  List<String> _headers = const [];
  List<Map<String, Object?>> _rows = const [];

  // paging
  static const int _pageSize = 50;
  int _currentPage = 0;

  bool _loading = false;
  String? _error;
  // Header row controller (1-based UX)
  final TextEditingController _headerRowController = TextEditingController();

  // File watcher for auto-refresh
  FileWatcher? _fileWatcher;
  StreamSubscription? _fileWatcherSubscription;
  bool _isRefreshing = false;

  Future<void> _pickXlsx() async {
    setState(() {
      _error = null;
    });
    try {
      try {
        await windowManager.focus();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 100));

      const typeGroup = XTypeGroup(label: 'Excel', extensions: ['xlsx']);
      XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);
      file ??= await openFile();
      if (file == null) return;

      final picked = file; // promote to non-null for closures

      // Stop previous watcher if exists
      await _stopFileWatcher();

      final bytes = await picked.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final names = excel.tables.keys.toList();

      setState(() {
        _workbook = excel;
        _fileName = picked.name;
        _filePath = picked.path;
        _sheetNames = names;
        _selectedSheet = names.isNotEmpty ? names.first : null;
      });

      // Start file watcher for auto-refresh
      await _startFileWatcher(picked.path);

      if (_selectedSheet != null) {
        await _loadSheet(_selectedSheet!);
      }
    } catch (e, st) {
      debugPrint('Failed to open xlsx: $e\n$st');
      setState(() => _error = e.toString());
      _showSnack('Failed to open .xlsx: $e');
    }
  }

  Future<void> _loadSheet(String sheetName) async {
    if (_workbook == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final table = _workbook!.tables[sheetName];
      if (table == null) {
        setState(() {
          _headers = const [];
          _rows = const [];
          _currentPage = 0;
        });
        return;
      }

      // Extract rows (List<List<Data?>?>)
      final rawRows = table.rows;
      // Resolve header row index: use user input if provided (1-based), else auto-detect first non-empty row
      int? manualOneBased;
      final hdrText = _headerRowController.text.trim();
      if (hdrText.isNotEmpty) {
        final parsed = int.tryParse(hdrText);
        if (parsed != null && parsed >= 1) manualOneBased = parsed;
      }
      int headerIndex;
      if (manualOneBased != null) {
        headerIndex = manualOneBased - 1;
      } else {
        int idx = 0;
        while (idx < rawRows.length &&
            rawRows[idx].every(
              (c) => (c?.value?.toString().trim().isEmpty ?? true),
            )) {
          idx++;
        }
        headerIndex = idx;
        if (_headerRowController.text.isEmpty && headerIndex < rawRows.length) {
          _headerRowController.text = (headerIndex + 1).toString();
        }
      }
      if (headerIndex >= rawRows.length) {
        setState(() {
          _headers = const [];
          _rows = const [];
          _currentPage = 0;
        });
        _showSnack(
          'Header row ${manualOneBased ?? (headerIndex + 1)} is out of range for sheet "$sheetName"',
        );
        return;
      }
      final headerCells = rawRows[headerIndex];
      final headers = headerCells
          .map((c) => c?.value?.toString() ?? '')
          .toList();

      // Build data rows after headerIndex
      final dataRows = <Map<String, Object?>>[];
      for (int i = headerIndex + 1; i < rawRows.length; i++) {
        final row = rawRows[i];
        if (row.every((c) => (c?.value?.toString().trim().isEmpty ?? true))) {
          // skip purely empty rows
          continue;
        }
        final map = <String, Object?>{};
        for (int j = 0; j < headers.length; j++) {
          final key = headers[j].isEmpty ? 'Column ${j + 1}' : headers[j];
          final cell = j < row.length ? row[j] : null;
          map[key] = cell
              ?.value; // DataTableView will stringify via DatabaseService.formatCellValue
        }
        dataRows.add(map);
      }

      setState(() {
        _headers = headers.map((h) => h.isEmpty ? 'Column' : h).toList();
        _rows = dataRows;
        _currentPage = 0;
        _selectedSheet = sheetName;
      });
    } catch (e) {
      setState(() => _error = e.toString());
      _showSnack('Failed to read sheet "$sheetName": $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _goPrev() async {
    if (_currentPage <= 0) return;
    setState(() => _currentPage -= 1);
  }

  Future<void> _goNext() async {
    final totalPages = (_rows.length / _pageSize).ceil();
    if (_currentPage >= totalPages - 1) return;
    setState(() => _currentPage += 1);
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _startFileWatcher(String filePath) async {
    try {
      await _stopFileWatcher();

      final file = File(filePath);
      if (!await file.exists()) return;

      _fileWatcher = FileWatcher(filePath);
      _fileWatcherSubscription = _fileWatcher!.events.listen(
        (event) async {
          debugPrint('File watcher event: ${event.type}');
          // Only react to modify events (file content changes)
          if (event.type == ChangeType.MODIFY && !_isRefreshing) {
            await _refreshFromFile();
          }
        },
        onError: (error) {
          debugPrint('File watcher error: $error');
        },
      );
    } catch (e) {
      debugPrint('Failed to start file watcher: $e');
    }
  }

  Future<void> _stopFileWatcher() async {
    await _fileWatcherSubscription?.cancel();
    _fileWatcherSubscription = null;
    _fileWatcher = null;
  }

  Future<void> _refreshFromFile() async {
    if (_filePath == null || _isRefreshing) return;

    _isRefreshing = true;

    try {
      // Stop watcher temporarily to prevent multiple simultaneous refreshes
      await _stopFileWatcher();

      final file = File(_filePath!);
      if (!await file.exists()) {
        _showSnack('File no longer exists');
        _isRefreshing = false;
        return;
      }

      // Try to read the file
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final names = excel.tables.keys.toList();

      // Preserve current sheet and header row settings
      final currentSheet = _selectedSheet;

      setState(() {
        _workbook = excel;
        _sheetNames = names;
        // Try to keep the same sheet selection, or select first if it doesn't exist
        if (currentSheet != null && names.contains(currentSheet)) {
          _selectedSheet = currentSheet;
        } else if (names.isNotEmpty) {
          _selectedSheet = names.first;
        } else {
          _selectedSheet = null;
        }
      });

      // Reload current sheet data
      if (_selectedSheet != null) {
        await _loadSheet(_selectedSheet!);
      }

      // Restart watcher
      await _startFileWatcher(_filePath!);
    } catch (e) {
      debugPrint('Failed to refresh from file: $e');
      // If file is locked or cannot be read, show error
      if (e.toString().contains('locked') ||
          e.toString().contains('access') ||
          e.toString().contains('permission')) {
        _showSnack('File is locked by another application');
      } else {
        _showSnack('Failed to refresh: $e');
      }
      // Restart watcher even on error so we can catch next change
      await _startFileWatcher(_filePath!);
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  void dispose() {
    _headerRowController.dispose();
    _stopFileWatcher();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _fileName == null ? 'XLSX Viewer' : 'XLSX: $_fileName';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 12.0),
            child: Center(child: Text(_filePath ?? '')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FilledButton.icon(
              onPressed: _pickXlsx,
              icon: const Icon(Icons.folder_open),
              label: const Text('Open XLSX'),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                const Text('Sheet:'),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedSheet,
                    hint: const Text('Select a sheet'),
                    items: _sheetNames
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        _loadSheet(value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: _headerRowController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Header row',
                      hintText: '1-based',
                      isDense: true,
                    ),
                    onSubmitted: (_) {
                      final sheet = _selectedSheet;
                      if (sheet != null) {
                        _loadSheet(sheet);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final sheet = _selectedSheet;
                    if (sheet != null) {
                      _loadSheet(sheet);
                    }
                  },
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_headers.isEmpty)
            const Expanded(
              child: Center(child: Text('Open a .xlsx and select a sheet')),
            )
          else
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: DataTableView(
                  headers: _headers,
                  rows: _pagedRows(),
                  totalCount: _rows.length,
                  pageSize: _pageSize,
                  currentPage: _currentPage,
                  onPrev: _goPrev,
                  onNext: _goNext,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Map<String, Object?>> _pagedRows() {
    final start = _currentPage * _pageSize;
    final end = (start + _pageSize).clamp(0, _rows.length);
    if (start >= _rows.length) return const [];
    return _rows.sublist(start, end);
  }
}
