import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:gs_analyzer_ui/models/scan_export_options.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/providers/storage_mode_provider.dart';
import 'package:gs_analyzer_ui/providers/storage_view_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/formatters.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';

class ExportScanDialog extends ConsumerStatefulWidget {
  final String driveName;

  const ExportScanDialog({super.key, required this.driveName});

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
    setState(() {
      _isExporting = true;
      _errorMessage = null;
      _noScanCached = false;
    });

    try {
      final api = ApiService();
      final bytes = await api.exportScan(
        root: widget.driveName,
        format: _selectedFormat,
        redactPaths: _redactPaths,
      );

      final nodeCount = _getNodeCount();
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

      if (mounted) {
        Navigator.of(context).pop();

        final formattedNodes = nodeCount > 0
            ? NumberFormat.decimalPattern().format(nodeCount)
            : 'CACHED';
        final formattedSize = formatBytes(bytes.length);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: HudTheme.bgPanel,
            content: Text(
              'EXPORTED $formattedNodes NODES — $formattedSize',
              style: HudTheme.bodyText.copyWith(color: HudTheme.accentCyan),
            ),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'OPEN FOLDER',
              textColor: HudTheme.accentGreen,
              onPressed: () {
                if (savedFilePath.isNotEmpty && Platform.isWindows) {
                  Process.run('explorer.exe', ['/select,', savedFilePath]);
                }
              },
            ),
          ),
        );
      }
    } on DiffNoScanException {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _noScanCached = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _errorMessage = e.toString();
        });
      }
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
    final nodeCount = _getNodeCount();
    final estimatedSize = formatBytes(_getEstimatedBytes(nodeCount));
    final isLargeExport = nodeCount > 50000;

    return Dialog(
      backgroundColor: HudTheme.bgPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.white10),
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
                const Icon(Icons.download_rounded, color: HudTheme.accentCyan, size: 20),
                const SizedBox(width: 8),
                Text('EXPORT SCAN REPORT', style: HudTheme.headerCyan),
                const Spacer(),
                Text(
                  widget.driveName,
                  style: HudTheme.labelMuted.copyWith(color: HudTheme.accentCyan),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 16),

            if (_noScanCached) ...[
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Text(
                        'NO SCAN DATA — RUN A SCAN FIRST',
                        style: HudTheme.labelMuted,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: HudTheme.accentCyan,
                          side: const BorderSide(color: HudTheme.accentCyan),
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
              Text('SELECT FORMAT', style: HudTheme.labelMuted),
              const SizedBox(height: 8),
              ...ScanExportFormat.values.map((format) {
                final isSelected = _selectedFormat == format;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _isExporting
                        ? null
                        : () => setState(() => _selectedFormat = format),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? HudTheme.accentCyan.withValues(alpha: 0.08)
                            : HudTheme.bgBase,
                        border: Border.all(
                          color: isSelected ? HudTheme.accentCyan : Colors.white10,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: isSelected ? HudTheme.accentCyan : HudTheme.textDim,
                            size: 16,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  format.label,
                                  style: HudTheme.bodyText.copyWith(
                                    color: isSelected
                                        ? HudTheme.accentCyan
                                        : Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  format.description,
                                  style: HudTheme.labelMuted.copyWith(fontSize: 11),
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
                onTap: _isExporting
                    ? null
                    : () => setState(() => _redactPaths = !_redactPaths),
                child: Row(
                  children: [
                    Checkbox(
                      value: _redactPaths,
                      activeColor: HudTheme.accentCyan,
                      onChanged: _isExporting
                          ? null
                          : (val) => setState(() => _redactPaths = val ?? false),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'REDACT USER PATHS',
                            style: HudTheme.bodyText.copyWith(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Replaces user profile path with ~ throughout export',
                            style: HudTheme.labelMuted.copyWith(fontSize: 11),
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
                  color: HudTheme.bgBase,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      nodeCount > 0 ? 'CACHED NODES: $nodeCount' : 'CACHED SCAN',
                      style: HudTheme.labelMuted.copyWith(fontSize: 11),
                    ),
                    Text(
                      'EST. SIZE: ~$estimatedSize',
                      style: HudTheme.labelMuted.copyWith(
                        color: HudTheme.accentCyan,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              if (isLargeExport && _isExporting) ...[
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('STREAMING EXPORT...', style: HudTheme.labelMuted),
                        Text('>50,000 NODES', style: HudTheme.labelMuted),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(
                      color: HudTheme.accentCyan,
                      backgroundColor: Colors.white10,
                    ),
                  ],
                ),
              ] else if (_isExporting) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(
                  color: HudTheme.accentCyan,
                  backgroundColor: Colors.white10,
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: HudTheme.bodyText.copyWith(color: HudTheme.accentRed, fontSize: 12),
                ),
              ],
            ],

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isExporting ? null : () => Navigator.of(context).pop(),
                  child: Text('CANCEL', style: TextStyle(color: HudTheme.textDim)),
                ),
                if (!_noScanCached) ...[
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HudTheme.accentCyan,
                      side: const BorderSide(color: HudTheme.accentCyan),
                      backgroundColor: HudTheme.accentCyan.withValues(alpha: 0.1),
                    ),
                    onPressed: _isExporting ? null : _triggerExport,
                    icon: _isExporting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: HudTheme.accentCyan,
                            ),
                          )
                        : const Icon(Icons.download, size: 16),
                    label: Text(_isExporting ? 'EXPORTING...' : 'EXPORT'),
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
