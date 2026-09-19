import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/models/age_heatmap_model.dart';
import 'package:gs_analyzer_ui/providers/age_heatmap_provider.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';
import 'package:gs_analyzer_ui/widgets/directory_node_widget.dart';

/// Resolves the HudTheme accent color for a given age bucket string.
Color bucketColor(String bucket) {
  switch (bucket) {
    case 'fresh':
      return HudTheme.accentCyan;
    case 'recent':
      return HudTheme.accentGreen;
    case 'aging':
      return HudTheme.accentAmber;
    case 'stale':
      return HudTheme.accentRed;
    default:
      return HudTheme.textDim;
  }
}

/// Combined legend bar + summary grid displayed above the directory table
/// when the age heatmap overlay is enabled.
class AgeHeatmapOverlay extends ConsumerWidget {
  const AgeHeatmapOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPath = ref.watch(directoryProvider).currentPath;
    final heatmapAsync = ref.watch(ageHeatmapProvider(currentPath));

    return heatmapAsync.when(
      loading: () => _buildLoadingState(),
      error: (err, _) {
        if (err is AgeHeatmapNoScanException) {
          return _buildNoScanPrompt();
        }
        return _buildErrorState(err.toString());
      },
      data: (result) => _buildOverlay(result),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: HudTheme.bgPanel,
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: HudTheme.accentCyan,
            ),
          ),
          SizedBox(width: 12),
          Text(
            'LOADING AGE HEATMAP...',
            style: TextStyle(
              fontFamily: HudTheme.fontCore,
              color: HudTheme.textDim,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoScanPrompt() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: HudTheme.bgPanel,
        border: Border.all(color: HudTheme.accentRed.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_outlined,
            color: HudTheme.accentAmber,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(
            'RUN A SCAN FIRST',
            style: HudTheme.actionRed.copyWith(letterSpacing: 2),
          ),
          const SizedBox(width: 8),
          Text(
            '— scan a directory to generate age heatmap data',
            style: HudTheme.labelMuted.copyWith(color: HudTheme.textDim),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        color: HudTheme.bgPanel,
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Text(
        'HEATMAP ERROR: $error',
        style: HudTheme.actionRed.copyWith(fontSize: 12),
      ),
    );
  }

  Widget _buildOverlay(AgeHeatmapResult result) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: HudTheme.bgPanel,
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Legend bar
          _buildLegendBar(),
          const SizedBox(height: 10),
          // Summary grid
          _buildSummaryGrid(result.summary),
        ],
      ),
    );
  }

  Widget _buildLegendBar() {
    return Row(
      children: [
        const Icon(
          Icons.thermostat_outlined,
          color: HudTheme.accentCyan,
          size: 16,
        ),
        const SizedBox(width: 8),
        Text(
          'FILE AGE MAP',
          style: HudTheme.labelMuted.copyWith(
            color: HudTheme.accentCyan,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(width: 16),
        _legendItem('FRESH', HudTheme.accentCyan),
        const SizedBox(width: 12),
        _legendItem('RECENT', HudTheme.accentGreen),
        const SizedBox(width: 12),
        _legendItem('AGING', HudTheme.accentAmber),
        const SizedBox(width: 12),
        _legendItem('STALE', HudTheme.accentRed),
      ],
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 4),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontFamily: HudTheme.fontCore,
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryGrid(Map<String, AgeBucketSummary> summary) {
    const buckets = ['fresh', 'recent', 'aging', 'stale'];
    const labels = ['< 7 DAYS', '7D – 1M', '1M – 1Y', '> 1 YEAR'];

    return Row(
      children: List.generate(buckets.length, (i) {
        final bucket = buckets[i];
        final data =
            summary[bucket] ?? const AgeBucketSummary(count: 0, totalBytes: 0);
        final color = bucketColor(bucket);

        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < 3 ? 8 : 0),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  labels[i],
                  style: TextStyle(
                    fontFamily: HudTheme.fontCore,
                    color: color.withValues(alpha: 0.7),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${data.count} items',
                  style: TextStyle(
                    fontFamily: HudTheme.fontCore,
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  formatBytes(data.totalBytes),
                  style: TextStyle(
                    fontFamily: HudTheme.fontCore,
                    color: color.withValues(alpha: 0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
