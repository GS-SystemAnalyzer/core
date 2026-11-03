import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/features/dashboard/widgets/status.dart';
import 'package:gs_analyzer_ui/providers/ram_provider.dart';
import 'package:gs_analyzer_ui/providers/ram_alert_provider.dart';
import 'package:gs_analyzer_ui/utils/hud_label.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';
import 'package:gs_analyzer_ui/widgets/telemetry_history_chart.dart';
import 'package:gs_analyzer_ui/providers/hud_density_provider.dart';
import 'package:gs_analyzer_ui/models/process_telemetry.dart';
import 'package:gs_analyzer_ui/widgets/hud_accent_toggle.dart';

class RamScannerScreen extends ConsumerStatefulWidget {
  const RamScannerScreen({super.key});

  @override
  ConsumerState<RamScannerScreen> createState() => _RamScannerScreenState();
}

class _RamScannerScreenState extends ConsumerState<RamScannerScreen> {
  bool _showHistory = false;
  final _metricKeys = {for (final metric in ProcessMemoryMetric.values) metric: GlobalKey()};

  @override
  Widget build(BuildContext context) {
    final ramState = ref.watch(ramProvider);
    final ramAlert = ref.watch(ramAlertProvider);
    final d = ref.watch(hudDensityProvider);
    final theme = context.hudTheme;
    final groups = ramState.memorySortedProcesses;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Critical banner
        if (ramState.isCritical && !_showHistory)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: theme.accentRed.withValues(alpha: 0.2),
            child: Center(
              child: Text(
                'RAM CRITICAL ALERT: REDUCE SYSTEM LOAD',
                style: theme.actionRed,
              ),
            ),
          ),

