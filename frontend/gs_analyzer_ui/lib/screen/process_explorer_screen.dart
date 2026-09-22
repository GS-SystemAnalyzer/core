import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/features/dashboard/widgets/status.dart';
import 'package:gs_analyzer_ui/models/process_telemetry.dart';
import 'package:gs_analyzer_ui/providers/cpu_provider.dart';
import 'package:gs_analyzer_ui/providers/process_explorer_provider.dart';
import 'package:gs_analyzer_ui/providers/ram_provider.dart';
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
    final theme = Theme.of(context);

    return Column(
      children: [
        // System Load Summary
        _SystemLoadBar(ramState: ramState, cpuState: cpuState),

        //  Toolbar
        _Toolbar(),

        // Table
        Expanded(
          child: ramState.isLoading && ramState.groupedProcesses.isEmpty
              ? Center(
                  child: CircularProgressIndicator(
                    color: theme.colorScheme.outline,
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
        final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: d.panelPad, vertical: d.gap),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerTheme.color!)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 520;
          final cpu = _LoadMetric(
            'CPU',
            cpuText,
            cpuPct.clamp(0.0, 1.0),
            theme.colorScheme.onPrimary,
          );
          final ram = _LoadMetric(
            'RAM',
            '${(ramPct * 100).toStringAsFixed(1)}%',
            ramPct.clamp(0.0, 1.0),
            theme.colorScheme.secondary,
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
            backgroundColor: Theme.of(context).dividerTheme.color!,
            minHeight: 4,
          ),
        ),
        const SizedBox(width: 8),
        Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color)),
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
    final theme =  Theme.of(context);

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
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerTheme.color!)),
      ),
      child: Row(
        children: [
          // Filter
          Expanded(
            flex: 3,
            child: TextFormField(
              initialValue: ref.read(processFilterProvider),
              style: theme.textTheme.bodyMedium,
              cursorColor: theme.colorScheme.onPrimary,
              decoration: InputDecoration(
                hintText: 'FILTER BY NAME OR PID...',
                hintStyle: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.surfaceDim),
                prefixIcon: Icon(
                  Icons.search,
                  color: theme.colorScheme.surfaceDim,
                  size: 18,
                ),
                filled: true,
                fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: theme.dividerTheme.color!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: theme.colorScheme.onPrimary),
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
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.04),
        border: Border.all(color: theme.dividerTheme.color!),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: theme.colorScheme.surfaceDim, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.surfaceDim),
          ),
          const SizedBox(width: 4),
          Icon(Icons.arrow_drop_down, color: theme.colorScheme.surfaceDim, size: 14),
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
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerTheme.color!)),
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
    final theme = Theme.of(context);
    final rowColor = isSelected
        ? theme.colorScheme.onPrimary.withValues(alpha: 0.06)
        : isHot
        ? theme.colorScheme.tertiary.withValues(alpha: 0.05)
        : Colors.transparent;

    final textColor = isHot ? theme.colorScheme.tertiary : theme.colorScheme.onSurface;
    final displayName = group.count > 1
        ? '${group.name} (x${group.count})'
        : group.name;

    return Column(
      children: [
        // ── Main row
        InkWell(
          onTap: onTap,
          hoverColor: theme.colorScheme.onSurface.withValues(alpha: 0.03),
          child: Container(
            height: d.rowHeight + 16,
            padding: EdgeInsets.symmetric(horizontal: d.panelPad, vertical: 8),
            decoration: BoxDecoration(
              color: rowColor,
              border: Border(
                left: BorderSide(
                  color: isSelected ? theme.colorScheme.onPrimary : Colors.transparent,
                  width: 3,
                ),
                bottom: BorderSide(color: theme.dividerTheme.color!),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    group.count > 1 ? 'GRP' : group.primaryPid.toString(),
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.surfaceDim),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    displayName,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isSelected ? theme.colorScheme.onPrimary : textColor,
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
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.surfaceDim),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${group.totalCpuPercent.toStringAsFixed(1)}%',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: isCpuHot
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.onPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${group.totalPercentMem.toStringAsFixed(1)}%',
                    style: theme.textTheme.bodyLarge?.copyWith(color: textColor),
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
                    icon: Icon(
                      Icons.cancel_outlined,
                      color: theme.colorScheme.error,
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
        final theme = Theme.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          'CONFIRM KILL',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(label, style: theme.textTheme.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'CANCEL',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.surfaceDim),
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
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
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
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.symmetric(horizontal: d.panelPad, vertical: d.gap),
      decoration: BoxDecoration(
        color: theme.colorScheme.onPrimary.withValues(alpha: 0.04),
        border: Border(
          left: BorderSide(color: theme.colorScheme.onPrimary, width: 3),
          bottom: BorderSide(color: theme.dividerTheme.color!),
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
                  color: theme.colorScheme.error,
                  onTap: () => _showKillDialog(context, ref),
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  label: 'COPY NAME',
                  color: theme.colorScheme.surfaceDim,
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
    final theme = Theme.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          'CONFIRM KILL',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          group.count > 1
              ? 'Terminate all ${group.count} instances of ${group.name}?'
              : 'Terminate PID ${group.primaryPid} (${group.name})?',
          style: theme.textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'CANCEL',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.surfaceDim),
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
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HudLabel(label),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onPrimary),
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
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color, fontSize: 11),
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
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerTheme.color!)),
      ),
      child: Row(
        children: [
          Text(
            'Showing $shown of $total processes',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.surfaceDim),
          ),
          const Spacer(),
          if (total > 100)
            InkWell(
              onTap: () =>
                  ref.read(showAllProcessesProvider.notifier).state = !showAll,
              child: Text(
                showAll ? 'SHOW TOP 100' : 'SHOW ALL ($total)',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
