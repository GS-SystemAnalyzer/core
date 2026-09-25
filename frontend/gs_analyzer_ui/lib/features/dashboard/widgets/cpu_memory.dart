import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/features/dashboard/widgets/custom_progress_indicator.dart';
import 'package:gs_analyzer_ui/providers/ram_provider.dart';
import 'package:gs_analyzer_ui/providers/ram_alert_provider.dart';
import 'package:gs_analyzer_ui/utils/hud_label.dart';
import 'package:gs_analyzer_ui/widgets/custom_container.dart';

class CpuMemory extends ConsumerStatefulWidget {
  const CpuMemory({super.key});

  @override
  ConsumerState<CpuMemory> createState() => _CpuMemoryState();
}

class _CpuMemoryState extends ConsumerState<CpuMemory>{

  @override
  Widget build(BuildContext context) {
    final ramstate = ref.watch(ramProvider);
    final ramAlert = ref.watch(ramAlertProvider);
    final theme = Theme.of(context);

    return CustomContainer(
      color: theme.colorScheme.surface,
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  HudLabel('MeM ALLOCATION'),
                  if (ramAlert != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: ramAlert.severity == 'critical' ? theme.colorScheme.error : theme.colorScheme.tertiary,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        ramAlert.severity == 'critical' ? 'CRITICAL' : 'PRESSURE',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Icon(
                Icons.memory,
                size: 40,
                color: theme.colorScheme.secondary.withValues(alpha: 0.1),
              )
            ],
          ),
          const SizedBox(height: 20,),
          // ListTile(
          //   // isThreeLine: true,
          //   contentPadding: EdgeInsets.zero,
          //   title: Text(
          //     'MEM_ALLOCATION',
          //     style: HudTheme.statGreen,
          //   ),
          //   // subtitle: RichText(
          //   //   text: TextSpan(
          //   //     text: '${drive.percentageUsed.toStringAsFixed(0)}',
          //   //     style: TextStyle(
          //   //       fontSize: 28,
          //   //       color: Colors.greenAccent
          //   //     ),
          //   //     children: [
          //   //       TextSpan(
          //   //         text: '%',
          //   //         style: HudTheme.statGreen
          //   //       ),
          //   //       TextSpan(
          //   //         text: ' of ${_formatGB(drive.totalBytes)}GB',
          //   //         style: TextStyle(
          //   //           fontSize: 14,
          //   //           color: Colors.white
          //   //         )
          //   //       )
          //   //     ]
          //   //   )
          //   // ),
          //   trailing: Icon(
          //     Icons.analytics_outlined,
          //     size: 35,
          //     color: Color(0xFF38453B),
          //   ),
          // ),
          // 
          CustomProgressIndicator(
            label: 'Active', 
            tag: '${ramstate.activeGb.toStringAsFixed(1)} GB', 
            value: ramstate.totalGb > 0 ? ramstate.activeGb / ramstate.totalGb : 0.0, 
            height: 6,
            color: AlwaysStoppedAnimation(Colors.greenAccent),
          ),
          const SizedBox(height: 20,),
          Spacer(),
          Row(
            children: [
              Expanded(
                child: CustomContainer(
                  color: theme.dividerTheme.color!,
                  padding: EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CACHED',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500
                        ),
                      ),
                      const SizedBox(height: 4,),
                      Text(
                        '${ramstate.cacheGb.toStringAsFixed(1)} GB',
                        style: TextStyle(
                          fontSize: 17
                        ),
                      )
                    ],
                  )             
                ),
              ),
              const SizedBox(width: 10,),
              Expanded(
                child: CustomContainer(
                  color: theme.dividerTheme.color!,
                  padding: EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SWAP',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500
                        ),
                      ),
                      const SizedBox(height: 4,),
                      Text(
                        '${ramstate.swapGb.toStringAsFixed(1)} GB',
                        style: TextStyle(
                          fontSize: 17
                        ),
                      )
                    ],
                  )
                ),
              )
            ],
          ),
          const SizedBox(height: 10,),
        ],
      )
    );
  }
}