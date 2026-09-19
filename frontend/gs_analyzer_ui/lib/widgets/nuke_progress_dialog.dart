import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/nuke_provider.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';
import '../services/api_service.dart';

class NukeProgressDialog extends ConsumerWidget {
  const NukeProgressDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(nukeProgressProvider);
    final target = ref.watch(nukeTargetProvider);
    final completed = ref.watch(nukeCompletedProvider);

    return PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: HudTheme.bgPanel,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: HudTheme.accentRed, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        title: const Text('NUKE IN PROGRESS...', style: HudTheme.actionRed),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Target: $target',
              style: HudTheme.bodyText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              'Completed: $completed',
              style: HudTheme.bodyText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress / 100,
              color: HudTheme.accentRed,
              backgroundColor: Colors.white10,
              minHeight: 8,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${progress.toStringAsFixed(1)}%',
                style: HudTheme.actionRed,
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: HudTheme.accentRed.withValues(alpha: 0.2),
              foregroundColor: HudTheme.accentRed,
              side: const BorderSide(color: HudTheme.accentRed),
            ),
            icon: const Icon(Icons.cancel_outlined, color: HudTheme.accentRed),
            label: const Text(
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
