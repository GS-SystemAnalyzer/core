import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/features/dashboard/widgets/cpu_bar_chart.dart';
import 'package:gs_analyzer_ui/providers/cpu_provider.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';
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

    if (snapShot == null) {
      return CustomContainer(
        color: HudTheme.bgPanel,
        padding: const EdgeInsets.all(20),
        child: const SizedBox(
          height: 240,
          child: Center(
            child: Text('AWAITING CPU TELEMETRY...', style: HudTheme.labelMuted),
          ),
        ),
      );
    }

    return CustomContainer(
      color: HudTheme.bgPanel,
      padding: EdgeInsets.all(20),
      child: Column(
        children: [
          ListTile(
            isThreeLine: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              'CPU LOAD [AVG]',
              style: HudTheme.labelMuted,
            ),
            subtitle: Row(
              children: [
                RichText(
                  text: TextSpan(
                    text: '${snapShot.averageLoad.toStringAsFixed(1)}',
                    style: TextStyle(
                      color: HudTheme.accentCyan,
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
                // const SizedBox(width: 5,),
                // Icon(Icons.arrow_upward, size: 14, color: Colors.greenAccent,),
                // Text(
                //   '2.4%',
                //   style: HudTheme.statGreen,
                // )
              ],
            ),
            trailing: Icon(
              Icons.memory,
              size: 40,
              color: HudTheme.accentCyan.withValues(alpha: 0.1),
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