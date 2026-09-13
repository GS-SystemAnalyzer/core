import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/thermal_provider.dart';
import 'package:gs_analyzer_ui/utils/hud_theme.dart';
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
    final telemetry = thermalState.telemetry!;

    return CustomContainer(
      color: HudTheme.bgPanel,
      padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'THERMAL SENSORS',
                style: HudTheme.labelMuted,
              ),
              const SizedBox(height: 17,),
              CustomContainer(
                color: Colors.black,
                child: ListTile(
                  leading: Icon(Icons.thermostat, color: HudTheme.accentCyan,),
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
                  leading: Icon(Icons.thermostat, color: HudTheme.accentGreen,),
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
                  leading: Icon(Icons.thermostat, color: HudTheme.primaryBorder),
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
                  style: HudTheme.statGreen,
                )
              ],
            )
        ],
      )
    );
  }
}