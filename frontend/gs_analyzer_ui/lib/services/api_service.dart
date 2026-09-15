import 'package:gs_analyzer_ui/utils/logger.dart';
import 'package:gs_analyzer_ui/models/temp_cleaner_model.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:gs_analyzer_ui/models/age_heatmap_model.dart';
import 'package:gs_analyzer_ui/models/drive_stats.dart';
import 'package:gs_analyzer_ui/models/nuke_preview.dart';
import 'package:gs_analyzer_ui/models/nuke_result.dart';
import 'package:http/http.dart' as http;
import 'package:gs_analyzer_ui/models/storage_node.dart';
import 'package:gs_analyzer_ui/models/file_type_model.dart';
import 'package:gs_analyzer_ui/models/extension_breakdown_model.dart';
import 'package:gs_analyzer_ui/providers/age_heatmap_provider.dart';
import 'package:gs_analyzer_ui/providers/file_type_provider.dart';
import 'package:gs_analyzer_ui/models/permission_audit_models.dart';
import 'package:gs_analyzer_ui/models/telemetry_history_model.dart';
import 'package:gs_analyzer_ui/models/startup_program.dart';
import 'package:gs_analyzer_ui/models/scheduled_scan_model.dart';
import 'package:gs_analyzer_ui/models/network_telemetry.dart';
import 'package:gs_analyzer_ui/models/disk_io_telemetry.dart';
import 'package:gs_analyzer_ui/models/scan_diff.dart';
import 'package:gs_analyzer_ui/models/cache_stats.dart';
import 'package:gs_analyzer_ui/models/scan_export_options.dart';
import 'package:gs_analyzer_ui/models/automation_rule.dart';
import 'dart:typed_data';

class ApiService {
  final http.Client _client;
  ApiService([http.Client? client]) : _client = client ?? http.Client();

  static const String storageUrl = 'http://localhost:5200/api/storage';
  static const String cacheUrl = 'http://localhost:5200/api/cache';
  static const String telemetryUrl = 'http://localhost:5200/api/Telemetry';
  static const String nukeUrl = 'http://localhost:5200/api/nuke';
  static const String thermalUrl = 'http://localhost:5200/api/thermal';
  static const String settingsUrl = 'http://localhost:5200/api/settings';
  static const String driveUrl = 'http://localhost:5200/api/drives';
  static const String auditUrl = 'http://localhost:5200/api/audit';
  static const String telemetryHistoryUrl = 'http://localhost:5200/api/telemetry/history';
  static const String tempFilesUrl = 'http://localhost:5200/api/tempfiles';
  static const String startupUrl = 'http://localhost:5200/api/startup';
  static const String schedulesUrl = 'http://localhost:5200/api/schedules';
  static const String scanDiffUrl = 'http://localhost:5200/api/scan/diff';
  static const String networkUrl = 'http://localhost:5200/api/network';
  static const String diskIoUrl = 'http://localhost:5200/api/diskio';
  static const String watcherUrl = 'http://localhost:5200/api/watcher';
  static const String automationUrl = 'http://localhost:5200/api/automation';

  Future<TelemetryHistoryResponse?> fetchTelemetryHistory(
    String metric,
    int minutes,
  ) async {
    final uri = Uri.parse(telemetryHistoryUrl).replace(
      queryParameters: {'metric': metric, 'minutes': minutes.toString()},
    );

    // appLogger.i('MATRIX BRIDGE FIRING TO: \$uri');
    final response = await _client.get(uri);

    if (response.statusCode == 200) {
      final jsonBody = jsonDecode(response.body);
      return TelemetryHistoryResponse.fromJson(jsonBody);
    } else {
      appLogger.i(
        'Failed to fetch telemetry history: \${response.statusCode} - \${response.body}',
      );
      return null;
    }
  }

