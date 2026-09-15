import 'dart:convert';

class AppSettings {
  ScanSettings scan;
  AlertSettings alerts;
  MonitoringSettings monitoring;
  CacheSettings cache;
  AppearanceSettings appearance;
  AdvancedSettings advanced;

  AppSettings({
    required this.scan,
    required this.alerts,
    required this.monitoring,
    required this.cache,
    required this.appearance,
    required this.advanced,
  });

  factory AppSettings.fromjson(Map<String, dynamic> json) {
    return AppSettings(
      scan: ScanSettings.fromJson(json['scan'] ?? {}),
      alerts: AlertSettings.fromJson(json['alerts'] ?? {}),
      monitoring: MonitoringSettings.fromJson(json['monitoring'] ?? {}),
      cache: CacheSettings.fromJson(json['cache'] ?? {}),
      appearance: AppearanceSettings.fromJson(json['appearance'] ?? {}),
      advanced: AdvancedSettings.fromJson(json['advanced'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
    'scan': scan.toJson(),
    'alerts': alerts.toJson(),
    'monitoring': monitoring.toJson(),
    'cache': cache.toJson(),
    'appearance': appearance.toJson(),
    'advanced': advanced.toJson(),
  };

  AppSettings clone() => AppSettings.fromjson(jsonDecode(jsonEncode(toJson())));
}

class ScanSettings {
  int depth;
  List<String> excludedPaths;
  bool followSymlinks;
  bool skipHiddenFiles;
  bool skipSystemFiles;
  int? maxFilesSizeMb;

  ScanSettings({
    this.depth = 10,
    this.excludedPaths = const [],
    this.followSymlinks = false,
    this.skipHiddenFiles = true,
    this.skipSystemFiles = true,
    this.maxFilesSizeMb,
  });

  factory ScanSettings.fromJson(Map<String, dynamic> json) => ScanSettings(
    depth: json['depth'] ?? 10,
    excludedPaths: List<String>.from(json['excludedPaths'] ?? []),
    followSymlinks: json['followSymlinks'] ?? false,
    skipHiddenFiles: json['skipHiddenFiles'] ?? true,
    skipSystemFiles: json['skipSystemFiles'] ?? true,
    maxFilesSizeMb: json['maxFilesSizeMb'],
  );
  Map<String, dynamic> toJson() => {
    'depth': depth,
    'excludedPaths': excludedPaths,
    'followSymlinks': followSymlinks,
    'skipHiddenFiles': skipHiddenFiles,
    'skipSystemFiles': skipSystemFiles,
    'maxFilesSizeMb': maxFilesSizeMb,
  };
}

class AlertSettings {
  int diskThresholdPercent,
      ramThresholdPercent,
      ramMinimumFreeMb,
      cpuThresholdPercent,
      thermalThresholdCelsius;
  bool enableDesktopNotifications;

  AlertSettings({
    this.diskThresholdPercent = 90,
    this.ramThresholdPercent = 85,
    this.ramMinimumFreeMb = 1024,
    this.cpuThresholdPercent = 95,
    this.thermalThresholdCelsius = 85,
    this.enableDesktopNotifications = true,
  });

  factory AlertSettings.fromJson(Map<String, dynamic> json) => AlertSettings(
    diskThresholdPercent: json['diskThresholdPercent'] ?? 90,
    ramThresholdPercent: json['ramThresholdPercent'] ?? 85,
    ramMinimumFreeMb: json['ramMinimumFreeMb'] ?? 1024,
    cpuThresholdPercent: json['cpuThresholdPercent'] ?? 95,
    thermalThresholdCelsius:
        json['thermalThresholdCelsius'] ??
        json['thermalThresholdPercent'] ??
        85,
    enableDesktopNotifications: json['enableDesktopNotifications'] ?? true,
  );
  Map<String, dynamic> toJson() => {
    'diskThresholdPercent': diskThresholdPercent,
    'ramThresholdPercent': ramThresholdPercent,
    'ramMinimumFreeMb': ramMinimumFreeMb,
    'cpuThresholdPercent': cpuThresholdPercent,
    'thermalThresholdCelsius': thermalThresholdCelsius,
    'enableDesktopNotifications': enableDesktopNotifications,
  };
}

class MonitoringSettings {
  int cpuPollIntervalMs,
      ramPollIntervalMs,
      thermalPollIntervalMs,
      networkPollIntervalMs,
      diskIoPollIntervalMs,
      scheduledScanIntervalMinutes;
  bool enableScheduledScans;
  String? preferredNetworkInterfaceId;

  MonitoringSettings({
    this.cpuPollIntervalMs = 1000,
    this.ramPollIntervalMs = 2000,
    this.thermalPollIntervalMs = 2000,
    this.networkPollIntervalMs = 1000,
    this.diskIoPollIntervalMs = 1000,
    this.scheduledScanIntervalMinutes = 15,
    this.enableScheduledScans = false,
    this.preferredNetworkInterfaceId,
  });
  factory MonitoringSettings.fromJson(Map<String, dynamic> json) =>
      MonitoringSettings(
        cpuPollIntervalMs: json['cpuPollIntervalMs'] ?? 1000,
        ramPollIntervalMs: json['ramPollIntervalMs'] ?? 2000,
        thermalPollIntervalMs: json['thermalPollIntervalMs'] ?? 2000,
        networkPollIntervalMs: json['networkPollIntervalMs'] ?? 1000,
        diskIoPollIntervalMs: json['diskIoPollIntervalMs'] ?? 1000,
        scheduledScanIntervalMinutes:
            json['scheduledScanIntervalMinutes'] ?? 15,
        enableScheduledScans: json['enableScheduledScans'] ?? false,
        preferredNetworkInterfaceId: json['preferredNetworkInterfaceId'],
      );
  Map<String, dynamic> toJson() => {
    'cpuPollIntervalMs': cpuPollIntervalMs,
    'ramPollIntervalMs': ramPollIntervalMs,
    'thermalPollIntervalMs': thermalPollIntervalMs,
    'networkPollIntervalMs': networkPollIntervalMs,
    'diskIoPollIntervalMs': diskIoPollIntervalMs,
    'scheduledScanIntervalMinutes': scheduledScanIntervalMinutes,
    'enableScheduledScans': enableScheduledScans,
    'preferredNetworkInterfaceId': preferredNetworkInterfaceId,
  };
}

class CacheSettings {
  int scanCacheTtlMinutes, maxCacheScans, maxCachedNodes;
  CacheSettings({
    this.scanCacheTtlMinutes = 15,
    this.maxCacheScans = 5,
    this.maxCachedNodes = 50000,
  });
  factory CacheSettings.fromJson(Map<String, dynamic> json) => CacheSettings(
    scanCacheTtlMinutes: json['scanCacheTtlMinutes'] ?? 15,
    maxCacheScans: json['maxCacheScans'] ?? 5,
    maxCachedNodes: json['maxCachedNodes'] ?? 50000,
  );
  Map<String, dynamic> toJson() => {
    'scanCacheTtlMinutes': scanCacheTtlMinutes,
    'maxCacheScans': maxCacheScans,
    'maxCachedNodes': maxCachedNodes,
  };
}

class AppearanceSettings {
  String theme, accentColor;
  bool compactMode, showAnimations;
  AppearanceSettings({
    this.theme = 'cyber_dark',
    this.accentColor = 'cyan',
    this.compactMode = true,
    this.showAnimations = true,
  });
  factory AppearanceSettings.fromJson(Map<String, dynamic> json) =>
      AppearanceSettings(
        theme: json['theme'] ?? 'cyber_dark',
        accentColor: json['accentColor'] ?? 'cyan',
        compactMode: json['compactMode'] ?? true,
        showAnimations: json['showAnimations'] ?? true,
      );
  Map<String, dynamic> toJson() => {
    'theme': theme,
    'accentColor': accentColor,
    'compactMode': compactMode,
    'showAnimations': showAnimations,
  };
}

class AdvancedSettings {
  int backendPort, signalrReconnectDelaysMs, maxSignalrRetries;
  bool enableDebugLogs;
  AdvancedSettings({
    this.backendPort = 5200,
    this.signalrReconnectDelaysMs = 3000,
    this.maxSignalrRetries = 10,
    this.enableDebugLogs = false,
  });
  factory AdvancedSettings.fromJson(Map<String, dynamic> json) =>
      AdvancedSettings(
        backendPort: json['backendPort'] ?? 5200,
        signalrReconnectDelaysMs: json['signalrReconnectDelaysMs'] ?? 3000,
        maxSignalrRetries: json['maxSignalrRetries'] ?? 10,
        enableDebugLogs: json['enableDebugLogs'] ?? false,
      );
  Map<String, dynamic> toJson() => {
    'backendPort': backendPort,
    'signalrReconnectDelaysMs': signalrReconnectDelaysMs,
    'maxSignalrRetries': maxSignalrRetries,
    'enableDebugLogs': enableDebugLogs,
  };
}
