class StorageNode {
  final String name;
  final String path;
  final String type;
  final int sizeBytes;
  final DateTime lastModified;
  final bool isHidden;
  final bool isSystem;
  bool get isDirectory => type.toLowerCase() == 'directory';

  StorageNode({
    required this.name,
    required this.path,
    required this.type,
    required this.sizeBytes,
    required this.lastModified,
    this.isHidden = false,
    this.isSystem = false,
  });

  factory StorageNode.fromJson(Map<String, dynamic> json) {
    return StorageNode(
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      type: json['type'] ?? 'File',
      sizeBytes: json['sizeBytes'] ?? 0,
      lastModified: DateTime.parse(json['lastModified']),
      isHidden: json['isHidden'] ?? false,
      isSystem: json['isSystem'] ?? false,
    );
  }
}
