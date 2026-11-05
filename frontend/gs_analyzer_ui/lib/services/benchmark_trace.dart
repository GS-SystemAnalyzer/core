import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:signalr_netcore/ihub_protocol.dart';
import 'package:signalr_netcore/itransport.dart';
import 'package:signalr_netcore/json_hub_protocol.dart';

class BenchmarkMetadata {
  final Map<String, Object?> fields;
  BenchmarkMetadata._(this.fields);
  String get streamId => fields['streamId'] as String;
  String get producerEpoch => fields['producerEpoch'] as String;
  BigInt get sequence => BigInt.parse(fields['sequence'] as String);

  static BenchmarkMetadata? fromPayload(Object? payload, String runId) {
    if (payload is! Map) return null;
    final raw = payload['benchmarkTrace'];
    if (raw is! Map || raw['schemaVersion'] != 1 || raw['runId'] != runId)
      return null;
    const strings = [
      'streamId',
      'producerEpoch',
      'sequence',
      'clockId',
      'frequencyHz',
    ];
    for (final key in strings) {
      if (raw[key] is! String ||
          (raw[key] as String).isEmpty ||
          (raw[key] as String).length > 128)
        return null;
    }
    for (final key in ['sequence', 'frequencyHz']) {
      if (!RegExp(r'^[1-9][0-9]*$').hasMatch(raw[key] as String)) return null;
    }
    final start = raw['acquisitionStartTicks'];
    final end = raw['acquisitionEndTicks'];
    if ((start == null) != (end == null)) return null;
    if (start != null &&
        (start is! String ||
            end is! String ||
            start.length > 128 ||
            end.length > 128 ||
            !RegExp(r'^[0-9]+$').hasMatch(start) ||
            !RegExp(r'^[0-9]+$').hasMatch(end) ||
            BigInt.parse(end) < BigInt.parse(start)))
      return null;
    return BenchmarkMetadata._(
      Map.unmodifiable({
        'schemaVersion': 1,
        'runId': runId,
        for (final key in strings) key: raw[key],
        if (start != null) 'acquisitionStartTicks': start,
        if (end != null) 'acquisitionEndTicks': end,
      }),
    );
  }
}

class BenchmarkTrace {
  static BenchmarkTrace? current;
  static final _markerKey = Object();
  static final _requestKey = Object();
  static const _ambientMarker = Object();
  static BenchmarkMetadata? get marker =>
      Zone.current[_markerKey] as BenchmarkMetadata?;
  static String? get requestId => Zone.current[_requestKey] as String?;
  static String newId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  final String runId;
  final String epoch = newId();
  final bool rich;
  final int capacity;
  final Future<void> Function(String) _writeLine;
  final Future<void> Function()? _closeWriter;
  final Future<void> Function()? _publish;
  final void Function(Map<String, Object?>)? onRecord;
  Future<void> Function(int minutes)? historyDeliveryDelay;
  final Set<Future<void>> _tasks = {};
  final Set<BenchmarkHttpClient> _clients = {};
  bool _notifying = false;
  final Stopwatch _clock = Stopwatch()..start();
  final Queue<Map<String, Object?>> _queue = Queue();
  final Map<String, BigInt> _lastSequence = {};
  Future<void>? _pump;
  Future<void>? _finishing;
  int _eventId = 0, _operation = 0, _written = 0;
  int dropped = 0, outstanding = 0;
  bool writeFailed = false, _closed = false;
  int get ticks => _clock.elapsedTicks;
  bool get isOpen => !_closed;

