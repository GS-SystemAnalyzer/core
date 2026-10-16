import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/nuke_provider.dart';
import 'package:gs_analyzer_ui/providers/minimized_ops_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';
import '../services/api_service.dart';

class NukeProgressDialog extends ConsumerStatefulWidget {
  const NukeProgressDialog({super.key});

  @override
  ConsumerState<NukeProgressDialog> createState() => _NukeProgressDialogState();
}

class _NukeProgressDialogState extends ConsumerState<NukeProgressDialog> {
  @override
  Widget build(BuildContext context) {
    // Self-close when the nuke finishes — unless the user minimised it (then
    // the dialog was already popped and the pill carries it to completion).
    ref.listen<bool>(isNukeActiveProvider, (prev, next) {
      if (!next && mounted && !ref.read(nukeMinimizedProvider)) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      }
    });

    final progress = ref.watch(nukeProgressProvider);
    final target = ref.watch(nukeTargetProvider);
    final completed = ref.watch(nukeCompletedProvider);
    final total = ref.watch(nukeTotalProvider);
    final hud = context.hudTheme;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: hud.panel,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: hud.accentRed, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text('NUKE IN PROGRESS...', style: hud.actionRed),
            ),
            IconButton(
              icon: Icon(Icons.remove, color: hud.accentRed),
              tooltip: 'Minimize',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                ref.read(nukeMinimizedProvider.notifier).state = true;
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Target: $target',
              style: hud.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              total > 0 ? 'Completed: $completed of $total' : 'Completed: $completed',
              style: hud.body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress / 100,
              color: hud.accentRed,
              backgroundColor: hud.textMain.withValues(alpha: 0.1),
              minHeight: 8,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${progress.toStringAsFixed(1)}%',
                style: hud.actionRed,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: hud.accentRed.withValues(alpha: 0.2),
              foregroundColor: hud.accentRed,
              side: BorderSide(color: hud.accentRed),
            ),
            icon: Icon(Icons.cancel_outlined, color: hud.accentRed),
            label: Text(
              'ABORT',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontFamily: HudTheme.fontCore,
              ),
            ),
            onPressed: () async {
              await ApiService().abortNuke();
            },
          ),
        ],
      ),
    );
  }
}
