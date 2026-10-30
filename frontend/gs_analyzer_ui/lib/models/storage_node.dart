class StorageNode {
  final String name;
  final String path;
  final String? parentPath;
  final String type;
  final int sizeBytes;
  final DateTime lastModified;
  final bool isHidden;
  final bool isSystem;
  final int ownBytes;
  final int recursiveBytes;
  final bool isRecursiveFinal;
  bool get isDirectory => type.toLowerCase() == 'directory';

  StorageNode({
    required this.name,
    required this.path,
    this.parentPath,
    required this.type,
    required this.sizeBytes,
    required this.lastModified,
    this.isHidden = false,
    this.isSystem = false,
    this.ownBytes = 0,
    this.recursiveBytes = 0,
    this.isRecursiveFinal = true,
  });

  factory StorageNode.fromJson(Map<String, dynamic> json) {
    return StorageNode(
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      parentPath: json['parentPath'],
      type: json['type'] ?? 'File',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      lastModified: DateTime.tryParse(json['lastModified']?.toString() ?? '') ?? DateTime.now(),
      isHidden: json['isHidden'] ?? false,
      isSystem: json['isSystem'] ?? false,
      ownBytes: (json['ownBytes'] as num?)?.toInt() ?? 0,
      recursiveBytes: (json['recursiveBytes'] as num?)?.toInt() ?? 0,
      isRecursiveFinal: json['recursiveBytesFinal'] as bool? ??
          json['isRecursiveFinal'] as bool? ??
          ((json['type']?.toString().toLowerCase() ?? '') != 'directory'),
    );
  }

  StorageNode copyWith({
    String? name,
    String? path,
    String? parentPath,
    String? type,
    int? sizeBytes,
    DateTime? lastModified,
    bool? isHidden,
    bool? isSystem,
    int? ownBytes,
    int? recursiveBytes,
    bool? isRecursiveFinal,
  }) {
    return StorageNode(
      name: name ?? this.name,
      path: path ?? this.path,
      parentPath: parentPath ?? this.parentPath,
      type: type ?? this.type,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      lastModified: lastModified ?? this.lastModified,
      isHidden: isHidden ?? this.isHidden,
      isSystem: isSystem ?? this.isSystem,
      ownBytes: ownBytes ?? this.ownBytes,
      recursiveBytes: recursiveBytes ?? this.recursiveBytes,
      isRecursiveFinal: isRecursiveFinal ?? this.isRecursiveFinal,
    );
  }
}
