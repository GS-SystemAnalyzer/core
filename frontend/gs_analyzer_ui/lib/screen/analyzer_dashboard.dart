import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';
import 'package:gs_analyzer_ui/widgets/_directory_search_widget.dart';
import 'package:gs_analyzer_ui/widgets/age_heatmap_overlay.dart';
import 'package:gs_analyzer_ui/widgets/directory_node_widget.dart';
import 'package:gs_analyzer_ui/widgets/drive_telemetry_widget.dart';
import 'package:gs_analyzer_ui/widgets/go_up_row_widget.dart';
import 'package:gs_analyzer_ui/widgets/telemetry_hud_widget.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/age_heatmap_provider.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import '../providers/drive_stats_provider.dart';
import '../providers/navigation_provider.dart';
import '../utils/nuke_protocol.dart';
import '../widgets/directory_table_header.dart';
import '../widgets/large_file_scanner_panel.dart';
import '../widgets/side_bar_widget.dart';
import 'package:gs_analyzer_ui/providers/storage_mode_provider.dart';
import 'package:gs_analyzer_ui/widgets/duplicate_scanner_pannel.dart';
import 'package:gs_analyzer_ui/providers/storage_view_provider.dart';
import 'package:gs_analyzer_ui/widgets/permission_audit_panel.dart';
import 'package:gs_analyzer_ui/widgets/temp_cleaner_panel.dart';

class AnalyzerDashboard extends ConsumerStatefulWidget {
  const AnalyzerDashboard({super.key});
  @override
  ConsumerState<AnalyzerDashboard> createState() => _AnalyzerDashboardState();
}

