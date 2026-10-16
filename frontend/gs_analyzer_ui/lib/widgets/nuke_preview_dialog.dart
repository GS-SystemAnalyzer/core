import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/models/nuke_preview.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';

class NukePreviewResult {
  final bool confirmed;
  final bool useRecycleBin;
  final String planToken;

  NukePreviewResult({
    required this.confirmed,
    required this.useRecycleBin,
    required this.planToken,
  });
}

class NukePreviewDialog extends StatefulWidget {
  final ApiService apiService;
  final List<String> targetPaths;
  NukePreviewDialog({
    super.key,
    required this.targetPaths,
    ApiService? apiService,
  }) : apiService = apiService ?? ApiService();

  @override
  State<NukePreviewDialog> createState() => _NukePreviewDialogState();
}

class _NukePreviewDialogState extends State<NukePreviewDialog> {
  late final ApiService _api = widget.apiService;
  NukePreviewResponse? _preview;
  bool _isLoading = true;
  String? _error;
  bool _useRecycleBin = false;

  @override
  void initState() {
    super.initState();
    _fetchPreview();
  }

  Future<void> _fetchPreview() async {
    try {
      final data = await _api.previewNuke(widget.targetPaths);
      setState(() {
        _preview = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hud = context.hudTheme;
    return AlertDialog(
      backgroundColor: hud.panel,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: hud.accentRed, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      title: Row(
        children: [
          Icon(
            Icons.warning_amber_outlined,
            color: hud.accentRed,
            size: 28,
          ),
          SizedBox(width: 12),
          Text('CONFIRM OBLITERATION', style: hud.actionRed),
        ],
      ),
      content: SizedBox(width: 500, child: _buildContent()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            NukePreviewResult(
              confirmed: false,
              useRecycleBin: false,
              planToken: '',
            ),
          ),
          child: Text('ABORT', style: TextStyle(color: hud.textMuted)),
        ),
        if (!_isLoading && _error == null)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: hud.accentRed.withValues(alpha: 0.2),
              side: BorderSide(color: hud.accentRed),
            ),
            onPressed: () => Navigator.of(context).pop(
              NukePreviewResult(
                confirmed: true,
                useRecycleBin: _useRecycleBin,
                planToken: _preview!.planToken,
              ),
            ),
            child: Text(
              _useRecycleBin ? 'MOVE TO RECYCLE BIN' : 'EXECUTE NUKE',
              style: TextStyle(
                color: hud.accentRed,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildContent() {
    final hud = context.hudTheme;
    if (_isLoading) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'CALCULATING BLAST RADIUS...',
            style: TextStyle(color: hud.accentRed),
          ),
        ],
      );
    }

    if (_error != null) {
      return Text(
        'PREVIEW FAILED: $_error',
        style: TextStyle(color: hud.accentRed),
      );
    }

    final data = _preview!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: hud.textPaint.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStat('FILES DETECTED', data.totalFiles.toString()),
              _buildStat('DATA TO BE FREED', data.totalFormatted),
            ],
          ),
        ),

        const SizedBox(height: 16),
        Text(
          'AFFECTED SECTORS:',
          style: TextStyle(color: hud.textDim, fontSize: 12),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 150),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: data.breakdown.length,
            itemBuilder: (context, index) {
              final item = data.breakdown[index];
              return Padding(
                padding: const EdgeInsetsGeometry.only(bottom: 8.0),
                child: Text(
                  '> ${item.path} (${item.fileCount} items)',
                  style: TextStyle(
                    color: hud.textMain,
                    fontSize: 13,
                    fontFamily: HudTheme.fontCore,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: hud.textPaint.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MOVE TO RECYCLE BIN',
                style: TextStyle(
                  color: hud.textMain,
                  fontFamily: HudTheme.fontCore,
                ),
              ),
              Switch(
                value: _useRecycleBin,
                activeThumbColor: hud.accentAmber,
                onChanged: (val) => setState(() => _useRecycleBin = val),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _useRecycleBin
                ? hud.accentAmber.withValues(alpha: 0.1)
                : hud.accentRed.withValues(alpha: 0.1),
            border: Border.all(
              color: _useRecycleBin ? hud.accentAmber : hud.accentRed,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _useRecycleBin
                ? 'FILES WILL BE RECOVERABLE FROM YOUR SYSTEM RECYCLE BIN'
                : '⚠ THIS CANNOT BE UNDONE — FILES WILL BE PERMANENTLY DELETED',
            style: TextStyle(
              color: _useRecycleBin ? hud.accentAmber : hud.accentRed,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFamily: HudTheme.fontCore,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStat(String label, String value) {
    final hud = context.hudTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: hud.textDim, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: hud.accentRed,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
