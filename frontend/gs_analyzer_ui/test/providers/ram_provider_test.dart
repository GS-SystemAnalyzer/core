import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/process_telemetry.dart';
import 'package:gs_analyzer_ui/providers/ram_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/globals.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockApiService extends Mock implements ApiService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late MockApiService mockApi;

  final proc1 = ProcessTelemetry(
    pid: 1001,
    name: 'app.exe',
    ramMb: 128.0,
    percentMem: 1.0,
    cpuPercent: 2.0,
    status: 'RUNNING',
    user: 'User',
  );

  final proc2 = ProcessTelemetry(
    pid: 1002,
    name: 'app.exe',
    ramMb: 256.0,
    percentMem: 2.0,
    cpuPercent: 3.0,
    status: 'RUNNING',
    user: 'User',
  );

  final systemProc = ProcessTelemetry(
    pid: 4,
    name: 'System',
    ramMb: 512.0,
    percentMem: 4.0,
    cpuPercent: 0.5,
    status: 'RUNNING',
    user: 'SYSTEM',
  );

  setUp(() {
    mockApi = MockApiService();
    when(() => mockApi.startRamRadar()).thenAnswer((_) async {});
  });

  group('RamNotifier killProcess & killProcessGroup tests', () {
    test('killProcess removes process on success', () async {
      when(() => mockApi.killRamProcesses([1001])).thenAnswer((_) async => true);

      final container = ProviderContainer(
        overrides: [
          ramProvider.overrideWith((ref) => RamNotifier(ref, mockApi)),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(ramProvider.notifier);
      final initialGroup = ProcessGroup(name: 'app.exe', processes: [proc1, proc2]);
      notifier.debugSetGroupsForTest([initialGroup]);

      await notifier.killProcess(1001);

      final state = notifier.state;
      expect(state.groupedProcesses.length, 1);
      expect(state.groupedProcesses.first.processes.length, 1);
      expect(state.groupedProcesses.first.processes.first.pid, 1002);
      expect(state.errorMessage, isNull);
      verify(() => mockApi.killRamProcesses([1001])).called(1);
    });

    test('killProcess preserves state and sets errorMessage on backend failure', () async {
      when(() => mockApi.killRamProcesses([4])).thenThrow(
        Exception('Access Denied: Run as Administrator to kill this process'),
      );

      final container = ProviderContainer(
        overrides: [
          ramProvider.overrideWith((ref) => RamNotifier(ref, mockApi)),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(ramProvider.notifier);
      final initialGroup = ProcessGroup(name: 'System', processes: [systemProc]);
      notifier.debugSetGroupsForTest([initialGroup]);

      await notifier.killProcess(4);

      final state = notifier.state;
      // Process should remain in the list without ever disappearing
      expect(state.groupedProcesses.length, 1);
      expect(state.groupedProcesses.first.processes.first.pid, 4);
      expect(
        state.errorMessage,
        'Access Denied: Run as Administrator to kill this process',
      );
      verify(() => mockApi.killRamProcesses([4])).called(1);
    });

    test('killProcess formats friendly message on SocketException / network error', () async {
      when(() => mockApi.killRamProcesses([4])).thenThrow(
        Exception(
          'ClientException with SocketException: The remote computer refused the network connection, errno = 1225',
        ),
      );

      final container = ProviderContainer(
        overrides: [
          ramProvider.overrideWith((ref) => RamNotifier(ref, mockApi)),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(ramProvider.notifier);
      final initialGroup = ProcessGroup(name: 'System', processes: [systemProc]);
      notifier.debugSetGroupsForTest([initialGroup]);

      await notifier.killProcess(4);

      final state = notifier.state;
      expect(state.groupedProcesses.length, 1);
      expect(state.groupedProcesses.first.processes.first.pid, 4);
      expect(
        state.errorMessage,
        'Backend offline: Unable to connect to Analyzer service (localhost:5200)',
      );
    });

    test('killProcessGroup removes group on success', () async {
      when(() => mockApi.killRamProcesses([1001, 1002])).thenAnswer((_) async => true);

      final container = ProviderContainer(
        overrides: [
          ramProvider.overrideWith((ref) => RamNotifier(ref, mockApi)),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(ramProvider.notifier);
      final group = ProcessGroup(name: 'app.exe', processes: [proc1, proc2]);
      final sysGroup = ProcessGroup(name: 'System', processes: [systemProc]);
      notifier.debugSetGroupsForTest([group, sysGroup]);

      await notifier.killProcessGroup('app.exe');

      final state = notifier.state;
      expect(state.groupedProcesses.length, 1);
      expect(state.groupedProcesses.first.name, 'System');
      expect(state.errorMessage, isNull);
      verify(() => mockApi.killRamProcesses([1001, 1002])).called(1);
    });

    test('killProcessGroup preserves state and sets errorMessage on failure', () async {
      when(() => mockApi.killRamProcesses([1001, 1002])).thenThrow(
        Exception('Access Denied: Run as Administrator to kill this process'),
      );

      final container = ProviderContainer(
        overrides: [
          ramProvider.overrideWith((ref) => RamNotifier(ref, mockApi)),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(ramProvider.notifier);
      final group = ProcessGroup(name: 'app.exe', processes: [proc1, proc2]);
      notifier.debugSetGroupsForTest([group]);

      await notifier.killProcessGroup('app.exe');

      final state = notifier.state;
      expect(state.groupedProcesses.length, 1);
      expect(state.groupedProcesses.first.name, 'app.exe');
      expect(state.groupedProcesses.first.processes.length, 2);
      expect(
        state.errorMessage,
        'Access Denied: Run as Administrator to kill this process',
      );
      verify(() => mockApi.killRamProcesses([1001, 1002])).called(1);
    });

    test('clearError resets errorMessage to null and hides SnackBar', () {
      final container = ProviderContainer(
        overrides: [
          ramProvider.overrideWith((ref) => RamNotifier(ref, mockApi)),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(ramProvider.notifier);
      notifier.state = notifier.state.copyWith(errorMessage: 'Some error');
      expect(notifier.state.errorMessage, 'Some error');

      notifier.clearError();
      expect(notifier.state.errorMessage, isNull);
    });

    testWidgets('surfaces SnackBar when kill fails and ScaffoldMessenger is mounted', (tester) async {
      when(() => mockApi.killRamProcesses([4])).thenThrow(
        Exception('Access Denied: Run as Administrator to kill this process'),
      );

      final container = ProviderContainer(
        overrides: [
          ramProvider.overrideWith((ref) => RamNotifier(ref, mockApi)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            scaffoldMessengerKey: snackbarKey,
            home: const Scaffold(
              body: Text('Test Host'),
            ),
          ),
        ),
      );

      final notifier = container.read(ramProvider.notifier);
      final sysGroup = ProcessGroup(name: 'System', processes: [systemProc]);
      notifier.debugSetGroupsForTest([sysGroup]);

      await notifier.killProcess(4);
      await tester.pumpAndSettle();

      expect(
        find.text('Access Denied: Run as Administrator to kill this process'),
        findsOneWidget,
      );
    });
  });
}
