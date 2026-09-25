import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/process_explorer_provider.dart';
import 'package:gs_analyzer_ui/widgets/custom_container.dart';

class ProcessFilter extends ConsumerStatefulWidget {
  const ProcessFilter({super.key});

  @override
  ConsumerState<ProcessFilter> createState() => _ProcessFilterState();
}

class _ProcessFilterState extends ConsumerState<ProcessFilter> {
  @override
  Widget build(BuildContext context) {
    final sort = ref.watch(processSortModeProvider);
    final status = ref.watch(processStatusFilterProvider);
    final theme = Theme.of(context);

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
    return Row(
      children: [
        PopupMenuButton<ProcessStatusFilter>(
            tooltip: 'Filter by status',
            child: CustomContainer(
              color: theme.dividerTheme.color!,
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                'FILTER BY: $statusLabel'
              ),),
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
          const SizedBox(width: 10),
        PopupMenuButton<ProcessSortMode>(
            tooltip: 'Sort by:',
            child: CustomContainer(
              color: theme.dividerTheme.color!,
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Text(
                'SORT BY: $sortLabel'
              )
            ),
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
      ],
    );
  }
}