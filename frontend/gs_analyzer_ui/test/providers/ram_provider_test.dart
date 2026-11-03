import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/process_telemetry.dart';
import 'package:gs_analyzer_ui/models/app_settings.dart';
import 'package:gs_analyzer_ui/providers/ram_provider.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/globals.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockApiService extends Mock implements ApiService {}

class TestSettingsNotifier extends StateNotifier<SettingsState> implements SettingsNotifier {
  TestSettingsNotifier() : super(const SettingsState(isLoading: false));
  void replaceSettings(AppSettings settings) => state = SettingsState(isLoading: false, currentSettings: settings);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> frame(List<ProcessTelemetry> processes) => {
  'global': {'totalGb': 8, 'activeGb': 2, 'cacheGb': 6, 'physicalTotalBytes': 8589934592},
  'processes': [for (final process in processes) {
    'processId': process.pid, 'name': process.name, 'ramMb': process.ramMb,
    'cpuPercent': process.cpuPercent, 'status': process.status, 'user': process.user,
  }],
};

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
          settingsProvider.overrideWith((ref) => TestSettingsNotifier()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(ramProvider.notifier);
      final initialGroup = ProcessGroup(name: 'app.exe', processes: [proc1, proc2]);
      notifier.debugSetGroupsForTest([initialGroup]);

      await notifier.killProcess(1001);
      expect(notifier.state.groupedProcesses.first.processes.length, 2);
      notifier.updateProcesses(frame([proc2]));

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
          settingsProvider.overrideWith((ref) => TestSettingsNotifier()),
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
          settingsProvider.overrideWith((ref) => TestSettingsNotifier()),
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
          settingsProvider.overrideWith((ref) => TestSettingsNotifier()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(ramProvider.notifier);
      final group = ProcessGroup(name: 'app.exe', processes: [proc1, proc2]);
      final sysGroup = ProcessGroup(name: 'System', processes: [systemProc]);
      notifier.debugSetGroupsForTest([group, sysGroup]);

      await notifier.killProcessGroup('app.exe');
      expect(notifier.state.groupedProcesses.length, 2);
      notifier.updateProcesses(frame([systemProc]));

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
          settingsProvider.overrideWith((ref) => TestSettingsNotifier()),
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
          settingsProvider.overrideWith((ref) => TestSettingsNotifier()),
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
          settingsProvider.overrideWith((ref) => TestSettingsNotifier()),
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

  test('metric selection changes only RAM projection and survives subsequent frames', () {
    final container = ProviderContainer(overrides: [
      ramProvider.overrideWith((ref) => RamNotifier(ref, mockApi)),
      settingsProvider.overrideWith((ref) => TestSettingsNotifier()),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(ramProvider.notifier);
    final payload = {
      'processMemorySemantics': 'windows-private-ws',
      'global': {'totalGb': 8, 'activeGb': 2, 'physicalTotalBytes': 8589934592},
      'processes': [
        {'processId': 1, 'name': 'a', 'workingSetBytes': 300, 'privateWorkingSetBytes': 100, 'commitBytes': 200},
        {'processId': 2, 'name': 'b', 'workingSetBytes': 100, 'privateWorkingSetBytes': 300, 'commitBytes': 100},
        {'processId': 3, 'name': 'c', 'workingSetBytes': 200, 'privateWorkingSetBytes': 200, 'commitBytes': 300},
      ],
    };
    notifier.updateProcesses(payload);
    final base = notifier.state.groupedProcesses;
    expect(notifier.state.memorySortedProcesses.map((g) => g.name), ['b', 'c', 'a']);
    notifier.setMemoryMetric(ProcessMemoryMetric.totalWorkingSet);
    expect(notifier.state.memorySortedProcesses.map((g) => g.name), ['a', 'c', 'b']);
    notifier.setMemoryMetric(ProcessMemoryMetric.commitSize);
    expect(notifier.state.memorySortedProcesses.map((g) => g.name), ['c', 'a', 'b']);
    expect(identical(notifier.state.groupedProcesses, base), isTrue);
    expect(base.map((g) => g.name), ['a', 'c', 'b']);
    notifier.updateProcesses(payload);
    expect(notifier.state.selectedMemoryMetric, ProcessMemoryMetric.commitSize);
    verify(() => mockApi.startRamRadar()).called(1);
  });

  test('display choice survives samples settings and actions without restarting radar', () async {
    when(() => mockApi.killRamProcesses([1001])).thenAnswer((_) async => true);
    final settingsNotifier = TestSettingsNotifier();
    final container = ProviderContainer(overrides: [
      ramProvider.overrideWith((ref) => RamNotifier(ref, mockApi)),
      settingsProvider.overrideWith((ref) => settingsNotifier),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(ramProvider.notifier);
    expect(notifier.state.memoryDisplayMode, ProcessMemoryDisplayMode.value);
    notifier.setMemoryDisplayMode(ProcessMemoryDisplayMode.percentage);
    notifier.setMemoryMetric(ProcessMemoryMetric.commitSize);
    notifier.updateProcesses(frame([proc1, proc2]));
    expect(notifier.state.memoryDisplayMode, ProcessMemoryDisplayMode.percentage);
    expect(notifier.state.selectedMemoryMetric, ProcessMemoryMetric.commitSize);
    final settings = AppSettings.fromjson({'alerts': {'ramThresholdPercent': 90}});
    settingsNotifier.replaceSettings(settings);
    expect(notifier.state.ramThresholdPercent, 90);
    expect(notifier.state.memoryDisplayMode, ProcessMemoryDisplayMode.percentage);
    await notifier.killProcess(1001);
    notifier.updateProcesses(frame([proc2]));
    expect(notifier.state.memoryDisplayMode, ProcessMemoryDisplayMode.percentage);
    expect(notifier.state.selectedMemoryMetric, ProcessMemoryMetric.commitSize);
    notifier.setMemoryDisplayMode(ProcessMemoryDisplayMode.value);
    expect(notifier.state.selectedMemoryMetric, ProcessMemoryMetric.commitSize);
    verify(() => mockApi.startRamRadar()).called(1);
    verify(() => mockApi.killRamProcesses([1001])).called(1);
  });

  test('live frames record history only every two elapsed seconds', () {
    var elapsed = Duration.zero;
    final container = ProviderContainer(overrides: [
      ramProvider.overrideWith((ref) => RamNotifier(ref, mockApi, () => elapsed)),
      settingsProvider.overrideWith((ref) => TestSettingsNotifier()),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(ramProvider.notifier);
    for (var i = 0; i <= 8; i++) {
      elapsed = Duration(milliseconds: i * 250);
      notifier.updateProcesses(frame([proc1]));
    }
    expect(notifier.state.usageHistory.length, 2);
  });

  test('pending group kill preserves newer untargeted members after acknowledgment', () async {
    final release = Completer<bool>();
    when(() => mockApi.killRamProcesses([1001, 1002])).thenAnswer((_) => release.future);
    final container = ProviderContainer(overrides: [
      ramProvider.overrideWith((ref) => RamNotifier(ref, mockApi)),
      settingsProvider.overrideWith((ref) => TestSettingsNotifier()),
    ]);
    addTearDown(container.dispose);
    final notifier = container.read(ramProvider.notifier);
    notifier.updateProcesses(frame([proc1, proc2]));
    final pending = notifier.killProcessGroup('app.exe');
    final newcomer = ProcessTelemetry(pid: 1003, name: 'app.exe', ramMb: 10, percentMem: 0,
        status: 'RUNNING', cpuPercent: 0, user: 'User');
    notifier.updateProcesses(frame([proc2, newcomer]));
    release.complete(true);
    await pending;
    expect(notifier.state.groupedProcesses.single.processes.map((p) => p.pid), [1002, 1003]);
    verify(() => mockApi.killRamProcesses([1001, 1002])).called(1);
  });
}
