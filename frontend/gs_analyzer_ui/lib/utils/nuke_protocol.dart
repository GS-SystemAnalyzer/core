import 'package:gs_analyzer_ui/utils/logger.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/providers/drive_stats_provider.dart';
import 'package:gs_analyzer_ui/providers/nuke_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/providers/root_tree_provider.dart';
import 'package:gs_analyzer_ui/utils/globals.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';
import '../widgets/nuke_preview_dialog.dart';
import '../widgets/nuke_progress_dialog.dart';
import '../widgets/undo_history_panel.dart';

Future<void> executeNukeProtocol(
  BuildContext context,
  WidgetRef ref, {
  String? fileName,
  String? filePath,
  List<String>? customPath,
  VoidCallback? onComplete,
}) async {
  final dirState = ref.read(directoryProvider);
  final dirNotifier = ref.read(directoryProvider.notifier);
  final List<String> targetsToNuke =
      customPath ??
      (dirState.isSelectionMode && dirState.selectedPath.isNotEmpty
          ? dirState.selectedPath.toList()
          : (fileName != null ? [filePath!] : []));

  if (targetsToNuke.isEmpty) return;

  final isBulk = targetsToNuke.length > 1;

  ref.invalidate(nukeProgressProvider);
  ref.invalidate(nukeCompletedProvider);
  ref.invalidate(nukeTargetProvider);

  final previewResult = await showDialog<NukePreviewResult>(
    context: context,
    barrierDismissible: false,
    builder: (context) => NukePreviewDialog(targetPaths: targetsToNuke),
  );

  if (previewResult == null || !previewResult.confirmed) {
    appLogger.i(
      'MATRIX: Nuke Sequence Aborted by System Administrator at Preview',
    );
    return;
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => NukeProgressDialog(),
  );

  final masterNavigator = Navigator.of(context, rootNavigator: true);
  try {
    final api = ApiService();
    final result = await api.executeNuke(
      targetsToNuke,
      previewResult.planToken,
      useRecycleBin: previewResult.useRecycleBin,
    );

    masterNavigator.pop();

    if (onComplete != null) {
      onComplete();
    } else {
      if (dirState.isSelectionMode) {
        dirNotifier.toggleSelectionMode();
      }
      final currentPath = ref.read(directoryProvider).currentPath;
      await ref.read(directoryProvider.notifier).scanDirectory(currentPath);
    }

    ref.invalidate(rootTreeProvider);
    ref.read(drivesProvider.notifier).refresh();
    ref.invalidate(undoHistoryProvider);

    if (result.recycleBinUsed) {
      snackbarKey.currentState?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 15),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${result.stagedFormatted} MOVED TO RECYCLE BIN',
                style: const TextStyle(
                  fontFamily: HudTheme.fontCore,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () async {
                  snackbarKey.currentState?.hideCurrentSnackBar();
                  try {
                    final undoResult = await api.undoNuke();
                    snackbarKey.currentState?.showSnackBar(
                      SnackBar(
                        content: Text(
                          'RESTORED ${undoResult.deletedFiles} FILES',
                          style: const TextStyle(
                            fontFamily: HudTheme.fontCore,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        backgroundColor: HudTheme.accentGreen,
                      ),
                    );
                    // Refresh directory view
                    ref.invalidate(rootTreeProvider);
                    ref.read(drivesProvider.notifier).refresh();
                    final currentPath = ref.read(directoryProvider).currentPath;
                    await ref
                        .read(directoryProvider.notifier)
                        .scanDirectory(currentPath);
                  } catch (e) {
                    snackbarKey.currentState?.showSnackBar(
                      SnackBar(
                        content: Text(
                          'UNDO FAILED: $e',
                          style: const TextStyle(fontFamily: HudTheme.fontCore),
                        ),
                        backgroundColor: HudTheme.accentRed,
                      ),
                    );
                  }
                },
                child: const Text(
                  '[UNDO]',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: HudTheme.accentAmber,
        ),
      );
    } else {
      snackbarKey.currentState?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            '${result.freedFormatted} PERMANENTLY DELETED',
            style: const TextStyle(
              fontFamily: HudTheme.fontCore,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: HudTheme.accentGreen,
        ),
      );
    }
  } catch (e) {
    masterNavigator.pop();
    snackbarKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          'ERROR: $e',
          style: TextStyle(fontFamily: HudTheme.fontCore),
        ),
        backgroundColor: HudTheme.accentRed,
      ),
    );
  } finally {
    ref.invalidate(nukeProgressProvider);
    ref.invalidate(nukeCompletedProvider);
    ref.invalidate(nukeTargetProvider);
  }
}
