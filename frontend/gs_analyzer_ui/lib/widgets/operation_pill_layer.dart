import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/providers/telemetry_provider.dart';
import 'package:gs_analyzer_ui/providers/nuke_provider.dart';
import 'package:gs_analyzer_ui/providers/temp_cleaner_provider.dart';
import 'package:gs_analyzer_ui/providers/minimized_ops_provider.dart';
import 'package:gs_analyzer_ui/providers/navigation_provider.dart';
import 'package:gs_analyzer_ui/providers/storage_view_provider.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/globals.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';
import 'package:gs_analyzer_ui/widgets/minimized_op_pill.dart';
import 'package:gs_analyzer_ui/widgets/nuke_progress_dialog.dart';
import 'package:gs_analyzer_ui/widgets/temp_clean_progress_dialog.dart';
import 'package:gs_analyzer_ui/widgets/export_scan_dialog.dart';

/// Mounted in [MaterialApp.builder] above the Navigator so pills survive every
/// route change. Renders a pill for each operation that is active AND minimised.
class OperationPillLayer extends ConsumerStatefulWidget {
  const OperationPillLayer({super.key});

  @override
  ConsumerState<OperationPillLayer> createState() => _OperationPillLayerState();
}

class _OperationPillLayerState extends ConsumerState<OperationPillLayer> {
  Timer? _scanCompleteTimer;
  bool _dragging = false;

