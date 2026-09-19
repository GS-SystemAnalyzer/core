import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/features/dashboard/widgets/status.dart';
import 'package:gs_analyzer_ui/models/process_telemetry.dart';
import 'package:gs_analyzer_ui/providers/cpu_provider.dart';
import 'package:gs_analyzer_ui/providers/process_explorer_provider.dart';
import 'package:gs_analyzer_ui/providers/ram_provider.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';
import 'package:gs_analyzer_ui/utils/hud_label.dart';
import 'package:gs_analyzer_ui/providers/hud_density_provider.dart';

class ProcessExplorerScreen extends ConsumerWidget {
  const ProcessExplorerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps ramProvider alive (starts RAM radar if not already running)
    final ramState = ref.watch(ramProvider);
    final CpuState cpuState = ref.watch(cpuProvider);
    final processes = ref.watch(filteredProcessesProvider);
    final selectedPid = ref.watch(selectedProcessPidProvider);
    final showAll = ref.watch(showAllProcessesProvider);
    final totalCount = ramState.groupedProcesses.length;
    final d = ref.watch(hudDensityProvider);

    return Column(
      children: [
        // System Load Summary
        _SystemLoadBar(ramState: ramState, cpuState: cpuState),

        //  Toolbar
        _Toolbar(),

        // Table
        Expanded(
          child: ramState.isLoading && ramState.groupedProcesses.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(
                    color: HudTheme.primaryBorder,
                  ),
                )
              : Column(
                  children: [
                    _TableHeader(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: processes.length,
                        itemBuilder: (context, i) {
                          final group = processes[i];
                          final isSelected = group.primaryPid == selectedPid;
                          return _ProcessRow(
                            group: group,
                            isSelected: isSelected,
                            d: d,
                            onTap: () {
                              final current = ref.read(
                                selectedProcessPidProvider,
                              );
                              ref
                                  .read(selectedProcessPidProvider.notifier)
                                  .state = current == group.primaryPid
                                  ? null
                                  : group.primaryPid;
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),

        // ── Footer ───────────────────────────────────────────────────────
        _Footer(shown: processes.length, total: totalCount, showAll: showAll),
      ],
    );
  }
}

//  System Load Bar
class _SystemLoadBar extends ConsumerWidget {
  final RamState ramState;
  final CpuState cpuState;

  const _SystemLoadBar({required this.ramState, required this.cpuState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(hudDensityProvider);
    final load = cpuState.snapshot?.averageLoad ?? 0.0;
    final cpuPct = load / 100.0;
    final ramPct = ramState.totalGb > 0
        ? ramState.activeGb / ramState.totalGb
        : 0.0;
    final cpuText = cpuState.snapshot != null
        ? '${load.toStringAsFixed(1)}%'
        : '--';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: d.panelPad, vertical: d.gap),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 520;
          final cpu = _LoadMetric(
            'CPU',
            cpuText,
            cpuPct.clamp(0.0, 1.0),
            HudTheme.accentCyan,
          );
          final ram = _LoadMetric(
            'RAM',
            '${(ramPct * 100).toStringAsFixed(1)}%',
            ramPct.clamp(0.0, 1.0),
            HudTheme.accentGreen,
          );

          if (wide) {
            return Row(
              children: [
                Expanded(child: cpu),
                SizedBox(width: d.gap),
                Expanded(child: ram),
                SizedBox(width: d.gap * 1.5),
                HudLabel('PROCS: ${ramState.groupedProcesses.length}'),
              ],
            );
          }
          return Wrap(
            spacing: d.gap * 2,
            runSpacing: d.gap,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(width: 200, child: cpu),
              SizedBox(width: 200, child: ram),
              HudLabel('PROCS: ${ramState.groupedProcesses.length}'),
            ],
          );
        },
      ),
    );
  }
}

class _LoadMetric extends StatelessWidget {
  final String label;
  final String value;
  final double pct;
  final Color color;

  const _LoadMetric(this.label, this.value, this.pct, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        HudLabel('$label  '),
        Expanded(
          child: LinearProgressIndicator(
            value: pct.clamp(0.0, 1.0),
            color: color,
            backgroundColor: Colors.white10,
            minHeight: 4,
          ),
        ),
        const SizedBox(width: 8),
        Text(value, style: HudTheme.bodyText.copyWith(color: color)),
      ],
    );
  }
}

