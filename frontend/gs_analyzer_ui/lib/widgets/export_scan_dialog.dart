import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_saver/file_saver.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';
import 'package:intl/intl.dart';
import 'package:gs_analyzer_ui/models/scan_export_options.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/providers/minimized_ops_provider.dart';
import 'package:gs_analyzer_ui/providers/storage_mode_provider.dart';
import 'package:gs_analyzer_ui/providers/storage_view_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/formatters.dart';
import 'package:gs_analyzer_ui/utils/globals.dart';
import 'package:gs_analyzer_ui/utils/scan_report_builder.dart';
import 'package:gs_analyzer_ui/utils/theme/report_palette.dart';


class ExportScanDialog extends ConsumerStatefulWidget {
  final String driveName;
  final ApiService? apiService;

  const ExportScanDialog({
    super.key,
    required this.driveName,
    this.apiService,
  });

  @override
  ConsumerState<ExportScanDialog> createState() => _ExportScanDialogState();
}

class _ExportScanDialogState extends ConsumerState<ExportScanDialog> {
  ScanExportFormat _selectedFormat = ScanExportFormat.json;
  bool _redactPaths = false;
  bool _isExporting = false;
  bool _noScanCached = false;
  String? _errorMessage;

  int _getNodeCount() {
    final dirState = ref.read(directoryProvider);
    if (dirState.allNodes.isNotEmpty) {
      return dirState.allNodes.length;
    }
    return 0;
  }

  int _getEstimatedBytes(int nodeCount) {
    if (nodeCount <= 0) return 4096;
    switch (_selectedFormat) {
      case ScanExportFormat.json:
        return nodeCount * 280;
      case ScanExportFormat.csv:
        return nodeCount * 120;
      case ScanExportFormat.html:
        return nodeCount * 360;
    }
  }