  BenchmarkTrace(
    this.runId,
    this._writeLine, {
    this.capacity = 4096,
    this.rich = false,
    Future<void> Function()? closeWriter,
    Future<void> Function()? publish,
    this.onRecord,
  }) : _closeWriter = closeWriter,
       _publish = publish {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(runId) || capacity < 1)
      throw ArgumentError('Invalid trace owner or capacity');
    emit('trace.start', counts: {'rich': rich ? 1 : 0});
  }

  static Future<BenchmarkTrace?> fromEnvironment({void Function(Map<String, Object?>)? onRecord}) async {
    final run = Platform.environment['GS_BENCHMARK_RUN_ID'];
    final output = Platform.environment['GS_BENCHMARK_OUTPUT'];
    if (run == null && output == null) return null;
    if (run == null || output == null)
      throw const FormatException(
        'Both trace ownership variables are required',
      );
    return createOwned(run, output, onRecord: onRecord);
  }

  static Future<BenchmarkTrace> createOwned(String run, String output, {void Function(Map<String, Object?>)? onRecord}) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(run))
      throw const FormatException('Invalid trace run ID');
    final owner =
        jsonDecode(await File('$output/owner.json').readAsString()) as Map;
    if (owner['runId'] != run ||
        owner['schemaVersion'] != 1 ||
        !['minimal', 'rich'].contains(owner['detail']))
      throw const FormatException('Trace ownership mismatch');
    final target = '$output/client-${newId()}.jsonl';
    final partial = File('$target.partial');
    final file = await partial.open(mode: FileMode.writeOnly);
    return BenchmarkTrace(
      run,
      (line) async {
        await file.writeString('$line\n');
      },
      rich: owner['detail'] == 'rich',
      onRecord: onRecord,
      closeWriter: () async {
        try {
          await file.flush();
        } finally {
          await file.close();
        }
      },
      publish: () async {
        await partial.rename(target);
      },
    );
  }

  T withRequest<T>(String id, T Function() action) =>
      runZoned(action, zoneValues: {_requestKey: id});

  Future<T> own<T>(Future<T> operation) {
    // The returned branch preserves the caller's original error handling.
    _track(operation.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    return operation.then<T>((value) => value);
  }

  void _track(Future<void> settlement) {
    if (_closed || _tasks.length >= capacity) { dropped++; return; }
    late Future<void> tracked;
    tracked = settlement.whenComplete(() => _tasks.remove(tracked));
    _tasks.add(tracked);
  }

  Future<void> joinOwned() async {
    while (_tasks.isNotEmpty) { await Future.wait(_tasks.toList()); }
  }

  void closeOwnedClients() {
    if (_tasks.isNotEmpty || outstanding != 0) throw StateError('Observed work has not settled');
    for (final client in _clients.toList()) { client.close(); }
  }

  T receive<T>(String event, Object? payload, T Function() action) {
    final metadata = BenchmarkMetadata.fromPayload(payload, runId);
    var outcome = payload is Map && payload.containsKey('benchmarkTrace')
        ? 'invalid_metadata'
        : 'legacy';
    final counts = <String, int>{};
    if (metadata != null) {
      final key = '${metadata.producerEpoch}/${metadata.streamId}';
      final last = _lastSequence[key];
      outcome = last == null || metadata.sequence > last
          ? 'received'
          : metadata.sequence == last
          ? 'duplicate'
          : 'out_of_order';
      if (last != null && metadata.sequence > last) {
        // Producer sequences also cover local stages; jumps are not packet-loss counts.
        counts['sequence_jump'] = (metadata.sequence - last).toInt();
      }
      if (_lastSequence.containsKey(key) || _lastSequence.length < 1024) {
        if (last == null || metadata.sequence > last)
          _lastSequence[key] = metadata.sequence;
      } else {
        dropped++;
      }
    }
    emit(
      'receive.$event',
      outcome: outcome,
      metadata: metadata,
      counts: counts,
    );
    return runZoned(action, zoneValues: {_markerKey: metadata});
  }

  BenchmarkSpan begin(
    String stage, {
    Object? metadata = _ambientMarker,
    String? operationId,
  }) {
    return BenchmarkSpan._(
      this,
      stage,
      identical(metadata, _ambientMarker)
          ? marker
          : metadata as BenchmarkMetadata?,
      operationId ?? 'client-${++_operation}',
    );
  }

  void emit(
    String stage, {
    String outcome = 'observed',
    Object? metadata = _ambientMarker,
    String? operationId,
    Map<String, int>? counts,
    String? label,
  }) {
    if (_closed || writeFailed || _queue.length >= capacity) {
      dropped++;
      return;
    }
    final record = _record(
        stage,
        outcome,
        identical(metadata, _ambientMarker)
            ? marker
            : metadata as BenchmarkMetadata?,
        operationId,
        counts,
        label,
      );
    _queue.add(record);
    if (onRecord != null) {
      if (_notifying) { dropped++; }
      else {
        _notifying = true;
        try { onRecord!(record); } catch (_) { dropped++; }
        finally { _notifying = false; }
      }
    }
    _pump ??= _drain();
  }

  Map<String, Object?> _record(
    String stage,
    String outcome,
    BenchmarkMetadata? metadata,
    String? operationId,
    Map<String, int>? counts,
    String? label,
  ) => Map.unmodifiable({
    'schemaVersion': 1,
    'runId': runId,
    'processId': pid,
    'producerEpoch': epoch,
    'eventId': '${++_eventId}',
    'stage': stage,
    'outcome': outcome,
    'localTicks': '$ticks',
    'clockId': 'dart-$epoch',
    'frequencyHz': '${_clock.frequency}',
    if (metadata != null) 'benchmarkTrace': metadata.fields,
    if (operationId != null) 'operationId': operationId,
    if (counts != null) 'counts': Map<String, int>.unmodifiable(counts),
    if (label != null) 'label': label,
  });

  Future<void> _drain() async {
    try {
      while (_queue.isNotEmpty) {
        await _writeLine(jsonEncode(_queue.removeFirst()));
        _written++;
      }
    } catch (_) {
      writeFailed = true;
      _queue.clear();
    } finally {
      _pump = null;
    }
  }

  Future<void> finish() => _finishing ??= _finish();
  Future<void> _finish() async {
    _closed = true;
    await _pump;
    try {
      if (!writeFailed) {
        await _writeLine(
          jsonEncode(
            _record(
              'trace.end',
               dropped == 0 && outstanding == 0 && _tasks.isEmpty ? 'drained' : 'incomplete',
              null,
              null,
              {
                'dropped': dropped,
                'written': _written,
                 'outstanding': outstanding,
                 'owned_tasks': _tasks.length,
              },
              null,
            ),
          ),
        );
      }
    } catch (_) {
      writeFailed = true;
    }
    try {
      await _closeWriter?.call();
    } catch (_) {
      writeFailed = true;
    }
    if (!writeFailed) {
      try {
        await _publish?.call();
      } catch (_) {
        writeFailed = true;
      }
    }
    _lastSequence.clear();
    _clock.stop();
  }

  void transportLog(LogRecord record) {
    final message = record.message;
    if (message.startsWith('Sending negotiation request: ')) {
      emit('transport.negotiate');
    } else if (message.startsWith('WebSocket connected to ')) {
      emit('transport.connected', outcome: 'succeeded', label: 'WebSockets');
    } else if (message.startsWith('Selecting transport ')) {
      final selected = [
        'WebSockets',
        'ServerSentEvents',
        'LongPolling',
      ].where(message.contains).toList();
      emit(
        'transport.selected',
        label: selected.length == 1 ? selected.single : 'unknown',
      );
    } else if (message == 'The HttpConnection connected successfully.') {
      emit('transport.http_connected', outcome: 'succeeded');
    }
  }
}

