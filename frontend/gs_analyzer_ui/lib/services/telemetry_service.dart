import 'dart:async';
import 'dart:io' show Platform;
import 'package:logging/logging.dart';
import 'package:gs_analyzer_ui/services/benchmark_trace.dart';
import 'package:gs_analyzer_ui/utils/logger.dart';
import 'package:signalr_netcore/signalr_client.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';

class TelemetryService {
  late HubConnection _hubConnection;
  final BenchmarkTrace? _trace;
  final bool allowTestTransport;
  StreamSubscription<LogRecord>? _traceLogs;

  Function(String)? onSectorChanged;
  final Function(
    String? scanId,
    String? status,
    int? completed,
    int? total,
    double? percentComplete,
    String? target,
  )
  onProgressUpdate;
  Function(double percentage, String target, int completed, int total)? onNukeProgress;
  Function(double percentage, String target, int completed, int total)? onTempCleanProgress;
  Function()? onNukeAborted;
  Function(Map<String, dynamic>)? onRamUpdate;
  Function(String? scanId, String path, List<dynamic> chunk)? onDirectoryChunk;
  Function(
    String? scanId,
    String path, {
    String? parentPath,
    int? ownBytes,
    int? recursiveBytes,
    bool? recursiveBytesFinal,
  })? onDirectoryStreamComplete;
  Function(Map<String, dynamic>)? onCpuUpdate;
  Function(List<dynamic>)? onDriveUpdate;
  Function(Map<String, dynamic>)? onAuditProgress;
  Function(List<dynamic>)? onScheduleUpdate;
  Function(Map<String, dynamic>)? onAutoScanComplete;
  Function(Map<String, dynamic>)? onDiskAlert;
  Function(Map<String, dynamic>)? onDiskAlertCleared;
  Function(Map<String, dynamic>)? onRamAlert;
  Function(Map<String, dynamic>)? onRamAlertCleared;
  Function(Map<String, dynamic>)? onNetworkUpdate;
  Function(Map<String, dynamic>)? onDiskIoUpdate;
  Function(Map<String, dynamic>)? onWatcherEventLogged;

  TelemetryService({
    required this.onProgressUpdate,
    int backendPort = 5200,
    int reconnectDelayMs = 3000,
    int maxRetries = 10,
    this.allowTestTransport = false,
    BenchmarkTrace? trace,
  }) : _trace = trace ?? BenchmarkTrace.current {
    _initRadio(backendPort, reconnectDelayMs, maxRetries);
  }

  void _initRadio(int port, int reconnectDelayMs, int maxRetries) {
    final url = "http://localhost:$port/systemHub";

    final retryDelays = List.generate(
      maxRetries,
      (i) => reconnectDelayMs * (i + 1),
    );

    final trace = _trace;
    final logger = trace == null ? null : (Logger.detached('benchmark.signalr')..level = Level.ALL);
    _traceLogs = logger?.onRecord.listen(trace!.transportLog);
    final builder = HubConnectionBuilder()
        .withUrl(url, options: logger == null ? null : HttpConnectionOptions(logger: logger, logMessageContent: false))
        .withAutomaticReconnect(retryDelays: retryDelays);
    if (trace != null) {
      builder.configureLogging(logger!);
      builder.withHubProtocol(BenchmarkHubProtocol(trace));
    }
    _hubConnection = builder.build();
    if (trace != null) {
      _hubConnection.onreconnecting(({error}) => trace.emit('transport.reconnecting', outcome: 'interrupted'));
      _hubConnection.onreconnected(({connectionId}) => trace.emit('transport.reconnected', outcome: 'connected'));
      _hubConnection.onclose(({error}) => trace.emit('transport.closed', outcome: error == null ? 'closed' : 'failed'));
    }

    _observe('ScanProgress', _handleIncomingTelemetry);
    _hubConnection.on('SectorChanged', _handleSectorChanged);
    _hubConnection.on('NukeProgress', _handleNukeProgress);
    _hubConnection.on('TempCleanProgress', _handleTempCleanProgress);
    _hubConnection.on('NukeAborted', _handleNukeAborted);
    _observe('RamUpdate', _handleRamUpdate);
    _observe('DirectoryChunk', _handleDirectoryChunk);
    _observe(
      'DirectoryStreamComplete',
      _handleDirectoryStreamComplete,
    );
    if (trace != null) _observe('DirectoryStreamError', (_) {});
    _hubConnection.on('ReceiveCpuTelemetry', _handleCpuUpdate);
    _hubConnection.on('DriveListUpdate', _handleDriveUpdate);
    _hubConnection.on('AuditProgress', _handleAuditProgress);
    _hubConnection.on('ScheduleUpdate', _handleScheduleUpdate);
    _hubConnection.on('AutoScanComplete', _handleAutoScanComplete);
    _hubConnection.on('DiskAlert', _handleDiskAlert);
    _hubConnection.on('DiskAlertCleared', _handleDiskAlertCleared);
    _hubConnection.on('RamAlert', _handleRamAlert);
    _hubConnection.on('RamAlertCleared', _handleRamAlertCleared);
    _hubConnection.on('NetworkUpdate', _handleNetworkUpdate);
    _hubConnection.on('DiskIoUpdate', _handleDiskIoUpdate);
    _hubConnection.on('WatcherEventLogged', _handleWatcherEventLogged);
  }

