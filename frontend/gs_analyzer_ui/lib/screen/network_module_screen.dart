import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/models/network_telemetry.dart';
import 'package:gs_analyzer_ui/providers/hud_density_provider.dart';
import 'package:gs_analyzer_ui/providers/network_provider.dart';
import 'package:gs_analyzer_ui/utils/formatters.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';
import 'package:gs_analyzer_ui/widgets/telemetry_history_chart.dart';

class NetworkModuleScreen extends ConsumerStatefulWidget {
  const NetworkModuleScreen({super.key});

  @override
  ConsumerState<NetworkModuleScreen> createState() => _NetworkModuleScreenState();
}

class _NetworkModuleScreenState extends ConsumerState<NetworkModuleScreen> {
  bool _showHistory = false;
  String _historyMetric = 'network_rx';

  @override
  Widget build(BuildContext context) {
    final netState = ref.watch(networkProvider);
    final d = ref.watch(hudDensityProvider);

    return Padding(
      padding: EdgeInsets.all(d.panelPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('NETWORK MODULE', style: HudTheme.headerCyan),

              // View Toggle Strip
              Row(
                children: [
                  _buildToggleBtn('LIVE VIEW', !_showHistory),
                  _buildToggleBtn('HISTORY', _showHistory),
                ],
              ),
            ],
          ),
          SizedBox(height: d.gap * 2),

          // Main View Content
          Expanded(
            child: _showHistory
                ? _buildHistoryView(d)
                : _buildLiveView(context, netState, d),
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

  Widget _buildHistoryView(HudDensity d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              onTap: () => setState(() => _historyMetric = 'network_rx'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _historyMetric == 'network_rx'
                      ? HudTheme.accentCyan.withValues(alpha: 0.15)
                      : Colors.transparent,
                  border: Border.all(
                    color: _historyMetric == 'network_rx'
                        ? HudTheme.accentCyan
                        : Colors.white10,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_downward, size: 14, color: HudTheme.accentCyan),
                    const SizedBox(width: 6),
                    Text(
                      'RX (DOWNLOAD)',
                      style: TextStyle(
                        fontFamily: HudTheme.fontCore,
                        color: _historyMetric == 'network_rx'
                            ? HudTheme.accentCyan
                            : HudTheme.textDim,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => setState(() => _historyMetric = 'network_tx'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: _historyMetric == 'network_tx'
                      ? HudTheme.accentAmber.withValues(alpha: 0.15)
                      : Colors.transparent,
                  border: Border.all(
                    color: _historyMetric == 'network_tx'
                        ? HudTheme.accentAmber
                        : Colors.white10,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_upward, size: 14, color: HudTheme.accentAmber),
                    const SizedBox(width: 6),
                    Text(
                      'TX (UPLOAD)',
                      style: TextStyle(
                        fontFamily: HudTheme.fontCore,
                        color: _historyMetric == 'network_tx'
                            ? HudTheme.accentAmber
                            : HudTheme.textDim,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: d.gap),
        Expanded(
          child: TelemetryHistoryChart(
            key: ValueKey(_historyMetric),
            metricKey: _historyMetric,
          ),
        ),
      ],
    );
  }

  Widget _buildLiveView(
    BuildContext context,
    NetworkState state,
    HudDensity d,
  ) {
    final snapshot = state.snapshot;
    final primary = state.primaryInterface;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Active Interface & Dual-line Chart Card
          _buildActiveInterfaceCard(primary, state, d),
          SizedBox(height: d.gap * 2),

          // Session Totals Card
          _buildSessionTotalsCard(primary, d),
          SizedBox(height: d.gap * 2),

          // All Interfaces List Card
          _buildAllInterfacesCard(snapshot, state, d),
        ],
      ),
    );
  }

  Widget _buildActiveInterfaceCard(
    NetInterfaceSnapshot? primary,
    NetworkState state,
    HudDensity d,
  ) {
    if (primary == null || !primary.isUp) {
      return Container(
        padding: EdgeInsets.all(d.panelPad),
        decoration: HudTheme.hudPanelDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('ACTIVE INTERFACE', style: HudTheme.labelMuted),
                Icon(Icons.wifi_off, color: HudTheme.textDim, size: 20),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'NO ACTIVE INTERFACE',
                  style: TextStyle(
                    fontFamily: HudTheme.fontCore,
                    color: HudTheme.textDim,
                    fontSize: 18,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final utilText = primary.utilisationPercent != null && primary.linkSpeedBitsPerSec > 0
        ? '${primary.utilisationPercent!.toStringAsFixed(1)}%'
        : 'N/A';

    return Container(
      padding: EdgeInsets.all(d.panelPad),
      decoration: HudTheme.hudPanelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'ACTIVE: ${primary.name.toUpperCase()}',
                  style: const TextStyle(
                    fontFamily: HudTheme.fontCore,
                    color: HudTheme.accentCyan,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              Text(
                primary.interfaceType.toUpperCase(),
                style: HudTheme.labelMuted.copyWith(fontSize: 11),
              ),
            ],
          ),
          if (primary.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              primary.description,
              style: HudTheme.bodyText.copyWith(color: HudTheme.textDim, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),

          // Primary Stats Row
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  'RX (DOWNLOAD)',
                  formatRate(primary.rxBytesPerSec),
                  Icons.arrow_downward,
                  HudTheme.accentCyan,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricTile(
                  'TX (UPLOAD)',
                  formatRate(primary.txBytesPerSec),
                  Icons.arrow_upward,
                  HudTheme.accentAmber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Sub-stats: Link Speed & Utilisation
          Row(
            children: [
              Expanded(
                child: _buildSubStatTile(
                  'LINK SPEED',
                  formatLinkSpeed(primary.linkSpeedBitsPerSec),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSubStatTile('UTILISATION', utilText),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Dual-Line Chart Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('60-SECOND THROUGHPUT', style: HudTheme.labelMuted),
              Row(
                children: [
                  _buildLegendItem('RX', HudTheme.accentCyan),
                  const SizedBox(width: 16),
                  _buildLegendItem('TX', HudTheme.accentAmber),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 60-Second Dual-Line LineChart
          SizedBox(
            height: 180,
            child: _buildDualLineChart(state),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(
    String label,
    String value,
    IconData icon,
    Color accentColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.05),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(icon, color: accentColor, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: HudTheme.labelMuted.copyWith(fontSize: 10)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontFamily: HudTheme.fontCore,
                  color: accentColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubStatTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        border: Border.all(color: Colors.white10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: HudTheme.labelMuted.copyWith(fontSize: 11)),
          Text(
            value,
            style: const TextStyle(
              fontFamily: HudTheme.fontCore,
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontFamily: HudTheme.fontCore,
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildDualLineChart(NetworkState state) {
    final rxSpots = state.rxRollingSpots;
    final txSpots = state.txRollingSpots;

    if (rxSpots.isEmpty) {
      return const Center(
        child: Text('COLLECTING THROUGHPUT DATA...', style: HudTheme.labelMuted),
      );
    }

    final double minX = rxSpots.first.x;
    final double maxX = rxSpots.last.x;
    final double maxY = state.rollingMaxY;

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          drawHorizontalLine: true,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.white10,
              strokeWidth: 1,
              dashArray: [4, 4],
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 55,
              getTitlesWidget: (value, meta) {
                if (value == 0 || value == maxY) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(right: 4.0),
                  child: Text(
                    formatRate(value),
                    style: HudTheme.labelMuted.copyWith(fontSize: 9),
                    textAlign: TextAlign.right,
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.white10),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (touchedSpot) => HudTheme.bgPanel,
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final isRx = spot.barIndex == 0;
                final label = isRx ? 'RX' : 'TX';
                final color = isRx ? HudTheme.accentCyan : HudTheme.accentAmber;
                return LineTooltipItem(
                  '$label: ${formatRate(spot.y)}',
                  TextStyle(
                    color: color,
                    fontFamily: HudTheme.fontCore,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          // RX Bar Data (Cyan)
          LineChartBarData(
            spots: rxSpots,
            isCurved: true,
            color: HudTheme.accentCyan,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: HudTheme.accentCyan.withValues(alpha: 0.1),
            ),
          ),
          // TX Bar Data (Amber)
          LineChartBarData(
            spots: txSpots,
            isCurved: true,
            color: HudTheme.accentAmber,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: HudTheme.accentAmber.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  Widget _buildSessionTotalsCard(NetInterfaceSnapshot? primary, HudDensity d) {
    final rxTotal = primary?.sessionRxBytes ?? 0;
    final txTotal = primary?.sessionTxBytes ?? 0;

    return Container(
      padding: EdgeInsets.all(d.panelPad),
      decoration: HudTheme.hudPanelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('SESSION TOTALS', style: HudTheme.labelMuted),
              Icon(Icons.data_usage, color: HudTheme.accentCyan, size: 18),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Text('RECEIVED: ', style: HudTheme.labelMuted),
                    Text(
                      formatBytes(rxTotal),
                      style: const TextStyle(
                        fontFamily: HudTheme.fontCore,
                        color: HudTheme.accentCyan,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    const Text('SENT: ', style: HudTheme.labelMuted),
                    Text(
                      formatBytes(txTotal),
                      style: const TextStyle(
                        fontFamily: HudTheme.fontCore,
                        color: HudTheme.accentAmber,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAllInterfacesCard(
    NetworkSnapshot? snapshot,
    NetworkState state,
    HudDensity d,
  ) {
    final interfaces = snapshot?.interfaces ?? [];
    final primaryId = snapshot?.primaryInterfaceId;

    return Container(
      padding: EdgeInsets.all(d.panelPad),
      decoration: HudTheme.hudPanelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ALL INTERFACES', style: HudTheme.labelMuted),
              Text(
                '${interfaces.length} TOTAL',
                style: HudTheme.labelMuted.copyWith(fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (interfaces.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: Text('NO NETWORK ADAPTERS DETECTED', style: HudTheme.labelMuted),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: interfaces.length,
              separatorBuilder: (context, index) => const Divider(
                height: 1,
                color: Colors.white10,
              ),
              itemBuilder: (context, index) {
                final nic = interfaces[index];
                final isPrimary = nic.id == primaryId;

                return InkWell(
                  onTap: () {
                    ref.read(networkProvider.notifier).setPreferredInterface(
                      isPrimary ? null : nic.id,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 4.0),
                    child: Row(
                      children: [
                        // Up/Down status dot
                        Icon(
                          nic.isUp ? Icons.circle : Icons.circle_outlined,
                          size: 10,
                          color: nic.isUp ? HudTheme.accentCyan : HudTheme.textDim,
                        ),
                        const SizedBox(width: 10),

                        // Name and type
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      nic.name.toUpperCase(),
                                      style: TextStyle(
                                        fontFamily: HudTheme.fontCore,
                                        color: nic.isUp ? Colors.white : HudTheme.textDim,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isPrimary) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: HudTheme.accentCyan.withValues(alpha: 0.15),
                                        border: Border.all(color: HudTheme.accentCyan, width: 0.8),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: const Text(
                                        'PINNED',
                                        style: TextStyle(
                                          fontFamily: HudTheme.fontCore,
                                          color: HudTheme.accentCyan,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                nic.interfaceType,
                                style: HudTheme.labelMuted.copyWith(fontSize: 11),
                              ),
                            ],
                          ),
                        ),

                        // Throughput or DOWN status
                        Expanded(
                          flex: 3,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: nic.isUp
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        formatRate(nic.rxBytesPerSec),
                                        style: const TextStyle(
                                          fontFamily: HudTheme.fontCore,
                                          color: HudTheme.accentCyan,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      const Icon(Icons.arrow_downward, size: 12, color: HudTheme.accentCyan),
                                      const SizedBox(width: 8),
                                      Text(
                                        formatRate(nic.txBytesPerSec),
                                        style: const TextStyle(
                                          fontFamily: HudTheme.fontCore,
                                          color: HudTheme.accentAmber,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      const Icon(Icons.arrow_upward, size: 12, color: HudTheme.accentAmber),
                                    ],
                                  )
                                : Text(
                                    'DOWN',
                                    style: HudTheme.labelMuted.copyWith(
                                      color: HudTheme.textDim,
                                      fontSize: 12,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
