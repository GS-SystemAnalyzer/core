import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/temp_cleaner_provider.dart';
import 'package:gs_analyzer_ui/providers/minimized_ops_provider.dart';
import 'package:gs_analyzer_ui/utils/hud_theme.dart';

class TempCleanProgressDialog extends ConsumerStatefulWidget {
  const TempCleanProgressDialog({super.key});

  @override
  ConsumerState<TempCleanProgressDialog> createState() =>
      _TempCleanProgressDialogState();
}

class _TempCleanProgressDialogState
    extends ConsumerState<TempCleanProgressDialog> {
  @override
  Widget build(BuildContext context) {
    // Self-close when cleaning finishes — unless minimised (then the dialog is
    // already gone and the pill carries it to completion).
    ref.listen<bool>(
      tempCleanerProvider.select((s) => s.isCleaning),
      (prev, next) {
        if (!next && mounted && !ref.read(tempCleanMinimizedProvider)) {
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        }
      },
    );

    final progress = ref.watch(tempCleanProgressProvider);
    final target = ref.watch(tempCleanTargetProvider);
    final completed = ref.watch(tempCleanCompletedProvider);
    final total = ref.watch(tempCleanTotalProvider);

    final double progressValue = total > 0
        ? (completed / total).clamp(0.0, 1.0)
        : (progress / 100).clamp(0.0, 1.0);

    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: HudTheme.bgPanel,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: HudTheme.accentGreen, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.cleaning_services_outlined,
              color: HudTheme.accentGreen,
              size: 24,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'PURGING TEMP SECTORS...',
                style: TextStyle(
                  color: HudTheme.accentGreen,
                  fontFamily: HudTheme.fontCore,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.remove, color: HudTheme.accentGreen),
              tooltip: 'Minimize',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                ref.read(tempCleanMinimizedProvider.notifier).state = true;
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                target.isNotEmpty ? 'Target: $target' : 'Target: INITIALIZING...',
                style: HudTheme.bodyText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                total > 0 ? 'Completed: $completed of $total' : 'Completed: $completed',
                style: HudTheme.bodyText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: progressValue,
                color: HudTheme.accentGreen,
                backgroundColor: Colors.white10,
                minHeight: 8,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${progress.toStringAsFixed(1)}%',
                  style: HudTheme.statGreen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
