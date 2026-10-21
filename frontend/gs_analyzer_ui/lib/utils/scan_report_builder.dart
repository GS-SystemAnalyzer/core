import 'dart:convert';
import 'dart:math' as math;
import 'package:gs_analyzer_ui/models/scan_report_summary.dart';
import 'package:gs_analyzer_ui/utils/formatters.dart';
import 'package:gs_analyzer_ui/utils/theme/report_palette.dart';
import 'package:intl/intl.dart';

const HtmlEscape _htmlEscape = HtmlEscape(
  HtmlEscapeMode(
    name: 'custom',
    escapeLtGt: true,
    escapeQuot: true,
    escapeApos: true,
    escapeSlash: false,
  ),
);

String _formatDateTime(DateTime dt) {
  return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt.toUtc());
}

String buildSvgDonutChart(
  List<ScanCategorySummary> categories,
  int totalBytes,
  ReportPalette palette,
) {
  if (totalBytes <= 0) {
    return '''<svg width="240" height="240" viewBox="0 0 240 240" role="img" aria-label="No scan data">
  <circle cx="120" cy="120" r="85" fill="none" stroke="${palette.borderColor}" stroke-width="30"/>
  <text x="120" y="125" text-anchor="middle" fill="${palette.textDim}" font-family="monospace" font-size="12">NO DATA</text>
</svg>''';
  }

  const cx = 120.0;
  const cy = 120.0;
  const r = 85.0;
  const strokeWidth = 30.0;
  const circumference = 2.0 * math.pi * r;

  final sb = StringBuffer();
  sb.writeln('<svg width="240" height="240" viewBox="0 0 240 240" role="img" aria-label="File type breakdown">');
  sb.writeln('  <circle cx="$cx" cy="$cy" r="$r" fill="none" stroke="${palette.bgBase}" stroke-width="$strokeWidth"/>');

  var currentOffset = 0.0;
  for (final cat in categories) {
    if (cat.totalBytes <= 0) continue;
    final fraction = cat.totalBytes / totalBytes;
    final dashLength = fraction * circumference;
    final col = palette.categoryColors[cat.name.toLowerCase()] ?? palette.textDim;
    final pct = (fraction * 100).toStringAsFixed(1);
    final escapedName = _htmlEscape.convert(cat.name.toUpperCase());
    final sizeFormatted = formatBytes(cat.totalBytes);

    sb.writeln(
      '  <circle cx="$cx" cy="$cy" r="$r" fill="none" stroke="$col" stroke-width="$strokeWidth" '
      'stroke-dasharray="${dashLength.toStringAsFixed(2)} ${circumference.toStringAsFixed(2)}" '
      'stroke-dashoffset="${(-currentOffset).toStringAsFixed(2)}" '
      'transform="rotate(-90 $cx $cy)">'
      '<title>$escapedName — $sizeFormatted ($pct%)</title>'
      '</circle>',
    );

    currentOffset += dashLength;
  }

  sb.writeln('  <text x="$cx" y="${cy - 5}" text-anchor="middle" fill="${palette.accentColor}" font-family="monospace" font-size="14" font-weight="bold">TOTAL</text>');
  sb.writeln('  <text x="$cx" y="${cy + 15}" text-anchor="middle" fill="${palette.textPrimary}" font-family="monospace" font-size="11">${formatBytes(totalBytes)}</text>');
  sb.writeln('</svg>');

  return sb.toString();
}

