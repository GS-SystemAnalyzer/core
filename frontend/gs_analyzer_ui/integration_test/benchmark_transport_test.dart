import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/storage_node.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/providers/ram_provider.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/providers/telemetry_history_provider.dart';
import 'package:gs_analyzer_ui/providers/telemetry_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/services/benchmark_trace.dart';
import 'package:integration_test/integration_test.dart';

const _methods = {'Idle', 'AppEmpty', 'AppHit', 'ChangedRescan', 'PersistedRestore',
  'ConcurrentRoots', 'ActiveCancelRestart', 'QueuedCancelRestart', 'HistoryRanges', 'Reconnect'};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var code = 1;
  testWidgets('owned production-provider transport capture', (tester) async {
    final path = Platform.environment['GS_BENCHMARK_SCENARIO'];
    if (path == null) throw StateError('Launch only through run-scenarios.ps1 in the supplied disposable environment');
    await tester.runAsync(() async {
      final driver = await BenchmarkTransportDriver.load(path);
      final finished = Completer<void>();
      runZonedGuarded(() async {
        try { code = await driver.run(); }
        catch (error, stack) { driver.recordError(error, stack); }
        finally { finished.complete(); }
      }, driver.recordError);
      await finished.future;
    });
    expect(code, 0, reason: 'Retained driver result contains failed or incomplete observations');
  }, timeout: const Timeout(Duration(minutes: 4)));
  // The launcher owns this built integration executable, including process exit.
  tearDownAll(() { exit(code); });
}

class BenchmarkTransportDriver {
  final Map<String, dynamic> config;
  final String runId, launchId, attemptId, method, control;
  final Duration timeout;
  final List<String> backendLaunches;
  final Set<String> requests = {}, scans = {}, allScans = {}, initialized = {};
  final Map<String, String> roots = {}, terminals = {};
  final Map<String, Map<String, Object?>> scanBindings = {};
  final List<String> setupArtifacts = [];
  String? seedScan;
  final Map<String, Map<String, int>> snapshots = {};
  final Map<int, int> historyApplied = {};
  final Map<String, int> historyRequested = {};
  final List<Completer<void>> deliveryGates = [];
  final List<String> errors = [];
  BenchmarkTrace? trace;
  ProviderContainer? container;
  ApiService? api;
  ProviderSubscription<TelemetryHistoryState>? historySubscription;
  BenchmarkSpan? interval;
  bool measuring = false, negotiated = false, connected = false, reconnected = false, interrupted = false;
  int ramUpdates = 0;
  String? ramEpoch;
  final Set<Future<void>> overheadRequests = {};
  final Map<String, Object?> overheadWorkEvidence = {};
  bool get isOverhead => config['measurement'] == 'overhead';

  BenchmarkTransportDriver(this.config)
      : runId = config['runId'] as String, launchId = config['launchId'] as String,
        attemptId = config['attemptId'] as String, method = config['method'] as String,
        control = config['controlDirectory'] as String,
        timeout = Duration(seconds: config['timeoutSeconds'] as int),
        backendLaunches = [config['backendLaunchId'] as String];

