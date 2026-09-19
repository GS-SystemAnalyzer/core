import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/features/dashboard/widgets/status.dart';
import 'package:gs_analyzer_ui/providers/ram_provider.dart';
import 'package:gs_analyzer_ui/providers/ram_alert_provider.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';
import 'package:gs_analyzer_ui/utils/hud_label.dart';
import 'package:gs_analyzer_ui/widgets/telemetry_history_chart.dart';
import 'package:gs_analyzer_ui/providers/hud_density_provider.dart';

class RamScannerScreen extends ConsumerStatefulWidget {
  const RamScannerScreen({super.key});

  @override
  ConsumerState<RamScannerScreen> createState() => _RamScannerScreenState();
}

class _RamScannerScreenState extends ConsumerState<RamScannerScreen> {
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final ramState = ref.watch(ramProvider);
    final ramAlert = ref.watch(ramAlertProvider);
    final d = ref.watch(hudDensityProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Critical banner
        if (ramState.isCritical && !_showHistory)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: HudTheme.accentRed.withValues(alpha: 0.2),
            child: const Center(
              child: Text(
                'RAM CRITICAL ALERT: REDUCE SYSTEM LOAD',
                style: HudTheme.actionRed,
              ),
            ),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('MEMORY SCANNER MODULE', style: HudTheme.headerCyan),
              Row(
                children: [
                  _buildToggleBtn('LIVE VIEW', !_showHistory),
                  _buildToggleBtn('HISTORY', _showHistory),
                ],
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
          Container(
            padding: EdgeInsets.all(d.panelPad),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: LayoutBuilder(
              builder: (ctx, c) {
                final row = c.maxWidth > 450;
    
                final activeCard = _buildAllocationCard(
                  'ACTIVE MEMORY',
                  '${ramState.activeGb.toStringAsFixed(1)} / ${ramState.totalGb.toStringAsFixed(1)} GB',
                  HudTheme.accentCyan,
                  ramState.totalGb > 0 ? ramState.activeGb / ramState.totalGb : 0.0,
                  d,
                );
                final cacheCard = _buildAllocationCard(
                  'CACHE (STANDBY)',
                  '${ramState.cacheGb.toStringAsFixed(1)} / ${ramState.totalGb.toStringAsFixed(1)} GB',
                  HudTheme.accentGreen,
                  ramState.totalGb > 0 ? ramState.cacheGb / ramState.totalGb : 0.0,
                  d,
                );
                final swapCard = _buildAllocationCard(
                  'SWAP / PAGEFILE',
                  '${ramState.swapGb.toStringAsFixed(1)} / ${ramState.totalSwapGb.toStringAsFixed(1)} GB',
                  HudTheme.accentAmber,
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
          ),

          // Process table
          ramState.isLoading && ramState.groupedProcesses.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: CircularProgressIndicator(
                      color: HudTheme.primaryBorder,
                    ),
                  ),
                )
              : Expanded(
                  child: ListView.builder(
                    itemCount: ramState.groupedProcesses.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) return _buildTableHeader(d);

                      final group = ramState.groupedProcesses[index - 1];
                      
                      final isTopConsumer = ramAlert?.topConsumers.any((c) => c.name == group.name) ?? false;
                      final isMemHot = group.totalPercentMem > 10.0;
                      final isHot = isMemHot || isTopConsumer;
                      final textColor = isHot
                          ? HudTheme.accentAmber
                          : HudTheme.textMain;
                      final displayName = group.count > 1
                          ? '${group.name} (x${group.count})'
                          : group.name;

                      return Container(
                        height: d.rowHeight + 16,
                        padding: EdgeInsets.symmetric(
                          horizontal: d.panelPad,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isHot
                              ? HudTheme.accentAmber.withValues(alpha: 0.05)
                              : Colors.transparent,
                          border: Border(
                            bottom: const BorderSide(color: Colors.white10),
                            left: isTopConsumer
                                ? const BorderSide(color: HudTheme.accentAmber, width: 4)
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
                                style: HudTheme.bodyText.copyWith(
                                  color: HudTheme.textDim,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              flex: 4,
                              child: Text(
                                displayName,
                                style: HudTheme.bodyText.copyWith(
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
                                style: HudTheme.bodyText.copyWith(
                                  color: HudTheme.textDim,
                                ),
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '${group.totalRamMb.toStringAsFixed(1)} MB',
                                style: HudTheme.statGreen.copyWith(
                                  color: textColor,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Center(
                                child: Status(status: group.dominantStatus),
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: IconButton(
                                icon: const Icon(
                                  Icons.cancel_outlined,
                                  color: HudTheme.accentRed,
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

  Widget _buildToggleBtn(String label, bool isSelected) {
    return InkWell(
      onTap: () {
        setState(() {
          _showHistory = label == 'HISTORY';
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? HudTheme.accentCyan.withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border.all(
            color: isSelected ? HudTheme.accentCyan : Colors.white10,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: HudTheme.fontCore,
            color: isSelected ? HudTheme.accentCyan : HudTheme.textDim,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildTableHeader(HudDensity d) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: d.panelPad, vertical: 8),
      height: d.rowHeight + 16,
      decoration: const BoxDecoration(
        color: HudTheme.bgPanel,
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: const Row(
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
          Expanded(flex: 2, child: HudLabel('MB', textAlign: TextAlign.center)),
          Expanded(
            flex: 3,
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
      decoration: HudTheme.hudPanelDecoration,
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
            backgroundColor: Colors.white10,
            minHeight: 4,
          ),
        ],
      ),
    );
  }
}