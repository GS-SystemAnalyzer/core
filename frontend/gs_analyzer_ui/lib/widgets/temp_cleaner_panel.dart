import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/storage_mode_provider.dart';
import 'package:gs_analyzer_ui/providers/temp_cleaner_provider.dart';
import 'package:gs_analyzer_ui/providers/drive_stats_provider.dart';
import 'package:gs_analyzer_ui/utils/globals.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';

class TempCleanerPanel extends ConsumerStatefulWidget {
  const TempCleanerPanel({super.key});

  @override
  _TempCleanerPanelState createState() => _TempCleanerPanelState();
}

class _TempCleanerPanelState extends ConsumerState<TempCleanerPanel> {
  @override
  Widget build(BuildContext context) {
    final tempState = ref.watch(tempCleanerProvider);
    final tempNotifier = ref.read(tempCleanerProvider.notifier);

    return Container(
      color: HudTheme.bgBase,
      child: Column(
        children: [
          // ── Header ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: const BoxDecoration(
              color: HudTheme.bgPanel,
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.cleaning_services_outlined,
                  color: HudTheme.accentGreen,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'TEMP CLEANER PROTOCOL',
                    style: TextStyle(
                      color: HudTheme.accentGreen,
                      fontFamily: HudTheme.fontCore,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    tempNotifier.reset();
                    ref.read(storageModeProvider.notifier).state =
                        StorageMode.diskAnalyzer;
                  },
                  icon: const Icon(Icons.close, color: HudTheme.textDim),
                  label: const Text('CLOSE TOOL', style: HudTheme.bodyText),
                ),
              ],
            ),
          ),

