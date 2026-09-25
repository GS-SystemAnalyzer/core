import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:gs_analyzer_ui/models/file_type_model.dart';
import 'package:gs_analyzer_ui/providers/file_type_provider.dart';
import 'package:gs_analyzer_ui/providers/extension_breakdown_provider.dart';
import 'package:gs_analyzer_ui/widgets/extension_breakdown_screen.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';

class FileTypeAnalyzerPanel extends ConsumerWidget {
  final String driveName;
  const FileTypeAnalyzerPanel({super.key, required this.driveName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanRoot = ref.watch(scanRootProvider(driveName));
    final asyncResult = ref.watch(fileTypesProvider(scanRoot));

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        collapsedBackgroundColor: const Color(0xFF1A1D23),
        backgroundColor: const Color(0xFF1A1D23),
        title: Row(
          children: [
            const Icon(
              Icons.grid_view_rounded,
              color: Color(0xFF00FFFF),
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              'FILE TYPE MATRIX',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(width: 12),
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => _showPathPicker(context, ref, scanRoot),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFF00FFFF).withValues(alpha: 0.35),
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.folder_open_rounded,
                      color: Color(0xFF00FFFF),
                      size: 13,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _shortenPath(scanRoot),
                      style: const TextStyle(
                        color: Color(0xFF00FFFF),
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'REFRESH FILE TYPES FROM MEMORY',
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: asyncResult.isLoading
                    ? null
                    : () {
                        ref
                            .read(
                              fileTypesRefreshTriggerProvider(
                                scanRoot,
                              ).notifier,
                            )
                            .state++;
                        ref
                            .read(
                              ebRefreshTriggerProvider(
                                scanRoot,
                              ).notifier,
                            )
                            .state++;
                        ref.invalidate(fileTypesProvider(scanRoot));
                        ref.invalidate(extensionBreakdownProvider(scanRoot));
                      },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF00FFFF).withValues(alpha: 0.35),
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: asyncResult.isLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF00FFFF),
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.refresh_rounded,
                          color: Color(0xFF00FFFF),
                          size: 14,
                        ),
                ),
              ),
            ),
          ],
        ),
        subtitle: asyncResult.whenOrNull(
          data: (result) => Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'TOTAL: ${result.totalScannedFormatted}  ·  '
              '${result.categories.length} CATEGORIES',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 11,
              ),
            ),
          ),
        ),
        children: [
          asyncResult.when(
            loading: () => const _LoadingState(),
            error: (e, _) => e is FileTypeNoScanException
                ? _NoScanState(driveName: driveName, root: scanRoot)
                : _ErrorState(error: e.toString()),
            data: (result) => _DataView(
              result: result,
              driveName: driveName,
              scanRoot: scanRoot,
            ),
          ),
        ],
      ),
    );
  }

  void _showPathPicker(BuildContext context, WidgetRef ref, String current) {
    final ctrl = TextEditingController(text: current);

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D23),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: const Color(0xFF00FFFF).withValues(alpha: 0.3),
          ),
        ),
        title: const Text(
          'SELECT SCAN ROOT',
          style: TextStyle(
            color: Color(0xFF00FFFF),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the folder path you want to analyze:',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: r'C:\Users\YourName\Projects',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.25),
                  fontSize: 12,
                ),
                filled: true,
                fillColor: const Color(0xFF0D0F14),
                prefixIcon: const Icon(
                  Icons.folder_open_rounded,
                  color: Color(0xFF00FFFF),
                  size: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: const Color(0xFF00FFFF).withValues(alpha: 0.3),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: const Color(0xFF00FFFF).withValues(alpha: 0.2),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF00FFFF)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'A Directory Scan must have been run on this path first.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 10,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'CANCEL',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00FFFF),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            icon: const Icon(Icons.search_rounded, size: 15),
            label: const Text(
              'SCAN',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
            onPressed: () {
              final newRoot = ctrl.text.trim();
              if (newRoot.isNotEmpty) {
                ref.read(scanRootProvider(driveName).notifier).state = newRoot;
                // Clear category selection from previous scan
                ref.read(selectedCategoryProvider.notifier).state = null;
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  /// Shows last 2 path segments so it doesn't overflow the header.
  String _shortenPath(String path) {
    final sep = path.contains('/') ? '/' : r'\';
    final parts = path.split(sep).where((s) => s.isNotEmpty).toList();
    if (parts.length <= 2) return path;
    return '...${sep}${parts[parts.length - 2]}${sep}${parts.last}';
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 40),
    child: Center(
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Color(0xFF00FFFF),
      ),
    ),
  );
}

class _NoScanState extends StatelessWidget {
  final String driveName;
  final String root;
  const _NoScanState({required this.driveName, required this.root});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        Icon(
          Icons.radar_rounded,
          color: Colors.white.withValues(alpha: 0.25),
          size: 40,
        ),
        const SizedBox(height: 12),
        Text(
          'No scan found for "$root"',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Run a Directory Scan on this path first, then return here.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.3),
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Text(
      error,
      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
    ),
  );
}

