/// Dart model mirroring the backend StartupProgramDto.
/// fromJson reads both camelCase and PascalCase JSON keys for serializer resilience.
class StartupProgram {
  final String id;
  final String name;
  final String executablePath;
  final String? arguments;
  final bool isEnabled;
  final String scope; // "user" | "system"
  final String platform; // "windows" | "linux"

  const StartupProgram({
    required this.id,
    required this.name,
    required this.executablePath,
    this.arguments,
    required this.isEnabled,
    required this.scope,
    required this.platform,
  });

  bool get isSystemScope => scope.toLowerCase() == 'system';

  factory StartupProgram.fromJson(Map<String, dynamic> json) {
    return StartupProgram(
      id: json['id'] ?? json['Id'] ?? '',
      name: json['name'] ?? json['Name'] ?? '',
      executablePath: json['executablePath'] ?? json['ExecutablePath'] ?? '',
      arguments: json['arguments'] ?? json['Arguments'],
      isEnabled: json['isEnabled'] ?? json['IsEnabled'] ?? false,
      scope: json['scope'] ?? json['Scope'] ?? 'user',
      platform: json['platform'] ?? json['Platform'] ?? '',
    );
  }

  StartupProgram copyWith({bool? isEnabled}) {
    return StartupProgram(
      id: id,
      name: name,
      executablePath: executablePath,
      arguments: arguments,
      isEnabled: isEnabled ?? this.isEnabled,
      scope: scope,
      platform: platform,
    );
  }
}
