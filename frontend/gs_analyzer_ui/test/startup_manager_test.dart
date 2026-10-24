import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/startup_program.dart';
import 'package:gs_analyzer_ui/providers/startup_provider.dart';
import 'package:gs_analyzer_ui/screen/startup_manager_screen.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:mocktail/mocktail.dart';

class MockApiService extends Mock implements ApiService {}

void main() {
  late MockApiService mockApi;

  setUp(() {
    mockApi = MockApiService();
  });

  group('Startup Manager Engine Test', () {
    test('Test 1: Core Engine Initialization (Loads Programs Successfully)', () async {
      final fakePrograms = [
        const StartupProgram(
          id: 'test_123',
          name: 'Discord',
          executablePath: 'C:\\Discord\\discord.exe',
          isEnabled: true,
          scope: 'user',
          platform: 'windows',
        ),
      ];

      when(() => mockApi.getStartupPrograms()).thenAnswer((_) async => fakePrograms);

      final notifier = StartupNotifier(mockApi);
      await notifier.load();

      final state = notifier.state;

      expect(state.isLoading, false, reason: 'State must not be loading after load finishes!');
      expect(state.hasValue, true, reason: 'State must have data!');
      expect(state.value!.length, 1, reason: 'CRITICAL: Startup list size is incorrect!');
      expect(state.value!.first.name, 'Discord', reason: 'Parsed program data is corrupted!');
    });

    test('Test 2: Optimistic UI Shield (Toggles State Instantly)', () async {
      final fakePrograms = [
        const StartupProgram(
          id: 'test_123',
          name: 'Discord',
          executablePath: 'C:\\Discord\\discord.exe',
          isEnabled: true,
          scope: 'user',
          platform: 'windows',
        ),
      ];

      when(() => mockApi.getStartupPrograms()).thenAnswer((_) async => fakePrograms);
      when(() => mockApi.setStartupEnabled(any(), any(), scope: any(named: 'scope'))).thenAnswer((_) async {});

      final notifier = StartupNotifier(mockApi);
      await notifier.load();
      
      final program = notifier.state.value!.first;
      
      // Perform toggle (true -> false)
      await notifier.toggle(program);
      
      final updatedProgram = notifier.state.value!.first;
      expect(
        updatedProgram.isEnabled, 
        false, 
        reason: 'CRITICAL FAILURE: The engine did not optimistically update the UI toggle state before the network call finished!',
      );
      
      verify(() => mockApi.setStartupEnabled('test_123', false, scope: 'user')).called(1);
    });

    test('Test 3: The Overload Reversal (Reverts State on Backend Failure)', () async {
      final fakePrograms = [
        const StartupProgram(
          id: 'test_123',
          name: 'Discord',
          executablePath: 'C:\\Discord\\discord.exe',
          isEnabled: true,
          scope: 'user',
          platform: 'windows',
        ),
      ];

      when(() => mockApi.getStartupPrograms()).thenAnswer((_) async => fakePrograms);
      when(() => mockApi.setStartupEnabled(any(), any(), scope: any(named: 'scope'))).thenThrow(Exception('Backend Offline'));

      final notifier = StartupNotifier(mockApi);
      await notifier.load();
      
      final program = notifier.state.value!.first;
      
      try {
        await notifier.toggle(program);
      } catch (_) {
        // Expected to throw
      }
      
      final revertedProgram = notifier.state.value!.first;
      expect(
        revertedProgram.isEnabled, 
        true, 
        reason: 'CRITICAL: The engine did not revert the optimistic UI update after a backend failure!',
      );
    });

    test('Test 4: Nuclear Delete (Removes Program Optimistically)', () async {
      final fakePrograms = [
        const StartupProgram(
          id: 'target_1',
          name: 'Malware',
          executablePath: 'C:\\temp\\virus.exe',
          isEnabled: true,
          scope: 'user',
          platform: 'windows',
        ),
      ];

      when(() => mockApi.getStartupPrograms()).thenAnswer((_) async => fakePrograms);
      when(() => mockApi.deleteStartupProgram(any())).thenAnswer((_) async {});

      final notifier = StartupNotifier(mockApi);
      await notifier.load();
      
      final program = notifier.state.value!.first;
      await notifier.remove(program);
      
      expect(
        notifier.state.value!.length, 
        0, 
        reason: 'CRITICAL: The Nuke function failed to remove the target from the startup array!',
      );
      
      verify(() => mockApi.deleteStartupProgram('target_1')).called(1);
    });

    testWidgets('Test 5: System scope startup entry renders ADMIN REQUIRED badge and shows dialog on tap', (tester) async {
      final fakePrograms = [
        const StartupProgram(
          id: 'sys_app',
          name: 'SecurityHealth',
          executablePath: 'C:\\Windows\\System32\\SecurityHealthSystray.exe',
          isEnabled: true,
          scope: 'system',
          platform: 'windows',
        ),
      ];

      when(() => mockApi.getStartupPrograms()).thenAnswer((_) async => fakePrograms);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            startupProvider.overrideWith((ref) => StartupNotifier(mockApi)..load()),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: StartupManagerScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ADMIN REQUIRED'), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);

      await tester.tap(find.text('ADMIN REQUIRED'));
      await tester.pumpAndSettle();

      expect(find.text('ADMINISTRATOR PRIVILEGES REQUIRED'), findsOneWidget);
    });

    testWidgets('Test 6: Empty startup entry list renders NO STARTUP ENTRIES FOUND', (tester) async {
      when(() => mockApi.getStartupPrograms()).thenAnswer((_) async => []);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            startupProvider.overrideWith((ref) => StartupNotifier(mockApi)..load()),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: StartupManagerScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('NO STARTUP ENTRIES FOUND'), findsOneWidget);
    });

    testWidgets('Test 7: Displays Startup Folder and AppModel items correctly', (tester) async {
      final fakePrograms = [
        const StartupProgram(
          id: 'folder|user|Ollama.lnk',
          name: 'Ollama',
          executablePath: 'C:\\Users\\User\\AppData\\Roaming\\Microsoft\\Windows\\Start Menu\\Programs\\Startup\\Ollama.lnk',
          isEnabled: true,
          scope: 'user',
          platform: 'windows',
        ),
        const StartupProgram(
          id: 'appmodel|Claude_pzs8sxrjxfjjc|ClaudeStartup',
          name: 'Claude',
          executablePath: 'Claude_pzs8sxrjxfjjc',
          isEnabled: false,
          scope: 'user',
          platform: 'windows',
        ),
      ];

      when(() => mockApi.getStartupPrograms()).thenAnswer((_) async => fakePrograms);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            startupProvider.overrideWith((ref) => StartupNotifier(mockApi)..load()),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: StartupManagerScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ollama'), findsOneWidget);
      expect(find.text('Claude'), findsOneWidget);
      expect(find.text('USER'), findsNWidgets(2));
    });
  });
}
