import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/models/extension_breakdown_model.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/providers/extension_breakdown_provider.dart';
import 'package:gs_analyzer_ui/providers/file_type_provider.dart';
import 'package:gs_analyzer_ui/utils/csv_exporter.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';

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

    return Scaffold(
      backgroundColor: HudTheme.bgBase,
      appBar: AppBar(
        backgroundColor: HudTheme.bgPanel,
        elevation: 0,
        title: Text(
          'EXTENSION_BREAKDOWN_${widget.driveName.replaceAll(' ', '_')}',
          style: HudTheme.headerCyan,
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(
              Icons.download,
              color: HudTheme.accentCyan,
              size: 18,
            ),
            label: const Text(
              'CSV',
              style: TextStyle(color: HudTheme.accentCyan),
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
        loading: () => const Center(
          child: CircularProgressIndicator(color: HudTheme.accentCyan),
        ),
        error: (e, _) {
          if (e is FileTypeNoScanException) {
            return _buildNoScanView();
          }
          return Center(child: Text('ERROR: $e', style: HudTheme.actionRed));
        },
        data: (result) => _buildDataView(context, ref, result),
      ),
    );
  }

  Widget _buildNoScanView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: HudTheme.accentAmber,
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            'RUN A SCAN FIRST',
            style: HudTheme.headerCyan.copyWith(color: HudTheme.accentAmber),
          ),
          const SizedBox(height: 8),
          const Text(
            'No scan data cached for this drive.\nPlease return to the dashboard and initiate a scan.',
            style: HudTheme.bodyText,
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
      color: HudTheme.bgPanel,
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
                    color: isSorted ? HudTheme.accentCyan : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSorted)
                Icon(
                  isAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  color: HudTheme.accentCyan,
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
    final catColor = HudTheme.fileTypeColor(item.category);

    return InkWell(
      onTap: () => _showDetailSheet(context, ref, item, catColor),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white10)),
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
                      style: const TextStyle(
                        color: Colors.white,
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
                style: HudTheme.statCyan,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                item.sizeFormatted,
                style: HudTheme.statCyan,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                item.averageSizeFormatted,
                style: HudTheme.statCyan,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            Expanded(
              flex: 1,
              child: Text(
                '${item.percentOfDisk}%',
                style: HudTheme.statCyan,
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

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search extensions...',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
              filled: true,
              fillColor: HudTheme.bgPanel,
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
                final catColor = HudTheme.fileTypeColor(cat);
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    label: Text(
                      cat.toUpperCase(),
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: HudTheme.accentCyan,
                    backgroundColor: catColor.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                      side: BorderSide(
                        color: isSelected
                            ? HudTheme.accentCyan
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: HudTheme.bgPanel,
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
              const Divider(color: Colors.white10),
              const SizedBox(height: 16),
              Text(
                'LARGEST FILE RECORDED',
                style: HudTheme.labelMuted.copyWith(color: HudTheme.accentCyan),
              ),
              const SizedBox(height: 8),
              if (item.largestFilePath.isEmpty)
                const Text(
                  'No file path recorded.',
                  style: TextStyle(color: Colors.white54),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.largestFilePath,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.largestSizeFormatted,
                      style: const TextStyle(
                        color: HudTheme.accentAmber,
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
                            backgroundColor: Colors.white12,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: item.largestFilePath),
                            );
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Path copied to clipboard'),
                                backgroundColor: HudTheme.bgPanel,
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
                            backgroundColor: HudTheme.accentCyan.withValues(
                              alpha: 0.1,
                            ),
                            foregroundColor: HudTheme.accentCyan,
                            side: const BorderSide(color: HudTheme.accentCyan),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: HudTheme.statCyan.copyWith(fontSize: 16)),
      ],
    );
  }
}