// Toolbar
class _Toolbar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(processSortModeProvider);
    final status = ref.watch(processStatusFilterProvider);

    String sortLabel;
    switch (sort) {
      case ProcessSortMode.cpu:
        sortLabel = '% CPU';
        break;
      case ProcessSortMode.ram:
        sortLabel = '% MEM';
        break;
      case ProcessSortMode.pid:
        sortLabel = 'PID';
        break;
      case ProcessSortMode.name:
        sortLabel = 'NAME';
        break;
    }

    String statusLabel;
    switch (status) {
      case ProcessStatusFilter.all:
        statusLabel = 'ALL';
        break;
      case ProcessStatusFilter.running:
        statusLabel = 'RUNNING';
        break;
      case ProcessStatusFilter.sleeping:
        statusLabel = 'SLEEPING';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          // Filter
          Expanded(
            flex: 3,
            child: TextFormField(
              initialValue: ref.read(processFilterProvider),
              style: HudTheme.bodyText,
              cursorColor: HudTheme.accentCyan,
              decoration: InputDecoration(
                hintText: 'FILTER BY NAME OR PID...',
                hintStyle: HudTheme.bodyText.copyWith(color: HudTheme.textDim),
                prefixIcon: const Icon(
                  Icons.search,
                  color: HudTheme.textDim,
                  size: 18,
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: const BorderSide(color: HudTheme.accentCyan),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) =>
                  ref.read(processFilterProvider.notifier).state = v,
            ),
          ),
          const SizedBox(width: 12),

          // Sort
          PopupMenuButton<ProcessSortMode>(
            tooltip: 'Sort by',
            child: _ToolbarChip('SORT: $sortLabel', Icons.sort),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: ProcessSortMode.cpu,
                child: Text('% CPU'),
              ),
              const PopupMenuItem(
                value: ProcessSortMode.ram,
                child: Text('% MEM'),
              ),
              const PopupMenuItem(
                value: ProcessSortMode.pid,
                child: Text('PID'),
              ),
              const PopupMenuItem(
                value: ProcessSortMode.name,
                child: Text('NAME'),
              ),
            ],
            onSelected: (m) =>
                ref.read(processSortModeProvider.notifier).state = m,
          ),
          const SizedBox(width: 8),

          // Status filter
          PopupMenuButton<ProcessStatusFilter>(
            tooltip: 'Filter by status',
            child: _ToolbarChip(statusLabel, Icons.filter_list),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: ProcessStatusFilter.all,
                child: Text('ALL'),
              ),
              const PopupMenuItem(
                value: ProcessStatusFilter.running,
                child: Text('RUNNING'),
              ),
              const PopupMenuItem(
                value: ProcessStatusFilter.sleeping,
                child: Text('SLEEPING'),
              ),
            ],
            onSelected: (m) =>
                ref.read(processStatusFilterProvider.notifier).state = m,
          ),
        ],
      ),
    );
  }
}

class _ToolbarChip extends StatelessWidget {
  final String label;
  final IconData icon;
  const _ToolbarChip(this.label, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: HudTheme.textDim, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: HudTheme.bodyText.copyWith(color: HudTheme.textDim),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down, color: HudTheme.textDim, size: 14),
        ],
      ),
    );
  }
}

// Table Header
class _TableHeader extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(hudDensityProvider);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: d.panelPad, vertical: 8),
      height: d.rowHeight + 16,
      decoration: BoxDecoration(
        color: HudTheme.bgPanel,
        border: const Border(bottom: BorderSide(color: Colors.white10)),
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
          Expanded(
            flex: 2,
            child: HudLabel('%CPU', textAlign: TextAlign.center),
          ),
          Expanded(
            flex: 2,
            child: HudLabel('%MEM', textAlign: TextAlign.center),
          ),
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
}

// Process Row
class _ProcessRow extends ConsumerWidget {
  final ProcessGroup group;
  final bool isSelected;
  final VoidCallback onTap;
  final HudDensity d;