String buildScanReportHtml(ScanReportSummary data, ReportPalette palette) {
  final displayRoot = _htmlEscape.convert(data.root);
  final scannedAtStr = _formatDateTime(data.scannedAt);
  final exportedAtStr = _formatDateTime(data.exportedAt);
  final svgChartHtml = buildSvgDonutChart(data.categories, data.totalBytes, palette);
  final totalBytesFormatted = formatBytes(data.totalBytes);
  final totalFilesFormatted = NumberFormat.decimalPattern().format(data.totalFiles);
  final nodeCountFormatted = NumberFormat.decimalPattern().format(data.directoryNodeCount);

  final categoryRows = StringBuffer();
  for (final cat in data.categories) {
    if (cat.fileCount == 0 && cat.totalBytes == 0) continue;
    final pct = data.totalBytes > 0
        ? (cat.totalBytes / data.totalBytes * 100.0).toStringAsFixed(1)
        : '0.0';
    final col = palette.categoryColors[cat.name.toLowerCase()] ?? palette.textDim;
    final nameEscaped = _htmlEscape.convert(cat.name.toUpperCase());
    final countFormatted = NumberFormat.decimalPattern().format(cat.fileCount);
    final sizeFormatted = formatBytes(cat.totalBytes);

    categoryRows.writeln('''          <tr>
            <td><span class="dot" style="background-color: $col;"></span>$nameEscaped</td>
            <td class="text-right">$countFormatted</td>
            <td class="text-right">$sizeFormatted</td>
            <td class="text-right">$pct%</td>
          </tr>''');
  }

  final dirRows = StringBuffer();
  for (final dir in data.topDirectories) {
    final pathEscaped = _htmlEscape.convert(dir.path);
    final filesFormatted = NumberFormat.decimalPattern().format(dir.fileCount);
    final ownFormatted = formatBytes(dir.ownBytes);
    final recFormatted = formatBytes(dir.recursiveBytes);

    dirRows.writeln('''      <tr>
        <td>$pathEscaped</td>
        <td class="text-right">$filesFormatted</td>
        <td class="text-right">$ownFormatted</td>
        <td class="text-right">$recFormatted</td>
      </tr>''');
  }

  return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>GS System Analyzer — Scan Report [$displayRoot]</title>
<style>
  :root {
    --bg-base: ${palette.bgBase};
    --bg-panel: ${palette.bgPanel};
    --bg-card: ${palette.bgCard};
    --accent-color: ${palette.accentColor};
    --text-primary: ${palette.textPrimary};
    --text-dim: ${palette.textDim};
    --border-color: ${palette.borderColor};
    --font-mono: 'Consolas', 'Courier New', monospace;
    --font-sans: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    background-color: var(--bg-base);
    color: var(--text-primary);
    font-family: var(--font-sans);
    padding: 24px;
    line-height: 1.5;
  }
  header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    border-bottom: 2px solid var(--border-color);
    padding-bottom: 16px;
    margin-bottom: 24px;
  }
  .title-group h1 {
    color: var(--accent-color);
    font-size: 24px;
    letter-spacing: 1.5px;
    font-family: var(--font-mono);
  }
  .title-group p {
    color: var(--text-dim);
    font-size: 13px;
    margin-top: 4px;
  }
  .badge {
    background-color: var(--bg-card);
    border: 1px solid var(--accent-color);
    color: var(--accent-color);
    padding: 6px 12px;
    border-radius: 4px;
    font-family: var(--font-mono);
    font-size: 12px;
    font-weight: bold;
  }
  .grid-summary {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 16px;
    margin-bottom: 24px;
  }
  .card {
    background-color: var(--bg-panel);
    border: 1px solid var(--border-color);
    border-radius: 6px;
    padding: 16px;
  }
  .card-label {
    color: var(--text-dim);
    font-size: 11px;
    letter-spacing: 1px;
    text-transform: uppercase;
    font-family: var(--font-mono);
  }
  .card-value {
    color: var(--accent-color);
    font-size: 22px;
    font-weight: bold;
    font-family: var(--font-mono);
    margin-top: 6px;
  }
  .section-title {
    color: var(--text-primary);
    font-size: 16px;
    letter-spacing: 1px;
    font-family: var(--font-mono);
    margin-bottom: 12px;
    border-left: 3px solid var(--accent-color);
    padding-left: 8px;
  }
  .chart-layout {
    display: flex;
    flex-wrap: wrap;
    gap: 24px;
    align-items: center;
    margin-bottom: 24px;
  }
  .chart-container {
    flex: 1;
    min-width: 280px;
    max-width: 380px;
    display: flex;
    justify-content: center;
  }
  .chart-legend {
    flex: 2;
    min-width: 320px;
  }
  table {
    width: 100%;
    border-collapse: collapse;
    font-size: 13px;
    font-family: var(--font-mono);
  }
  th {
    background-color: var(--bg-card);
    color: var(--accent-color);
    text-align: left;
    padding: 10px;
    border-bottom: 1px solid var(--border-color);
  }
  td {
    padding: 8px 10px;
    border-bottom: 1px solid var(--border-color);
  }
  .text-right { text-align: right; }
  .dot {
    display: inline-block;
    width: 10px;
    height: 10px;
    border-radius: 50%;
    margin-right: 8px;
  }
  footer {
    margin-top: 32px;
    padding-top: 16px;
    border-top: 1px solid var(--border-color);
    color: var(--text-dim);
    font-size: 11px;
    text-align: center;
    font-family: var(--font-mono);
  }
</style>
</head>
<body>
<header>
  <div class="title-group">
    <h1>SCAN_REPORT // $displayRoot</h1>
    <p>GS System Analyzer v2.0 • Scanned: $scannedAtStr UTC • Exported: $exportedAtStr UTC</p>
  </div>
  <div class="badge">CYBER-HUD OFFLINE REPORT</div>
</header>

<div class="grid-summary">
  <div class="card">
    <div class="card-label">ROOT TARGET</div>
    <div class="card-value">$displayRoot</div>
  </div>
  <div class="card">
    <div class="card-label">TOTAL SIZE</div>
    <div class="card-value">$totalBytesFormatted</div>
  </div>
  <div class="card">
    <div class="card-label">TOTAL FILES</div>
    <div class="card-value">$totalFilesFormatted</div>
  </div>
  <div class="card">
    <div class="card-label">DIRECTORY NODES</div>
    <div class="card-value">$nodeCountFormatted</div>
  </div>
</div>

<div class="card" style="margin-bottom: 24px;">
  <div class="section-title">FILE TYPE ANALYTICS</div>
  <div class="chart-layout">
    <div class="chart-container">
      $svgChartHtml
    </div>
    <div class="chart-legend">
      <table>
        <thead>
          <tr>
            <th>CATEGORY</th>
            <th class="text-right">FILES</th>
            <th class="text-right">SIZE</th>
            <th class="text-right">% TOTAL</th>
          </tr>
        </thead>
        <tbody>
$categoryRows        </tbody>
      </table>
    </div>
  </div>
</div>

<div class="card">
  <div class="section-title">TOP DIRECTORIES</div>
  <table>
    <thead>
      <tr>
        <th>PATH</th>
        <th class="text-right">FILES</th>
        <th class="text-right">OWN SIZE</th>
        <th class="text-right">RECURSIVE SIZE</th>
      </tr>
    </thead>
    <tbody>
$dirRows    </tbody>
  </table>
</div>

<footer>
  GS System Analyzer • Non-intrusive local telemetry &amp; disk diagnostics • Report generated fully offline with zero network egress.
</footer>
</body>
</html>
''';
}
