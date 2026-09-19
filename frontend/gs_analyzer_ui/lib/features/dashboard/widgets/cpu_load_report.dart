import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/features/dashboard/widgets/cpu_bar_chart.dart';
import 'package:gs_analyzer_ui/providers/cpu_provider.dart';
import 'package:gs_analyzer_ui/widgets/custom_container.dart';

class CpuLoadReport extends ConsumerStatefulWidget {
  const CpuLoadReport({super.key});

  @override
  ConsumerState<CpuLoadReport> createState() => _CpuLoadReportState();
}

class _CpuLoadReportState extends ConsumerState<CpuLoadReport> {

  @override
  Widget build(BuildContext context) {
    final cpuState = ref.watch(cpuProvider);
    final snapShot = cpuState.snapshot;
    final theme = Theme.of(context);

    if (snapShot == null) {
      return CustomContainer(
        color: theme.colorScheme.surface,
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          height: 240,
          child: Center(
            child: Text('AWAITING CPU TELEMETRY...', style: theme.textTheme.titleMedium),
          ),
        ),
      );
    }

    return CustomContainer(
      color: theme.colorScheme.surface,
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          ListTile(
            isThreeLine: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              'CPU LOAD [AVG]',
              style: theme.textTheme.titleMedium,
            ),
            subtitle: Row(
              children: [
                RichText(
                  text: TextSpan(
                    text: '${snapShot.averageLoad.toStringAsFixed(1)}',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontSize: 28
                    ),
                    children: [
                      TextSpan(
                        text: '%',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w300
                        )
                      )
                    ]
                  )
                ),
              ],
            ),
            trailing: Icon(
              Icons.memory,
              size: 40,
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.1),
            ),
          ),
          const SizedBox(height: 10,),
          SizedBox(
            height: 140,
            child: CpuBarChart(
              coreGroups: snapShot.coreGroups,
            ),
          ),
        ],
      )
    );
  }
}