  Future<void> _triggerExport() async {
    // Capture provider controllers and theme up front: the export future outlives this
    // dialog if the user minimises it, so we must not touch `ref`/`context`
    // after disposal. StateControllers are owned by the container and stay valid.
    final hud = context.hudTheme;
    final activeCtl = ref.read(exportActiveProvider.notifier);
    final minCtl = ref.read(exportMinimizedProvider.notifier);
    ref.read(exportDriveProvider.notifier).state = widget.driveName;
    final nodeCount = _getNodeCount();

    activeCtl.state = true;
    setState(() {
      _isExporting = true;
      _errorMessage = null;
      _noScanCached = false;
    });

    try {
      final api = widget.apiService ?? ApiService();
      final Uint8List bytes;
      if (_selectedFormat == ScanExportFormat.html) {
        final summary = await api.getScanReportSummary(
          root: widget.driveName,
          redactPaths: _redactPaths,
        );
        final palette = ReportPalette.fromHudTheme(hud);
        final html = buildScanReportHtml(summary, palette);
        bytes = Uint8List.fromList(utf8.encode(html));
      } else {
        bytes = await api.exportScan(
          root: widget.driveName,
          format: _selectedFormat,
          redactPaths: _redactPaths,
        );
      }


      final cleanDrive = widget.driveName.replaceAll(RegExp(r'[:\\/]+'), '');
      final timestamp = DateFormat('yyyy-MM-ddTHHmmss').format(DateTime.now());
      final filename = 'gs-scan-$cleanDrive-$timestamp';
      final ext = _selectedFormat.fileExtension;

      String savedFilePath = '';
      try {
        savedFilePath = await FileSaver.instance.saveFile(
          name: filename,
          bytes: bytes,
          fileExtension: ext,
          mimeType: _selectedFormat == ScanExportFormat.json
              ? MimeType.json
              : _selectedFormat == ScanExportFormat.csv
                  ? MimeType.csv
                  : MimeType.other,
          customMimeType: _selectedFormat == ScanExportFormat.html ? 'text/html' : null,
        );
      } catch (saveEx) {
        // Fallback saving directly to Downloads or Desktop
        final userProfile = Platform.environment['USERPROFILE'];
        var targetDir = Directory('$userProfile\\Downloads');
        if (!await targetDir.exists()) {
          targetDir = Directory('$userProfile\\Desktop');
        }
        final file = File('${targetDir.path}\\$filename.$ext');
        await file.writeAsBytes(bytes);
        savedFilePath = file.path;
      }

      // Close the dialog if it is still open (i.e. not minimised).
      if (mounted) Navigator.of(context).pop();

      final formattedNodes = nodeCount > 0
          ? NumberFormat.decimalPattern().format(nodeCount)
          : 'CACHED';
      final formattedSize = formatBytes(bytes.length);

      // Global messenger so the result shows even when minimised.
      snackbarKey.currentState?.showSnackBar(
        SnackBar(
          backgroundColor: hud.panel,
          content: Text(
            'EXPORTED $formattedNodes NODES — $formattedSize',
            style: hud.body.copyWith(color: hud.accentCyan),
          ),
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'OPEN FOLDER',
            textColor: hud.accentGreen,
            onPressed: () {
              if (savedFilePath.isNotEmpty && Platform.isWindows) {
                Process.run('explorer.exe', ['/select,', savedFilePath]);
              }
            },
          ),
        ),
      );
    } on DiffNoScanException {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _noScanCached = true;
        });
      } else {
        snackbarKey.currentState?.showSnackBar(
          const SnackBar(content: Text('NO SCAN DATA — RUN A SCAN FIRST')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _errorMessage = e.toString();
        });  
      } else {
        snackbarKey.currentState?.showSnackBar( 
          SnackBar(
            backgroundColor: hud.panel,
            content: Text(
              'EXPORT FAILED: $e',
              style: hud.body.copyWith(color: hud.accentRed),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
      activeCtl.state = false;
      minCtl.state = false;
    }

  }

  void _triggerScanNow() {
    Navigator.of(context).pop();
    ref.read(storageModeProvider.notifier).state = StorageMode.diskAnalyzer;
    ref.read(directoryProvider.notifier).scanDirectory(widget.driveName, forceRefresh: true);
    ref.read(storageViewProvider.notifier).state = StorageView.analyzer;
  }

  @override
  Widget build(BuildContext context) {
    final hud = context.hudTheme;
    // A re-shown dialog (restored from the pill) observes the in-flight export
    // via the provider and self-closes when it finishes.
    ref.listen<bool>(exportActiveProvider, (prev, next) {
      if (!next &&
          mounted &&
          !_isExporting &&
          !ref.read(exportMinimizedProvider) &&
          Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });

    final busy = _isExporting || ref.watch(exportActiveProvider);
    final nodeCount = _getNodeCount();
    final estimatedSize = formatBytes(_getEstimatedBytes(nodeCount));
    final isLargeExport = nodeCount > 50000;

    return Dialog(
      backgroundColor: hud.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: hud.textMain.withValues(alpha: 0.10)),
      ),
      child: Container(
        width: 480,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              children: [
                Icon(Icons.download_rounded, color: hud.accentCyan, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'EXPORT SCAN REPORT',
                    style: hud.header,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.driveName,
                  style: hud.label.copyWith(color: hud.accentCyan),
                ),
                if (busy)
                  IconButton(
                    icon: Icon(Icons.remove, color: hud.accentCyan),
                    tooltip: 'Minimize',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      ref.read(exportMinimizedProvider.notifier).state = true;
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: hud.textMain.withValues(alpha: 0.10), height: 1),
            const SizedBox(height: 16),

            if (_noScanCached) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Text(
                        'NO SCAN DATA — RUN A SCAN FIRST',
                        style: hud.label,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: hud.accentCyan,
                          side: BorderSide(color: hud.accentCyan),
                        ),
                        onPressed: _triggerScanNow,
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: const Text('SCAN NOW'),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              Text('SELECT FORMAT', style: hud.label),
              const SizedBox(height: 8),
              ...ScanExportFormat.values.map((format) {
                final isSelected = _selectedFormat == format;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: busy
                        ? null
                        : () => setState(() => _selectedFormat = format),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? hud.accentCyan.withValues(alpha: 0.08)
                            : hud.base,
                        border: Border.all(
                          color: isSelected ? hud.accentCyan : hud.textMain.withValues(alpha: 0.10),
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: isSelected ? hud.accentCyan : hud.textDim,
                            size: 16,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  format.label,
                                  style: hud.body.copyWith(
                                    color: isSelected
                                        ? hud.accentCyan
                                        : hud.textMain,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  format.description,
                                  style: hud.label.copyWith(fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),

              // Redact Paths Checkbox
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: busy
                    ? null
                    : () => setState(() => _redactPaths = !_redactPaths),
                child: Row(
                  children: [
                    Checkbox(
                      value: _redactPaths,
                      activeColor: hud.accentCyan,
                      onChanged: busy
                          ? null
                          : (val) => setState(() => _redactPaths = val ?? false),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'REDACT USER PATHS',
                            style: hud.body.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Replaces user profile path with ~ throughout export',
                            style: hud.label.copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Estimated size and node count info
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: hud.base,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: hud.textMain.withValues(alpha: 0.10)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      nodeCount > 0 ? 'CACHED NODES: $nodeCount' : 'CACHED SCAN',
                      style: hud.label.copyWith(fontSize: 11),
                    ),
                    Text(
                      'EST. SIZE: ~$estimatedSize',
                      style: hud.label.copyWith(
                        color: hud.accentCyan,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              if (isLargeExport && busy) ...[
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('STREAMING EXPORT...', style: hud.label),
                        Text('>50,000 NODES', style: hud.label),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      color: hud.accentCyan,
                      backgroundColor: hud.textMain.withValues(alpha: 0.10),
                    ),
                  ],
                ),
              ] else if (busy) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  color: hud.accentCyan,
                  backgroundColor: hud.textMain.withValues(alpha: 0.10),
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: hud.body.copyWith(color: hud.accentRed, fontSize: 12),
                ),
              ],
            ],

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.of(context).pop(),
                  child: Text('CANCEL', style: TextStyle(color: hud.textDim)),
                ),
                if (!_noScanCached) ...[
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: hud.accentCyan,
                      side: BorderSide(color: hud.accentCyan),
                      backgroundColor: hud.accentCyan.withValues(alpha: 0.1),
                    ),
                    onPressed: busy ? null : _triggerExport,
                    icon: busy
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: hud.accentCyan,
                            ),
                          )
                        : const Icon(Icons.download, size: 16),
                    label: Text(busy ? 'EXPORTING...' : 'EXPORT'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
  );
  }
}
