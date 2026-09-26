import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/hud_density_provider.dart';
import 'package:gs_analyzer_ui/utils/hud_label.dart';
import 'package:gs_analyzer_ui/providers/process_explorer_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';

class ProcessTable extends ConsumerStatefulWidget {
  const ProcessTable({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _ProcessTableState();    
}

class _ProcessTableState extends ConsumerState<ProcessTable> {

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(hudDensityProvider);
    final currentSort = ref.watch(processSortModeProvider);

    Widget buildHeader(String label, ProcessSortMode? sortMode) {
      final isSorted = currentSort == sortMode;
      return Expanded(
        child: InkWell(
          onTap: sortMode != null
              ? () => ref.read(processSortModeProvider.notifier).state = sortMode
              : null,
          child: Row(
            children: [
              HudLabel(label),
              if (isSorted)
                Icon(Icons.arrow_drop_down, color: context.HudTheme.accentCyan, size: 16),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: d.rowHeight + 16,
      child: Row(
        children: [
          buildHeader('PID', ProcessSortMode.pid),
          buildHeader('COMMAND', ProcessSortMode.name),
          Expanded(child: HudLabel('USER')), // Not sortable yet
          buildHeader('%CPU', ProcessSortMode.cpu),
          buildHeader('%MEM', ProcessSortMode.ram),
          Expanded(child: HudLabel('STATUS')), // Not sortable via sort provider
        ],
      ),
    );
  }
}