import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/cpu_provider.dart';
import 'package:gs_analyzer_ui/providers/thermal_provider.dart';
import 'package:gs_analyzer_ui/models/thermal_telemetry.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';
import 'package:gs_analyzer_ui/utils/hud_label.dart';
import 'package:gs_analyzer_ui/widgets/telemetry_history_chart.dart';
import 'package:gs_analyzer_ui/providers/hud_density_provider.dart';

class ThermalModuleScreen extends ConsumerStatefulWidget {
  const ThermalModuleScreen({super.key});

  @override
  ConsumerState<ThermalModuleScreen> createState() =>
      _ThermalModuleScreenState();
}

class _ThermalModuleScreenState extends ConsumerState<ThermalModuleScreen> {
  bool _isAdvancedExpanded = false;
  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final thermalState = ref.watch(thermalProvider);
    final telemetry = thermalState.telemetry;
    final cpuState = ref.watch(cpuProvider).snapshot;
    final d = ref.watch(hudDensityProvider);

    return Padding(
      padding: EdgeInsets.all(d.panelPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('THERMAL RADAR MODULE', style: HudTheme.headerCyan),

              Row(
                children: [
                  _buildToggleBtn('LIVE VIEW', !_showHistory),
                  _buildToggleBtn('HISTORY', _showHistory),
                ],
              ),

              if (thermalState.isCritical && !_showHistory)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: HudTheme.accentRed.withValues(alpha: 0.2),
                    border: Border.all(color: HudTheme.accentRed),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'OVERHEAT ALERT',
                    style: HudTheme.actionRed,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),

          if (_showHistory)
            const Expanded(
              child: TelemetryHistoryChart(metricKey: 'thermal_cpu_package'),
            )
          else if (telemetry == null)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: HudTheme.accentAmber),
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCpuSection(telemetry, cpuState, d),
                    SizedBox(height: d.gap),

                    if (telemetry.motherBoardCelsius != null ||
                        telemetry.chipsetCelsius != null ||
                        telemetry.ramCelsius != null ||
                        telemetry.ambientCelsius != null) ...[
                      _buildBoardSection(telemetry, d),
                      SizedBox(height: d.gap),
                    ],

                    if (telemetry.nvmeCelsius != null) ...[
                      _buildStorageSection(telemetry, d),
                      SizedBox(height: d.gap),
                    ],

                    if (_hasActiveFans(telemetry)) ...[
                      _buildFansSection(telemetry, d),
                      SizedBox(height: d.gap),
                    ],

