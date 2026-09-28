import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/temp_cleaner_provider.dart';
import 'package:gs_analyzer_ui/utils/hud_theme.dart';

class TempCleanProgressDialog extends ConsumerWidget {
  const TempCleanProgressDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        title: const Row(
          children: [
            Icon(
              Icons.cleaning_services_outlined,
              color: HudTheme.accentGreen,
              size: 24,
            ),
            SizedBox(width: 12),
            Text(
              'PURGING TEMP SECTORS...',
              style: TextStyle(
                color: HudTheme.accentGreen,
                fontFamily: HudTheme.fontCore,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
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
