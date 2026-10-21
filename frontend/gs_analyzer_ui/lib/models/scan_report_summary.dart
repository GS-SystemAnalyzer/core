class ScanCategorySummary {
  final String name;
  final int fileCount;
  final int totalBytes;

  const ScanCategorySummary({
    required this.name,
    required this.fileCount,
    required this.totalBytes,
  });

  factory ScanCategorySummary.fromJson(Map<String, dynamic> json) {
    return ScanCategorySummary(
      name: json['name'] as String? ?? 'other',
      fileCount: (json['fileCount'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'fileCount': fileCount,
    'totalBytes': totalBytes,
  };
}

class TopDirectorySummary {
  final String path;
  final int fileCount;
  final int ownBytes;
  final int recursiveBytes;

  const TopDirectorySummary({
    required this.path,
    required this.fileCount,
    required this.ownBytes,
    required this.recursiveBytes,
  });

  factory TopDirectorySummary.fromJson(Map<String, dynamic> json) {
    return TopDirectorySummary(
      path: json['path'] as String? ?? '',
      fileCount: (json['fileCount'] as num?)?.toInt() ?? 0,
      ownBytes: (json['ownBytes'] as num?)?.toInt() ?? 0,
      recursiveBytes: (json['recursiveBytes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'path': path,
    'fileCount': fileCount,
    'ownBytes': ownBytes,
    'recursiveBytes': recursiveBytes,
  };
}

class ScanReportSummary {
  final String root;
  final DateTime scannedAt;
  final DateTime exportedAt;
  final int totalBytes;
  final int totalFiles;
  final int directoryNodeCount;
  final List<ScanCategorySummary> categories;
  final List<TopDirectorySummary> topDirectories;

  const ScanReportSummary({
    required this.root,
    required this.scannedAt,
    required this.exportedAt,
    required this.totalBytes,
    required this.totalFiles,
    required this.directoryNodeCount,
    required this.categories,
    required this.topDirectories,
  });

  factory ScanReportSummary.fromJson(Map<String, dynamic> json) {
    return ScanReportSummary(
      root: json['root'] as String? ?? '',
      scannedAt: json['scannedAt'] != null
          ? DateTime.tryParse(json['scannedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      exportedAt: json['exportedAt'] != null
          ? DateTime.tryParse(json['exportedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      totalFiles: (json['totalFiles'] as num?)?.toInt() ?? 0,
      directoryNodeCount: (json['directoryNodeCount'] as num?)?.toInt() ?? 0,
      categories: (json['categories'] as List<dynamic>?)
              ?.map((e) => ScanCategorySummary.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      topDirectories: (json['topDirectories'] as List<dynamic>?)
              ?.map((e) => TopDirectorySummary.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'root': root,
    'scannedAt': scannedAt.toIso8601String(),
    'exportedAt': exportedAt.toIso8601String(),
    'totalBytes': totalBytes,
    'totalFiles': totalFiles,
    'directoryNodeCount': directoryNodeCount,
    'categories': categories.map((c) => c.toJson()).toList(),
    'topDirectories': topDirectories.map((d) => d.toJson()).toList(),
  };
}
