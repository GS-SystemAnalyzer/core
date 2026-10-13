import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/models/extension_breakdown_model.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/providers/extension_breakdown_provider.dart';
import 'package:gs_analyzer_ui/providers/file_type_provider.dart';
import 'package:gs_analyzer_ui/utils/csv_exporter.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';

class ExtensionBreakdownScreen extends ConsumerStatefulWidget {
  final String scanRoot;
  final String driveName;

  const ExtensionBreakdownScreen({
    super.key,
    required this.scanRoot,
    required this.driveName,
  });

  @override
  ConsumerState<ExtensionBreakdownScreen> createState() =>
      _ExtensionBreakdownScreenState();
}

class _ExtensionBreakdownScreenState
    extends ConsumerState<ExtensionBreakdownScreen> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncResult = ref.watch(extensionBreakdownProvider(widget.scanRoot));
    final hud = context.hudTheme;

    return Scaffold(
      backgroundColor: hud.base,
      appBar: AppBar(
        backgroundColor: hud.panel,
        elevation: 0,
        title: Text(
          'EXTENSION_BREAKDOWN_${widget.driveName.replaceAll(' ', '_')}',
          style: hud.header,
        ),
        actions: [
          TextButton.icon(
            icon: Icon(
              Icons.download,
              color: hud.accentCyan,
              size: 18,
            ),
            label: Text(
              'CSV',
              style: TextStyle(color: hud.accentCyan),
            ),
            onPressed: () {
              final items = ref.read(
                filteredExtensionBreakdownProvider(widget.scanRoot),
              );
              if (items.isNotEmpty) {
                CsvExporter.exportExtensionBreakdown(context, items);
              }
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: asyncResult.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: hud.accentCyan),
        ),
        error: (e, _) {
          if (e is FileTypeNoScanException) {
            return _buildNoScanView();
          }
          return Center(child: Text('ERROR: $e', style: hud.actionRed));
        },
        data: (result) => _buildDataView(context, ref, result),
      ),
    );
  }

  Widget _buildNoScanView() {
    final hud = context.hudTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: hud.accentAmber,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'RUN A SCAN FIRST',
            style: hud.header.copyWith(color: hud.accentAmber),
          ),
          const SizedBox(height: 8),
          Text(
            'No scan data cached for this drive.\nPlease return to the dashboard and initiate a scan.',
            style: hud.body,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDataView(
    BuildContext context,
    WidgetRef ref,
    ExtensionBreakdownResult result,
  ) {
    final filteredItems = ref.watch(
      filteredExtensionBreakdownProvider(widget.scanRoot),
    );

    return Column(
      children: [
        _buildFilters(context, ref, result.extensions),
        _buildHeaderRow(ref),
        Expanded(
          child: ListView.builder(
            itemCount: filteredItems.length,
            itemExtent: 44, // Fixed height for performance
            itemBuilder: (context, index) {
              final item = filteredItems[index];
              return _buildListRow(context, ref, item);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderRow(WidgetRef ref) {
    return Container(
      color: context.hudTheme.panel,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _buildSortableHeader(ref, 'Ext', 'ext', flex: 2),
          _buildSortableHeader(ref, 'Category', 'category', flex: 2),
          _buildSortableHeader(
            ref,
            'Files',
            'fileCount',
            flex: 1,
            numeric: true,
          ),
          _buildSortableHeader(
            ref,
            'Total Size',
            'totalBytes',
            flex: 2,
            numeric: true,
          ),
          _buildSortableHeader(
            ref,
            'Avg Size',
            'averageFileSizeBytes',
            flex: 2,
            numeric: true,
          ),
          _buildSortableHeader(
            ref,
            '% Disk',
            'percentOfDisk',
            flex: 1,
            numeric: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSortableHeader(
    WidgetRef ref,
    String label,
    String key, {
    required int flex,
    bool numeric = false,
  }) {
    final currentSort = ref.watch(ebSortColumnProvider);
    final isAscending = ref.watch(ebSortAscendingProvider);
    final isSorted = currentSort == key;
    final hud = context.hudTheme;

    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () {
          ref.read(ebSortColumnProvider.notifier).state = key;
          if (isSorted) {
            ref.read(ebSortAscendingProvider.notifier).state = !isAscending;
          } else {
            ref.read(ebSortAscendingProvider.notifier).state =
                false; // default desc on new col
          }
        },
        child: Container(
          alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSorted ? hud.accentCyan : hud.textMuted,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSorted)
                Icon(
                  isAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  color: hud.accentCyan,
                  size: 16,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildListRow(
    BuildContext context,
    WidgetRef ref,
    ExtensionBreakdownItem item,
  ) {
    final hud = context.hudTheme;
    final catColor = hud.fileTypeColor(item.category);

    return InkWell(
      onTap: () => _showDetailSheet(context, ref, item, catColor),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: hud.textMain.withValues(alpha: 0.10))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: catColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      item.ext,
                      style: TextStyle(
                        color: hud.textMain,
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                item.category.toUpperCase(),
                style: TextStyle(color: catColor, fontSize: 12),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                '${item.fileCount}',
                style: hud.statCyan,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                item.sizeFormatted,
                style: hud.statCyan,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                item.averageSizeFormatted,
                style: hud.statCyan,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                '${item.percentOfDisk}%',
                style: hud.statCyan,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(
    BuildContext context,
    WidgetRef ref,
    List<ExtensionBreakdownItem> allItems,
  ) {
    final selectedCategories = ref.watch(ebSelectedCategoriesProvider);
    final allCategories = allItems.map((e) => e.category).toSet().toList()
      ..sort();
    final hud = context.hudTheme;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: hud.textMain.withValues(alpha: 0.10))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            style: TextStyle(color: hud.textMain),
            decoration: InputDecoration(
              hintText: 'Search extensions...',
              hintStyle: TextStyle(color: hud.textMain.withValues(alpha: 0.38)),
              prefixIcon: Icon(Icons.search, color: hud.textMain.withValues(alpha: 0.38)),
              filled: true,
              fillColor: hud.panel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) {
              if (_debounce?.isActive ?? false) _debounce!.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () {
                ref.read(ebSearchQueryProvider.notifier).state = val;
              });
            },
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: allCategories.map((cat) {
                final isSelected = selectedCategories.contains(cat);
                final catColor = hud.fileTypeColor(cat);
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    label: Text(
                      cat.toUpperCase(),
                      style: TextStyle(
                        color: isSelected ? hud.textPaint : hud.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: hud.accentCyan,
                    backgroundColor: catColor.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: BorderSide(
                        color: isSelected
                            ? hud.accentCyan
                            : catColor.withValues(alpha: 0.3),
                      ),
                    ),
                    onSelected: (selected) {
                      final notif = ref.read(
                        ebSelectedCategoriesProvider.notifier,
                      );
                      if (selected) {
                        notif.state = {...notif.state, cat};
                      } else {
                        notif.state = notif.state
                            .where((c) => c != cat)
                            .toSet();
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _showDetailSheet(
    BuildContext context,
    WidgetRef ref,
    ExtensionBreakdownItem item,
    Color catColor,
  ) {
    final hud = context.hudTheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: hud.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: catColor.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      item.ext,
                      style: TextStyle(
                        color: catColor,
                        fontSize: 20,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    item.category.toUpperCase(),
                    style: TextStyle(
                      color: catColor,
                      fontSize: 14,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _DetailStat(label: 'TOTAL FILES', value: '${item.fileCount}'),
                  _DetailStat(label: 'TOTAL SIZE', value: item.sizeFormatted),
                  _DetailStat(
                    label: 'AVG SIZE',
                    value: item.averageSizeFormatted,
                  ),
                  _DetailStat(label: '% DISK', value: '${item.percentOfDisk}%'),
                ],
              ),
              const SizedBox(height: 24),
              Divider(color: hud.textMain.withValues(alpha: 0.10)),
              const SizedBox(height: 16),
              Text(
                'LARGEST FILE RECORDED',
                style: hud.label.copyWith(color: hud.accentCyan),
              ),
              const SizedBox(height: 8),
              if (item.largestFilePath.isEmpty)
                Text(
                  'No file path recorded.',
                  style: TextStyle(color: hud.textDim),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.largestFilePath,
                      style: TextStyle(
                        color: hud.textMain,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.largestSizeFormatted,
                      style: TextStyle(
                        color: hud.accentAmber,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('COPY PATH'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: hud.textMain.withValues(alpha: 0.12),
                            foregroundColor: hud.textMain,
                          ),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: item.largestFilePath),
                            );
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Path copied to clipboard'),
                                backgroundColor: hud.panel,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.folder_open, size: 16),
                          label: const Text('FIND IN EXPLORER'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: hud.accentCyan.withValues(
                              alpha: 0.1,
                            ),
                            foregroundColor: hud.accentCyan,
                            side: BorderSide(color: hud.accentCyan),
                          ),
                          onPressed: () {
                            // Close bottom sheet
                            Navigator.pop(ctx);
                            // Close extension breakdown screen to go back to dashboard
                            Navigator.pop(context);
                            // Set directory provider to parent directory
                            final path = item.largestFilePath;
                            final parentDir = path.substring(
                              0,
                              path.lastIndexOf(RegExp(r'[\\/]')),
                            );
                            ref
                                .read(directoryProvider.notifier)
                                .scanDirectory(parentDir);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DetailStat extends StatelessWidget {
  final String label;
  final String value;
  const _DetailStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final hud = context.hudTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: hud.textMain.withValues(alpha: 0.38),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: hud.statCyan.copyWith(fontSize: 16)),
      ],
    );
  }
}