  void _observe(String event, void Function(List<Object?>?) handler) {
    final trace = _trace;
    if (trace == null) {
      _hubConnection.on(event, handler);
      return;
    }
    _hubConnection.on(event, (arguments) {
      trace.receive(event, arguments == null || arguments.isEmpty ? null : arguments.first, () {
        final span = trace.begin('service.dispatch');
        try { handler(arguments); span.end(outcome: 'returned'); }
        catch (_) { span.end(outcome: 'failed'); rethrow; }
      });
    });
  }

  bool get isConnected => _hubConnection.state == HubConnectionState.Connected;
  Future<void>? _connectingFuture;

  Future<void> ensureConnected({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    if (isConnected) return;
    if (Platform.environment.containsKey('FLUTTER_TEST') && !allowTestTransport) return;
    if (_connectingFuture != null) {
      try {
        await _connectingFuture!.timeout(timeout);
      } catch (_) {}
      return;
    }
    if (_hubConnection.state == HubConnectionState.Disconnected) {
      try {
        await startListening().timeout(timeout);
      } catch (_) {}
    }
  }

  Future<void> startListening() async {
    if (Platform.environment.containsKey('FLUTTER_TEST') && !allowTestTransport) return;
    if (_hubConnection.state == HubConnectionState.Disconnected) {
      final attempt = _trace?.begin('transport.start');
      final fut = _hubConnection.start();
      _connectingFuture = fut;
      try {
        await fut;
        attempt?.end(outcome: isConnected ? 'connected' : 'not_connected');
        appLogger.i('TELEMETRY RADIO: CONNECTED TO BASE STATION!');

        final api = ApiService();
        final starts = [api.startRamRadar(), api.startCpuRadar(), api.startNetworkRadar()];
        if (_trace != null) {
          for (final start in starts) { _trace.own(start); }
        }
      } catch (e) {
        attempt?.end(outcome: 'failed');
        appLogger.i(
          'TELEMETRY RADIO ERROR: FAILED TO CONNECT TO BASE STATION! - $e',
        );
      } finally {
        _connectingFuture = null;
      }
    }
  }

  Future<void> stopListening() async {
    if (_hubConnection.state == HubConnectionState.Connected) {
      await _hubConnection.stop();
      appLogger.i('TELEMETRY RADIO: DISCONNECTED FROM BASE STATION!');
    }
  }

  Future<void> dispose() async {
    try { await stopListening(); }
    finally {
      await _traceLogs?.cancel();
      _trace?.emit('transport.dispose', outcome: _hubConnection.state == HubConnectionState.Disconnected ? 'disconnected' : 'unsettled');
    }
  }

  void _handleIncomingTelemetry(List<Object?>? arguments) {
    if (arguments != null && arguments.isNotEmpty) {
      final data = arguments[0] as Map<String, dynamic>;

      final scanId = data['scanId'] as String?;
      final status = data['status'] as String?;
      final completed = (data['completed'] as num?)?.toInt();
      final total = (data['total'] as num?)?.toInt();
      final percentageComplete = (data['percentComplete'] as num?)?.toDouble();
      final target = data['currentTarget'] as String?;

      onProgressUpdate(
        scanId,
        status,
        completed,
        total,
        percentageComplete,
        target,
      );
    }
  }

  void _handleSectorChanged(List<Object?>? arguments) {
    if (arguments != null && arguments.isNotEmpty) {
      String changedFolder = arguments[0].toString();
      appLogger.i('RADAR ALERT RECEIVED: Changes in $changedFolder');

      if (onSectorChanged != null) {
        onSectorChanged!(changedFolder);
      }
    }
  }

  void _handleNukeProgress(List<Object?>? arguments) {
    if (arguments != null && arguments.isNotEmpty) {
      final data = arguments[0] as Map<String, dynamic>;

      final percentage = (data['percentage'] as num?)?.toDouble() ?? 0.0;
      final target = data['currentTarget'] as String? ?? (data['target'] as String? ?? '');
      final completed = (data['completed'] as num?)?.toInt() ?? 0;
      final total = (data['total'] as num?)?.toInt() ?? 0;
      if (onNukeProgress != null) {
        onNukeProgress!(percentage, target, completed, total);
      }
    }
  }

  void _handleTempCleanProgress(List<Object?>? arguments) {
    if (arguments != null && arguments.isNotEmpty) {
      final data = arguments[0] as Map<String, dynamic>;

      final percentage = (data['percentage'] as num?)?.toDouble() ?? 0.0;
      final target = data['currentTarget'] as String? ?? (data['target'] as String? ?? '');
      final completed = (data['completed'] as num?)?.toInt() ?? 0;
      final total = (data['total'] as num?)?.toInt() ?? 0;
      if (onTempCleanProgress != null) {
        onTempCleanProgress!(percentage, target, completed, total);
      }
    }
  }

  void _handleNukeAborted(List<Object?>? arguments) {
    appLogger.i('RADIO ALERT: NUKE ABORT SIGNAL RECEIVED FROM BACKEND');
    if (onNukeAborted != null) {
      onNukeAborted!();
    }
  }

  void _handleRamUpdate(List<Object?>? arguments) {
    if (arguments == null || arguments.isEmpty) return;
    try {
      final rawData = arguments[0];

      if (rawData is Map) {
        final data = Map<String, dynamic>.from(rawData);
        if (onRamUpdate != null) {
          onRamUpdate!(data);
        }
      } else if (rawData is List) {
        appLogger.i(
          'ARCHITECT ALERT: The backend is still sending the old list! The C# engine needs to be rebuilt',
        );
      } else {
        appLogger.i('UNKNOWN PAYLOAD TYPE: ${rawData.runtimeType}');
      }
    } catch (e) {
      appLogger.i('RAM PAYLOAD CRASH: $e');
    }
  }

  void _handleDirectoryChunk(List<Object?>? arguments) {
    if (arguments != null && arguments.isNotEmpty) {
      final data = arguments[0] as Map<String, dynamic>;
      onDirectoryChunk?.call(
        data['scanId'] as String?,
        data['path'],
        data['chunk'],
      );
    }
  }

  void _handleDirectoryStreamComplete(List<Object?>? arguments) {
    if (arguments != null && arguments.isNotEmpty) {
      final data = arguments[0] as Map<String, dynamic>;
      onDirectoryStreamComplete?.call(
        data['scanId'] as String?,
        data['path'].toString(),
        parentPath: data['parentPath'] as String?,
        ownBytes: (data['ownBytes'] as num?)?.toInt(),
        recursiveBytes: (data['recursiveBytes'] as num?)?.toInt(),
        recursiveBytesFinal: data['recursiveBytesFinal'] as bool?,
      );
    }
  }

  void _handleCpuUpdate(List<Object?>? arguments) {
    if (arguments == null || arguments.isEmpty) return;

    try {
      final rawData = arguments[0];

      if (rawData is Map) {
        final data = Map<String, dynamic>.from(rawData);
        if (onCpuUpdate != null) {
          onCpuUpdate!(data);
        }
      }
    } catch (e) {
      appLogger.i('CPU TELEMETRY CRASH: $e');
    }
  }

  void _handleDriveUpdate(List<Object?>? arguments) {
    if (arguments == null || arguments.isEmpty) return;
    try {
      final rawData = arguments[0];

      if (rawData is List) {
        if (onDriveUpdate != null) {
          onDriveUpdate!(rawData);
        }
      } else {
        appLogger.i('UNKNOWN DRIVE PAYLOAD TYPE: ${rawData.runtimeType}');
      }
    } catch (e) {
      appLogger.i('DRIVE TELEMETRY CRASH: $e');
    }
  }

  void _handleAuditProgress(List<Object?>? arguments) {
    if (onAuditProgress != null && arguments != null && arguments.isNotEmpty) {
      onAuditProgress!(arguments[0] as Map<String, dynamic>);
    }
  }

  void _handleScheduleUpdate(List<Object?>? arguments) {
    if (onScheduleUpdate != null && arguments != null && arguments.isNotEmpty) {
      final data = arguments[0] as Map<String, dynamic>;
      onScheduleUpdate!(data['schedules'] as List<dynamic>);
    }
  }

  void _handleAutoScanComplete(List<Object?>? arguments) {
    if (onAutoScanComplete != null && arguments != null && arguments.isNotEmpty) {
      onAutoScanComplete!(arguments[0] as Map<String, dynamic>);
    }
  }

  void _handleDiskAlert(List<Object?>? arguments) {
    if (onDiskAlert != null && arguments != null && arguments.isNotEmpty) {
      try {
        final rawData = arguments[0];
        if (rawData is Map) {
          onDiskAlert!(Map<String, dynamic>.from(rawData));
        }
      } catch (e) {
        appLogger.w('DISK ALERT PARSE ERROR: $e');
      }
    }
  }

  void _handleDiskAlertCleared(List<Object?>? arguments) {
    if (onDiskAlertCleared != null && arguments != null && arguments.isNotEmpty) {
      try {
        final rawData = arguments[0];
        if (rawData is Map) {
          onDiskAlertCleared!(Map<String, dynamic>.from(rawData));
        }
      } catch (e) {
        appLogger.w('DISK ALERT CLEARED PARSE ERROR: $e');
      }
    }
  }

  void _handleRamAlert(List<Object?>? arguments) {
    if (onRamAlert != null && arguments != null && arguments.isNotEmpty) {
      try {
        final rawData = arguments[0];
        if (rawData is Map) {
          onRamAlert!(Map<String, dynamic>.from(rawData));
        }
      } catch (e) {
        appLogger.w('RAM ALERT PARSE ERROR: $e');
      }
    }
  }

  void _handleRamAlertCleared(List<Object?>? arguments) {
    if (onRamAlertCleared != null && arguments != null && arguments.isNotEmpty) {
      try {
        final rawData = arguments[0];
        if (rawData is Map) {
          onRamAlertCleared!(Map<String, dynamic>.from(rawData));
        }
      } catch (e) {
        appLogger.w('RAM ALERT CLEARED PARSE ERROR: $e');
      }
    }
  }

  void _handleNetworkUpdate(List<Object?>? arguments) {
    if (arguments == null || arguments.isEmpty) return;
    try {
      final rawData = arguments[0];
      if (rawData is Map) {
        final data = Map<String, dynamic>.from(rawData);
        if (onNetworkUpdate != null) {
          onNetworkUpdate!(data);
        }
      }
    } catch (e) {
      appLogger.i('NETWORK TELEMETRY CRASH: $e');
    }
  }

  void _handleDiskIoUpdate(List<Object?>? arguments) {
    if (arguments == null || arguments.isEmpty) return;
    try {
      final rawData = arguments[0];
      if (rawData is Map) {
        final data = Map<String, dynamic>.from(rawData);
        if (onDiskIoUpdate != null) {
          onDiskIoUpdate!(data);
        }
      }
    } catch (e) {
      appLogger.i('DISK IO TELEMETRY CRASH: $e');
    }
  }

  void _handleWatcherEventLogged(List<Object?>? arguments) {
    if (onWatcherEventLogged != null && arguments != null && arguments.isNotEmpty) {
      try {
        final rawData = arguments[0];
        if (rawData is Map) {
          onWatcherEventLogged!(Map<String, dynamic>.from(rawData));
        }
      } catch (e) {
        appLogger.w('WATCHER EVENT PARSE ERROR: $e');
      }
    }
  }
}