  static Future<BenchmarkTransportDriver> load(String path) async {
    if (!Platform.isWindows || !File(path).isAbsolute) throw StateError('Windows absolute owned configuration required');
    final file = File(path);
    if (await file.length() > 16 * 1024 * 1024) throw const FormatException('Oversized driver configuration');
    final config = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (config['schemaVersion'] != 1 || config['port'] != 5200 || config['ordinal'] != 1 ||
        !_methods.contains(config['method']) || config['timeoutSeconds'] is! int ||
        (config['timeoutSeconds'] as int) < 1 || (config['timeoutSeconds'] as int) > 60) {
      throw const FormatException('Unsupported driver configuration');
    }
    for (final key in ['runId', 'launchId', 'attemptId', 'backendLaunchId']) {
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(config[key] as String)) throw const FormatException('Invalid owner ID');
    }
    final overhead = config['measurement'] == 'overhead';
    if (config.containsKey('measurement') && !overhead) throw const FormatException('Unknown measurement');
    final off = overhead && config['detail'] == 'off';
    if (overhead && (config['method'] != 'AppHit' || !['off', 'minimal', 'rich'].contains(config['detail']))) {
      throw const FormatException('Invalid overhead workload');
    }
    if (off) {
      if (Platform.environment.containsKey('GS_BENCHMARK_RUN_ID') || Platform.environment.containsKey('GS_BENCHMARK_OUTPUT')) {
        throw const FormatException('Off measurement has trace activation');
      }
    } else if (config['runId'] != Platform.environment['GS_BENCHMARK_RUN_ID']) {
      throw const FormatException('Run ownership mismatch');
    }
    final traceDirectory = overhead ? config['outputDirectory'] as String? : Platform.environment['GS_BENCHMARK_OUTPUT'];
    if (traceDirectory == null || Directory(traceDirectory).uri.pathSegments.where((s) => s.isNotEmpty).last != config['launchId']) {
      throw const FormatException('Launch output ownership mismatch');
    }
    if (overhead) {
      final supplied = Directory(traceDirectory);
      if (!supplied.isAbsolute || (await supplied.resolveSymbolicLinks()).toLowerCase() != supplied.absolute.path.toLowerCase()) {
        throw const FormatException('Linked overhead output');
      }
      final owner = jsonDecode(await File('$traceDirectory/owner.json').readAsString()) as Map;
      if (owner['schemaVersion'] != 1 || owner['runId'] != config['runId'] || owner['detail'] != config['detail'] ||
          (!off && Platform.environment['GS_BENCHMARK_OUTPUT'] != traceDirectory)) {
        throw const FormatException('Overhead output ownership mismatch');
      }
    }
    final caseDirectory = file.parent.absolute.path;
    for (final directory in [config['controlDirectory'], ...(config['fixtures'] as Map).values.map((f) => f['root'])]) {
      final supplied = Directory(directory as String);
      final resolved = await supplied.resolveSymbolicLinks();
      final parent = caseDirectory.replaceAll(r'\', '/').toLowerCase();
      final normalized = resolved.replaceAll(r'\', '/').toLowerCase();
      if (!supplied.isAbsolute || !normalized.startsWith('$parent/') ||
          normalized != supplied.absolute.path.replaceAll(r'\', '/').toLowerCase()) {
        throw const FormatException('Linked or foreign driver directory');
      }
    }
    return BenchmarkTransportDriver(config);
  }

  String root(String name) => ((config['fixtures'] as Map)[name] as Map)['root'] as String;
  String normalizeId(String value) => value.replaceAll('-', '').toLowerCase();
  void recordError(Object error, StackTrace stack) {
    if (errors.length < 64) errors.add(error.runtimeType.toString());
    trace?.emit('scenario.async_error', outcome: 'failed', label: error.runtimeType.toString());
  }

  void observe(Map<String, Object?> record) {
    final stage = record['stage'];
    final marker = record['benchmarkTrace'] as Map?;
    final stream = marker?['streamId'] as String?;
    final counts = record['counts'] as Map?;
    if (stage == 'transport.negotiate') negotiated = true;
    if (stage == 'transport.http_connected') connected = true;
    if (stage == 'transport.reconnecting') interrupted = true;
    if (stage == 'transport.reconnected') reconnected = true;
    if (stage == 'state.ram.applied' && (counts?['processes'] as int? ?? 0) > 0) {
      ramUpdates++;
      ramEpoch = marker?['producerEpoch'] as String?;
    }
    if ((measuring || allScans.contains(stream)) && stage == 'http.round_trip.start') {
      if (requests.length >= 2048) throw StateError('Request membership limit');
      requests.add(record['operationId'] as String);
    }
    if (stage == 'state.directory.selected') {
      final id = normalizeId(record['label'] as String);
      if (allScans.length >= 128) throw StateError('Scan membership limit');
      allScans.add(id);
      if (measuring) scans.add(id);
      roots.putIfAbsent(id, () => container!.read(directoryProvider).currentPath);
      bindScan(id, roots[id]!);
      for (final previous in scanBindings.values) {
        final old = previous['scan_id'] as String;
        if (old != id && previous['role'] == 'current' && !terminals.containsKey(old)) {
          previous['role'] = 'superseded';
          previous['superseded_by_scan_id'] = id;
        }
      }
    }
    if (stage == 'state.directory.request') {
      final id = normalizeId(record['label'] as String);
      final binding = bindScan(id, roots[id]!);
      binding['request_id'] = record['operationId'];
      requests.add(record['operationId'] as String);
    }
    if (stage == 'state.progress.applied') {
      final progress = container!.read(telemetryProvider);
      if (progress.status == 'INITIALIZING' && progress.currentScanId != null) initialized.add(normalizeId(progress.currentScanId!));
    }
    if (stream != null && allScans.contains(stream)) {
      if (stage == 'state.directory.applied' || stage == 'state.directory.terminal' && record['outcome'] == 'applied') {
        snapshots[stream] = snapshot(container!.read(directoryProvider).allNodes, roots[stream]!);
      }
      if (stage == 'state.directory.terminal') terminals[stream] = record['outcome'] as String;
    }
    if (stage == 'history.requested') historyRequested[record['operationId'] as String] = counts!['minutes'] as int;
    if (stage == 'history.applied') {
      final minutes = counts!['minutes'] as int;
      historyApplied[minutes] = (historyApplied[minutes] ?? 0) + 1;
    }
  }

  Map<String, int> snapshot(List<StorageNode> nodes, String rootPath) {
    final prefix = '${rootPath.replaceAll(r'\', '/').toLowerCase()}/';
    final byPath = <String, List<StorageNode>>{};
    var unknown = 0;
    for (final node in nodes) {
      final path = node.path.replaceAll(r'\', '/').toLowerCase();
      if (!path.startsWith(prefix)) { unknown++; continue; }
      byPath.putIfAbsent(path.substring(prefix.length), () => []).add(node);
    }
    int value(String name, bool directory) {
      final found = byPath[name];
      if (found == null || found.length != 1 || found.single.isDirectory != directory || !found.single.isRecursiveFinal) {
        unknown++; return -1;
      }
      return directory ? found.single.recursiveBytes : found.single.sizeBytes;
    }
    final largeRoot = (config['fixtures'] as Map?)?['large']?['root'] as String?;
    if (largeRoot != null && largeRoot.replaceAll(r'\', '/').toLowerCase() == rootPath.replaceAll(r'\', '/').toLowerCase()) {
      final expected = {for (var i = 0; i < 5; i++) 'root_$i'};
      var complete = 0;
      for (final name in expected) {
        final bytes = value(name, true);
        if (bytes == 0) { complete++; } else if (bytes > 0) { unknown++; }
      }
      return {'nodes': nodes.length, 'large_roots': complete,
        'unknown': unknown + byPath.keys.where((k) => !expected.contains(k)).length};
    }
    final result = {'nodes': nodes.length, 'a_bytes': value('a', true), 'b_bytes': value('b', true),
      'root_bytes': value('root.txt', false), 'zero_bytes': value('zero.txt', false)};
    result['unknown'] = unknown + byPath.keys.where((k) => !{'a', 'b', 'root.txt', 'zero.txt'}.contains(k)).length;
    return result;
  }

  Future<void> waitFor(bool Function() condition, String reason, {Duration? limit}) async {
    final clock = Stopwatch()..start();
    while (!condition()) {
      if (clock.elapsed >= (limit ?? timeout)) throw TimeoutException(reason);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  void begin() {
    measuring = true;
    interval = trace!.begin('scenario.$method', operationId: attemptId, metadata: null);
  }

  Map<String, Object?> bindScan(String id, String path) => scanBindings.putIfAbsent(id, () {
    final fixtures = config['fixtures'] as Map? ?? {};
    final matches = fixtures.entries.where((entry) =>
      (entry.value['root'] as String).replaceAll(r'\', '/').toLowerCase() == path.replaceAll(r'\', '/').toLowerCase());
    return {'scan_id': id, 'request_id': '', 'backend_launch': backendLaunches.last, 'root_key': '',
      'fixture_artifact': 'cases/$attemptId/fixtures.json', 'fixture_name': matches.length == 1 ? matches.single.key : 'unknown',
      'role': 'current', 'setup_kind': {'AppHit': 'app_hit', 'ChangedRescan': 'changed_rescan',
        'PersistedRestore': 'persisted_restore'}[method] ?? 'app_empty',
      'setup_artifacts': List<String>.of(setupArtifacts), if (seedScan != null) 'seed_scan_id': seedScan};
  });

  Future<String> startScan(String path, {String role = 'current'}) async {
    final directory = container!.read(directoryProvider.notifier);
    final operation = trace!.own(directory.scanDirectory(path, forceRefresh: true));
    final id = normalizeId(directory.currentScanId!);
    roots[id] = path.replaceAll(r'\', '/');
    final binding = bindScan(id, roots[id]!);
    binding['role'] = role;
    if (role == 'seed') binding['setup_kind'] = 'app_empty';
    await operation.timeout(timeout);
    return id;
  }

  Future<String> scan(String path, {String role = 'current'}) async {
    final id = await startScan(path, role: role);
    await waitFor(() => terminals.containsKey(id), 'Directory terminal missing');
    if (terminals[id] != 'applied') throw StateError('Directory terminal ${terminals[id]}');
    return id;
  }

  Future<void> publish(String name, Map<String, Object?> value) async {
    final target = File('$control/$name');
    if (await target.exists()) throw StateError('Control history already exists');
    final partial = File('${target.path}.${BenchmarkTrace.newId()}.partial');
    await partial.writeAsString('${jsonEncode(value)}\n', flush: true);
    await partial.rename(target.path);
  }

  Future<void> command(String action) async {
    final id = BenchmarkTrace.newId();
    final replacement = action == 'restart' ? BenchmarkTrace.newId() : null;
    final restore = replacement != null && method == 'PersistedRestore';
    if (restore) { interrupted = false; reconnected = false; }
    setupArtifacts.addAll(['cases/$attemptId/control/$id.request.json', 'cases/$attemptId/control/$id.ack.json',
      'cases/$attemptId/control/$id.${action == 'restart' ? 'state' : 'fixture'}.json']);
    if (replacement != null) {
      trace!.emit('scenario.backend_restart', operationId: attemptId, label: replacement, metadata: null);
      backendLaunches.add(replacement);
    }
    trace!.emit('scenario.control.requested', operationId: id, label: action, metadata: null);
    await publish('$id.request.json', {'schemaVersion': 1, 'runId': runId, 'attemptId': attemptId,
      'commandId': id, 'action': action, if (replacement != null) 'oldLaunchId': backendLaunches[backendLaunches.length - 2],
      if (replacement != null) 'newLaunchId': replacement});
    final ack = File('$control/$id.ack.json');
    await waitFor(() => ack.existsSync(), 'Runner command acknowledgment missing');
    final result = jsonDecode(await ack.readAsString()) as Map;
    if (result['schemaVersion'] != 1 || result['runId'] != runId || result['commandId'] != id ||
        result['attemptId'] != attemptId || result['backendLaunchId'] != backendLaunches.last || result['outcome'] != 'ready') {
      throw const FormatException('Runner acknowledgment mismatch');
    }
    trace!.emit('scenario.control.acknowledged', operationId: id, label: action, metadata: null);
    if (restore) await waitFor(() => interrupted && reconnected, 'Restore hub reconnection missing');
  }

  Future<void> history() async {
    final provider = telemetryHistoryProvider('cpu');
    historySubscription = container!.listen(provider, (_, _) {});
    await waitFor(() => (historyApplied[5] ?? 0) > 0, 'Initial history unavailable');
    for (final minutes in [15, 30, 60]) {
      container!.read(provider.notifier).setMinutes(minutes);
      await waitFor(() => (historyApplied[minutes] ?? 0) > 0, 'History range unavailable');
    }
    final late = Completer<void>(); deliveryGates.add(late);
    trace!.historyDeliveryDelay = (minutes) => minutes == 5 ? late.future : Future<void>.value();
    final before = historyRequested.length;
    container!.read(provider.notifier).setMinutes(5);
    await waitFor(() => historyRequested.length > before, 'Delayed history request missing');
    final fifteen = historyApplied[15] ?? 0;
    container!.read(provider.notifier).setMinutes(15);
    await waitFor(() => (historyApplied[15] ?? 0) > fifteen, 'Current history request missing');
    late.complete();
    await trace!.joinOwned().timeout(timeout);
    final disposed = Completer<void>(); deliveryGates.add(disposed);
    trace!.historyDeliveryDelay = (_) => disposed.future;
    final requested = historyRequested.length;
    container!.read(provider.notifier).setMinutes(30);
    await waitFor(() => historyRequested.length > requested, 'Dispose-control request missing');
    historySubscription!.close(); historySubscription = null;
    container!.invalidate(provider);
    await container!.pump();
    disposed.complete();
    await trace!.joinOwned().timeout(timeout);
    trace!.historyDeliveryDelay = null;
  }

  Future<int> run() async {
    if (isOverhead) return runOverhead();
    var outcome = 'failed';
    var resourcesSettled = false;
    try {
      trace = await BenchmarkTrace.fromEnvironment(onRecord: observe);
      if (trace == null) throw StateError('Trace ownership unavailable');
      BenchmarkTrace.current = trace;
      setupArtifacts.add('cases/$attemptId/state-before.json');
      api = ApiService();
      container = ProviderContainer(overrides: [
        settingsProvider.overrideWith((ref) => SettingsNotifier(api)),
        directoryProvider.overrideWith((ref) => DirectoryNotifier(ref, apiService: api, initialRoot: root('primary'), autoStart: false)),
        ramProvider.overrideWith((ref) => RamNotifier(ref, api)),
        telemetryProvider.overrideWith((ref) => TelemetryNotifier(ref, allowTestTransport: true)),
        apiServiceProvider.overrideWithValue(api!),
      ]);
      await trace!.own(container!.read(settingsProvider.notifier).initialized).timeout(timeout);
      final settings = container!.read(settingsProvider);
      if (!settings.serviceConfirmed || settings.savedSettings?.advanced.backendPort != 5200) throw StateError('Owned backend settings unavailable');
      container!.read(directoryProvider.notifier);
      if (method == 'Idle') begin();
      container!.read(ramProvider.notifier);
      container!.read(telemetryProvider.notifier);
      await waitFor(() => negotiated && connected && ramUpdates > 0, 'Negotiated nonempty telemetry missing');
      if (method != 'Idle') {
        if ({'AppHit', 'ChangedRescan', 'PersistedRestore'}.contains(method)) {
          seedScan = await scan(root('primary'), role: 'seed');
          await trace!.joinOwned().timeout(timeout);
          trace!.emit('scenario.setup', outcome: 'warm_scan_observed', label: method, metadata: null);
        }
        if (method == 'PersistedRestore') await command('restart');
        begin();
      }
      switch (method) {
        case 'Idle':
          final count = ramUpdates;
          await waitFor(() => ramUpdates >= count + 2, 'Idle telemetry stalled');
        case 'AppEmpty': case 'AppHit': case 'PersistedRestore':
          await scan(root('primary'));
        case 'ChangedRescan':
          final count = scans.length;
          await command('mutate');
          await waitFor(() => scans.length > count, 'Watcher did not initiate changed rescan');
          await waitFor(() => scans.every(terminals.containsKey), 'Changed rescan did not settle');
        case 'ConcurrentRoots':
          final first = startScan(root('primary'));
          final second = startScan(root('secondary'));
          await Future.wait([first, second]);
          await waitFor(() => scans.length >= 2 && scans.every(terminals.containsKey), 'Concurrent terminals missing');
          final count = ramUpdates;
          await waitFor(() => ramUpdates > count, 'Concurrent telemetry stalled');
        case 'ActiveCancelRestart': case 'QueuedCancelRestart':
          final blocker = await startScan(root('large'), role: method == 'QueuedCancelRestart' ? 'blocker' : 'cancel_target');
          await waitFor(() => initialized.contains(blocker), 'Bounded scan missed active window');
          final cancel = method == 'QueuedCancelRestart' ? await startScan(root('secondary'), role: 'cancel_target') : blocker;
          await trace!.own(api!.abortScan(scanId: _uuid(cancel))).timeout(timeout);
          await startScan(root('primary'));
          await waitFor(() => scans.every(terminals.containsKey), 'Cancelled/replacement terminals missing');
        case 'HistoryRanges':
          await history();
        case 'Reconnect':
          final old = ramEpoch;
          final count = ramUpdates;
          await waitFor(() => ramUpdates > count, 'Original reconnect sample missing');
          await command('restart');
          await waitFor(() => interrupted && reconnected && ramEpoch != old && ramUpdates > count + 1, 'Fresh automatic reconnect sample missing');
      }
      outcome = errors.isEmpty ? 'succeeded' : 'failed';
    } on TimeoutException catch (error, stack) {
      outcome = 'timed_out'; recordError(error, stack);
    } catch (error, stack) { recordError(error, stack); }
    finally {
      for (final id in allScans.where(snapshots.containsKey)) {
        trace?.emit('scenario.snapshot', operationId: attemptId, label: id, metadata: null,
          counts: snapshots[id]);
      }
      interval?.end(outcome: outcome);
      measuring = false;
      resourcesSettled = await settleResources();
      trace?.emit('client.lifetime', outcome: 'unknown', metadata: null,
        counts: {'owned_resources_settled': resourcesSettled ? 1 : 0, 'transport_internal_unknown': 1});
      await trace?.finish();
      BenchmarkTrace.current = null;
      await publish('result.json', {'id': attemptId, 'method': method, 'ordinal': 1, 'client_launch': launchId,
        'backend_launches': backendLaunches, 'scan_ids': allScans.toList(), 'request_ids': requests.toList(),
        'scans': scanBindings.values.toList(), 'outcome': outcome});
      await publish('driver-outcome.json', {'outcome': outcome, 'resourcesSettled': resourcesSettled,
        'transportInternals': 'unknown', 'errors': errors, 'traceWriteFailed': trace?.writeFailed ?? true});
    }
    return outcome == 'succeeded' && errors.isEmpty && resourcesSettled && trace?.writeFailed == false && trace?.dropped == 0 ? 0 : 1;
  }

  Future<bool> settleResources() async {
    for (final gate in deliveryGates) { if (!gate.isCompleted) gate.complete(); }
    if (trace != null) trace!.historyDeliveryDelay = null;
    try {
      historySubscription?.close(); historySubscription = null;
      if (container == null || trace == null) return false;
      container!.invalidate(telemetryHistoryProvider('cpu'));
      await container!.pump();
      for (final id in allScans.where((id) => !terminals.containsKey(id))) {
        await trace!.own(api!.abortScan(scanId: _uuid(id))).timeout(timeout);
      }
      await trace!.joinOwned().timeout(timeout);
      await container!.read(telemetryProvider.notifier).service?.dispose().timeout(timeout);
      await trace!.joinOwned().timeout(timeout);
      container!.dispose();
      container = null;
      await trace!.joinOwned().timeout(timeout);
      trace!.closeOwnedClients();
      return true;
    } catch (error, stack) { recordError(error, stack); return false; }
  }

  Future<Map<String, int>> overheadScan() async {
    final provider = container!;
    final notifier = provider.read(directoryProvider.notifier);
    final previous = notifier.currentScanId;
    String? selected;
    var sawLoading = false;
    final terminal = Completer<void>();
    final subscription = provider.listen(directoryProvider, (_, state) {
      final current = notifier.currentScanId;
      if (current == null || current == previous || terminal.isCompleted) return;
      selected ??= current;
      if (current != selected) { terminal.completeError(StateError('Overhead scan superseded')); return; }
      if (state.errorMessage != null) { terminal.completeError(StateError('Overhead scan failed')); return; }
      if (state.isLoading) sawLoading = true;
      if (sawLoading && !state.isLoading) terminal.complete();
    });
    final request = notifier.scanDirectory(root('primary'));
    overheadRequests.add(request);
    unawaited(request.then((_) { overheadRequests.remove(request); }, onError: (Object _, StackTrace __) { overheadRequests.remove(request); }));
    try {
      await Future.wait([request, terminal.future]).timeout(timeout);
      if (selected == null || notifier.currentScanId != selected) throw StateError('Overhead scan identity lost');
      final result = snapshot(provider.read(directoryProvider).allNodes, root('primary'));
      const expected = {'nodes': 4, 'a_bytes': 33, 'b_bytes': 54, 'root_bytes': 3, 'zero_bytes': 0, 'unknown': 0};
      if (result.length != expected.length || expected.entries.any((e) => result[e.key] != e.value)) {
        throw StateError('Overhead fixture output mismatch: $result');
      }
      return result;
    } finally { subscription.close(); }
  }

  Future<Map<String, Object?>> overheadWork() async {
    final samples = <Map<String, Object?>>[];
    overheadWorkEvidence.addAll({'completed_scans': 0, 'scans': samples});
    final seed = await overheadScan();
    overheadWorkEvidence['seed'] = seed;
    final clock = Stopwatch()..start();
    try {
      for (var i = 0; i < 16; i++) {
        final before = clock.elapsedMicroseconds;
        final output = await overheadScan();
        samples.add({'ordinal': i + 1, 'elapsed_us': clock.elapsedMicroseconds - before, 'output': output});
        overheadWorkEvidence['completed_scans'] = samples.length;
      }
    } finally {
      clock.stop();
      overheadWorkEvidence['elapsed_us'] = clock.elapsedMicroseconds;
    }
    return overheadWorkEvidence;
  }

  Future<int> runOverhead() async {
    final detail = config['detail'] as String;
    final result = <String, Object?>{'schema_version': 1, 'run_id': runId, 'launch_id': launchId,
      'attempt_id': attemptId, 'detail': detail, 'workload': 'tiny-seed+16-warm-streams', 'outcome': 'failed'};
    ProviderSubscription<RamState>? ramSubscription;
    var settled = false, publications = 0, groups = 0;
    try {
      trace = await BenchmarkTrace.fromEnvironment();
      if ((detail == 'off') != (trace == null)) throw StateError('Overhead trace activation mismatch');
      BenchmarkTrace.current = trace;
      api = ApiService();
      container = ProviderContainer(overrides: [
        settingsProvider.overrideWith((ref) => SettingsNotifier(api)),
        directoryProvider.overrideWith((ref) => DirectoryNotifier(ref, apiService: api, initialRoot: root('primary'), autoStart: false)),
        ramProvider.overrideWith((ref) => RamNotifier(ref, api)),
        telemetryProvider.overrideWith((ref) => TelemetryNotifier(ref, allowTestTransport: true)),
        apiServiceProvider.overrideWithValue(api!),
      ]);
      await container!.read(settingsProvider.notifier).initialized.timeout(timeout);
      final settings = container!.read(settingsProvider);
      if (!settings.serviceConfirmed || settings.savedSettings?.advanced.backendPort != 5200) throw StateError('Owned backend settings unavailable');
      container!.read(directoryProvider.notifier);
      ramSubscription = container!.listen(ramProvider, (before, state) {
        if (state.groupedProcesses.isNotEmpty && !identical(before?.groupedProcesses, state.groupedProcesses)) {
          publications++; groups += state.groupedProcesses.length;
        }
      });
      container!.read(telemetryProvider.notifier);
      await waitFor(() => publications > 0 && container!.read(telemetryProvider.notifier).service?.isConnected == true,
        'Overhead nonempty live telemetry missing');
      final initialPublications = publications, initialGroups = groups;
      result['work'] = overheadWorkEvidence;
      await overheadWork();
      result['ram_publications_during_seed_and_work'] = publications - initialPublications;
      result['ram_groups_during_seed_and_work'] = groups - initialGroups;
      result['outcome'] = 'succeeded';
    } on TimeoutException catch (error, stack) {
      result['outcome'] = 'timed_out'; recordError(error, stack);
    } catch (error, stack) { recordError(error, stack); }
    finally {
      final drain = Stopwatch()..start();
      try {
        ramSubscription?.close();
        final provider = container;
        if (provider != null) {
          final notifier = provider.read(directoryProvider.notifier);
          if (provider.read(directoryProvider).isLoading && notifier.currentScanId != null) {
            await api!.abortScan(scanId: notifier.currentScanId).timeout(timeout);
          }
          await Future.wait(overheadRequests.toList()).timeout(timeout);
          await provider.read(telemetryProvider.notifier).service?.dispose().timeout(timeout);
          await trace?.joinOwned().timeout(timeout);
          provider.dispose(); container = null;
          await trace?.joinOwned().timeout(timeout);
          api?.close(); trace?.closeOwnedClients();
          await trace?.finish();
          settled = true;
        }
      } catch (error, stack) { recordError(error, stack); }
      BenchmarkTrace.current = null;
      drain.stop();
      result.addAll({'client_cleanup_us': drain.elapsedMicroseconds, 'owned_resources_settled': settled,
        'transport_internals': 'unknown', 'errors': errors, 'recorder_created': trace != null,
        'trace_write_failed': trace?.writeFailed ?? false, 'trace_dropped': trace?.dropped ?? 0});
      if (errors.isNotEmpty || !settled || trace?.writeFailed == true || (trace?.dropped ?? 0) != 0) {
        if (result['outcome'] == 'succeeded') result['outcome'] = 'failed';
      }
      await publish('overhead-result.json', result);
    }
    return result['outcome'] == 'succeeded' ? 0 : 1;
  }

  String _uuid(String id) => '${id.substring(0, 8)}-${id.substring(8, 12)}-${id.substring(12, 16)}-${id.substring(16, 20)}-${id.substring(20)}';
}
