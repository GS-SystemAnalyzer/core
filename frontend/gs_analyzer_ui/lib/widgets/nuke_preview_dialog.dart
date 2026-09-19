import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/models/nuke_preview.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';

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
    return AlertDialog(
      backgroundColor: HudTheme.bgPanel,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: HudTheme.accentRed, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      title: const Row(
        children: [
          Icon(
            Icons.warning_amber_outlined,
            color: HudTheme.accentRed,
            size: 28,
          ),
          SizedBox(width: 12),
          Text('CONFIRM OBLITERATION', style: HudTheme.actionRed),
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
          child: const Text('ABORT', style: TextStyle(color: Colors.white70)),
        ),
        if (!_isLoading && _error == null)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: HudTheme.accentRed.withValues(alpha: 0.2),
              side: const BorderSide(color: HudTheme.accentRed),
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
              style: const TextStyle(
                color: HudTheme.accentRed,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'CALCULATING BLAST RADIUS...',
            style: TextStyle(color: HudTheme.accentRed),
          ),
        ],
      );
    }

    if (_error != null) {
      return Text(
        'PREVIEW FAILED: $_error',
        style: const TextStyle(color: HudTheme.accentRed),
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
            color: Colors.black45,
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
        const Text(
          'AFFECTED SECTORS:',
          style: TextStyle(color: Colors.white54, fontSize: 12),
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
                  style: const TextStyle(
                    color: Colors.white,
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
            color: Colors.black45,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'MOVE TO RECYCLE BIN',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: HudTheme.fontCore,
                ),
              ),
              Switch(
                value: _useRecycleBin,
                activeColor: HudTheme.accentAmber,
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
                ? HudTheme.accentAmber.withValues(alpha: 0.1)
                : HudTheme.accentRed.withValues(alpha: 0.1),
            border: Border.all(
              color: _useRecycleBin ? HudTheme.accentAmber : HudTheme.accentRed,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _useRecycleBin
                ? 'FILES WILL BE RECOVERABLE FROM YOUR SYSTEM RECYCLE BIN'
                : '⚠ THIS CANNOT BE UNDONE — FILES WILL BE PERMANENTLY DELETED',
            style: TextStyle(
              color: _useRecycleBin ? HudTheme.accentAmber : HudTheme.accentRed,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: HudTheme.accentRed,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