  Future<List<StorageNode>> scanDirectory(String path, String scanId) async {
    final uri = Uri.parse('$storageUrl/scan');
    appLogger.i('MATRIX BRIDGE FIRING TO: $uri (root: $path, scanId: $scanId)');

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'Root': path, 'ScanId': scanId}),
    );

    if (response.statusCode == 200) {
      final jsonBody = jsonDecode(response.body);

      if (jsonBody['success'] == true) {
        appLogger.i('FEDEX BOX OPENED! Data is: ${jsonBody['data']}');
        List<dynamic> data = jsonBody['data'];
        return data.map((json) => StorageNode.fromJson(json)).toList();
      } else {
        throw Exception(jsonBody['message']);
      }
    } else {
      throw Exception(
        'Bridge Failed with Status: ${response.statusCode} - ${response.body}',
      );
    }
  }

  http.Client? _auditClient;

  Future<PermissionAuditResult> auditPermissions(String root) async {
    final uri = Uri.parse('$auditUrl/permissions');
    appLogger.i('FIRING PERMISSION AUDIT ON: $uri (root: $root)');

    _auditClient = http.Client();
    try {
      final response = await _auditClient!.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'root': root}),
      );

      if (response.statusCode == 200) {
        final jsonBody = jsonDecode(response.body);
        return PermissionAuditResult.fromJson(jsonBody);
      } else if (response.statusCode == 499) {
        throw Exception('AUDIT CANCELLED BY USER');
      } else {
        throw Exception(
          'Audit Failed with Status: ${response.statusCode} - ${response.body}',
        );
      }
    } finally {
      _auditClient?.close();
      _auditClient = null;
    }
  }

  void cancelAudit() {
    if (_auditClient != null) {
      appLogger.i('USER ABORT: CANCELLING PERMISSION AUDIT!');
      _auditClient!.close();
      _auditClient = null;
    }
  }

  Future<DriveStats> getDriveTelemetry(String driveLetter) async {
    final response = await _client.get(
      Uri.parse('$storageUrl/drive-stats?driveLetter=$driveLetter'),
    );

    if (response.statusCode == 200) {
      final jsonBody = json.decode(response.body);

      if (jsonBody['success'] == true) {
        return DriveStats.fromJson(jsonBody['data']);
      } else {
        throw Exception(jsonBody['message']);
      }
    } else {
      throw Exception('Failed to load hardware telemetry');
    }
  }

  Future<NukeResultDto> executeNuke(
    List<String> paths,
    String planToken, {
    bool useRecycleBin = false,
  }) async {
    final uri = Uri.parse('$nukeUrl/execute');

    appLogger.i("INITIATING NUKE PROTOCOL ON: $uri");

    final response = await _client.delete(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'paths': paths,
        'planToken': planToken,
        'useRecycleBin': useRecycleBin,
      }),
    );

    if (response.statusCode == 200) {
      final jsonBody = json.decode(response.body);

      if (jsonBody['success'] == true) {
        return NukeResultDto.fromJson(jsonBody['data']);
      } else {
        throw Exception(jsonBody['message']);
      }
    } else {
      throw Exception('Nuke Failed: ${response.statusCode} - ${response.body}');
    }
  }

  Future<NukeResultDto> undoNuke([String? operationId]) async {
    final uriStr = operationId != null
        ? '$nukeUrl/undo/$operationId'
        : '$nukeUrl/undo';
    final uri = Uri.parse(uriStr);
    final response = await _client.post(uri);

    if (response.statusCode == 200) {
      final jsonBody = json.decode(response.body);
      if (jsonBody['success'] == true) {
        return NukeResultDto.fromJson(jsonBody['data']);
      } else {
        throw Exception(jsonBody['message']);
      }
    } else {
      throw Exception('Undo Failed: ${response.statusCode} - ${response.body}');
    }
  }

  Future<List<NukeOperation>> getUndoHistory() async {
    final uri = Uri.parse('$nukeUrl/undo/history');
    final response = await _client.get(uri);

    if (response.statusCode == 200) {
      final jsonBody = json.decode(response.body);
      if (jsonBody['success'] == true) {
        List<dynamic> data = jsonBody['data'];
        return data.map((json) => NukeOperation.fromJson(json)).toList();
      } else {
        throw Exception(jsonBody['message']);
      }
    } else {
      throw Exception(
        'Failed to load undo history: ${response.statusCode} - ${response.body}',
      );
    }
  }

  Future<void> clearUndoStack() async {
    final uri = Uri.parse('$nukeUrl/undo');
    final response = await _client.delete(uri);
    if (response.statusCode != 200) {
      throw Exception('Failed to clear undo stack');
    }
  }

  Future<void> abortNuke() async {
    try {
      appLogger.i('SENDING NUKE ABORT SIGNAL....');
      await _client.post(Uri.parse('$nukeUrl/abort'));
    } catch (e) {
      appLogger.i('Failed to send abort signal: $e');
    }
  }

  Future<void> abortScan({String? scanId}) async {
    try {
      appLogger.i('SENDING SCAN ABORT SIGNAL... (scanId: $scanId)');
      var uri = Uri.parse('$storageUrl/abort-scan');
      if (scanId != null) {
        uri = uri.replace(queryParameters: {'scanId': scanId});
      }
      await _client.post(uri);
    } catch (e) {
      appLogger.i('Failed to send abort signal: $e');
    }
  }

  Future<bool> killRamProcesses(List<int> pids) async {
    final uri = Uri.parse('$telemetryUrl/ram/kill');
    appLogger.i(
      'INITIATING ASSASSINATION PROTOCOL ON ${pids.length}: TARGETS AT:  $uri',
    );

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(pids),
    );

    if (response.statusCode == 200) {
      return true;
    } else {
      throw Exception(
        'Failed to terminate PID Status: ${response.statusCode} - ${response.body}',
      );
    }
  }

  Future<void> startRamRadar() async {
    final uri = Uri.parse('$telemetryUrl/ram/start');
    try {
      final response = await _client.post(uri);
      if (response.statusCode == 200) {
        appLogger.i('FLUTTER COMMAND: RAM Radar Started Successfully!');
      }
    } catch (e) {
      appLogger.i('FLUTTER ERROR: Failed to start RAM Radar - $e');
    }
  }

  Future<void> startCpuRadar() async {
    final uri = Uri.parse('$telemetryUrl/cpu-load');
    try {
      final response = await _client.get(uri);
      if (response.statusCode == 200) {
        appLogger.i('FLUTTER COMMAND: CPU Radar Started Successfully!');
      } else {
        appLogger.i('FLUTTER COMMAND: Backend returned ${response.statusCode}');
      }
    } catch (e) {
      appLogger.i('FLUTTER ERROR: Failed to start CPU Radar - $e');
    }
  }

  Future<void> requestDirectoryStream(String path, String scanId) async {
    final uri = Uri.parse(
      '$storageUrl/stream-sector',
    ).replace(queryParameters: {'path': path, 'scanId': scanId});
    await _client.post(uri);
  }

  Future<List<dynamic>> scanForDuplicates(String path, String scanId) async {
    final uri = Uri.parse('$storageUrl/duplicates');
    appLogger.i(
      'INITIATING DUPLICATE HUNTER ON: $uri (root: $path, scanId: $scanId)',
    );

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'Root': path, 'ScanId': scanId}),
    );

    if (response.statusCode == 200) {
      final jsonBody = jsonDecode(response.body);

      if (jsonBody['success'] == true) {
        return jsonBody['data'] as List<dynamic>;
      } else {
        throw Exception(jsonBody['message']);
      }
    } else if (response.statusCode == 499) {
      // Backend signalled the duplicate scan was cancelled by the user — not an error.
      return <dynamic>[];
    } else {
      throw Exception(
        'Bridge Failed with Status: ${response.statusCode} - ${response.body}',
      );
    }
  }

  Future<List<dynamic>> scanForLargeFiles(String rootPath, int topN) async {
    final uri = Uri.parse(
      '$storageUrl/scan-largefiles',
    ).replace(queryParameters: {'root': rootPath, 'top': topN.toString()});

    appLogger.i('INITIATING LARGE FILE HUNTER ON: $uri');

    final response = await _client.get(uri);

    if (response.statusCode == 200) {
      final jsonBody = jsonDecode(response.body);

      if (jsonBody['success'] == true) {
        return jsonBody['data'] as List<dynamic>;
      } else {
        throw Exception(jsonBody['message']);
      }
    } else {
      throw Exception('Bridge Failed with Status: ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>?> getCurrentThermals() async {
    final uri = Uri.parse('$thermalUrl/current');
    appLogger.i('MATRIX BRIDGE: Requesting Instant Thermal Snapshot...');

    try {
      final response = await _client.get(uri);

      if (response.statusCode == 200) {
        final jsonBody = jsonDecode(response.body);

        if (jsonBody['success'] == true && jsonBody['data'] != null) {
          return jsonBody['data'] as Map<String, dynamic>;
        } else {
          appLogger.i('THERMAL SNAPSHOT FAILED: ${jsonBody['message']}');
          return null;
        }
      } else {
        appLogger.i('THERMAL SNAPSHOT FAILED: Status ${response.statusCode}');
        return null;
      }
    } catch (e) {
      appLogger.i('THERMAL BRIDGE ERROR: $e');
      return null;
    }
  }

  Future<NukePreviewResponse> previewNuke(List<String> paths) async {
    final uri = Uri.parse('$nukeUrl/preview');
    appLogger.i(
      'MATRIX BRIDGE: REQUESTING BLAST RADIUS FOR ${paths.length} TARGETTs',
    );

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'paths': paths}),
    );

    if (response.statusCode == 200) {
      final jsonBody = jsonDecode(response.body);

      if (jsonBody['success'] == true) {
        return NukePreviewResponse.fromJson(jsonBody['data']);
      } else {
        throw Exception(jsonBody['message']);
      }
    } else {
      throw Exception(
        'Bridge Failed with Status: ${response.statusCode} - ${response.body}',
      );
    }
  }

  Future<Map<String, dynamic>?> getSettings() async {
    try {
      final response = await _client.get(Uri.parse(settingsUrl));
      if (response.statusCode == 200) return jsonDecode(response.body)['data'];
    } catch (e) {
      appLogger.i('[API] Settings Fetch Error: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> saveSettings(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _client.post(
        Uri.parse(settingsUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      return jsonDecode(response.body);
    } catch (e) {
      return {'success': false, 'message': 'Network Error'};
    }
  }

  Future<Map<String, dynamic>?> resetSettings() async {
    try {
      final response = await _client.post(Uri.parse('$settingsUrl/reset'));
      if (response.statusCode == 200) return jsonDecode(response.body)['data'];
    } catch (e) {
      appLogger.i('[API] Reset Error: $e');
    }
    return null;
  }

  Future<List<dynamic>?> getDrives() async {
    try {
      final response = await _client.get(Uri.parse(driveUrl));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        if (decoded is List) return decoded;
        if (decoded['data'] != null) return decoded['data'];
      }
    } catch (e) {
      appLogger.i("[Api] Drives Fetch Error: $e");
    }
    return null;
  }

  Future<FileTypeResult> getFileTypes(String root, {bool refresh = false}) async {
    final query = <String, String>{'root': root};
    if (refresh) query['refresh'] = 'true';
    final uri = Uri.parse(
      '$storageUrl/scan/filetypes',
    ).replace(queryParameters: query);

    final response = await _client.get(uri);

    if (response.statusCode == 409) {
      throw FileTypeNoScanException();
    }

    if (response.statusCode != 200) {
      throw Exception(
        'FileTypes fetch failed [${response.statusCode}]: ${response.body}',
      );
    }

    return FileTypeResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<ExtensionBreakdownResult> getExtensionBreakdown(String root, {bool refresh = false}) async {
    final query = <String, String>{'root': root};
    if (refresh) query['refresh'] = 'true';
    final uri = Uri.parse(
      '$storageUrl/scan/extensions',
    ).replace(queryParameters: query);

    final response = await _client.get(uri);

    if (response.statusCode == 409) {
      throw const FileTypeNoScanException();
    }

    if (response.statusCode != 200) {
      throw Exception(
        'ExtensionBreakdown fetch failed [${response.statusCode}]: ${response.body}',
      );
    }

    return compute(_parseBreakdown, response.body);
  }

  Future<bool> clearCache() async {
    try {
      final response = await _client.delete(
        Uri.parse(cacheUrl),
      );
      if (response.statusCode == 200) {
        appLogger.i('[API] Cache cleared successfully.');
        return true;
      }
      appLogger.i('[API] Cache clear failed: ${response.statusCode}');
      return false;
    } catch (e) {
      appLogger.i('[API] Cache clear error: $e');
      return false;
    }
  }

  Future<CacheStats?> getCacheStats() async {
    try {
      final response = await _client.get(
        Uri.parse('$cacheUrl/stats'),
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json.containsKey('data') && json['data'] is Map<String, dynamic>
            ? json['data'] as Map<String, dynamic>
            : json;
        return CacheStats.fromJson(data);
      }
      appLogger.i('[API] Fetch cache stats failed: ${response.statusCode}');
      return null;
    } catch (e) {
      appLogger.i('[API] Fetch cache stats error: $e');
      return null;
    }
  }

  Future<AgeHeatmapResult> getAgeHeatmap(String root) async {
    final uri = Uri.parse(
      '$storageUrl/scan/ageheatmap',
    ).replace(queryParameters: {'root': root});

    appLogger.i('MATRIX BRIDGE: Requesting Age Heatmap for $root');

    final response = await _client.get(uri);

    if (response.statusCode == 409) {
      throw AgeHeatmapNoScanException();
    }

    if (response.statusCode != 200) {
      throw Exception(
        'AgeHeatmap fetch failed [${response.statusCode}]: ${response.body}',
      );
    }

    return AgeHeatmapResult.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<TempPreviewResponse> getTempPreview() async {
    final uri = Uri.parse('$tempFilesUrl/preview');
    appLogger.i('MATRIX BRIDGE: Requesting Temp Folder Preview...');

    final response = await _client.get(uri);

    if (response.statusCode == 200) {
      final jsonBody = jsonDecode(response.body);

      if (jsonBody['success'] == true) {
        return TempPreviewResponse.fromJson(jsonBody['data']);
      } else {
        throw Exception(jsonBody['message']);
      }
    } else {
      throw Exception(
        'Bridge Failed with Status: ${response.statusCode} - ${response.body}',
      );
    }
  }

  Future<TempCleanResult> cleanTempFiles(List<String> paths) async {
    final uri = Uri.parse('$tempFilesUrl/clean');
    appLogger.i(
      'INITIATING TEMP CLEAN PROTOCOL ON: $uri (${paths.length} locations)',
    );

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'paths': paths}),
    );

    if (response.statusCode == 200) {
      final jsonBody = jsonDecode(response.body);

      if (jsonBody['success'] == true) {
        return TempCleanResult.fromJson(jsonBody['data']);
      } else {
        throw Exception(jsonBody['message']);
      }
    } else {
      throw Exception(
        'Temp Clean Failed: ${response.statusCode} - ${response.body}',
      );
    }
  }

  Future<List<StartupProgram>> getStartupPrograms() async {
    final response = await _client.get(Uri.parse(startupUrl));

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      final List data = decoded is List ? decoded : (decoded['data'] ?? []);
      return data
          .map((e) => StartupProgram.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw Exception(
      'Startup fetch failed [${response.statusCode}]: ${response.body}',
    );
  }

  Future<void> setStartupEnabled(String id, bool enable) async {
    final action = enable ? 'enable' : 'disable';
    final uri = Uri.parse('$startupUrl/${Uri.encodeComponent(id)}/$action');
    appLogger.i('STARTUP BRIDGE: ${action.toUpperCase()} -> $uri');
    final response = await _client.post(uri);
    _ensureStartupSuccess(response);
  }

  Future<void> deleteStartupProgram(String id) async {
    final uri = Uri.parse('$startupUrl/${Uri.encodeComponent(id)}');
    appLogger.i('STARTUP BRIDGE: DELETE -> $uri');
    final response = await _client.delete(uri);
    _ensureStartupSuccess(response);
  }

  void _ensureStartupSuccess(http.Response response) {
    if (response.statusCode == 200) return;

    String message;
    try {
      final body = jsonDecode(response.body);
      message = body['error'] ?? body['message'] ?? response.body;
    } catch (_) {
      message = response.body;
    }

    if (response.statusCode == 403) {
      throw StartupAdminRequiredException(message);
    }
    throw Exception('Startup action failed [${response.statusCode}]: $message');
  }

  // --- SCHEDULED SCANS ---

  Future<List<ScheduledScan>> getSchedules() async {
    final uri = Uri.parse(schedulesUrl);
    final response = await _client.get(uri);

    if (response.statusCode == 200) {
      final List<dynamic> jsonList = jsonDecode(response.body);
      return jsonList.map((j) => ScheduledScan.fromJson(j)).toList();
    } else {
      throw Exception('Failed to load schedules: ${response.body}');
    }
  }

  Future<ScheduledScan> createSchedule(Map<String, dynamic> data) async {
    final uri = Uri.parse(schedulesUrl);
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );

    if (response.statusCode == 201) {
      return ScheduledScan.fromJson(jsonDecode(response.body));
    } else {
      _throwDetailedError('Failed to create schedule', response);
      throw Exception('Unreachable');
    }
  }

  Future<ScheduledScan> updateSchedule(
    String id,
    Map<String, dynamic> data,
  ) async {
    final uri = Uri.parse('$schedulesUrl/$id');
    final response = await _client.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );

    if (response.statusCode == 200) {
      return ScheduledScan.fromJson(jsonDecode(response.body));
    } else {
      _throwDetailedError('Failed to update schedule', response);
      throw Exception('Unreachable');
    }
  }

  Future<void> deleteSchedule(String id) async {
    final uri = Uri.parse('$schedulesUrl/$id');
    final response = await _client.delete(uri);

    if (response.statusCode != 200) {
      _throwDetailedError('Failed to delete schedule', response);
    }
  }

  Future<void> runScheduleNow(String id) async {
    final uri = Uri.parse('$schedulesUrl/$id/run-now');
    final response = await _client.post(uri);

    if (response.statusCode == 409) {
      throw ScheduleBusyException();
    } else if (response.statusCode != 200) {
      _throwDetailedError('Failed to run schedule', response);
    }
  }

  void _throwDetailedError(String prefix, http.Response response) {
    try {
      final body = jsonDecode(response.body);
      final message = body['message'] ?? response.body;
      throw Exception('$prefix: $message');
    } catch (_) {
      throw Exception('$prefix [${response.statusCode}]: ${response.body}');
    }
  }

  // --- SCAN RESULT DIFF ---

  /// Fetches the diff of the latest scan of [root] against its stored baseline.
  /// Throws [DiffNoScanException] when no scan is cached (409) — never triggers a scan.
  Future<ScanDiff> getScanDiff(String root, {int minDeltaBytes = 0}) async {
    final uri = Uri.parse(scanDiffUrl).replace(
      queryParameters: {
        'root': root,
        'minDeltaBytes': minDeltaBytes.toString(),
      },
    );

    final response = await _client.get(uri);

    if (response.statusCode == 409) {
      throw const DiffNoScanException();
    }

    if (response.statusCode != 200) {
      throw Exception(
        'ScanDiff fetch failed [${response.statusCode}]: ${response.body}',
      );
    }

    return ScanDiff.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  /// Clears the stored baseline for [root]; the next scan will report hasBaseline=false.
  Future<void> clearDiffBaseline(String root) async {
    final uri = Uri.parse(
      '$scanDiffUrl/baseline',
    ).replace(queryParameters: {'root': root});

    final response = await _client.delete(uri);

    if (response.statusCode != 200) {
      throw Exception(
        'Clear baseline failed [${response.statusCode}]: ${response.body}',
      );
    }
  }

  /// Fetches the latest network snapshot via REST.
  Future<NetworkSnapshot?> fetchNetworkSnapshot() async {
    final uri = Uri.parse('$networkUrl/interfaces');
    try {
      final response = await _client.get(uri);
      if (response.statusCode == 200) {
        final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
        return NetworkSnapshot.fromJson(jsonBody);
      } else {
        appLogger.i('Failed to fetch network snapshot: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      appLogger.i('Network snapshot request failed: $e');
      return null;
    }
  }

  /// Sets or clears the preferred primary network interface.
  Future<bool> setPreferredNetworkInterface(String? interfaceId) async {
    final uri = Uri.parse('$networkUrl/primary');
    try {
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'interfaceId': interfaceId}),
      );
      return response.statusCode == 200;
    } catch (e) {
      appLogger.i('Failed to set primary network interface: $e');
      return false;
    }
  }

  /// Fetches the latest disk I/O snapshot via REST.
  Future<DiskIoSnapshotCollection?> fetchDiskIoSnapshot() async {
    final uri = Uri.parse(diskIoUrl);
    try {
      final response = await _client.get(uri);
      if (response.statusCode == 200) {
        final jsonBody = jsonDecode(response.body) as Map<String, dynamic>;
        return DiskIoSnapshotCollection.fromJson(jsonBody);
      } else {
        appLogger.i('Failed to fetch disk I/O snapshot: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      appLogger.i('Disk I/O snapshot request failed: $e');
      return null;
    }
  }

  // --- WATCHER EVENT LOG ---

  Future<List<dynamic>> getWatcherLog({int limit = 500, String? kind}) async {
    var uri = Uri.parse('$watcherUrl/log').replace(queryParameters: {
      'limit': limit.toString(),
      if (kind != null) 'kind': kind,
    });

    try {
      final response = await _client.get(uri);
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as List<dynamic>;
      } else {
        appLogger.i('Failed to fetch watcher log: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      appLogger.i('Watcher log fetch error: $e');
      return [];
    }
  }

  Future<bool> clearWatcherLog() async {
    final uri = Uri.parse('$watcherUrl/log');
    try {
      final response = await _client.delete(uri);
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (e) {
      appLogger.i('Watcher log clear error: $e');
      return false;
    }
  }

  /// Triggers network engine snapshot query upon app startup.
  Future<void> startNetworkRadar() async {
    final uri = Uri.parse('$networkUrl/interfaces');
    try {
      await _client.get(uri);
    } catch (e) {
      appLogger.i('Failed to trigger network radar: $e');
    }
  }

  /// Exports the cached scan report in JSON, CSV, or HTML format.
  /// Throws [DiffNoScanException] if 409 Conflict is returned (no cache).
  Future<Uint8List> exportScan({
    required String root,
    ScanExportFormat format = ScanExportFormat.json,
    bool redactPaths = false,
  }) async {
    final uri = Uri.parse('http://localhost:5200/api/scan/export').replace(queryParameters: {
      'root': root,
      'format': format.value,
      'redactPaths': redactPaths.toString(),
    });

    final response = await _client.get(uri);
    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else if (response.statusCode == 409) {
      throw const DiffNoScanException();
    } else {
      throw Exception('Failed to export scan report: HTTP ${response.statusCode}');
    }
  }

  Future<List<AutomationRule>> getAutomationRules() async {
    final uri = Uri.parse('$automationUrl/rules');
    final response = await _client.get(uri);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => AutomationRule.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load automation rules: HTTP ${response.statusCode}');
    }
  }

  Future<AutomationRule> createAutomationRule(Map<String, dynamic> request) async {
    final uri = Uri.parse('$automationUrl/rules');
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(request),
    );
    if (response.statusCode == 201) {
      return AutomationRule.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 400) {
      final json = jsonDecode(response.body);
      throw Exception(json['message'] ?? 'Validation error on rule root allowlist');
    } else {
      throw Exception('Failed to create rule: HTTP ${response.statusCode}');
    }
  }

  Future<AutomationRule> updateAutomationRule(String id, Map<String, dynamic> request) async {
    final uri = Uri.parse('$automationUrl/rules/$id');
    final response = await _client.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(request),
    );
    if (response.statusCode == 200) {
      return AutomationRule.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 400) {
      final json = jsonDecode(response.body);
      throw Exception(json['message'] ?? 'Validation error');
    } else {
      throw Exception('Failed to update rule: HTTP ${response.statusCode}');
    }
  }

  Future<void> deleteAutomationRule(String id) async {
    final uri = Uri.parse('$automationUrl/rules/$id');
    final response = await _client.delete(uri);
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw Exception('Failed to delete rule: HTTP ${response.statusCode}');
    }
  }

  Future<NukePreviewResponse> dryRunAutomationRule(String id) async {
    final uri = Uri.parse('$automationUrl/rules/$id/dryrun');
    final response = await _client.post(uri);
    if (response.statusCode == 200) {
      return NukePreviewResponse.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Dry run failed: HTTP ${response.statusCode}');
    }
  }

  Future<AutomationRule> armAutomationRule(String id) async {
    final uri = Uri.parse('$automationUrl/rules/$id/arm');
    final response = await _client.post(uri);
    if (response.statusCode == 200) {
      return AutomationRule.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to arm rule: HTTP ${response.statusCode}');
    }
  }

  Future<AutomationAuditEntry> runAutomationRule(String id) async {
    final uri = Uri.parse('$automationUrl/rules/$id/run');
    final response = await _client.post(uri);
    if (response.statusCode == 200) {
      return AutomationAuditEntry.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 409) {
      throw const ScheduleBusyException();
    } else {
      throw Exception('Failed to trigger rule: HTTP ${response.statusCode}');
    }
  }

  Future<List<AutomationAuditEntry>> getAutomationAudit([int days = 30]) async {
    final uri = Uri.parse('$automationUrl/audit?days=$days');
    final response = await _client.get(uri);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => AutomationAuditEntry.fromJson(json)).toList();
    } else {
      throw Exception('Failed to fetch audit log: HTTP ${response.statusCode}');
    }
  }
}

ExtensionBreakdownResult _parseBreakdown(String body) {
  return ExtensionBreakdownResult.fromJson(
    jsonDecode(body) as Map<String, dynamic>,
  );
}

class StartupAdminRequiredException implements Exception {
  final String message;
  const StartupAdminRequiredException([
    this.message =
        'Administrator privileges are required to modify system-scope startup entries.',
  ]);

  @override
  String toString() => message;
}

class ScheduleBusyException implements Exception {
  const ScheduleBusyException();
  @override
  String toString() => 'A scan is already in progress. Try again later.';
}

class DiffNoScanException implements Exception {
  const DiffNoScanException();
  @override
  String toString() => 'No scan cached for this root. Run a scan first.';
}
