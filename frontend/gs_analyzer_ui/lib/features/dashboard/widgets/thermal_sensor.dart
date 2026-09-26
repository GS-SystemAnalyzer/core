import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/thermal_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';
import 'package:gs_analyzer_ui/widgets/custom_container.dart';

class ThermalSensor extends ConsumerStatefulWidget {
  const ThermalSensor({super.key});

  @override
  ConsumerState<ThermalSensor> createState() => _ThermalSensorState();
}

class _ThermalSensorState extends ConsumerState<ThermalSensor> {
  @override
  Widget build(BuildContext context) {
    final thermalState = ref.watch(thermalProvider);
    final telemetry = thermalState.telemetry;
    final theme = context.HudTheme;

    if (telemetry == null) {
      return CustomContainer(
        color: theme.panel,
        padding: const EdgeInsets.all(20),
        child:  SizedBox(
          height: 240,
          child: Center(
            child: Text('AWAITING CPU TELEMETRY...', style: theme.label),
          ),
        ),
      );
    }

    return CustomContainer(
      color: theme.panel,
      padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'THERMAL SENSORS',
                style: theme.label,
              ),
              const SizedBox(height: 17,),
              CustomContainer(
                color: Colors.black,
                child: ListTile(
                  leading: Icon(Icons.thermostat, color: theme.accentCyan,),
                    title: Text(
                      'CPU_PKG'
                    ),
                  trailing: Text(
                    '${telemetry.cpuPackageCelsius?.toStringAsFixed(1) ?? 'N/A'}\u{00B0}C',
                    style: TextStyle(
                      fontSize: 18
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15,),
              CustomContainer(
                color: Colors.black,
                child: ListTile(
                  leading: Icon(Icons.thermostat, color: theme.accentGreen,),
                  title: Text(
                    'SYS_BOARD'
                  ),
                  trailing: Text(
                    '${telemetry.motherBoardCelsius ?? 'N/A'}\u{00B0}C',
                    style: TextStyle(
                      fontSize: 18
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15,),
              CustomContainer(
                color: Colors.black,
                child: ListTile(
                  leading: Icon(Icons.thermostat, color: theme.border),
                  title: Text(
                    'AMBIENT'
                  ),
                  trailing: Text(
                    '${telemetry.ambientCelsius ?? 'N/A'}\u{00B0}C',
                    style: TextStyle(
                      fontSize: 18
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 50,),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'FAN SPEED',
                ),
                Text(
                  '${telemetry.cpuFanRpm} rpm',
                  style: theme.statGreen,
                )
              ],
            )
        ],
      )
    );
  }
}