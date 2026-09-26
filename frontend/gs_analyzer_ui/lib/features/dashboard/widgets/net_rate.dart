import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/network_provider.dart';
import 'package:gs_analyzer_ui/utils/formatters.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';
import 'package:gs_analyzer_ui/widgets/custom_container.dart';

class NetRate extends ConsumerStatefulWidget {
  const NetRate({super.key});

  @override
  ConsumerState<NetRate> createState() => _NetRateState();
}

class _NetRateState extends ConsumerState<NetRate> {
  String _getSimplifiedName(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('cellular')) return 'Cellular';
    if (lower.contains('wi-fi') || lower.contains('wifi') || lower.contains('wireless')) return 'Wi-Fi';
    if (lower.contains('ethernet')) return 'Ethernet';
    
    final parts = name.split('-');
    if (parts.isNotEmpty) {
      return parts[0].trim();
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final netState = ref.watch(networkProvider);
    final primary = netState.primaryInterface;
    final theme = context.HudTheme;
    
    if (primary == null) {
      return CustomContainer(
        color: theme.panel,
        padding: EdgeInsets.all(20),
        child: Center(
          child:  SizedBox(
            height: 240,
            child: Center(
              child: Text('AWAITING CPU TELEMETRY...', style: theme.label),
            ),
          ),
        ),
      );
    }

    return 
      CustomContainer(
        color: theme.panel,
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NET IO',
              style: theme.label,
            ),
            const SizedBox(height: 10,),
            Text(
              'ACTIVE: ${_getSimplifiedName(primary.name)}',
              style: theme.statCyan.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.bold
              ),
            ),
            const SizedBox(height: 15,),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: theme.accentCyan.withValues(alpha: 0.1),
                foregroundColor: theme.accentCyan,
                radius: 18,
                child: Icon(
                  Icons.arrow_downward
                ),
              ),
              title: Text(
                'RX RATE',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white60
                ),
              ),
              subtitle: Text(
                formatRate(primary.rxBytesPerSec),
                style: theme.statCyan.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold
                ),
              )
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: theme.accentAmber.withValues(alpha: 0.1),
                foregroundColor: theme.accentAmber,
                radius: 18,
                child: Icon(
                  Icons.arrow_upward
                ),
              ),
              title: Text(
                'TX RATE',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white60
                ),
              ),
              subtitle: Text(
                formatRate(primary.txBytesPerSec),
                style: TextStyle(
                  fontSize: 16,
                  color: theme.accentAmber,
                  fontWeight: FontWeight.bold
                ),
              )
            ),
            const SizedBox(height: 60,)
          ],
        ), 
      );
  }
}