  @override
  void dispose() {
    _scanCompleteTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact =
        ref.watch(
          settingsProvider.select(
            (s) => s.currentSettings?.appearance.compactMode ?? false,
          ),
        );
    final offset = ref.watch(scanPillOffsetProvider);

    final pills = <Widget>[];

    _maybeAddScanPill(pills, compact);
    _maybeAddNukePill(pills, compact);
    _maybeAddTempCleanPill(pills, compact);
    _maybeAddExportPill(pills, compact);

    if (pills.isEmpty) return const SizedBox.shrink();

    final media = MediaQuery.of(context);
    // Clamp the anchor into the visible window. A negative dy anchors from the
    // bottom edge.
    final size = media.size;
    final left = offset.dx.clamp(0.0, (size.width - 220).clamp(0.0, size.width));
    final bottom = (offset.dy < 0 ? -offset.dy : offset.dy).clamp(
      16.0,
      (size.height - 72).clamp(16.0, size.height),
    );

    return Positioned(
      left: left,
      bottom: bottom,
      child: MouseRegion(
        cursor: _dragging
            ? SystemMouseCursors.grabbing
            : SystemMouseCursors.grab,
        child: GestureDetector(
          onPanStart: (_) {
            if (!_dragging) setState(() => _dragging = true);
          },
          onPanUpdate: (d) {
            final cur = ref.read(scanPillOffsetProvider);
            // Drag: x follows pointer, y stored as distance from bottom.
            final newDx = (cur.dx + d.delta.dx).clamp(0.0, size.width - 220);
            final newBottom = (bottom - d.delta.dy).clamp(16.0, size.height - 72);
            ref.read(scanPillOffsetProvider.notifier).update(
              Offset(newDx, -newBottom),
            );
          },
          onPanEnd: (_) {
            if (_dragging) setState(() => _dragging = false);
          },
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in pills) ...[p, const SizedBox(height: 8)],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Scan -----------------------------------------------------------------

  void _maybeAddScanPill(List<Widget> pills, bool compact) {
    final minimized = ref.watch(scanMinimizedProvider);
    if (!minimized) {
      _scanCompleteTimer?.cancel();
      _scanCompleteTimer = null;
      return;
    }

    final isLoading = ref.watch(
      directoryProvider.select((s) => s.isLoading),
    );
    final telemetry = ref.watch(telemetryProvider);
    final hud = context.hudTheme;

    final status = telemetry.status.toUpperCase();
    final isComplete = status == 'COMPLETED';
    final isFailed = status == 'FAILED';

    if (isComplete) {
      // Green pill, auto-dismiss after 10s.
      _scanCompleteTimer ??= Timer(const Duration(seconds: 10), () {
        if (mounted) {
          ref.read(scanMinimizedProvider.notifier).state = false;
        }
      });
      pills.add(
        MinimizedOpPill(
          key: const Key('pill_scan'),
          label: 'SCAN COMPLETE — TAP TO VIEW',
          accent: hud.accentGreen,
          progress: 1.0,
          target: telemetry.target,
          compact: compact,
          state: OpVisualState.complete,
          onRestore: _restoreScan,
        ),
      );
      return;
    }

    if (isFailed) {
      // Red pill, no auto-dismiss.
      _scanCompleteTimer?.cancel();
      _scanCompleteTimer = null;
      pills.add(
        MinimizedOpPill(
          key: const Key('pill_scan'),
          label: 'SCAN FAILED — TAP FOR DETAIL',
          accent: hud.accentRed,
          progress: null,
          target: telemetry.target,
          compact: compact,
          state: OpVisualState.failed,
          onRestore: _restoreScan,
        ),
      );
      return;
    }

    // Active scan.
    if (!isLoading) return;
    _scanCompleteTimer?.cancel();
    _scanCompleteTimer = null;
    final progress = telemetry.total > 0
        ? telemetry.completed / telemetry.total
        : null;
    pills.add(
      MinimizedOpPill(
        key: const Key('pill_scan'),
        label: 'SCANNING',
        accent: hud.accentCyan,
        progress: progress,
        target: telemetry.target,
        compact: compact,
        onRestore: _restoreScan,
        onAbort: () async {
          await ApiService().abortScan();
          ref.read(directoryProvider.notifier).purgeStaleCache();
          ref.read(scanMinimizedProvider.notifier).state = false;
          snackbarKey.currentState?.showSnackBar(
            const SnackBar(content: Text('Scan Aborted')),
          );
        },
      ),
    );
  }

  void _restoreScan() {
    _scanCompleteTimer?.cancel();
    _scanCompleteTimer = null;
    ref.read(scanMinimizedProvider.notifier).state = false;
    // Bring the Storage/analyzer view forward so the full card is visible.
    ref.read(navigationProvider.notifier).state = AppRoute.storage;
    ref.read(storageViewProvider.notifier).state = StorageView.analyzer;
  }

  // ---- Nuke -----------------------------------------------------------------

  void _maybeAddNukePill(List<Widget> pills, bool compact) {
    final minimized = ref.watch(nukeMinimizedProvider);
    final active = ref.watch(isNukeActiveProvider);
    if (!minimized || !active) return;

    final hud = context.hudTheme;
    final progress = ref.watch(nukeProgressProvider);
    final target = ref.watch(nukeTargetProvider);

    pills.add(
      MinimizedOpPill(
        key: const Key('pill_nuke'),
        label: 'NUKING',
        accent: hud.accentRed,
        progress: (progress / 100).clamp(0.0, 1.0),
        target: target,
        compact: compact,
        onRestore: () {
          ref.read(nukeMinimizedProvider.notifier).state = false;
          final ctx = rootNavigatorKey.currentContext;
          if (ctx != null) {
            showDialog(
              context: ctx,
              barrierDismissible: false,
              builder: (_) => const NukeProgressDialog(),
            );
          }
        },
        onAbort: () async {
          await ApiService().abortNuke();
        },
      ),
    );
  }

  // ---- Temp clean -----------------------------------------------------------

  void _maybeAddTempCleanPill(List<Widget> pills, bool compact) {
    final minimized = ref.watch(tempCleanMinimizedProvider);
    final active = ref.watch(
      tempCleanerProvider.select((s) => s.isCleaning),
    );
    if (!minimized || !active) return;

    final hud = context.hudTheme;
    final progress = ref.watch(tempCleanProgressProvider);
    final target = ref.watch(tempCleanTargetProvider);

    pills.add(
      MinimizedOpPill(
        key: const Key('pill_tempclean'),
        label: 'PURGING TEMP',
        accent: hud.accentGreen,
        progress: (progress / 100).clamp(0.0, 1.0),
        target: target,
        compact: compact,
        onRestore: () {
          ref.read(tempCleanMinimizedProvider.notifier).state = false;
          final ctx = rootNavigatorKey.currentContext;
          if (ctx != null) {
            showDialog(
              context: ctx,
              barrierDismissible: false,
              builder: (_) => const TempCleanProgressDialog(),
            );
          }
        },
      ),
    );
  }

  // ---- Export ---------------------------------------------------------------

  void _maybeAddExportPill(List<Widget> pills, bool compact) {
    final minimized = ref.watch(exportMinimizedProvider);
    final active = ref.watch(exportActiveProvider);
    if (!minimized || !active) return;

    final hud = context.hudTheme;
    final drive = ref.watch(exportDriveProvider);

    pills.add(
      MinimizedOpPill(
        key: const Key('pill_export'),
        label: 'EXPORTING',
        accent: hud.accentCyan,
        progress: null,
        target: drive ?? '',
        compact: compact,
        onRestore: () {
          ref.read(exportMinimizedProvider.notifier).state = false;
          final ctx = rootNavigatorKey.currentContext;
          if (ctx != null && drive != null) {
            showDialog(
              context: ctx,
              builder: (_) => ExportScanDialog(driveName: drive),
            );
          }
        },
      ),
    );
  }
}
