enum ScanExportFormat {
  json,
  csv,
  html,
}

extension ScanExportFormatExtension on ScanExportFormat {
  String get value {
    switch (this) {
      case ScanExportFormat.json:
        return 'json';
      case ScanExportFormat.csv:
        return 'csv';
      case ScanExportFormat.html:
        return 'html';
    }
  }

  String get label {
    switch (this) {
      case ScanExportFormat.json:
        return 'JSON';
      case ScanExportFormat.csv:
        return 'CSV';
      case ScanExportFormat.html:
        return 'HTML';
    }
  }

  String get fileExtension {
    switch (this) {
      case ScanExportFormat.json:
        return 'json';
      case ScanExportFormat.csv:
        return 'csv';
      case ScanExportFormat.html:
        return 'html';
    }
  }

  String get description {
    switch (this) {
      case ScanExportFormat.json:
        return 'Full nested tree with metadata envelope (round-trippable)';
      case ScanExportFormat.csv:
        return 'Flat table with depth column, suitable for Excel and spreadsheets';
      case ScanExportFormat.html:
        return 'Self-contained offline report with inline SVG charts in Cyber-HUD theme';
    }
  }
}

class ScanExportOptions {
  final String root;
  final ScanExportFormat format;
  final bool redactPaths;

  const ScanExportOptions({
    required this.root,
    this.format = ScanExportFormat.json,
    this.redactPaths = false,
  });

  Map<String, String> toQueryParameters() {
    return {
      'root': root,
      'format': format.value,
      'redactPaths': redactPaths.toString(),
    };
  }
}
