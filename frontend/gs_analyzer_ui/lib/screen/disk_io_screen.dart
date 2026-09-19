import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/disk_io_provider.dart';
import 'package:gs_analyzer_ui/providers/hud_density_provider.dart';
import 'package:gs_analyzer_ui/utils/formatters.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';
import 'package:gs_analyzer_ui/widgets/disk_io_card.dart';
import 'package:gs_analyzer_ui/widgets/telemetry_history_chart.dart';

class DiskIoScreen extends ConsumerStatefulWidget {
  const DiskIoScreen({super.key});

  @override
  ConsumerState<DiskIoScreen> createState() => _DiskIoScreenState();
}

class _DiskIoScreenState extends ConsumerState<DiskIoScreen> {
  bool _showHistory = false;
  String _historyMetric = 'disk_io_read';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(diskIoProvider);
    final d = ref.watch(hudDensityProvider);

    return Padding(
      padding: EdgeInsets.all(d.panelPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('DISK I/O THROUGHPUT', style: HudTheme.headerCyan),

              // View Toggle Strip
              Row(
                children: [
                  _buildToggleBtn('LIVE VIEW', !_showHistory),
                  _buildToggleBtn('HISTORY', _showHistory),
                ],
              ),
            ],
          ),
          SizedBox(height: d.gap * 2),

          // Main Screen Content
          Expanded(
            child: _showHistory
                ? _buildHistoryView()
                : _buildLiveView(state, d),
          ),
        ],
      ),
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

  Widget _buildHistoryView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              onTap: () => setState(() => _historyMetric = 'disk_io_read'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _historyMetric == 'disk_io_read'
                      ? HudTheme.accentCyan.withValues(alpha: 0.1)
                      : Colors.transparent,
                  border: Border.all(
                    color: _historyMetric == 'disk_io_read'
                        ? HudTheme.accentCyan
                        : Colors.white10,
                  ),
                ),
                child: Text(
                  'READ THROUGHPUT',
                  style: TextStyle(
                    fontFamily: HudTheme.fontCore,
                    fontSize: 12,
                    color: _historyMetric == 'disk_io_read'
                        ? HudTheme.accentCyan
                        : HudTheme.textDim,
                    fontWeight: _historyMetric == 'disk_io_read'
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => setState(() => _historyMetric = 'disk_io_write'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _historyMetric == 'disk_io_write'
                      ? HudTheme.accentAmber.withValues(alpha: 0.1)
                      : Colors.transparent,
                  border: Border.all(
                    color: _historyMetric == 'disk_io_write'
                        ? HudTheme.accentAmber
                        : Colors.white10,
                  ),
                ),
                child: Text(
                  'WRITE THROUGHPUT',
                  style: TextStyle(
                    fontFamily: HudTheme.fontCore,
                    fontSize: 12,
                    color: _historyMetric == 'disk_io_write'
                        ? HudTheme.accentAmber
                        : HudTheme.textDim,
                    fontWeight: _historyMetric == 'disk_io_write'
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TelemetryHistoryChart(metricKey: _historyMetric),
        ),
      ],
    );
  }

  Widget _buildLiveView(DiskIoState state, HudDensity d) {
    if (state.snapshot == null) {
      return const Center(
        child: CircularProgressIndicator(color: HudTheme.primaryBorder),
      );
    }

    if (state.snapshot!.disks.isEmpty) {
      return const Center(
        child: Text(
          'NO PHYSICAL DISKS DETECTED',
          style: HudTheme.labelMuted,
        ),
      );
    }

    final disks = state.snapshot!.disks;
    final activeDisk = state.activeDisk;
    final selectedId = activeDisk?.id ?? disks.first.id;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Disk Selector Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: disks.map((disk) {
                final isSelected = disk.id == selectedId;
                final driveLetters = disk.driveLetters.isNotEmpty
                    ? ' [${disk.driveLetters.map((l) => l.toUpperCase()).join(", ")}]'
                    : '';
                final tabLabel = 'DISK ${disk.id}$driveLetters';

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () {
                      ref.read(diskIoProvider.notifier).selectDisk(disk.id);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? HudTheme.accentCyan.withValues(alpha: 0.1)
                            : Colors.transparent,
                        border: Border.all(
                          color: isSelected
                              ? HudTheme.accentCyan
                              : Colors.white10,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.storage_outlined,
                            size: 14,
                            color: isSelected
                                ? HudTheme.accentCyan
                                : HudTheme.textDim,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            tabLabel,
                            style: TextStyle(
                              fontFamily: HudTheme.fontCore,
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? HudTheme.accentCyan
                                  : HudTheme.textDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          SizedBox(height: d.gap * 1.5),

          // Primary Disk Telemetry Card
          DiskIoCard(overrideDisk: activeDisk),

          // Multi-Disk Overview Grid/List if more than 1 disk
          if (disks.length > 1) ...[
            SizedBox(height: d.gap * 2),
            const Text(
              'ALL PHYSICAL DISKS',
              style: TextStyle(
                fontFamily: HudTheme.fontCore,
                fontSize: 12,
                color: HudTheme.textDim,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            SizedBox(height: d.gap),
            ...disks.map((disk) {
              final isCurrent = disk.id == selectedId;
              final letters = disk.driveLetters.isNotEmpty
                  ? disk.driveLetters.map((l) => '[$l]').join(' ')
                  : 'UNMAPPED';

              return InkWell(
                onTap: () {
                  ref.read(diskIoProvider.notifier).selectDisk(disk.id);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? HudTheme.accentCyan.withValues(alpha: 0.05)
                        : HudTheme.bgPanel,
                    border: Border.all(
                      color: isCurrent ? HudTheme.accentCyan : Colors.white10,
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'DISK ${disk.id}',
                        style: TextStyle(
                          fontFamily: HudTheme.fontCore,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isCurrent ? HudTheme.accentCyan : Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        letters,
                        style: const TextStyle(
                          fontFamily: HudTheme.fontCore,
                          fontSize: 11,
                          color: HudTheme.accentCyan,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          disk.model,
                          style: const TextStyle(
                            fontFamily: HudTheme.fontCore,
                            fontSize: 11,
                            color: HudTheme.textDim,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        'R: ${formatRate(disk.readBytesPerSec)}',
                        style: const TextStyle(
                          fontFamily: HudTheme.fontCore,
                          fontSize: 11,
                          color: HudTheme.accentCyan,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'W: ${formatRate(disk.writeBytesPerSec)}',
                        style: const TextStyle(
                          fontFamily: HudTheme.fontCore,
                          fontSize: 11,
                          color: HudTheme.accentAmber,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Q: ${disk.avgQueueLength.toStringAsFixed(1)}',
                        style: TextStyle(
                          fontFamily: HudTheme.fontCore,
                          fontSize: 11,
                          color: disk.avgQueueLength < 2.0
                              ? HudTheme.accentGreen
                              : disk.avgQueueLength <= 5.0
                                  ? HudTheme.accentAmber
                                  : HudTheme.accentRed,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
