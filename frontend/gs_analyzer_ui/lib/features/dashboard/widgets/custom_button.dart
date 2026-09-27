import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/cpu_provider.dart';
import 'package:gs_analyzer_ui/providers/ram_provider.dart';
import 'package:gs_analyzer_ui/providers/thermal_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';

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
    final theme = context.HudTheme;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: stable ? theme.accentCyan.withValues(alpha: 0.1) : theme.accentRed.withValues(alpha: 0.1)
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 9,
            color: stable ? theme.accentCyan : theme.accentRed,
          ),
          const SizedBox(width: 5,),
          Text(
            stable ? 'SYSTEM STABLE' : 'SYSTEM UNSTABLE',
            style: TextStyle(
              color: stable ? theme.accentCyan : theme.accentRed,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4
            ),
          )
        ],
      ),
    );
  }
}