        if (ramState.errorMessage != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: theme.accentRed.withValues(alpha: 0.2),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: theme.accentRed, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ramState.errorMessage!,
                    style: theme.actionRed,
                  ),
                ),
                InkWell(
                  onTap: () => ref.read(ramProvider.notifier).clearError(),
                  child: Icon(Icons.close, color: theme.accentRed, size: 18),
                ),
              ],
            ),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: d.gap,
            runSpacing: d.gap,
            children: [
              Text('MEMORY SCANNER MODULE', style: theme.header),
              HudAccentToggle<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('LIVE VIEW')),
                  ButtonSegment(value: true, label: Text('HISTORY')),
                ],
                selected: _showHistory,
                showSelectedIcon: false,
                visualDensity: d.rowHeight <= 32 ? VisualDensity.compact : VisualDensity.standard,
                onChanged: (value) => setState(() => _showHistory = value),
              ),
            ],
          ),
        ),

        if (_showHistory)
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(d.panelPad),
              child: const TelemetryHistoryChart(metricKey: 'ram'),
            ),
          )
        else ...[
          // Allocation cards
          Flexible(
            flex: 1,
            fit: FlexFit.loose,
            child: SingleChildScrollView(child: Container(
            padding: EdgeInsets.all(d.panelPad),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.textMain.withValues(alpha: 0.1))),
            ),
            child: LayoutBuilder(
              builder: (ctx, c) {
                final row = c.maxWidth > 450;
    
                final activeCard = _buildAllocationCard(
                  'ACTIVE MEMORY',
                  '${ramState.activeGb.toStringAsFixed(1)} / ${ramState.totalGb.toStringAsFixed(1)} GB',
                  theme.accentCyan,
                  ramState.totalGb > 0 ? ramState.activeGb / ramState.totalGb : 0.0,
                  d,
                );
                final cacheCard = _buildAllocationCard(
                  'CACHE (STANDBY)',
                  '${ramState.cacheGb.toStringAsFixed(1)} / ${ramState.totalGb.toStringAsFixed(1)} GB',
                  theme.accentGreen,
                  ramState.totalGb > 0 ? ramState.cacheGb / ramState.totalGb : 0.0,
                  d,
                );
                final swapCard = _buildAllocationCard(
                  'SWAP / PAGEFILE',
                  '${ramState.swapGb.toStringAsFixed(1)} / ${ramState.totalSwapGb.toStringAsFixed(1)} GB',
                  theme.accentAmber,
                  ramState.totalSwapGb > 0 ? ramState.swapGb / ramState.totalSwapGb : 0.0,
                  d,
                );

                final gap = SizedBox(width: d.gap, height: d.gap);

                if (row) {
                  return Row(
                    children: [
                      Expanded(child: activeCard),
                      gap,
                      Expanded(child: cacheCard),
                      gap,
                      Expanded(child: swapCard),
                    ],
                  );
                } else {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      activeCard,
                      gap,
                      cacheCard,
                      gap,
                      swapCard,
                    ],
                  );
                }
              },
            ),
          )),
          ),

          Padding(
            padding: EdgeInsets.symmetric(horizontal: d.panelPad, vertical: d.gap),
            child: Row(
              children: [
                Expanded(child: SingleChildScrollView(
                  key: const ValueKey('ram-memory-metric'),
                  scrollDirection: Axis.horizontal,
                  child: HudAccentToggle<ProcessMemoryMetric>(
                    compact: true,
                    showSelectedIcon: false,
                    segments: [for (final metric in ProcessMemoryMetric.values)
                      ButtonSegment(value: metric,
                        label: Text(metric.shortLabel, key: _metricKeys[metric]), tooltip: '${metric.label}\n${metric.tooltip}')],
                    selected: ramState.selectedMemoryMetric,
                    visualDensity: d.rowHeight <= 32 ? VisualDensity.compact : VisualDensity.standard,
                    onChanged: (selected) {
                      ref.read(ramProvider.notifier).setMemoryMetric(selected);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final target = _metricKeys[selected]?.currentContext;
                        if (mounted && target != null) Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 100));
                      });
                    },
                  ),
                )),
                const SizedBox(width: 8),
                HudAccentToggle<ProcessMemoryDisplayMode>(
                  key: const ValueKey('ram-memory-display'),
                  compact: true,
                  showSelectedIcon: false,
                  segments: [for (final mode in ProcessMemoryDisplayMode.values)
                    ButtonSegment(value: mode, label: Text(mode.label), tooltip: mode.tooltip)],
                  selected: ramState.memoryDisplayMode,
                  visualDensity: d.rowHeight <= 32 ? VisualDensity.compact : VisualDensity.standard,
                  onChanged: ref.read(ramProvider.notifier).setMemoryDisplayMode,
                ),
              ],
            ),
          ),

          // Process table
          ramState.isLoading && ramState.groupedProcesses.isEmpty
              ? Expanded(child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(
                      color: theme.border,
                    ),
                  ),
                 ))
              : Expanded(
                  flex: 2,
                  child: ListView.builder(
                    itemCount: groups.isEmpty ? 2 : groups.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) return _buildTableHeader(d);

                      if (groups.isEmpty) return Padding(padding: EdgeInsets.all(d.panelPad),
                          child: Text('NO PROCESS DATA', style: theme.body, textAlign: TextAlign.center));
                      final group = groups[index - 1];
                      final memory = group.memoryFor(ramState.selectedMemoryMetric);
                      final ratio = memory.percentOfCapacity(ramState.physicalTotalBytes);
                      
                      final isTopConsumer = ramAlert?.topConsumers.any((c) => c.name == group.name) ?? false;
                      final isMemHot = ratio != null && ratio > 10.0;
                      final isHot = isMemHot || isTopConsumer;
                      final textColor = isHot
                          ? theme.accentAmber
                          : theme.textMain;
                      final displayName = group.count > 1
                          ? '${group.name} (x${group.count})'
                          : group.name;

                      return Container(
                        constraints: BoxConstraints(minHeight: d.rowHeight + 16),
                        padding: EdgeInsets.symmetric(
                          horizontal: d.panelPad,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isHot
                              ? theme.accentAmber.withValues(alpha: 0.05)
                              : Colors.transparent,
                          border: Border(
                            bottom: BorderSide(color: theme.textMain.withValues(alpha: 0.1)),
                            left: isTopConsumer
                                ? BorderSide(color: theme.accentAmber, width: 4)
                                : BorderSide.none,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                group.count > 1
                                    ? 'GRP'
                                    : group.primaryPid.toString(),
                                style: theme.body.copyWith(
                                  color: theme.textDim,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              flex: 4,
                              child: Text(
                                displayName,
                                style: theme.body.copyWith(
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                group.primaryUser,
                                style: theme.body.copyWith(
                                  color: theme.textDim,
                                ),
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Tooltip(
                                message: '${ramState.selectedMemoryMetric.tooltip}\n${ramState.memoryDisplayMode.tooltip}\n'
                                    '${memory.availableMembers}/${group.count} members available; ${memory.estimatedMembers} legacy estimates; ${memory.unknownSourceMembers} unknown sources.',
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Text(ramState.memoryDisplayMode == ProcessMemoryDisplayMode.value
                                      ? memory.formattedMiB : memory.formattedPercentOfCapacity(ramState.physicalTotalBytes),
                                      key: ValueKey('ram-value-${group.primaryPid}'),
                                      style: theme.statGreen.copyWith(color: textColor), textAlign: TextAlign.center),
                                  if (memory.provenance.label != null)
                                    FittedBox(fit: BoxFit.scaleDown, child: Text(memory.provenance.label!,
                                      style: theme.body.copyWith(color: theme.accentAmber, fontSize: 9))),
                                ]),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Center(
                                child: Status(status: group.dominantStatus),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: IconButton(
                                icon: Icon(
                                  Icons.cancel_outlined,
                                  color: theme.accentRed,
                                  size: 20,
                                ),
                                tooltip: 'Kill Process',
                                onPressed: () {
                                  if (group.count > 1) {
                                    ref
                                        .read(ramProvider.notifier)
                                        .killProcessGroup(group.name);
                                  } else {
                                    ref
                                        .read(ramProvider.notifier)
                                        .killProcess(group.primaryPid);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ],
      ],
    );
  }

  Widget _buildTableHeader(HudDensity d) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: d.panelPad, vertical: 8),
      height: d.rowHeight + 16,
      decoration: BoxDecoration(
        color: context.hudTheme.panel,
        border: Border(bottom: BorderSide(color: context.hudTheme.textMain.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: HudLabel('PID', textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 4,
            child: HudLabel('COMMAND', textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 3,
            child: HudLabel('USER', textAlign: TextAlign.center),
          ),
          Expanded(flex: 3, child: Tooltip(
              message: '${ref.watch(ramProvider).selectedMemoryMetric.tooltip}\n${ref.watch(ramProvider).memoryDisplayMode.tooltip}',
              child: FittedBox(fit: BoxFit.scaleDown,
                  child: HudLabel(ref.watch(ramProvider).memoryDisplayMode == ProcessMemoryDisplayMode.value
                      ? ref.watch(ramProvider).selectedMemoryMetric.label
                      : '${ref.watch(ramProvider).selectedMemoryMetric.shortLabel} (%)', textAlign: TextAlign.center)))),
          Expanded(
            flex: 2,
            child: HudLabel('STATUS', textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 1,
            child: HudLabel('ACTION', textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  Widget _buildAllocationCard(
    String title,
    String subtitle,
    Color accentColor,
    double percentage,
    HudDensity d,
  ) {
    return Container(
      padding: EdgeInsets.all(d.panelPad),
      decoration: context.hudTheme.hudPanelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HudLabel(title),
          SizedBox(height: d.gap),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              subtitle,
              style: TextStyle(
                color: accentColor,
                fontSize: d.titleSize,
                fontWeight: FontWeight.bold,
                fontFamily: HudTheme.fontCore,
              ),
            ),
          ),
          SizedBox(height: d.gap),
          LinearProgressIndicator(
            value: percentage.clamp(0.0, 1.0),
            color: accentColor,
            backgroundColor: context.hudTheme.textMain.withValues(alpha: 0.1),
            minHeight: 4,
          ),
        ],
      ),
    );
  }
}