class _AnalyzerDashboardState extends ConsumerState<AnalyzerDashboard> {
  @override
  Widget build(BuildContext context) {
    final dirState = ref.watch(directoryProvider);
    final dirNotifier = ref.read(directoryProvider.notifier);
    final activeDrive = ref.watch(currentDriveProvider);
    final currentMode = ref.watch(storageModeProvider);
    final theme = context.HudTheme;
    final text = context.HudTextTheme;

    return Scaffold(
      backgroundColor: theme.panel,
      appBar: AppBar(
        title: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: theme.accentCyan),
              tooltip: 'Back to Drives',
              onPressed: () => ref.read(storageViewProvider.notifier).state =
                  StorageView.drivePicker,
            ),
            IconButton(
              icon: Icon(
                ref.watch(treeExpandedProvider)
                    ? Icons.menu_open_outlined
                    : Icons.menu_outlined,
                  color: theme.accentCyan
              ),
              tooltip: 'Toggle Data Tree',
              onPressed: () {
                final notifier = ref.read(treeExpandedProvider.notifier);
                notifier.state = !notifier.state;
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                dirState.currentPath,
                style: text.bodyMedium?.copyWith(
                  color: theme.text,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: theme.panel,
        elevation: 0,
        actions: [
          PopupMenuButton<StorageMode>(
            icon: Icon(
              Icons.build_circle_outlined,
              color: theme.accentAmber,
            ),
            tooltip: 'Storage Tools',
            color: theme.panel,
            offset: const Offset(0, 50),
            onSelected: (mode) {
              ref.read(storageModeProvider.notifier).state = mode;
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: StorageMode.duplicateScanner,
                child: Text(
                  'DUPLICATE HUNTER',
                  style: text.bodyMedium?.copyWith(
                    color: theme.accentAmber,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              PopupMenuItem(
                value: StorageMode.largeFileScanner,
                child: Text(
                  'LARGE FILE SCANNER',
                  style: text.bodyMedium?.copyWith(
                    color: theme.accentAmber,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              PopupMenuItem(
                value: StorageMode.tempFileCleaner,
                child: Text(
                  'TEMP FILE CLEANER',
                  style: text.bodyMedium?.copyWith(
                    color: theme.accentAmber,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              PopupMenuItem(
                value: StorageMode.permissionAudit,
                child: Text(
                  'PERMISSION AUDIT',
                  style: text.titleMedium?.copyWith(
                    color: theme.accentAmber,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (currentMode == StorageMode.diskAnalyzer) ...[
            // FILE AGE HEATMAP toggle
            Consumer(
              builder: (context, ref, _) {
                final isHeatmapOn = ref.watch(ageHeatmapEnabledProvider);
                return TextButton.icon(
                  icon: Icon(
                    isHeatmapOn ? Icons.thermostat : Icons.thermostat_outlined,
                    color: isHeatmapOn
                        ? theme.accentAmber
                        : theme.textDim,
                    size: 18,
                  ),
                  label: Text(
                    'AGE MAP',
                    style: text.titleMedium?.copyWith(
                      color: isHeatmapOn
                          ? theme.accentAmber
                          : theme.textDim,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 1,
                    ),
                  ),
                  onPressed: () {
                    ref.read(ageHeatmapEnabledProvider.notifier).state =
                        !isHeatmapOn;
                  },
                );
              },
            ),
            PopupMenuButton<dynamic>(
              icon: Icon(Icons.sort_outlined),
              tooltip: 'Sort Option',
              color: theme.panel,
              onSelected: (value) {
                if (value is SortMethod) {
                  ref.read(directoryProvider.notifier).setSortMethod(value);
                } else if (value is bool) {
                  ref.read(directoryProvider.notifier).setAscending(value);
                }
              },
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                  value: SortMethod.name,
                  checked: dirState.sortMethod == SortMethod.name,
                  child: Text('Name', style: text.titleMedium),
                ),
                CheckedPopupMenuItem(
                  value: SortMethod.size,
                  checked: dirState.sortMethod == SortMethod.size,
                  child: Text('Total Size', style: text.titleMedium),
                ),
                CheckedPopupMenuItem(
                  value: SortMethod.date,
                  checked: dirState.sortMethod == SortMethod.date,
                  child: Text('DateModified', style: text.titleMedium),
                ),
                const PopupMenuDivider(),
                CheckedPopupMenuItem(
                  value: true,
                  checked: dirState.isAscending == true,
                  child: Text('Ascending', style:text.titleMedium),
                ),
                CheckedPopupMenuItem(
                  value: false,
                  checked: dirState.isAscending == false,
                  child: Text('Descending', style: text.titleMedium),
                ),
              ],
            ),
            TextButton(
              onPressed: () {
                ref.read(directoryProvider.notifier).toggleSelectionMode();
              },
              child: Text(
                dirState.isSelectionMode
                    ? 'CANCEL SELECTION'
                    : 'SELECT MULTIPLE',
                style: context.HudTextTheme.titleMedium?.copyWith(
                  color: theme.accentCyan,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (dirState.isSelectionMode && dirState.selectedPath.isNotEmpty)
              IconButton(
                icon: Icon(
                  Icons.delete_forever_outlined,
                  color: theme.accentRed,
                ),
                tooltip: 'Nuke Selected (${dirState.selectedPath.length})',
                onPressed: () => executeNukeProtocol(context, ref),
              ),
            IconButton(
              icon: Icon(
                Icons.refresh_outlined,
                color: theme.accentCyan,
              ),
              tooltip: 'Refresh',
              onPressed: () => dirNotifier.scanDirectory(
                dirState.currentPath,
                forceRefresh: true,
              ),
            ),
          ],
        ],
        bottom: currentMode == StorageMode.diskAnalyzer
            ? const PreferredSize(
                preferredSize: Size.fromHeight(60),
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: DirectorySearchWidget(),
                ),
              )
            : null,
      ),
      body: activeDrive == null
          ? _buildAwaitingSelectionUI(ref)
          : Row(
              children: [
                // LEFT PANEL: Persistent Tree
                if (currentMode == StorageMode.diskAnalyzer)
                  SideBarTreeWidget(
                    onNuke: (name, path) => executeNukeProtocol(
                      context,
                      ref,
                      fileName: name,
                      filePath: path,
                    ),
                  ),
                // RIGHT PANEL: Directory Table
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: _buildMainContent(
                          context,
                          currentMode,
                          dirState,
                          dirNotifier,
                        ),
                      ),
                      const DriveTelemetryWidget(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// Picks the central panel based on the active [StorageMode] and the
  /// directory state. Extracted out of the widget tree so the nested
  /// conditionals stay readable.
  Widget _buildMainContent(
    BuildContext context,
    StorageMode currentMode,
    dynamic dirState,
    dynamic dirNotifier,
  ) {
    if (currentMode == StorageMode.duplicateScanner) {
      return const DuplicateScannerPanel();
    }
    if (currentMode == StorageMode.largeFileScanner) {
      return const LargeFileScannerPanel();
    }
    if (currentMode == StorageMode.tempFileCleaner) {
      return const TempCleanerPanel();
    }
    if (currentMode == StorageMode.permissionAudit) {
      return const PermissionAuditPanel();
    }
    // Default: disk analyzer table.
    if (dirState.isLoading) {
      return const TelemetryHudWidget();
    }
    if (dirState.errorMessage != null) {
      return Center(
        child: Text(
          'BRIDGE FAILURE: ${dirState.errorMessage}',
          style: context.HudTextTheme.displayMedium,
        ),
      );
    }
    final isHeatmapOn = ref.watch(ageHeatmapEnabledProvider);

    return Column(
      children: [
        // Age Heatmap overlay (legend + summary) Ã¢â‚¬â€ shown when toggle is on
        if (isHeatmapOn) const AgeHeatmapOverlay(),
        DirectoryTableHeader(),
        if (dirState.currentPath != 'C:/' && dirState.searchQuery.isEmpty)
          GoUpRowWidget(),
        Expanded(
          child:
              dirState.displayNodes.isEmpty && dirState.searchQuery.isNotEmpty
              ? Center(
                  child: Text(
                    'NO DATA FOUND IN SECTOR',
                    style: context.HudTextTheme.bodySmall,
                  ),
                )
              : ListView.builder(
                  itemCount: dirState.displayNodes.length,
                  itemBuilder: (context, index) {
                    return DirectoryNodeWidget(
                      node: dirState.displayNodes[index],
                      apiService: ApiService(),
                      onNuke: (name, path) => executeNukeProtocol(
                        context,
                        ref,
                        fileName: name,
                        filePath: path,
                      ),
                      onNavigate: dirNotifier.scanDirectory,
                      depth: 0,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAwaitingSelectionUI(WidgetRef ref) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(40),
        decoration: context.HudTheme.hudPanelDecoration,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storage, size: 64, color: Colors.white24),
            const SizedBox(height: 24),
            Text(
              'SYSTEM STANDBY',
              style: context.HudTextTheme.bodyMedium?.copyWith(
                color: context.HudTheme.accentCyan,
                fontSize: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Awaiting target matrix assignment for Directory Indexing.',
              style: context.HudTextTheme.titleMedium?.copyWith(color: context.HudTheme.textDim),
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              icon: Icon(Icons.touch_app, color: context.HudTheme.accentCyan),
              label: Text(
                'ASSIGN TARGET DRIVE',
                style: TextStyle(letterSpacing: 2),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                side: BorderSide(color: context.HudTheme.accentCyan),
                foregroundColor: context.HudTheme.accentCyan,
              ),
              onPressed: () {
                // Flips the sidebar to the Storage Screen (Index 1)
                ref.read(navigationProvider.notifier).state = AppRoute.storage;
              },
            ),
          ],
        ),
      ),
    );
  }
}
