import 'package:flutter/material.dart';
import '../db/database_service.dart';

class DataTableView extends StatelessWidget {
  final List<String> headers;
  final List<Map<String, Object?>> rows;
  final int totalCount;
  final int pageSize;
  final int currentPage; // zero-based
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const DataTableView({
    super.key,
    required this.headers,
    required this.rows,
    required this.totalCount,
    required this.pageSize,
    required this.currentPage,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final totalPages = (totalCount / pageSize).ceil();
    final isFirst = currentPage <= 0;
    final isLast = currentPage >= (totalPages - 1) || totalPages == 0;

    final columns = headers
        .map((h) => DataColumn(label: Text(h, overflow: TextOverflow.ellipsis)))
        .toList();

    final dataRows = rows.map((row) {
      return DataRow(
        cells: headers
            .map(
              (h) => DataCell(
                Tooltip(
                  message: DatabaseService.formatCellValue(row[h]),
                  child: SizedBox(
                    width: 200,
                    child: Text(
                      DatabaseService.formatCellValue(row[h]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: row[h] == null
                          ? TextStyle(color: Theme.of(context).hintColor)
                          : null,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: headers.length * 276,
                child: Scrollbar(
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    child: DataTable(
                      columns: columns,
                      rows: dataRows,
                      headingRowHeight: 48,
                      dataRowMinHeight: 40,
                      dataRowMaxHeight: 56,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Rows: $totalCount  •  Page ${totalPages == 0 ? 0 : (currentPage + 1)} of $totalPages'),
            Row(
              children: [
                IconButton(onPressed: isFirst ? null : onPrev, icon: const Icon(Icons.chevron_left)),
                IconButton(onPressed: isLast ? null : onNext, icon: const Icon(Icons.chevron_right)),
              ],
            )
          ],
        )
      ],
    );
  }

  // Formatting handled by DatabaseService.formatCellValue
}


