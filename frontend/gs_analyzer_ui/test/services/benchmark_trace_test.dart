import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/telemetry_history_model.dart';
import 'package:gs_analyzer_ui/models/storage_node.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/providers/ram_provider.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/providers/telemetry_history_provider.dart';
import 'package:gs_analyzer_ui/providers/telemetry_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/services/benchmark_trace.dart';
import 'package:gs_analyzer_ui/services/telemetry_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:logging/logging.dart';
import 'package:mocktail/mocktail.dart';
import 'package:signalr_netcore/json_hub_protocol.dart';

import '../../integration_test/benchmark_transport_test.dart';

class _Api extends Mock implements ApiService {}

class _ClosingClient extends http.BaseClient {
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(const Stream.empty(), 200);
  @override
  void close() { closed = true; }
}

BenchmarkTransportDriver _driver(String method) => BenchmarkTransportDriver({
  'runId': _run, 'launchId': 'b' * 32, 'attemptId': 'c' * 32,
  'backendLaunchId': 'd' * 32, 'method': method,
  'controlDirectory': 'unused', 'timeoutSeconds': 1,
  'fixtures': {for (final name in ['primary', 'secondary', 'large']) name: {'root': 'C:/owned/$name'}},
});

class _Settings extends StateNotifier<SettingsState>
    implements SettingsNotifier {
  _Settings() : super(const SettingsState(isLoading: false));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _run = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
Map<String, Object?> _payload(
  String sequence, {
  String epoch = 'backend-epoch',
}) => {
  'benchmarkTrace': {
    'schemaVersion': 1,
    'runId': _run,
    'streamId': 'ram',
    'producerEpoch': epoch,
    'sequence': sequence,
    'clockId': 'dotnet-$epoch',
    'frequencyHz': '10000000',
    'acquisitionStartTicks': '9007199254740993',
    'acquisitionEndTicks': '9007199254740994',
  },
};
TelemetryHistoryResponse _history(int minutes) => TelemetryHistoryResponse(
  metric: 'cpu',
  minutes: minutes,
  unit: '%',
  points: [],
  stats: TelemetryStats(min: 1, max: 2, avg: 1.5, current: 2),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Map<String, dynamic>> records;
  late BenchmarkTrace trace;
  setUp(() {
    records = [];
    trace = BenchmarkTrace(_run, (line) async {
      records.add(jsonDecode(line) as Map<String, dynamic>);
    });
    BenchmarkTrace.current = trace;
  });
  tearDown(() async {
    BenchmarkTrace.current = null;
    await trace.finish();
  });

  for (final action in ['mutate', 'restart']) {
    for (final valid in [true, false]) {
      test('driver control $action retains request and only valid acknowledgment $valid', () async {
        final owned = await Directory.systemTemp.createTemp('gs-driver-control-');
        final config = Map<String, dynamic>.of(_driver('ChangedRescan').config)
          ..['controlDirectory'] = owned.path
          ..['timeoutSeconds'] = 5;
        final driver = BenchmarkTransportDriver(config)..trace = trace;
        final command = driver.command(action);
        final outcome = command.then<Object?>((_) => null, onError: (Object e) => e);
        try {
          await driver.waitFor(() => owned.listSync().whereType<File>().any((f) => f.path.endsWith('.request.json')), 'Request missing');
          final file = owned.listSync().whereType<File>().singleWhere((f) => f.path.endsWith('.request.json'));
          final request = jsonDecode(await file.readAsString()) as Map;
          final id = request['commandId'] as String;
          expect(request['action'], action);
          expect(request['runId'], _run);
          await File('${owned.path}/$id.ack.json').writeAsString(jsonEncode({
            'schemaVersion': 1, 'runId': _run, 'attemptId': config['attemptId'],
            'commandId': valid ? id : 'wrong', 'backendLaunchId': driver.backendLaunches.last, 'outcome': 'ready',
          }), flush: true);
          expect(await outcome, valid ? isNull : isA<FormatException>());
          final controls = records.where((e) => (e['stage'] as String).startsWith('scenario.control.')).toList();
          expect(controls.map((e) => e['stage']), ['scenario.control.requested', if (valid) 'scenario.control.acknowledged']);
          expect(controls.every((e) => e['operationId'] == id && e['label'] == action && e['benchmarkTrace'] == null), isTrue);
          expect(driver.setupArtifacts, contains('cases/${config['attemptId']}/control/$id.${action == 'restart' ? 'state' : 'fixture'}.json'));
          if (action == 'restart') {
            expect(request['oldLaunchId'], config['backendLaunchId']);
            expect(request['newLaunchId'], driver.backendLaunches.last);
          }
        } finally {
          await outcome;
          await owned.delete(recursive: true);
        }
      });
    }
  }

  test('driver includes seed-metadata HTTP membership outside measurement', () {
    final driver = _driver('AppHit');
    driver.allScans.add('1' * 32);
    driver.observe({'stage': 'http.round_trip.start', 'operationId': '2' * 32,
      'benchmarkTrace': {'streamId': '1' * 32}});
    driver.observe({'stage': 'http.round_trip.start', 'operationId': '3' * 32});
    expect(driver.requests, {'2' * 32});
  });

  test('restore control waits for fresh hub reconnection after backend acknowledgment', () async {
    final owned = await Directory.systemTemp.createTemp('gs-driver-restore-');
    final config = Map<String, dynamic>.of(_driver('PersistedRestore').config)
      ..['controlDirectory'] = owned.path
      ..['timeoutSeconds'] = 5;
    final driver = BenchmarkTransportDriver(config)..trace = trace
      ..interrupted = true..reconnected = true;
    var finished = false;
    final outcome = driver.command('restart').then<Object?>((_) { finished = true; return null; },
      onError: (Object e) { finished = true; return e; });
    try {
      await driver.waitFor(() => owned.listSync().whereType<File>().any((f) => f.path.endsWith('.request.json')), 'Request missing');
      final request = jsonDecode(await owned.listSync().whereType<File>().single.readAsString()) as Map;
      final id = request['commandId'] as String;
      await File('${owned.path}/$id.ack.json').writeAsString(jsonEncode({
        'schemaVersion': 1, 'runId': _run, 'attemptId': config['attemptId'],
        'commandId': id, 'backendLaunchId': driver.backendLaunches.last, 'outcome': 'ready',
      }), flush: true);
      await driver.waitFor(() => records.any((e) => e['stage'] == 'scenario.control.acknowledged'), 'Acknowledgment missing');
      expect(finished, isFalse);
      driver.observe({'stage': 'transport.reconnecting'});
      expect(finished, isFalse);
      driver.observe({'stage': 'transport.reconnected'});
      expect(await outcome, isNull);
    } finally {
      driver.interrupted = true;
      driver.reconnected = true;
      await outcome;
      await owned.delete(recursive: true);
    }
  });

  for (final defect in ['none', 'missing', 'duplicate', 'not-final', 'wrong-type', 'nonzero']) {
    test('driver large snapshot validates zero-byte membership $defect', () {
      final driver = _driver('QueuedCancelRestart');
      final nodes = [for (var i = 0; i < 5; i++) <String, dynamic>{
        'name': 'Root_$i', 'path': 'C:/owned/large/Root_$i', 'type': 'Directory',
        'recursiveBytes': 0, 'recursiveBytesFinal': true,
      }];
      if (defect == 'missing') nodes.removeLast();
      if (defect == 'duplicate') nodes[4] = Map.of(nodes[0]);
      if (defect == 'not-final') nodes[0]['recursiveBytesFinal'] = false;
      if (defect == 'wrong-type') nodes[0]['type'] = 'File';
      if (defect == 'nonzero') nodes[0]['recursiveBytes'] = 1;
      final result = driver.snapshot(nodes.map(StorageNode.fromJson).toList(), 'C:/owned/large');
      expect(result['large_roots'], defect == 'none' ? 5 : lessThan(5));
      expect(result['unknown'], defect == 'none' ? 0 : greaterThan(0));
    });
  }

  for (final defect in ['none', 'wrong-output', 'old-terminal']) {
    test('overhead uses trace-free provider completion and retains work $defect', () async {
      BenchmarkTrace.current = null;
      final api = _Api();
      final driver = _driver('AppHit');
      final container = ProviderContainer(overrides: [
        settingsProvider.overrideWith((_) => _Settings()),
        telemetryProvider.overrideWith((ref) => TelemetryNotifier(ref, autoConnect: false)),
        directoryProvider.overrideWith((ref) => DirectoryNotifier(ref,
          apiService: api, initialRoot: 'C:/owned/primary', autoStart: false)),
      ]);
      driver.container = container;
      var requests = 0;
      final selected = <String>{};
      when(() => api.requestDirectoryStream(any(), any())).thenAnswer((invocation) async {
        requests++;
        final path = invocation.positionalArguments[0] as String;
        final id = invocation.positionalArguments[1] as String;
        selected.add(id);
        final notifier = container.read(directoryProvider.notifier);
        notifier.receiveStreamChunk(id, path, [
          {'name': 'A', 'path': '$path/A', 'type': 'Directory', 'recursiveBytes': defect == 'wrong-output' && requests == 3 ? 32 : 33, 'recursiveBytesFinal': true},
          {'name': 'B', 'path': '$path/B', 'type': 'Directory', 'recursiveBytes': 54, 'recursiveBytesFinal': true},
          {'name': 'root.txt', 'path': '$path/root.txt', 'type': 'File', 'sizeBytes': 3},
          {'name': 'zero.txt', 'path': '$path/zero.txt', 'type': 'File', 'sizeBytes': 0},
        ]);
        notifier.finalizeStream(defect == 'old-terminal' && requests == 3 ? 'old' : id, path);
      });
      try {
        if (defect == 'none') {
          final result = await driver.overheadWork();
          expect(result['completed_scans'], 16);
          expect(result['scans'], hasLength(16));
          expect(requests, 17);
          expect(selected, hasLength(17));
        } else {
          await expectLater(driver.overheadWork(), defect == 'old-terminal' ? throwsA(isA<TimeoutException>()) : throwsStateError);
          expect(driver.overheadWorkEvidence['completed_scans'], 1);
          expect(driver.overheadWorkEvidence['scans'], hasLength(1));
          expect(requests, 3);
        }
        expect(driver.trace, isNull);
        expect(driver.overheadRequests, isEmpty);
        expect(records.where((e) => (e['stage'] as String).startsWith('state.directory')), isEmpty);
      } finally {
        container.dispose();
        BenchmarkTrace.current = trace;
      }
    });
  }

  test('driver binds concurrent scan roots before connection yields', () async {
    final api = _Api();
    when(() => api.requestDirectoryStream(any(), any())).thenAnswer((_) async {});
    final driver = _driver('ConcurrentRoots');
    final recorder = BenchmarkTrace(_run, (_) async {}, onRecord: driver.observe);
    driver.trace = recorder;
    BenchmarkTrace.current = recorder;
    final container = ProviderContainer(overrides: [
      settingsProvider.overrideWith((_) => _Settings()),
      telemetryProvider.overrideWith((ref) => TelemetryNotifier(ref, autoConnect: false)),
      directoryProvider.overrideWith((ref) => DirectoryNotifier(ref,
        apiService: api, initialRoot: 'C:/owned/primary', autoStart: false)),
    ]);
    driver.container = container;
    driver.begin();
    try {
      final first = driver.startScan('C:/owned/primary');
      final second = driver.startScan('C:/owned/secondary');
      final ids = await Future.wait([first, second]);
      expect(driver.roots[ids[0]], 'C:/owned/primary');
      expect(driver.roots[ids[1]], 'C:/owned/secondary');
      expect(driver.scans, ids.toSet());
      expect(driver.scanBindings[ids[0]]!['fixture_name'], 'primary');
      expect(driver.scanBindings[ids[1]]!['fixture_name'], 'secondary');
      expect(driver.scanBindings[ids[0]]!['role'], 'superseded');
      expect(driver.scanBindings[ids[0]]!['superseded_by_scan_id'], ids[1]);
      expect(driver.scanBindings[ids[1]]!['role'], 'current');
      verify(() => api.requestDirectoryStream('C:/owned/primary', any())).called(1);
      verify(() => api.requestDirectoryStream('C:/owned/secondary', any())).called(1);
      final notifier = container.read(directoryProvider.notifier);
      final current = notifier.currentScanId!;
      Map<String, Object?> payload(String id, String sequence) {
        final value = _payload(sequence);
        (value['benchmarkTrace'] as Map)['streamId'] = id;
        return value;
      }
      recorder.receive('DirectoryStreamComplete', payload(ids[0], '1'), () =>
        notifier.finalizeStream('old-scan', 'C:/owned/primary'));
      expect(driver.terminals[ids[0]], 'old_scan');
      expect(driver.snapshots.containsKey(ids[0]), isFalse);
      final nodes = [
        {'name': 'A', 'path': 'C:/owned/secondary/A', 'type': 'Directory', 'recursiveBytes': 33, 'recursiveBytesFinal': true},
        {'name': 'B', 'path': 'C:/owned/secondary/B', 'type': 'Directory', 'recursiveBytes': 54, 'recursiveBytesFinal': true},
        {'name': 'root.txt', 'path': 'C:/owned/secondary/root.txt', 'type': 'File', 'sizeBytes': 3},
        {'name': 'zero.txt', 'path': 'C:/owned/secondary/zero.txt', 'type': 'File', 'sizeBytes': 0},
      ];
      recorder.receive('DirectoryChunk', payload(ids[1], '2'), () =>
        notifier.receiveStreamChunk(current, 'C:/owned/secondary', nodes));
      final published = Map<String, int>.of(driver.snapshots[ids[1]]!);
      expect(published, {'nodes': 4, 'a_bytes': 33, 'b_bytes': 54, 'root_bytes': 3, 'zero_bytes': 0, 'unknown': 0});
      // Later product state cannot rewrite the immutable publication already observed.
      nodes[0]['recursiveBytes'] = 999;
      expect(driver.snapshots[ids[1]], published);
    } finally {
      await recorder.joinOwned();
      driver.interval!.end();
      container.dispose();
      await recorder.finish();
      BenchmarkTrace.current = trace;
    }
  });

  for (final check in ['seed-kind', 'frozen-artifacts', 'cancel-roles']) {
    test('driver scan binding $check retains setup and membership', () async {
      final api = _Api();
      when(() => api.requestDirectoryStream(any(), any())).thenAnswer((_) async {});
      final driver = _driver('AppHit');
      final recorder = BenchmarkTrace(_run, (_) async {}, onRecord: driver.observe);
      driver.trace = recorder;
      BenchmarkTrace.current = recorder;
      final container = ProviderContainer(overrides: [
        settingsProvider.overrideWith((_) => _Settings()),
        telemetryProvider.overrideWith((ref) => TelemetryNotifier(ref, autoConnect: false)),
        directoryProvider.overrideWith((ref) => DirectoryNotifier(ref,
          apiService: api, initialRoot: 'C:/owned/primary', autoStart: false)),
      ]);
      driver.container = container;
      driver.setupArtifacts.add('before.json');
      try {
        final seed = await driver.startScan('C:/owned/primary', role: 'seed');
        expect(driver.scans, isEmpty);
        expect(driver.allScans, {seed});
        expect(driver.requests, {driver.scanBindings[seed]!['request_id']});
        driver.seedScan = seed;
        driver.setupArtifacts.add('later.json');
        if (check == 'seed-kind') expect(driver.scanBindings[seed]!['setup_kind'], 'app_empty');
        if (check == 'frozen-artifacts') expect(driver.scanBindings[seed]!['setup_artifacts'], ['before.json']);
        driver.begin();
        final blocker = await driver.startScan('C:/owned/large', role: 'blocker');
        final target = await driver.startScan('C:/owned/secondary', role: 'cancel_target');
        final current = await driver.startScan('C:/owned/primary');
        expect(driver.scanBindings[seed]!['role'], 'seed');
        expect(driver.scanBindings[blocker]!['role'], 'blocker');
        expect(driver.scanBindings[target]!['role'], 'cancel_target');
        expect(driver.scanBindings[current]!['seed_scan_id'], seed);
        expect(driver.scanBindings[current]!['setup_artifacts'], ['before.json', 'later.json']);
        expect(driver.requests.length, 4);
      } finally {
        await recorder.joinOwned();
        driver.interval?.end();
        container.dispose();
        await recorder.finish();
        BenchmarkTrace.current = trace;
      }
    });
  }

  test('driver history exercises real body delivery gates and retains stale/disposed attempts', () async {
    final driver = _driver('HistoryRanges');
    final captured = <Map<String, Object?>>[];
    final recorder = BenchmarkTrace(_run, (_) async {}, onRecord: (record) {
      captured.add(record); driver.observe(record);
    });
    driver.trace = recorder;
    BenchmarkTrace.current = recorder;
    final api = ApiService.observed(trace: recorder, client: MockClient((request) async {
      final minutes = int.parse(request.url.queryParameters['minutes']!);
      return http.Response(jsonEncode({'metric': 'cpu', 'minutes': minutes, 'unit': '%', 'points': [],
        'stats': {'min': 0, 'max': 0, 'avg': 0, 'current': 0}}), 200);
    }));
    final container = ProviderContainer(overrides: [apiServiceProvider.overrideWithValue(api)]);
    driver.container = container;
    final finished = Completer<void>();
    runZonedGuarded(() async {
      try { await driver.history(); }
      catch (error, stack) { driver.recordError(error, stack); }
      finally { finished.complete(); }
    }, driver.recordError);
    try {
      await finished.future;
      expect(driver.historyApplied.keys, containsAll([5, 15, 30, 60]));
      expect(captured.where((r) => r['stage'] == 'history.publication_attempt').map((r) => r['outcome']),
        containsAll(['stale', 'post_dispose']));
      expect(driver.errors, isNotEmpty);
      expect(captured.where((r) => r['stage'] == 'history.client_delivery_delay.end')
        .map((r) => driver.historyRequested[r['operationId']]), [15, 5, 30]);
      expect(driver.deliveryGates.every((gate) => gate.isCompleted), isTrue);
    } finally {
      for (final gate in driver.deliveryGates) { if (!gate.isCompleted) gate.complete(); }
      driver.historySubscription?.close();
      container.dispose();
      await recorder.joinOwned();
      recorder.closeOwnedClients();
      await recorder.finish();
      BenchmarkTrace.current = trace;
    }
  });

  for (final timeout in [false, true]) {
    test('driver ${timeout ? 'retains owner on timeout' : 'joins owned work before disposing clients'}', () async {
      final driver = _driver('Idle');
      final inner = _ClosingClient();
      BenchmarkHttpClient(inner, trace);
      driver.trace = trace;
      final container = ProviderContainer(overrides: [
        telemetryProvider.overrideWith((ref) => TelemetryNotifier(ref, autoConnect: false)),
      ]);
      driver.container = container;
      final release = Completer<void>();
      final operation = trace.own(release.future);
      try {
        final cleanup = driver.settleResources();
        await Future<void>.delayed(Duration.zero);
        expect(inner.closed, isFalse);
        if (timeout) {
          expect(await cleanup, isFalse);
          expect(driver.container, same(container));
          expect(driver.errors, contains('TimeoutException'));
          expect(inner.closed, isFalse);
        }
        release.complete();
        await operation;
        if (!timeout) {
          expect(await cleanup, isTrue);
          expect(driver.container, isNull);
          expect(inner.closed, isTrue);
        }
      } finally {
        if (!release.isCompleted) release.complete();
        await operation;
        await trace.joinOwned();
        if (driver.container != null) container.dispose();
        trace.closeOwnedClients();
      }
    });
  }

  test('disabled minimal and rich recording preserve equal bounded protocol work', () async {
    const count = 256;
    final payloads = List.generate(count, (i) => {..._payload('${i + 1}'), 'value': i, 'name': '雪🤡'});
    final inputs = payloads.map((payload) => '${jsonEncode({
      'type': 1, 'target': 'RamUpdate', 'arguments': [payload],
    })}\u001e').toList();
    final reference = JsonHubProtocol();
    final expected = inputs.map((input) => reference.writeMessage(reference.parseMessages(input, null).single)).toList();
    for (var trial = 0; trial < 3; trial++) {
      final order = ['disabled', 'minimal', 'rich'];
      for (var index = 0; index < order.length; index++) {
        final mode = order[(trial + index) % order.length];
        final records = <Map<String, dynamic>>[];
        var bytes = 0, sum = 0;
        final recorder = mode == 'disabled' ? null : BenchmarkTrace(_run, (line) async {
          bytes += utf8.encode(line).length;
          records.add(jsonDecode(line) as Map<String, dynamic>);
        }, rich: mode == 'rich');
        final protocol = recorder == null ? reference : BenchmarkHubProtocol(recorder);
        final output = <Object>[];
        final clock = Stopwatch()..start();
        for (var i = 0; i < count; i++) {
          final message = protocol.parseMessages(inputs[i], null).single;
          output.add(protocol.writeMessage(message));
          void apply() { sum += i; recorder?.emit('state.ram.applied', counts: {'processes': 1}); }
          if (recorder == null) { apply(); }
          else { recorder.receive('RamUpdate', payloads[i], apply); }
        }
        final hotMicros = clock.elapsedMicroseconds;
        await recorder?.finish();
        clock.stop();
        expect(output, expected);
        expect(sum, count * (count - 1) ~/ 2);
        if (recorder != null) {
          expect(recorder.dropped, 0);
          expect(recorder.writeFailed, isFalse);
          expect(records.last['outcome'], 'drained');
          expect(records.where((r) => r['stage'] == 'receive.RamUpdate').every((r) => r['outcome'] == 'received'), isTrue);
          expect(records.where((r) => r['stage'] == 'protocol.parse.end')
            .fold<int>(0, (total, r) => total + (r['counts']['hub_protocol_bytes'] as int)),
            inputs.fold<int>(0, (total, input) => total + utf8.encode(input).length));
        }
        // Test-host/JIT and in-memory sink evidence, not live transport qualification.
        print(jsonEncode({'observation_control': mode, 'trial': trial, 'iterations': count,
          'hot_path_us': hotMicros, 'through_drain_us': clock.elapsedMicroseconds, 'trace_utf8_bytes': bytes}));
      }
    }
  });

  test('phase observer sees immutable publication before deferred writing', () async {
    final gate = Completer<void>();
    final observed = <Map<String, Object?>>[];
    final output = <Map<String, dynamic>>[];
    final recorder = BenchmarkTrace(_run, (line) async {
      await gate.future;
      output.add(jsonDecode(line) as Map<String, dynamic>);
    }, onRecord: observed.add);
    final counts = {'nodes': 4};
    recorder.emit('state.directory.applied', counts: counts);
    counts['nodes'] = 9;
    expect(output, isEmpty);
    expect(observed.last['stage'], 'state.directory.applied');
    expect((observed.last['counts'] as Map)['nodes'], 4);
    expect(() => observed.last['stage'] = 'changed', throwsUnsupportedError);
    expect(() => (observed.last['counts'] as Map)['nodes'] = 9, throwsUnsupportedError);
    gate.complete();
    await recorder.finish();
    expect(output[1], observed.last);
  });

  test('observer failure and recursive emission invalidate without escaping', () async {
    final output = <Map<String, dynamic>>[];
    late BenchmarkTrace recorder;
    recorder = BenchmarkTrace(_run, (line) async {
      output.add(jsonDecode(line) as Map<String, dynamic>);
    }, onRecord: (record) {
      if (record['stage'] == 'throw') throw StateError('observer');
      if (record['stage'] == 'reenter') recorder.emit('nested');
    });
    recorder.emit('throw');
    recorder.emit('reenter');
    await recorder.finish();
    expect(recorder.dropped, 2);
    expect(output.last['outcome'], 'incomplete');
    expect(output.map((r) => r['stage']), contains('nested'));
  });

  test('owned tasks join late work and preserve returned errors', () async {
    final first = Completer<int>(), second = Completer<int>();
    final one = trace.own(first.future.then((value) {
      trace.own(second.future);
      return value;
    }));
    var joined = false;
    final join = trace.joinOwned().then((_) => joined = true);
    first.complete(7);
    expect(await one, 7);
    await Future<void>.delayed(Duration.zero);
    expect(joined, isFalse);
    expect(trace.closeOwnedClients, throwsStateError);
    second.complete(8);
    await join;
    final failure = trace.own(Future<int>.error(StateError('retained')));
    await expectLater(failure, throwsStateError);
    await trace.joinOwned();
    expect(joined, isTrue);
  });

  test('history delivery gate begins after entity body and before decode', () async {
    final gate = Completer<void>();
    trace.historyDeliveryDelay = (_) => gate.future;
    final api = ApiService.observed(trace: trace, client: MockClient((request) async =>
      http.Response(jsonEncode({'metric': 'cpu', 'minutes': 5, 'unit': '%', 'points': [],
        'stats': {'min': 1, 'max': 2, 'avg': 1.5, 'current': 2}}), 200)));
    final request = trace.own(api.fetchTelemetryHistory('cpu', 5));
    for (var i = 0; i < 10 && !records.any((r) => r['stage'] == 'history.client_delivery_delay.start'); i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(records.any((r) => r['stage'] == 'http.round_trip.end'), isTrue);
    expect(records.any((r) => r['stage'] == 'http.decode.start'), isFalse);
    var joined = false;
    final join = trace.joinOwned().then((_) => joined = true);
    await Future<void>.delayed(Duration.zero);
    expect(joined, isFalse);
    gate.complete();
    expect((await request)?.minutes, 5);
    await join;
    trace.closeOwnedClients();
    await trace.finish();
    final stages = records.map((r) => r['stage']).toList();
    expect(stages.indexOf('history.client_delivery_delay.end'), lessThan(stages.indexOf('http.decode.start')));
    expect(records.last['counts']['owned_tasks'], 0);
  });

  test(
    'metadata preserves decimal strings and rejects foreign or malformed fields',
    () {
      final metadata = BenchmarkMetadata.fromPayload(
        _payload('9007199254740993'),
        _run,
      )!;
      expect(metadata.sequence, BigInt.parse('9007199254740993'));
      expect(metadata.fields['acquisitionStartTicks'], '9007199254740993');
      expect(BenchmarkMetadata.fromPayload({}, _run), isNull);
      for (final pair in <String, Object?>{
        'runId': 'foreign',
        'sequence': 5,
        'frequencyHz': '0',
        'acquisitionEndTicks': '1',
      }.entries) {
        final payload = _payload('1');
        (payload['benchmarkTrace'] as Map)[pair.key] = pair.value;
        expect(BenchmarkMetadata.fromPayload(payload, _run), isNull);
      }
    },
  );

  test(
    'receive records duplicate, order and restart without dropping callbacks',
    () async {
      var received = 0;
      for (final sequence in ['7', '7', '3', '10']) {
        trace.receive('RamUpdate', _payload(sequence), () {
          received++;
          expect(BenchmarkTrace.marker, isNotNull);
        });
      }
      trace.receive(
        'RamUpdate',
        _payload('1', epoch: 'restarted'),
        () => received++,
      );
      trace.receive('RamUpdate', {}, () => received++);
      await trace.finish();
      expect(received, 6);
      final events = records
          .where((r) => r['stage'] == 'receive.RamUpdate')
          .toList();
      expect(events.map((r) => r['outcome']), [
        'received',
        'duplicate',
        'out_of_order',
        'received',
        'received',
        'legacy',
      ]);
      expect(events[3]['counts']['sequence_jump'], 3);
      expect(BenchmarkTrace.marker, isNull);
      expect(records.last['outcome'], 'drained');
    },
  );

  test(
    'bounded writer retains overflow and outstanding work in footer',
    () async {
      final gate = Completer<void>();
      final output = <Map<String, dynamic>>[];
      final bounded = BenchmarkTrace(_run, (line) async {
        await gate.future;
        output.add(jsonDecode(line) as Map<String, dynamic>);
      }, capacity: 1);
      final span = bounded.begin('held');
      for (var i = 0; i < 100; i++) {
        bounded.emit('burst');
      }
      gate.complete();
      await bounded.finish();
      expect(output.length, lessThanOrEqualTo(3));
      expect(output.last['outcome'], 'incomplete');
      expect(output.last['counts']['outstanding'], 1);
      expect(output.last['counts']['dropped'], greaterThan(0));
      span.end();
    },
  );

  test('failed close never publishes evidence', () async {
    var published = false;
    final failed = BenchmarkTrace(
      _run,
      (_) async {},
      closeWriter: () async => throw StateError('controlled'),
      publish: () async {
        published = true;
      },
    );
    await failed.finish();
    expect(failed.writeFailed, true);
    expect(published, false);
  });

  test('owned output is committed only after flush and close', () async {
    final root = await Directory.systemTemp.createTemp('pr2-client-owned-');
    BenchmarkTrace? owned;
    try {
      await File('${root.path}/owner.json').writeAsString(
        jsonEncode({'runId': _run, 'schemaVersion': 1, 'detail': 'minimal'}),
      );
      await expectLater(
        BenchmarkTrace.createOwned('invalid', root.path),
        throwsFormatException,
      );
      expect(root.listSync(), hasLength(1));
      owned = await BenchmarkTrace.createOwned(_run, root.path);
      expect(root.listSync().where((f) => f.path.endsWith('.jsonl')), isEmpty);
      expect(
        root.listSync().where((f) => f.path.endsWith('.partial')),
        hasLength(1),
      );
      await owned.finish();
      final file = root.listSync().whereType<File>().singleWhere(
        (f) => f.path.endsWith('.jsonl'),
      );
      expect(jsonDecode((await file.readAsLines()).last)['outcome'], 'drained');
      expect(
        root.listSync().where((f) => f.path.endsWith('.partial')),
        isEmpty,
      );
    } finally {
      await owned?.finish();
      await root.delete(recursive: true);
    }
  });

  test(
    'protocol measures original UTF8 input and delegates parsing failures',
    () async {
      final protocol = BenchmarkHubProtocol(trace);
      const input =
          '{"type":1,"target":"RamUpdate","arguments":[{"name":"雪🤡"}]}\u001e';
      final messages = protocol.parseMessages(input, null);
      expect(messages, hasLength(1));
      expect(
        () => protocol.parseMessages('bad\u001e', null),
        throwsA(anything),
      );
      await trace.finish();
      final ends = records
          .where((r) => r['stage'] == 'protocol.parse.end')
          .toList();
      expect(
        ends.first['counts']['hub_protocol_bytes'],
        utf8.encode(input).length,
      );
      expect(ends.last['outcome'], 'failed');
    },
  );

  test(
    'transport logging persists only allowlisted lifecycle fields',
    () async {
      trace.transportLog(
        LogRecord(
          Level.INFO,
          "WebSocket connected to 'http://private?token=secret'.",
          'test',
        ),
      );
      trace.transportLog(
        LogRecord(Level.FINEST, 'Sending data: private-payload', 'test'),
      );
      await trace.finish();
      expect(
        records
            .where((r) => r['stage'] == 'transport.connected')
            .single['label'],
        'WebSockets',
      );
      expect(jsonEncode(records), isNot(contains('private')));
      expect(jsonEncode(records), isNot(contains('secret')));
    },
  );

  test('ordinary test service never enables IO implicitly', () async {
    final service = TelemetryService(
      onProgressUpdate: (_, __, ___, ____, _____, ______) {},
    );
    expect(service.allowTestTransport, false);
    await service.ensureConnected();
    await service.startListening();
    expect(service.isConnected, false);
    await service.dispose();
    await trace.finish();
    expect(records.where((r) => r['stage'] == 'transport.negotiate'), isEmpty);
  });

  test(
    'HTTP uses received entity bytes, correlates decode and preserves DTO',
    () async {
      final bytes = utf8.encode(
        jsonEncode({
          'metric': 'cpu',
          'minutes': 5,
          'unit': '雪',
          'points': [],
          'stats': {'min': 1, 'max': 2, 'avg': 1.5, 'current': 2},
        }),
      );
      final client = MockClient((request) async {
        expect(
          request.headers['X-GS-Benchmark-Request-Id'],
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        );
        return http.Response.bytes(
          bytes,
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final api = ApiService.observed(client: client, trace: trace);
      final result = await trace.withRequest(
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        () => api.fetchTelemetryHistory('cpu', 5),
      );
      expect(result!.unit, '雪');
      api.close();
      await trace.finish();
      final end = records.singleWhere(
        (r) => r['stage'] == 'http.round_trip.end',
      );
      expect(end['counts']['entity_bytes'], bytes.length);
      expect(
        records.singleWhere(
          (r) => r['stage'] == 'http.decode.end',
        )['operationId'],
        end['operationId'],
      );
    },
  );

  test(
    'cancelling HTTP consumption settles the observation and source subscription',
    () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      final client = BenchmarkHttpClient(
        MockClient.streaming(
          (_, __) async => http.StreamedResponse(body.stream, 200),
        ),
        trace,
      );
      final response = await client.send(
        http.Request('GET', Uri.parse('http://localhost/controlled')),
      );
      final subscription = response.stream.listen((_) {});
      await subscription.cancel();
      await body.close();
      client.close();
      await trace.finish();
      expect(cancelled, true);
      expect(trace.outstanding, 0);
      expect(
        records.singleWhere(
          (r) => r['stage'] == 'http.round_trip.end',
        )['outcome'],
        'cancelled',
      );
    },
  );

  test(
    'HTTP error stays outstanding until asynchronous cancellation settles',
    () async {
      final release = Completer<void>(),
          cancelling = Completer<void>(),
          received = Completer<void>();
      final body = StreamController<List<int>>(
        onCancel: () {
          cancelling.complete();
          return release.future;
        },
      );
      final client = BenchmarkHttpClient(
        MockClient.streaming(
          (_, __) async => http.StreamedResponse(body.stream, 200),
        ),
        trace,
      );
      final response = await client.send(
        http.Request('GET', Uri.parse('http://localhost/controlled')),
      );
      final subscription = response.stream.listen(
        (_) {},
        onError: (Object _) => received.complete(),
      );
      Future<void>? cancellation;
      try {
        body.addError(StateError('controlled'));
        await received.future;
        cancellation = subscription.cancel();
        await cancelling.future;
        expect(trace.outstanding, 1);
      } finally {
        release.complete();
        await (cancellation ?? subscription.cancel());
        await body.close();
        client.close();
      }
      await trace.finish();
      expect(trace.outstanding, 0);
      expect(
        records.singleWhere(
          (r) => r['stage'] == 'http.round_trip.end',
        )['outcome'],
        'failed',
      );
    },
  );

  test('HTTP decode correlates without an ambient request scope', () async {
    final api = ApiService.observed(
      trace: trace,
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'metric': 'cpu',
            'minutes': 5,
            'unit': '%',
            'points': [],
            'stats': {'min': 0, 'max': 0, 'avg': 0, 'current': 0},
          }),
          200,
        ),
      ),
    );
    try {
      expect((await api.fetchTelemetryHistory('cpu', 5))!.minutes, 5);
    } finally {
      api.close();
    }
    await trace.finish();
    expect(
      records.singleWhere(
        (r) => r['stage'] == 'http.decode.end',
      )['operationId'],
      records.singleWhere(
        (r) => r['stage'] == 'http.round_trip.end',
      )['operationId'],
    );
  });

  test(
    'oversized acquisition metadata is rejected without suppressing the callback',
    () async {
      var callbacks = 0;
      final payload = _payload('1');
      final metadata = payload['benchmarkTrace'] as Map;
      metadata['acquisitionStartTicks'] = '1' * 129;
      metadata['acquisitionEndTicks'] = '2' * 129;
      trace.receive('RamUpdate', payload, () => callbacks++);
      await trace.finish();
      expect(callbacks, 1);
      final receipt = records.singleWhere(
        (r) => r['stage'] == 'receive.RamUpdate',
      );
      expect(receipt['outcome'], 'invalid_metadata');
      expect(receipt.containsKey('benchmarkTrace'), false);
    },
  );

  for (final invalid in [false, true]) {
    testWidgets(
      'directory deferred flush clears ${invalid ? 'invalid' : 'legacy'} source metadata',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith((_) => _Settings()),
            directoryProvider.overrideWith(
              (ref) => DirectoryNotifier(
                ref,
                apiService: _Api(),
                initialRoot: 'C:/owned',
                autoStart: false,
              ),
            ),
          ],
        );
        final notifier = container.read(directoryProvider.notifier);
        void chunk(int size) => notifier.receiveStreamChunk(null, 'C:/owned', [
          {
            'name': 'child',
            'path': 'C:/owned/child',
            'type': 'File',
            'sizeBytes': size,
          },
        ]);
        try {
          trace.receive('DirectoryChunk', _payload('1'), () => chunk(1));
          trace.receive('DirectoryChunk', _payload('2'), () => chunk(2));
          trace.receive(
            'DirectoryChunk',
            invalid ? {'benchmarkTrace': {}} : {},
            () => chunk(3),
          );
          await tester.pump(const Duration(milliseconds: 65));
          expect(
            container.read(directoryProvider).allNodes.single.sizeBytes,
            3,
          );
        } finally {
          container.dispose();
        }
        await tester.runAsync(trace.finish);
        final applied = records
            .where((r) => r['stage'] == 'state.directory.applied')
            .toList();
        expect(applied, hasLength(2));
        expect(applied.first['benchmarkTrace']['sequence'], '1');
        expect(applied.last.containsKey('benchmarkTrace'), false);
        expect(applied.last['counts']['received_updates'], 2);
      },
    );
  }

  testWidgets(
    'directory records coalesced last marker and rejects old scan events',
    (tester) async {
      final api = _Api();
      when(
        () => api.requestDirectoryStream(any(), any()),
      ).thenAnswer((_) async {});
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith((_) => _Settings()),
          telemetryProvider.overrideWith(
            (ref) => TelemetryNotifier(ref, autoConnect: false),
          ),
          directoryProvider.overrideWith(
            (ref) => DirectoryNotifier(
              ref,
              apiService: api,
              initialRoot: 'C:/owned',
              autoStart: false,
            ),
          ),
        ],
      );
      final notifier = container.read(directoryProvider.notifier);
      verifyNever(() => api.requestDirectoryStream(any(), any()));
      await notifier.scanDirectory('C:/owned');
      final scanId = notifier.currentScanId;
      Map<String, dynamic> node(int bytes) => {
        'name': 'child',
        'path': 'C:/owned/child',
        'type': 'File',
        'sizeBytes': bytes,
      };
      for (var i = 1; i <= 3; i++) {
        trace.receive(
          'DirectoryChunk',
          _payload('$i'),
          () => notifier.receiveStreamChunk(scanId, 'C:/owned', [node(i)]),
        );
      }
      notifier.receiveStreamChunk('old', 'C:/owned', [node(99)]);
      await tester.pump(const Duration(milliseconds: 65));
      expect(container.read(directoryProvider).allNodes.single.sizeBytes, 3);
      notifier.finalizeStream(scanId, 'C:/owned');
      container.dispose();
      await tester.runAsync(trace.finish);
      final applied = records
          .where((r) => r['stage'] == 'state.directory.applied')
          .toList();
      expect(applied, hasLength(2));
      expect(applied.last['benchmarkTrace']['sequence'], '3');
      expect(applied.last['counts']['received_updates'], 2);
      expect(
        records.where(
          (r) =>
              r['stage'] == 'state.directory.accept' &&
              r['outcome'] == 'old_scan',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'RAM applied marker follows state publication with original complete values',
    () async {
      final api = _Api();
      when(() => api.startRamRadar()).thenAnswer((_) async {});
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith((_) => _Settings()),
          ramProvider.overrideWith((ref) => RamNotifier(ref, api)),
        ],
      );
      final notifier = container.read(ramProvider.notifier);
      trace.receive(
        'RamUpdate',
        {
          ..._payload('42'),
          'global': {'activeGb': 4, 'totalGb': 8},
          'processes': [],
        },
        () => notifier.updateProcesses({
          'global': {'activeGb': 4, 'totalGb': 8},
          'processes': [],
        }),
      );
      expect(container.read(ramProvider).activeGb, 4);
      container.dispose();
      await trace.finish();
      expect(
        records.singleWhere(
          (r) => r['stage'] == 'state.ram.applied',
        )['benchmarkTrace']['sequence'],
        '42',
      );
    },
  );

  test(
    'history records late old range without repairing stale publication',
    () async {
      final api = _Api();
      final old = Completer<TelemetryHistoryResponse?>(),
          latest = Completer<TelemetryHistoryResponse?>();
      when(
        () => api.fetchTelemetryHistory('cpu', 5),
      ).thenAnswer((_) => old.future);
      when(
        () => api.fetchTelemetryHistory('cpu', 30),
      ).thenAnswer((_) => latest.future);
      final notifier = TelemetryHistoryNotifier(api, 'cpu');
      notifier.setMinutes(30);
      latest.complete(_history(30));
      await Future<void>.delayed(Duration.zero);
      old.complete(_history(5));
      await Future<void>.delayed(Duration.zero);
      expect(notifier.state.minutes, 30);
      expect(notifier.state.response!.minutes, 5);
      notifier.dispose();
      await trace.finish();
      expect(
        records
            .where((r) => r['stage'] == 'history.publication_attempt')
            .map((r) => r['outcome']),
        ['current', 'stale'],
      );
      expect(trace.outstanding, 0);
    },
  );

  test(
    'history records post-dispose attempt before the original state error',
    () async {
      final api = _Api();
      final response = Completer<TelemetryHistoryResponse?>();
      final error = Completer<Object>();
      when(
        () => api.fetchTelemetryHistory('cpu', 5),
      ).thenAnswer((_) => response.future);
      late TelemetryHistoryNotifier notifier;
      runZonedGuarded(
        () {
          notifier = TelemetryHistoryNotifier(api, 'cpu');
        },
        (e, _) {
          error.complete(e);
        },
      );
      notifier.dispose();
      response.complete(_history(5));
      expect(await error.future, isA<StateError>());
      await trace.finish();
      expect(
        records
            .where((r) => r['stage'] == 'history.publication_attempt')
            .every((r) => r['outcome'] == 'post_dispose'),
        true,
      );
      expect(
        records.where((r) => r['stage'] == 'history.publication_attempt'),
        isNotEmpty,
      );
      expect(trace.outstanding, 0);
    },
  );
}