          // ── Controls Bar ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HudTheme.accentGreen,
                    foregroundColor: Colors.black,
                  ),
                  icon: const Icon(Icons.preview_outlined, size: 18),
                  label: const Text(
                    'PREVIEW',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      fontFamily: HudTheme.fontCore,
                    ),
                  ),
                  onPressed: tempState.isLoading
                      ? null
                      : () => tempNotifier.fetchPreview(),
                ),
                if (tempState.preview != null) ...[
                  Text(
                    'TOTAL: ${tempState.preview!.totalFormatted}',
                    style: HudTheme.statGreen.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${tempState.selectedPaths.length} OF ${tempState.preview!.locations.length} SELECTED',
                    style: HudTheme.bodyText.copyWith(
                      color: HudTheme.textDim,
                      fontSize: 12,
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: HudTheme.accentRed.withValues(
                        alpha: 0.2,
                      ),
                      foregroundColor: HudTheme.accentRed,
                      side: const BorderSide(color: HudTheme.accentRed),
                    ),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: Text(
                      'CLEAN SELECTED (${tempState.selectedPaths.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        fontFamily: HudTheme.fontCore,
                      ),
                    ),
                    onPressed:
                        tempState.selectedPaths.isEmpty || tempState.isLoading
                        ? null
                        : () => _showCleanConfirmation(
                            context,
                            tempState,
                            tempNotifier,
                          ),
                  ),
                ],
              ],
            ),
          ),

          // ── Body ──
          Expanded(
            child: tempState.isLoading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: HudTheme.accentGreen),
                        SizedBox(height: 24),
                        Text(
                          'SCANNING TEMP SECTORS...',
                          style: TextStyle(
                            color: HudTheme.accentGreen,
                            fontFamily: HudTheme.fontCore,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                : tempState.errorMessage != null
                ? Center(
                    child: Text(
                      'ERROR: ${tempState.errorMessage}',
                      style: HudTheme.actionRed,
                    ),
                  )
                : tempState.preview == null
                ? Center(
                    child: Text(
                      'AWAITING TEMP SCAN COMMAND...',
                      style: HudTheme.bodyText.copyWith(
                        color: HudTheme.textDim,
                      ),
                    ),
                  )
                : tempState.preview!.locations.isEmpty
                ? Center(
                    child: Text(
                      'NO TEMP LOCATIONS DETECTED ON THIS PLATFORM',
                      style: HudTheme.bodyText.copyWith(
                        color: HudTheme.textDim,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: tempState.preview!.locations.length,
                    itemBuilder: (context, index) {
                      final loc = tempState.preview!.locations[index];
                      final isSelected = tempState.selectedPaths.contains(
                        loc.path,
                      );
                      final isCacheCat = loc.category.toLowerCase() == 'cache';
                      final badgeColor = isCacheCat
                          ? HudTheme.accentAmber
                          : HudTheme.accentCyan;
                      final badgeLabel = isCacheCat ? 'CACHE' : 'TEMP';

                      return Container(
                        decoration: HudTheme.listItemDecoration,
                        child: CheckboxListTile(
                          activeColor: HudTheme.accentGreen,
                          checkColor: Colors.black,
                          value: isSelected,
                          onChanged: (_) => tempNotifier.togglePath(loc.path),
                          title: Row(
                            children: [
                              // Category badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: badgeColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                    color: badgeColor.withValues(alpha: 0.6),
                                  ),
                                ),
                                child: Text(
                                  badgeLabel,
                                  style: TextStyle(
                                    color: badgeColor,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: HudTheme.fontCore,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  loc.label.isNotEmpty ? loc.label : loc.path,
                                  style: HudTheme.bodyText.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '${loc.path}  •  ${loc.fileCount} files',
                              style: HudTheme.bodyText.copyWith(
                                color: HudTheme.textDim,
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          secondary: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: HudTheme.accentGreen.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: HudTheme.accentGreen.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            child: Text(
                              loc.sizeFormatted,
                              style: HudTheme.statGreen.copyWith(
                                color: HudTheme.accentGreen,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Dry Run confirmation modal — mirrors the NukePreviewDialog pattern.
  /// Shows the preview data the user already has, so no redundant API call.
  void _showCleanConfirmation(
    BuildContext context,
    TempCleanerState tempState,
    TempCleanerNotifier tempNotifier,
  ) {
    final selectedLocations = tempState.preview!.locations
        .where((loc) => tempState.selectedPaths.contains(loc.path))
        .toList();

    final totalFiles = selectedLocations.fold<int>(
      0,
      (sum, loc) => sum + loc.fileCount,
    );
    final totalBytes = selectedLocations.fold<int>(
      0,
      (sum, loc) => sum + loc.sizeBytes,
    );

    String formatSize(int bytes) {
      const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
      int counter = 0;
      double number = bytes.toDouble();
      while (number >= 1024 && counter < suffixes.length - 1) {
        number /= 1024;
        counter++;
      }
      return '${number.toStringAsFixed(1)} ${suffixes[counter]}';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: HudTheme.bgPanel,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: HudTheme.accentRed, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.warning_amber_outlined,
              color: HudTheme.accentRed,
              size: 28,
            ),
            SizedBox(width: 12),
            Text('CONFIRM TEMP PURGE', style: HudTheme.actionRed),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary stats
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStat('FILES DETECTED', totalFiles.toString()),
                    _buildStat('DATA TO BE FREED', formatSize(totalBytes)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'AFFECTED SECTORS:',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: selectedLocations.length,
                  itemBuilder: (context, index) {
                    final loc = selectedLocations[index];
                    final displayName = loc.label.isNotEmpty
                        ? loc.label
                        : loc.path;
                    return Padding(
                      padding: const EdgeInsetsGeometry.only(bottom: 8.0),
                      child: Text(
                        '> $displayName (${loc.fileCount} files — ${loc.sizeFormatted})',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontFamily: HudTheme.fontCore,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: HudTheme.accentRed.withValues(alpha: 0.1),
                  border: Border.all(color: HudTheme.accentRed),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '⚠ TEMP FILES WILL BE PERMANENTLY DELETED — LOCKED FILES WILL BE SKIPPED',
                  style: TextStyle(
                    color: HudTheme.accentRed,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: HudTheme.fontCore,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('ABORT', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: HudTheme.accentRed.withValues(alpha: 0.2),
              side: const BorderSide(color: HudTheme.accentRed),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _executeClean(tempNotifier);
            },
            child: const Text(
              'EXECUTE PURGE',
              style: TextStyle(
                color: HudTheme.accentRed,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _executeClean(TempCleanerNotifier tempNotifier) async {
    await tempNotifier.cleanSelected();

    final resultState = ref.read(tempCleanerProvider);

    if (resultState.cleanResult != null) {
      final result = resultState.cleanResult!;
      snackbarKey.currentState?.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'FREED ${result.freedFormatted} — ${result.deletedFiles} FILES REMOVED (${result.skippedFiles} SKIPPED)',
            style: const TextStyle(
              fontFamily: HudTheme.fontCore,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: HudTheme.accentGreen,
        ),
      );

      // Refresh drives to reflect freed space.
      ref.read(drivesProvider.notifier).refresh();
    } else if (resultState.errorMessage != null) {
      snackbarKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(
            'TEMP CLEAN FAILED: ${resultState.errorMessage}',
            style: const TextStyle(fontFamily: HudTheme.fontCore),
          ),
          backgroundColor: HudTheme.accentRed,
        ),
      );
    }
  }

  Widget _buildStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: HudTheme.accentRed,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