                    _buildAdvancedSection(d),
                    SizedBox(height: d.gap * 2),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToggleBtn(String label, bool isSelected) {
    return InkWell(
      onTap: () {
        setState(() {
          _showHistory = label == 'HISTORY';
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? HudTheme.accentCyan.withValues(alpha: 0.1)
              : Colors.transparent,
          border: Border.all(
            color: isSelected ? HudTheme.accentCyan : Colors.white10,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: HudTheme.fontCore,
            color: isSelected ? HudTheme.accentCyan : HudTheme.textDim,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  bool _hasActiveFans(ThermalTelemetry t) {
    return (t.cpuFanRpm ?? 0) > 0 ||
        (t.chassisFan1Rpm ?? 0) > 0 ||
        (t.chassisFan2Rpm ?? 0) > 0 ||
        (t.pumpRpm ?? 0) > 0;
  }

  Widget _buildCpuSection(
    ThermalTelemetry telemetry,
    dynamic cpuState,
    HudDensity d,
  ) {
    return _ThermalSection(
      title: 'CPU',
      icon: Icons.memory_outlined,
      d: d,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PKG: ${telemetry.cpuPackageCelsius?.toStringAsFixed(1) ?? 'N/A'}°C',
                style: const TextStyle(
                  color: HudTheme.accentCyan,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  fontFamily: HudTheme.fontCore,
                ),
              ),
              if (telemetry.isThermalThrottling)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: HudTheme.accentRed.withValues(alpha: 0.2),
                    border: Border.all(color: HudTheme.accentRed),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('THROTTLING', style: HudTheme.actionRed),
                ),
              // Later is i can access the power directly from the hardware
              // Text(
              //   'POWER: ${telemetry.cpuPowerWatts?.toStringAsFixed(1) ?? 'N/A'} W',
              //   style: HudTheme.statGreen,
              Text(
                'POWER: ${_getDisplayPower(telemetry, cpuState)}',
                style: HudTheme.statGreen,
              ),
            ],
          ),

          if (telemetry.coreCelsius.isNotEmpty) ...[
            SizedBox(height: d.gap),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: telemetry.coreCelsius.asMap().entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsetsGeometry.only(right: 8.0),
                    child: _ThermalChip(
                      label: 'C${entry.key}',
                      celsius: entry.value,
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBoardSection(ThermalTelemetry telemetry, HudDensity d) {
    return _ThermalSection(
      title: 'SYSTEM ENVIRONMENT',
      icon: Icons.developer_board_outlined,
      d: d,
      child: Wrap(
        spacing: 32,
        runSpacing: d.gap,
        children: [
          if (telemetry.motherBoardCelsius != null)
            _buildEnvironmentRow('MOBO', telemetry.motherBoardCelsius!),

          if (telemetry.chipsetCelsius != null)
            _buildEnvironmentRow('CHIPSET', telemetry.chipsetCelsius!),

          if (telemetry.ramCelsius != null)
            _buildEnvironmentRow('RAM', telemetry.ramCelsius!),

          if (telemetry.ambientCelsius != null)
            _buildEnvironmentRow('AMBIENT', telemetry.ambientCelsius!),
        ],
      ),
    );
  }

  Widget _buildEnvironmentRow(String label, double temp) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HudLabel('$label: '),
        Text(
          '${temp.toStringAsFixed(1)}°C',
          style: HudTheme.bodyText.copyWith(
            color: HudTheme.textMain,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _buildStorageSection(ThermalTelemetry telemetry, HudDensity d) {
    return _ThermalSection(
      title: 'STORAGE',
      icon: Icons.storage_outlined,
      d: d,
      child: Text(
        'NAME: ${telemetry.nvmeCelsius}°C',
        style: HudTheme.bodyText.copyWith(
          color: HudTheme.textMain,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildFansSection(ThermalTelemetry telemetry, HudDensity d) {
    return _ThermalSection(
      title: 'FANS',
      icon: Icons.air_outlined,
      d: d,
      child: Wrap(
        spacing: 24,
        runSpacing: d.gap,
        children: [
          if ((telemetry.cpuFanRpm ?? 0) > 0)
            _buildFanRow('CPU_FAN', telemetry.cpuFanRpm!),
          if ((telemetry.chassisFan1Rpm ?? 0) > 0)
            _buildFanRow('CHA_FAN1', telemetry.chassisFan1Rpm!),
          if ((telemetry.chassisFan2Rpm ?? 0) > 0)
            _buildFanRow('CHA_FAN2', telemetry.chassisFan2Rpm!),
          if ((telemetry.pumpRpm ?? 0) > 0)
            _buildFanRow('PUMP', telemetry.pumpRpm!),
        ],
      ),
    );
  }

  Widget _buildFanRow(String label, int rpm) {
    Color rpmColor = HudTheme.accentGreen;
    if (rpm > 3500)
      rpmColor = HudTheme.accentRed;
    else if (rpm > 2000)
      rpmColor = HudTheme.accentAmber;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HudLabel('$label: '),
        Text('$rpm RPM', style: HudTheme.statGreen.copyWith(color: rpmColor)),
      ],
    );
  }

  Widget _buildAdvancedSection(HudDensity d) {
    return Material(
      color: HudTheme.bgPanel,
      borderRadius: BorderRadius.circular(12),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          collapsedIconColor: HudTheme.textDim,
          iconColor: HudTheme.accentCyan,
          onExpansionChanged: (expanded) =>
              setState(() => _isAdvancedExpanded = expanded),
          title: Row(
            children: [
              Icon(
                Icons.tune_outlined,
                color: _isAdvancedExpanded
                    ? HudTheme.accentCyan
                    : HudTheme.textDim,
                size: 20,
              ),
              const SizedBox(width: 12),
              HudLabel('ADVANCED', textAlign: TextAlign.left),
            ],
          ),
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: d.panelPad,
                right: d.panelPad,
                bottom: d.panelPad,
                top: 8,
              ),
              child: Wrap(
                spacing: 32,
                runSpacing: d.gap,
                children: [
                  _buildAdvancedRow('GPU_CORE', 'N/A'),
                  _buildAdvancedRow('GPU_HOTSPOT', 'N/A'),
                  _buildAdvancedRow('VRAM_TEMP', 'N/A'),
                  _buildAdvancedRow('GPU_FAN', 'N/A'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedRow(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: HudTheme.labelMuted),
        Text(
          '$value ',
          style: HudTheme.bodyText.copyWith(color: HudTheme.textDim),
        ),
        const Text(
          '[v3.0]',
          style: TextStyle(
            color: Colors.white24,
            fontSize: 10,
            fontFamily: HudTheme.fontCore,
          ),
        ),
      ],
    );
  }

  String _getDisplayPower(ThermalTelemetry telemetry, dynamic cpuState) {
    if (telemetry.cpuPowerWatts != null && telemetry.cpuPowerWatts! > 0) {
      return '${telemetry.cpuPowerWatts!.toStringAsFixed(1)} W';
    }

    if (cpuState != null) {
      const double maxTdp = 45.0;
      const double idlePower = 5.0;
      const double turboPower = 90.0;
      const double baseFrequency = 2.6;

      double loadFactor = cpuState.averageLoad / 100.0;
      double currentGhz = cpuState.currentFrequencyGhz;

      double freqFactor = 1.0;
      if (currentGhz > 0) {
        freqFactor = math.pow((currentGhz / baseFrequency), 2.5).toDouble();
      }

      double estimatePower =
          idlePower + ((maxTdp - idlePower) * loadFactor * freqFactor);

      if (telemetry.isThermalThrottling) {
        estimatePower *= 0.65;
      }

      if (estimatePower > turboPower) {
        estimatePower = turboPower;
      }
      return '~${estimatePower.toStringAsFixed(1)} W';
    }

    return 'N/A W';
  }
}

class _ThermalSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final HudDensity d;

  const _ThermalSection({
    required this.title,
    required this.icon,
    required this.child,
    required this.d,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(d.panelPad),
      decoration: HudTheme.hudPanelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: HudTheme.textDim, size: 20),
              const SizedBox(width: 12),
              HudLabel(title),
            ],
          ),
          SizedBox(height: d.gap),
          child,
        ],
      ),
    );
  }
}

class _ThermalChip extends StatelessWidget {
  final String label;
  final double celsius;
  const _ThermalChip({required this.label, required this.celsius});

  @override
  Widget build(BuildContext context) {
    Color tempColor = HudTheme.accentGreen;
    if (celsius > 85)
      tempColor = HudTheme.accentRed;
    else if (celsius > 70)
      tempColor = HudTheme.accentAmber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tempColor.withValues(alpha: 0.1),
        border: Border.all(color: tempColor.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label:', style: HudTheme.labelMuted),
          const SizedBox(width: 4),
          Text(
            '${celsius.toStringAsFixed(0)}°',
            style: HudTheme.statGreen.copyWith(color: tempColor),
          ),
        ],
      ),
    );
  }
}
