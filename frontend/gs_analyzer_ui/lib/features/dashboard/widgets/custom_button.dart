import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/cpu_provider.dart';
import 'package:gs_analyzer_ui/providers/ram_provider.dart';
import 'package:gs_analyzer_ui/providers/thermal_provider.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';

class CustomButton extends ConsumerWidget {
  final EdgeInsets? padding;
  final IconData? icon;
  
  const CustomButton({
    this.padding,
    this.icon,
    super.key
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ramState = ref.watch(ramProvider);
    final CpuState = ref.watch(cpuProvider);
    final thermalState = ref.watch(thermalProvider);
    final stable = !ramState.isCritical && !CpuState.isCritical && !thermalState.isCritical;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: stable ? HudTheme.accentCyan.withValues(alpha: 0.1) : HudTheme.accentRed.withValues(alpha: 0.1)
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 9,
            color: stable ? HudTheme.accentCyan : HudTheme.accentRed,
          ),
          const SizedBox(width: 5,),
          Text(
            stable ? 'SYSTEM STABLE' : 'SYSTEM UNSTABLE',
            style: TextStyle(
              color: stable ? HudTheme.accentCyan : HudTheme.accentRed,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4
            ),
          )
        ],
      ),
    );
  }
}