class BenchmarkSpan {
  final BenchmarkTrace trace;
  final String stage, id;
  final BenchmarkMetadata? metadata;
  bool _ended = false;
  BenchmarkSpan._(this.trace, this.stage, this.metadata, this.id) {
    trace.outstanding++;
    trace.emit(
      '$stage.start',
      outcome: 'started',
      metadata: metadata,
      operationId: id,
    );
  }
  void end({String outcome = 'succeeded', Map<String, int>? counts}) {
    if (_ended) return;
    _ended = true;
    trace.emit(
      '$stage.end',
      outcome: outcome,
      metadata: metadata,
      operationId: id,
      counts: counts,
    );
    trace.outstanding--;
  }
}

class BenchmarkHubProtocol implements IHubProtocol {
  final BenchmarkTrace trace;
  final IHubProtocol delegate;
  BenchmarkHubProtocol(this.trace, {IHubProtocol? delegate})
    : delegate = delegate ?? JsonHubProtocol();
  @override
  String get name => delegate.name;
  @override
  int get version => delegate.version;
  @override
  TransferFormat get transferFormat => delegate.transferFormat;
  @override
  List<HubMessageBase> parseMessages(Object input, Logger? logger) {
    final bytes = input is String ? utf8.encode(input).length : null;
    final span = trace.begin('protocol.parse');
    try {
      final result = delegate.parseMessages(input, logger);
      span.end(
        counts: {
          'messages': result.length,
          if (bytes != null) 'hub_protocol_bytes': bytes,
        },
      );
      return result;
    } catch (_) {
      span.end(
        outcome: 'failed',
        counts: {if (bytes != null) 'hub_protocol_bytes': bytes},
      );
      rethrow;
    }
  }

