import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/models/nuke_result.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';
import 'package:gs_analyzer_ui/utils/globals.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/providers/root_tree_provider.dart';
import 'package:gs_analyzer_ui/providers/drive_stats_provider.dart';
import 'package:intl/intl.dart';

final undoHistoryProvider = FutureProvider.autoDispose<List<NukeOperation>>((
  ref,
) async {
  final api = ApiService();
  return await api.getUndoHistory();
});

class UndoHistoryPanel extends ConsumerStatefulWidget {
  final ApiService apiService;
  UndoHistoryPanel({super.key, ApiService? apiService})
    : apiService = apiService ?? ApiService();

  @override
  ConsumerState<UndoHistoryPanel> createState() => _UndoHistoryPanelState();
}

class _UndoHistoryPanelState extends ConsumerState<UndoHistoryPanel> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(undoHistoryProvider);

    return Container(
      margin: const EdgeInsets.all(16.0),
      decoration: HudTheme.hudPanelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.history, color: HudTheme.accentCyan),
                      const SizedBox(width: 12),
                      Text(
                        'UNDO HISTORY',
                        style: HudTheme.headerCyan.copyWith(
                          color: HudTheme.accentCyan,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.refresh,
                          color: HudTheme.accentCyan,
                          size: 20,
                        ),
                        onPressed: () {
                          ref.invalidate(undoHistoryProvider);
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_forever,
                          color: HudTheme.accentRed,
                          size: 20,
                        ),
                        tooltip: 'Empty Recycle Bin',
                        onPressed: () async {
                          final api = widget.apiService;
                          await api.clearUndoStack();
                          ref.invalidate(undoHistoryProvider);
                          ref.read(drivesProvider.notifier).refresh();
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 16),
                      Icon(
                        _isExpanded ? Icons.expand_less : Icons.expand_more,
                        color: HudTheme.accentCyan,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded)
            historyAsync.when(
              data: (history) {
                if (history.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'NO OPERATIONS RECORDED',
                      style: HudTheme.bodyText.copyWith(
                        color: HudTheme.textDim,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: history.length,
                  separatorBuilder: (context, index) =>
                      const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (context, index) {
                    final op = history[index];
                    final timeFormatted = DateFormat(
                      'HH:mm:ss',
                    ).format(op.executedAt.toLocal());
                    final targets = op.deletedFiles;

                    return ListTile(
                      title: Text(
                        '$targets ITEMS',
                        style: const TextStyle(
                          fontFamily: HudTheme.fontCore,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      subtitle: Text(
                        timeFormatted,
                        style: TextStyle(
                          color: HudTheme.textDim,
                          fontFamily: HudTheme.fontCore,
                        ),
                      ),
                      trailing: op.usedRecycleBin
                          ? ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: HudTheme.accentAmber
                                    .withValues(alpha: 0.2),
                                side: const BorderSide(
                                  color: HudTheme.accentAmber,
                                ),
                              ),
                              onPressed: () => _handleUndo(op.operationId),
                              child: const Text(
                                'UNDO',
                                style: TextStyle(
                                  color: HudTheme.accentAmber,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '🔒 PERMANENT',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                    );
                  },
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, stack) => Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'ERROR: $err',
                  style: const TextStyle(color: HudTheme.accentRed),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleUndo(String operationId) async {
    final api = widget.apiService;
    try {
      final undoResult = await api.undoNuke(operationId);
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

      ref.invalidate(rootTreeProvider);
      ref.read(drivesProvider.notifier).refresh();
      final currentPath = ref.read(directoryProvider).currentPath;
      await ref.read(directoryProvider.notifier).scanDirectory(currentPath);

      // Refresh the history panel
      ref.invalidate(undoHistoryProvider);
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
  }
}
