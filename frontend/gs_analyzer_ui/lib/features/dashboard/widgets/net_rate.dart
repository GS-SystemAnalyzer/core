import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/network_provider.dart';
import 'package:gs_analyzer_ui/utils/formatters.dart';
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
    final theme = Theme.of(context);
    
    if (primary == null) {
      return CustomContainer(
        color: theme.colorScheme.surface,
        padding: EdgeInsets.all(20),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return 
      CustomContainer(
        color: theme.colorScheme.surface,
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NET IO',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 10,),
            Text(
              'ACTIVE: ${_getSimplifiedName(primary.name)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.bold
              ),
            ),
            const SizedBox(height: 15,),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.onPrimary.withValues(alpha: 0.1),
                foregroundColor: theme.colorScheme.onPrimary,
                radius: 18,
                child: Icon(
                  Icons.arrow_downward
                ),
              ),
              title: Text(
                'RX RATE',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.surfaceDim
                ),
              ),
              subtitle: Text(
                formatRate(primary.rxBytesPerSec),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold
                ),
              )
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.tertiary.withValues(alpha: 0.1),
                foregroundColor: theme.colorScheme.tertiary,
                radius: 18,
                child: Icon(
                  Icons.arrow_upward
                ),
              ),
              title: Text(
                'TX RATE',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.surfaceDim
                ),
              ),
              subtitle: Text(
                formatRate(primary.txBytesPerSec),
                style: TextStyle(
                  fontSize: 16,
                  color: theme.colorScheme.tertiary,
                  fontWeight: FontWeight.bold
                ),
              )
              
              // RichText(
              //   text: TextSpan(
              //     text: formatRate(primary.txBytesPerSec),
              //     style: TextStyle(
              //       fontSize: 16,
              //       fontWeight: FontWeight.bold
              //     ),
              //     children: [
              //       TextSpan(
              //         text: ' MB/S',
              //         style: TextStyle(
              //           fontSize: 13,
              //           color: HudTheme.accentAmber
              //         )
              //       )
              //     ]
              //   )
              // )
            ),
            const SizedBox(height: 60,)
          ],
        ), 
      );
  }
}