  @override
  Object writeMessage(HubMessageBase message) => delegate.writeMessage(message);
}

class BenchmarkHttpClient extends http.BaseClient {
  final http.Client inner;
  final BenchmarkTrace trace;
  bool _closed = false;
  BenchmarkHttpClient(this.inner, this.trace) {
    if (trace._clients.length >= trace.capacity) { trace.dropped++; }
    else { trace._clients.add(this); }
  }
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final id = BenchmarkTrace.requestId ?? BenchmarkTrace.newId();
    request.headers['X-GS-Benchmark-Request-Id'] = id;
    final span = trace.begin('http.round_trip', operationId: id);
    final settlement = Completer<void>();
    trace._track(settlement.future);
    void settled() { if (!settlement.isCompleted) settlement.complete(); }
    var bytes = 0;
    var failed = false;
    try {
      final response = await inner.send(request);
      trace.emit(
        'http.headers',
        operationId: id,
        counts: {'status': response.statusCode},
      );
      late StreamSubscription<List<int>> subscription;
      late StreamController<List<int>> body;
      body = StreamController<List<int>>(
        sync: true,
        onListen: () {
          subscription = response.stream.listen(
            (data) {
              bytes += data.length;
              body.add(data);
            },
            onError: (Object error, StackTrace stack) {
              failed = true;
              trace.emit(
                'http.body_error',
                operationId: id,
                outcome: 'failed',
                counts: {'entity_bytes': bytes},
              );
              body.addError(error, stack);
            },
            onDone: () {
              span.end(
                outcome: failed ? 'failed' : 'succeeded',
                counts: {'entity_bytes': bytes, 'status': response.statusCode},
              );
              body.close().then((_) => settled());
            },
          );
        },
        onPause: () => subscription.pause(),
        onResume: () => subscription.resume(),
        onCancel: () async {
          try {
            await subscription.cancel();
            span.end(
              outcome: failed ? 'failed' : 'cancelled',
              counts: {'entity_bytes': bytes},
            );
          } catch (_) {
            span.end(outcome: 'failed');
            rethrow;
          } finally {
            settled();
          }
        },
      );
      return http.StreamedResponse(
        body.stream,
        response.statusCode,
        contentLength: response.contentLength,
        request: request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (_) {
      span.end(outcome: 'failed');
      settled();
      rethrow;
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    trace._clients.remove(this);
    inner.close();
  }
}
