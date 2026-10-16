import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/features/dashboard/widgets/net_rate.dart';
import 'package:gs_analyzer_ui/models/network_telemetry.dart';
import 'package:gs_analyzer_ui/providers/network_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/widgets/custom_container.dart';

class MockNetworkNotifier extends StateNotifier<NetworkState>
    implements NetworkNotifier {
  MockNetworkNotifier([NetworkState state = const NetworkState()]) : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('NetRate Theme & Widget Tests', () {
    testWidgets('renders placeholder when primaryInterface is null and adapts panel color', (tester) async {
      final emptyState = const NetworkState(snapshot: null);

      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkProvider.overrideWith((ref) => MockNetworkNotifier(emptyState)),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: NetRate(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('COLLECTING DATA — CHECK BACK IN A MOMENT'), findsOneWidget);
      final lightContainer = tester.widget<CustomContainer>(find.byType(CustomContainer));
      expect(lightContainer.color, equals(HudColor.lightBgPanel));

      final lightPlaceholderText = tester.widget<Text>(find.text('COLLECTING DATA — CHECK BACK IN A MOMENT'));
      expect(lightPlaceholderText.style?.color, equals(HudColor.lightTextDim));

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkProvider.overrideWith((ref) => MockNetworkNotifier(emptyState)),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: NetRate(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('COLLECTING DATA — CHECK BACK IN A MOMENT'), findsOneWidget);
      final darkContainer = tester.widget<CustomContainer>(find.byType(CustomContainer));
      expect(darkContainer.color, equals(HudColor.darkBgPanel));

      final darkPlaceholderText = tester.widget<Text>(find.text('COLLECTING DATA — CHECK BACK IN A MOMENT'));
      expect(darkPlaceholderText.style?.color, equals(HudColor.darkTextDim));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('renders active interface rates and adapts textDim labels and avatars between themes', (tester) async {
      final sampleNic = NetInterfaceSnapshot(
        id: 'eth-1',
        name: 'Ethernet-Adapter',
        description: 'Gigabit Network',
        interfaceType: 'Ethernet',
        isUp: true,
        linkSpeedBitsPerSec: 1000000000,
        rxBytesPerSec: 10485760.0, // 10.00 MB/s
        txBytesPerSec: 5242880.0,  // 5.00 MB/s
        sessionRxBytes: 10485760,
        sessionTxBytes: 5242880,
      );

      final populatedSnapshot = NetworkSnapshot(
        timestamp: DateTime.now(),
        primaryInterfaceId: 'eth-1',
        interfaces: [sampleNic],
      );

      final populatedState = NetworkState(
        snapshot: populatedSnapshot,
        preferredInterfaceId: 'eth-1',
      );

      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkProvider.overrideWith((ref) => MockNetworkNotifier(populatedState)),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: NetRate(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('NET IO'), findsOneWidget);
      expect(find.text('ACTIVE: Ethernet'), findsOneWidget);
      expect(find.text('10.00 MB/s'), findsOneWidget);
      expect(find.text('5.00 MB/s'), findsOneWidget);

      final lightRxLabel = tester.widget<Text>(find.text('RX RATE'));
      expect(lightRxLabel.style?.color, equals(HudColor.lightTextDim));

      final lightTxLabel = tester.widget<Text>(find.text('TX RATE'));
      expect(lightTxLabel.style?.color, equals(HudColor.lightTextDim));

      final lightAvatars = tester.widgetList<CircleAvatar>(find.byType(CircleAvatar)).toList();
      expect(lightAvatars.length, 2);
      // Downward (RX) avatar
      expect(lightAvatars[0].backgroundColor, equals(HudColor.lightAccentCyan.withValues(alpha: 0.1)));
      expect(lightAvatars[0].foregroundColor, equals(HudColor.lightAccentCyan));
      // Upward (TX) avatar
      expect(lightAvatars[1].backgroundColor, equals(HudColor.lightAccentAmber.withValues(alpha: 0.1)));
      expect(lightAvatars[1].foregroundColor, equals(HudColor.lightAccentAmber));

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkProvider.overrideWith((ref) => MockNetworkNotifier(populatedState)),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: NetRate(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('NET IO'), findsOneWidget);
      expect(find.text('ACTIVE: Ethernet'), findsOneWidget);
      expect(find.text('10.00 MB/s'), findsOneWidget);
      expect(find.text('5.00 MB/s'), findsOneWidget);

      final darkRxLabel = tester.widget<Text>(find.text('RX RATE'));
      expect(darkRxLabel.style?.color, equals(HudColor.darkTextDim));

      final darkTxLabel = tester.widget<Text>(find.text('TX RATE'));
      expect(darkTxLabel.style?.color, equals(HudColor.darkTextDim));

      final darkAvatars = tester.widgetList<CircleAvatar>(find.byType(CircleAvatar)).toList();
      expect(darkAvatars.length, 2);
      // Downward (RX) avatar
      expect(darkAvatars[0].backgroundColor, equals(HudColor.darkAccentCyan.withValues(alpha: 0.1)));
      expect(darkAvatars[0].foregroundColor, equals(HudColor.darkAccentCyan));
      // Upward (TX) avatar
      expect(darkAvatars[1].backgroundColor, equals(HudColor.darkAccentAmber.withValues(alpha: 0.1)));
      expect(darkAvatars[1].foregroundColor, equals(HudColor.darkAccentAmber));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
