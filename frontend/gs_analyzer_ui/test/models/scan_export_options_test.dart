import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/scan_export_options.dart';

void main() {
  group('ScanExportFormat', () {
    test('values and extensions map correctly', () {
      expect(ScanExportFormat.json.value, 'json');
      expect(ScanExportFormat.csv.value, 'csv');
      expect(ScanExportFormat.html.value, 'html');

      expect(ScanExportFormat.json.fileExtension, 'json');
      expect(ScanExportFormat.csv.fileExtension, 'csv');
      expect(ScanExportFormat.html.fileExtension, 'html');

      expect(ScanExportFormat.json.label, 'JSON');
      expect(ScanExportFormat.csv.label, 'CSV');
      expect(ScanExportFormat.html.label, 'HTML');

      expect(ScanExportFormat.json.description.isNotEmpty, true);
      expect(ScanExportFormat.csv.description.isNotEmpty, true);
      expect(ScanExportFormat.html.description.isNotEmpty, true);
    });
  });

  group('ScanExportOptions', () {
    test('toQueryParameters formats query correctly', () {
      const options = ScanExportOptions(
        root: r'C:\',
        format: ScanExportFormat.csv,
        redactPaths: true,
      );

      final params = options.toQueryParameters();
      expect(params['root'], r'C:\');
      expect(params['format'], 'csv');
      expect(params['redactPaths'], 'true');
    });

    test('default options format is json and redactPaths is false', () {
      const options = ScanExportOptions(root: r'D:\');
      final params = options.toQueryParameters();
      expect(params['root'], r'D:\');
      expect(params['format'], 'json');
      expect(params['redactPaths'], 'false');
    });
  });
}