class _DataView extends ConsumerWidget {
  final FileTypeResult result;
  final String driveName;
  final String scanRoot;
  const _DataView({
    required this.result,
    required this.driveName,
    required this.scanRoot,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCat = ref.watch(selectedCategoryProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Donut
          SizedBox(
            width: 180,
            height: 180,
            child: _DonutChart(result: result, selected: selectedCat),
          ),
          const SizedBox(width: 24),
          // Category list
          Expanded(
            child: _CategoryList(
              result: result,
              selected: selectedCat,
              driveName: driveName,
              scanRoot: scanRoot,
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutChart extends ConsumerWidget {
  final FileTypeResult result;
  final String? selected;
  const _DonutChart({required this.result, required this.selected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = result.categories.map((cat) {
      final isSelected = selected == null || selected == cat.name;
      return PieChartSectionData(
        value: cat.percentOfDisk,
        color: HudTheme.fileTypeColor(
          cat.name,
        ).withValues(alpha: isSelected ? 1.0 : 0.25),
        radius: selected == cat.name ? 38 : 32,
        title: '',
        showTitle: false,
      );
    }).toList();

    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            sections: sections,
            centerSpaceRadius: 64,
            sectionsSpace: 2,
            pieTouchData: PieTouchData(
              touchCallback: (event, response) {
                if (!event.isInterestedForInteractions) return;
                final idx = response?.touchedSection?.touchedSectionIndex;
                if (idx == null || idx < 0) return;
                final tapped = result.categories[idx].name;
                ref
                    .read(selectedCategoryProvider.notifier)
                    .state = ref.read(selectedCategoryProvider) == tapped
                    ? null
                    : tapped;
              },
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              result.totalScannedFormatted,
              style: const TextStyle(
                color: Color(0xFF00FFFF),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'SCANNED',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 10,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CategoryList extends StatelessWidget {
  final FileTypeResult result;
  final String? selected;
  final String driveName;
  final String scanRoot;
  const _CategoryList({
    required this.result,
    required this.selected,
    required this.driveName,
    required this.scanRoot,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: result.categories.map((cat) {
        final isSelected = selected == cat.name;
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isSelected
                    ? HudTheme.fileTypeColor(cat.name)
                    : HudTheme.fileTypeColor(cat.name).withValues(alpha: 0.3),
                width: 3,
              ),
            ),
          ),
          child: ExpansionTile(
            dense: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 10),
            collapsedBackgroundColor: const Color(0xFF0D0F14),
            backgroundColor: const Color(0xFF0D0F14),
            onExpansionChanged: (_) {
              // Now we don't need ref.read here for category selection since it pushes a screen
              // Wait, ExpansionTile still needs it if it expands? It's fine to leave it or remove it.
              // We'll leave the Expansion logic for the tile but we will push the screen from an icon.
            },
            title: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: HudTheme.fileTypeColor(cat.name),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  cat.name.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  cat.sizeFormatted,
                  style: TextStyle(
                    color: HudTheme.fileTypeColor(cat.name),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${cat.percentOfDisk}%',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${cat.fileCount} f',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(width: 8),
                Consumer(
                  builder: (context, ref, child) {
                    return IconButton(
                      icon: const Icon(
                        Icons.open_in_new,
                        color: HudTheme.accentCyan,
                        size: 16,
                      ),
                      tooltip: 'View Extensions Breakdown',
                      onPressed: () {
                        ref.read(ebSelectedCategoriesProvider.notifier).state =
                            {cat.name};
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => ExtensionBreakdownScreen(
                              scanRoot: scanRoot,
                              driveName: driveName,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
                const Icon(
                  Icons.expand_more_rounded,
                  color: Colors.white38,
                  size: 16,
                ),
              ],
            ),
            children: cat.extensions
                .map(
                  (ext) => _ExtRow(
                    ext: ext,
                    catColor: HudTheme.fileTypeColor(cat.name),
                    scanRoot: scanRoot,
                    driveName: driveName,
                    category: cat.name,
                  ),
                )
                .toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _ExtRow extends ConsumerWidget {
  final FileTypeExtensionEntry ext;
  final Color catColor;
  final String scanRoot;
  final String driveName;
  final String category;
  const _ExtRow({
    required this.ext,
    required this.catColor,
    required this.scanRoot,
    required this.driveName,
    required this.category,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) => InkWell(
    onTap: () {
      ref.read(ebSelectedCategoriesProvider.notifier).state = {category};
      ref.read(ebSearchQueryProvider.notifier).state = ext.ext;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (ctx) => ExtensionBreakdownScreen(
            scanRoot: scanRoot,
            driveName: driveName,
          ),
        ),
      );
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: catColor.withValues(alpha: 0.3)),
            ),
            child: Text(
              ext.ext,
              style: TextStyle(
                color: catColor,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const Spacer(),
          Text(
            ext.sizeFormatted,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(width: 12),
          Text(
            '${ext.percentOfDisk}%',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${ext.fileCount} files',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 10,
            ),
          ),
        ],
      ),
    ),
  );
}
