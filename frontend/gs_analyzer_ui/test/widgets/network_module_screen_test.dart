import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/network_telemetry.dart';
import 'package:gs_analyzer_ui/providers/network_provider.dart';
import 'package:gs_analyzer_ui/screen/network_module_screen.dart';

class MockNetworkNotifier extends NetworkNotifier {
  final NetworkSnapshot? initialSnapshot;
  MockNetworkNotifier(this.initialSnapshot);
}

void main() {
  testWidgets(
    'NetworkModuleScreen renders offline state when no primary interface',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: NetworkModuleScreen())),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('NETWORK MODULE'), findsOneWidget);
      expect(find.text('NO ACTIVE INTERFACE'), findsOneWidget);
      expect(find.text('LIVE VIEW'), findsOneWidget);
      expect(find.text('HISTORY'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'NetworkModuleScreen renders active interface details when primary is available',
    (tester) async {
      final testSnapshot = NetworkSnapshot(
        timestamp: DateTime.now(),
        primaryInterfaceId: '{test-nic-id}',
        interfaces: [
          NetInterfaceSnapshot(
            id: '{test-nic-id}',
            name: 'Wi-Fi 6',
            description: 'Intel AX200',
            interfaceType: 'Wireless80211',
            isUp: true,
            linkSpeedBitsPerSec: 866000000,
            rxBytesPerSec: 1048576.0,
            txBytesPerSec: 524288.0,
            utilisationPercent: 1.2,
            sessionRxBytes: 104857600,
            sessionTxBytes: 52428800,
          ),
        ],
      );

      final mockNotifier = MockNetworkNotifier(testSnapshot);
      mockNotifier.updateFromSnapshot(testSnapshot);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [networkProvider.overrideWith((ref) => mockNotifier)],
          child: const MaterialApp(home: Scaffold(body: NetworkModuleScreen())),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('ACTIVE: WI-FI 6'), findsOneWidget);
      expect(find.text('Intel AX200'), findsOneWidget);
      expect(
        find.text('1.00 MB/s'),
        findsNWidgets(2),
      ); // in primary tile + all interfaces row
      expect(
        find.text('512.0 KB/s'),
        findsNWidgets(2),
      ); // in primary tile + all interfaces row
      expect(find.text('866 Mbps'), findsOneWidget);
      expect(find.text('1.2%'), findsOneWidget);
      expect(find.text('100.00 MB'), findsOneWidget);
      expect(find.text('50.00 MB'), findsOneWidget);
      expect(find.text('PINNED'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