  const _ProcessRow({
    required this.group,
    required this.isSelected,
    required this.onTap,
    required this.d,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCpuHot = group.totalCpuPercent > 10.0;
    final isMemHot = group.totalPercentMem > 10.0;
    final isHot = isCpuHot || isMemHot;
    final rowColor = isSelected
        ? HudTheme.accentCyan.withValues(alpha: 0.06)
        : isHot
        ? HudTheme.accentAmber.withValues(alpha: 0.05)
        : Colors.transparent;

    final textColor = isHot ? HudTheme.accentAmber : HudTheme.textMain;
    final displayName = group.count > 1
        ? '${group.name} (x${group.count})'
        : group.name;

    return Column(
      children: [
        // ── Main row
        InkWell(
          onTap: onTap,
          hoverColor: Colors.white.withValues(alpha: 0.03),
          child: Container(
            height: d.rowHeight + 16,
            padding: EdgeInsets.symmetric(horizontal: d.panelPad, vertical: 8),
            decoration: BoxDecoration(
              color: rowColor,
              border: Border(
                left: BorderSide(
                  color: isSelected ? HudTheme.accentCyan : Colors.transparent,
                  width: 3,
                ),
                bottom: const BorderSide(color: Colors.white10),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    group.count > 1 ? 'GRP' : group.primaryPid.toString(),
                    style: HudTheme.bodyText.copyWith(color: HudTheme.textDim),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    displayName,
                    style: HudTheme.bodyText.copyWith(
                      color: isSelected ? HudTheme.accentCyan : textColor,
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
                    style: HudTheme.bodyText.copyWith(color: HudTheme.textDim),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${group.totalCpuPercent.toStringAsFixed(1)}%',
                    style: HudTheme.statGreen.copyWith(
                      color: isCpuHot
                          ? HudTheme.accentAmber
                          : HudTheme.accentCyan,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${group.totalPercentMem.toStringAsFixed(1)}%',
                    style: HudTheme.statGreen.copyWith(color: textColor),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Center(child: Status(status: group.dominantStatus,)),
                ),
                Expanded(
                  flex: 1,
                  child: IconButton(
                    icon: const Icon(
                      Icons.cancel_outlined,
                      color: HudTheme.accentRed,
                      size: 18,
                    ),
                    tooltip: group.count > 1
                        ? 'Kill all ${group.name}'
                        : 'Kill PID ${group.primaryPid}',
                    padding: EdgeInsets.zero,
                    onPressed: () => _confirmKill(context, ref),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Expanded detail drawer
        if (isSelected) _DetailDrawer(group: group, d: d),
      ],
    );
  }

  void _confirmKill(BuildContext context, WidgetRef ref) {
    final label = group.count > 1
        ? 'Kill all ${group.count} instances of ${group.name}?'
        : 'Kill PID ${group.primaryPid} (${group.name})?';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          'CONFIRM KILL',
          style: HudTheme.bodyText.copyWith(
            color: HudTheme.accentRed,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(label, style: HudTheme.bodyText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'CANCEL',
              style: HudTheme.bodyText.copyWith(color: HudTheme.textDim),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (group.count > 1) {
                ref.read(ramProvider.notifier).killProcessGroup(group.name);
              } else {
                ref.read(ramProvider.notifier).killProcess(group.primaryPid);
              }
              ref.read(selectedProcessPidProvider.notifier).state = null;
            },
            child: Text(
              'KILL',
              style: HudTheme.bodyText.copyWith(
                color: HudTheme.accentRed,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Expanded Detail Drawer
class _DetailDrawer extends ConsumerWidget {
  final ProcessGroup group;
  final HudDensity d;
  const _DetailDrawer({required this.group, required this.d});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.symmetric(horizontal: d.panelPad, vertical: d.gap),
      decoration: BoxDecoration(
        color: HudTheme.accentCyan.withValues(alpha: 0.04),
        border: const Border(
          left: BorderSide(color: HudTheme.accentCyan, width: 3),
          bottom: BorderSide(color: Colors.white10),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Stats
            Wrap(
              spacing: 32,
              runSpacing: 8,
              children: [
                _DrawerStat(
                  'PID',
                  group.count > 1
                      ? 'GROUPED (${group.count})'
                      : group.primaryPid.toString(),
                ),
                _DrawerStat(
                  'WORKING SET',
                  '${group.totalRamMb.toStringAsFixed(1)} MB',
                ),
                _DrawerStat(
                  '% CPU',
                  '${group.totalCpuPercent.toStringAsFixed(2)}%',
                ),
                _DrawerStat('STATUS', group.dominantStatus),
                _DrawerStat('USER', group.primaryUser),
              ],
            ),
            const SizedBox(width: 24),
            // Actions
            Row(
              children: [
                _ActionButton(
                  label: group.count > 1
                      ? 'KILL ALL ${group.name.toUpperCase()} (${group.count})'
                      : 'KILL PID ${group.primaryPid}',
                  color: HudTheme.accentRed,
                  onTap: () => _showKillDialog(context, ref),
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  label: 'COPY NAME',
                  color: HudTheme.textDim,
                  onTap: () =>
                      Clipboard.setData(ClipboardData(text: group.name)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showKillDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          'CONFIRM KILL',
          style: HudTheme.bodyText.copyWith(
            color: HudTheme.accentRed,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          group.count > 1
              ? 'Terminate all ${group.count} instances of ${group.name}?'
              : 'Terminate PID ${group.primaryPid} (${group.name})?',
          style: HudTheme.bodyText,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'CANCEL',
              style: HudTheme.bodyText.copyWith(color: HudTheme.textDim),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (group.count > 1) {
                ref.read(ramProvider.notifier).killProcessGroup(group.name);
              } else {
                ref.read(ramProvider.notifier).killProcess(group.primaryPid);
              }
              ref.read(selectedProcessPidProvider.notifier).state = null;
            },
            child: Text(
              'EXECUTE',
              style: HudTheme.bodyText.copyWith(
                color: HudTheme.accentRed,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerStat extends StatelessWidget {
  final String label;
  final String value;
  const _DrawerStat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HudLabel(label),
        const SizedBox(height: 2),
        Text(
          value,
          style: HudTheme.bodyText.copyWith(color: HudTheme.accentCyan),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: HudTheme.bodyText.copyWith(color: color, fontSize: 11),
        ),
      ),
    );
  }
}

// Footer
class _Footer extends ConsumerWidget {
  final int shown;
  final int total;
  final bool showAll;
  const _Footer({
    required this.shown,
    required this.total,
    required this.showAll,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Text(
            'Showing $shown of $total processes',
            style: HudTheme.bodyText.copyWith(color: HudTheme.textDim),
          ),
          const Spacer(),
          if (total > 100)
            InkWell(
              onTap: () =>
                  ref.read(showAllProcessesProvider.notifier).state = !showAll,
              child: Text(
                showAll ? 'SHOW TOP 100' : 'SHOW ALL ($total)',
                style: HudTheme.bodyText.copyWith(
                  color: HudTheme.accentCyan,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
