import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/scan_report_summary.dart';
import 'package:gs_analyzer_ui/utils/scan_report_builder.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_extension.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/report_palette.dart';

void main() {
  group('ScanReportBuilder Tests', () {
    final sampleData = ScanReportSummary(
      root: r'C:\Users\User\Projects',
      scannedAt: DateTime.utc(2026, 10, 19, 12, 0, 0),
      exportedAt: DateTime.utc(2026, 10, 19, 12, 5, 0),
      totalBytes: 104857600, // 100 MB
      totalFiles: 1500,
      directoryNodeCount: 50,
      categories: const [
        ScanCategorySummary(name: 'media', fileCount: 200, totalBytes: 52428800), // 50%
        ScanCategorySummary(name: 'code', fileCount: 800, totalBytes: 31457280),  // 30%
        ScanCategorySummary(name: 'documents', fileCount: 500, totalBytes: 20971520), // 20%
      ],
      topDirectories: const [
        TopDirectorySummary(
          path: r'C:\Users\User\Projects\src',
          fileCount: 400,
          ownBytes: 10485760,
          recursiveBytes: 52428800,
        ),
        TopDirectorySummary(
          path: r'C:\Users\User\Projects\assets',
          fileCount: 200,
          ownBytes: 20971520,
          recursiveBytes: 31457280,
        ),
      ],
    );

    test('generates self-contained HTML report with zero external network references and zero scripts', () {
      final darkTheme = HudTheme.darkTheme(HudColor.darkAccentCyan);
      final hud = darkTheme.extension<HudThemeExtension>()!;
      final palette = ReportPalette.fromHudTheme(hud);

      final html = buildScanReportHtml(sampleData, palette);

      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('GS System Analyzer — Scan Report'));
      expect(html, contains('CYBER-HUD OFFLINE REPORT'));
      expect(html, contains('FILE TYPE ANALYTICS'));
      expect(html, contains('TOP DIRECTORIES'));

      // Strict self-contained offline guarantees
      expect(html, isNot(contains('http://')));
      expect(html, isNot(contains('https://')));
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('</script>')));
    });

    test('applies dark theme tokens when dark theme is active', () {
      final darkTheme = HudTheme.darkTheme(HudColor.darkAccentCyan);
      final hud = darkTheme.extension<HudThemeExtension>()!;
      final palette = ReportPalette.fromHudTheme(hud);

      final html = buildScanReportHtml(sampleData, palette);

      final expectedBg = ReportPalette.toCssHex(hud.base);
      final expectedText = ReportPalette.toCssHex(hud.textMain);
      final expectedAccent = ReportPalette.toCssHex(hud.accentColor);

      expect(html, contains('--bg-base: $expectedBg'));
      expect(html, contains('--text-primary: $expectedText'));
      expect(html, contains('--accent-color: $expectedAccent'));
    });

    test('applies light theme tokens when light theme is active', () {
      final lightTheme = HudTheme.lightTheme(HudColor.lightAccentCyan);
      final hud = lightTheme.extension<HudThemeExtension>()!;
      final palette = ReportPalette.fromHudTheme(hud);

      final html = buildScanReportHtml(sampleData, palette);

      final expectedBg = ReportPalette.toCssHex(hud.base);
      final expectedText = ReportPalette.toCssHex(hud.textMain);
      final expectedAccent = ReportPalette.toCssHex(hud.accentColor);

      expect(html, contains('--bg-base: $expectedBg'));
      expect(html, contains('--text-primary: $expectedText'));
      expect(html, contains('--accent-color: $expectedAccent'));
      // Light theme background must not be dark
      expect(expectedBg.toLowerCase(), equals('#eef2f5'));
    });

    test('applies user-selected Amber accent in dark theme to HTML report', () {
      final amberTheme = HudTheme.darkTheme(HudColor.darkAccentAmber);
      final hud = amberTheme.extension<HudThemeExtension>()!;
      final palette = ReportPalette.fromHudTheme(hud);

      final html = buildScanReportHtml(sampleData, palette);

      final expectedAccent = ReportPalette.toCssHex(HudColor.darkAccentAmber);
      expect(html, contains('--accent-color: $expectedAccent'));
      expect(html, isNot(contains('--accent-color: ${ReportPalette.toCssHex(HudColor.darkAccentCyan)}')));
    });

    test('applies user-selected Green accent in light theme to HTML report', () {
      final greenTheme = HudTheme.lightTheme(HudColor.lightAccentGreen);
      final hud = greenTheme.extension<HudThemeExtension>()!;
      final palette = ReportPalette.fromHudTheme(hud);

      final html = buildScanReportHtml(sampleData, palette);

      final expectedAccent = ReportPalette.toCssHex(HudColor.lightAccentGreen);
      final expectedBg = ReportPalette.toCssHex(HudColor.lightBgBase);

      expect(html, contains('--accent-color: $expectedAccent'));
      expect(html, contains('--bg-base: $expectedBg'));
    });

    test('HTML-escapes special characters in root, category names, and directory paths', () {
      final xssData = ScanReportSummary(
        root: r'C:\test\<script>alert("xss")</script>&dir',
        scannedAt: DateTime.utc(2026, 10, 19, 12, 0, 0),
        exportedAt: DateTime.utc(2026, 10, 19, 12, 5, 0),
        totalBytes: 1000,
        totalFiles: 5,
        directoryNodeCount: 2,
        categories: const [
          ScanCategorySummary(name: 'a & b\'s "media" <x>', fileCount: 2, totalBytes: 500),
        ],
        topDirectories: const [
          TopDirectorySummary(
            path: r'C:\Users\test\<b>bold</b>&"quoted"',
            fileCount: 2,
            ownBytes: 500,
            recursiveBytes: 500,
          ),
        ],
      );

      final darkTheme = HudTheme.darkTheme(HudColor.darkAccentCyan);
      final hud = darkTheme.extension<HudThemeExtension>()!;
      final palette = ReportPalette.fromHudTheme(hud);

      final html = buildScanReportHtml(xssData, palette);

      expect(html, isNot(contains('<script>alert')));
      expect(html, contains('&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;&amp;dir'));
      expect(html, contains('&lt;b&gt;bold&lt;/b&gt;&amp;&quot;quoted&quot;'));
      expect(html, contains('A &amp; B&#39;S &quot;MEDIA&quot; &lt;X&gt;'));
    });

    test('renders NO DATA SVG donut when totalBytes is 0', () {
      final darkTheme = HudTheme.darkTheme(HudColor.darkAccentCyan);
      final hud = darkTheme.extension<HudThemeExtension>()!;
      final palette = ReportPalette.fromHudTheme(hud);

      final svg = buildSvgDonutChart([], 0, palette);

      expect(svg, contains('<svg width="240" height="240"'));
      expect(svg, contains('<circle cx="120" cy="120" r="85"'));
      expect(svg, contains('NO DATA'));
      expect(svg, contains('aria-label="No scan data"'));
    });

    test('SVG donut chart dash lengths sum to circumference within rounding', () {
      final darkTheme = HudTheme.darkTheme(HudColor.darkAccentCyan);
      final hud = darkTheme.extension<HudThemeExtension>()!;
      final palette = ReportPalette.fromHudTheme(hud);

      final svg = buildSvgDonutChart(sampleData.categories, sampleData.totalBytes, palette);

      expect(svg, contains('<svg width="240" height="240"'));
      expect(svg, contains('role="img"'));
      expect(svg, contains('aria-label="File type breakdown"'));
      expect(svg, contains('<title>MEDIA — 50.00 MB (50.0%)</title>'));
      expect(svg, contains('<title>CODE — 30.00 MB (30.0%)</title>'));
      expect(svg, contains('<title>DOCUMENTS — 20.00 MB (20.0%)</title>'));


      // Circumference is 2 * pi * 85 ~= 534.07
      const totalCircumference = 2.0 * 3.141592653589793 * 85.0;
      final dashMatches = RegExp(r'stroke-dasharray="([0-9.]+) [0-9.]+"').allMatches(svg);
      expect(dashMatches.length, equals(3));

      double sumDashes = 0.0;
      for (final match in dashMatches) {
        sumDashes += double.parse(match.group(1)!);
      }

      expect((sumDashes - totalCircumference).abs(), lessThan(0.5));
    });
  });
}
