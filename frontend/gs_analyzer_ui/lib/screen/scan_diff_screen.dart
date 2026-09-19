import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/models/scan_diff.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/providers/drive_stats_provider.dart';
import 'package:gs_analyzer_ui/providers/scan_diff_provider.dart';
import 'package:gs_analyzer_ui/providers/storage_view_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';

/// Signed byte formatter: "+4.8 GB", "-512 MB", "0 B".
String _formatSignedBytes(int bytes) {
  if (bytes == 0) return '0 B';
  final sign = bytes > 0 ? '+' : '-';
  return '$sign${_formatBytes(bytes.abs())}';
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  final i = (log(bytes) / log(1024)).floor().clamp(0, suffixes.length - 1);
  final val = bytes / pow(1024, i);
  return '${val < 10 && i > 0 ? val.toStringAsFixed(2) : val.toStringAsFixed(0)} ${suffixes[i]}';
}

/// Dedicated SCAN_DIFF screen — shows what changed on the active drive since the
/// previous scan of the same root. Scoped to [currentDriveProvider]; switching
/// drives shows that drive's diff. Never hardcodes a path.
class ScanDiffScreen extends ConsumerWidget {
  const ScanDiffScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drive = ref.watch(currentDriveProvider);

    return Scaffold(
      backgroundColor: HudTheme.bgPanel,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('WHAT_CHANGED', style: HudTheme.headerCyan),
        iconTheme: const IconThemeData(color: HudTheme.accentCyan),
        actions: [
          if (drive != null)
            IconButton(
              tooltip: 'CLEAR BASELINE',
              icon: const Icon(Icons.restart_alt, color: HudTheme.textDim),
              onPressed: () => _confirmClearBaseline(context, ref, drive.name),
            ),
        ],
      ),
      body: drive == null
          ? const _CenteredMessage(
              text: 'NO DRIVE SELECTED',
              color: HudTheme.textDim,
            )
          : ref
                .watch(scanDiffProvider(drive.name))
                .when(
                  loading: () => const _LoadingState(),
                  error: (e, _) => _ErrorState(error: e),
                  data: (diff) => _DiffBody(diff: diff),
                ),
    );
  }

  Future<void> _confirmClearBaseline(
    BuildContext context,
    WidgetRef ref,
    String root,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HudTheme.bgPanel,
        title: Text('CLEAR BASELINE', style: HudTheme.headerCyan),
        content: Text(
          'Forget the stored baseline for $root? The next scan will report '
          'a fresh baseline with no changes.',
          style: HudTheme.bodyText,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: HudTheme.textDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('CLEAR', style: HudTheme.actionRed),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(apiServiceProvider).clearDiffBaseline(root);
      ref.invalidate(scanDiffProvider(root));
    } catch (_) {
      // Best effort — the provider will surface any read error on refresh.
    }
  }
}

class _DiffBody extends StatelessWidget {
  final ScanDiff diff;

  const _DiffBody({required this.diff});

  @override
  Widget build(BuildContext context) {
    if (!diff.hasBaseline) {
      return const _CenteredMessage(
        text: 'FIRST SCAN — BASELINE SAVED.\nNEXT SCAN WILL SHOW CHANGES.',
        color: HudTheme.textDim,
      );
    }

    if (diff.isEmpty) {
      return const _CenteredMessage(
        text: 'NO CHANGES SINCE LAST SCAN',
        color: HudTheme.accentGreen,
      );
    }

    return Column(
      children: [
        _SummaryStrip(diff: diff),
        const Divider(color: Colors.white10, height: 1),
        Expanded(
          child: ListView(
            children: [
              _DiffSection(
                title: 'ADDED',
                color: HudTheme.accentGreen,
                entries: diff.added,
              ),
              _DiffSection(
                title: 'REMOVED',
                color: HudTheme.accentRed,
                entries: diff.removed,
              ),
              _DiffSection(
                title: 'GROWN',
                color: HudTheme.accentAmber,
                entries: diff.grown,
              ),
              _DiffSection(
                title: 'SHRUNK',
                color: HudTheme.accentCyan,
                entries: diff.shrunk,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  final ScanDiff diff;

  const _SummaryStrip({required this.diff});

  @override
  Widget build(BuildContext context) {
    final s = diff.summary;
    // NET: red when the drive consumed more space (>0), green when freed (<0).
    final netColor = s.netDeltaBytes > 0
        ? HudTheme.accentRed
        : (s.netDeltaBytes < 0 ? HudTheme.accentGreen : HudTheme.textDim);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: HudTheme.bgBase,
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _chip('+${s.addedCount} ADDED', HudTheme.accentGreen),
          _chip('-${s.removedCount} REMOVED', HudTheme.accentRed),
          _chip('▲${s.grownCount} GROWN', HudTheme.accentAmber),
          _chip('▼${s.shrunkCount} SHRUNK', HudTheme.accentCyan),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: netColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: netColor),
            ),
            child: Text(
              'NET: ${_formatSignedBytes(s.netDeltaBytes)}',
              style: HudTheme.bodyText.copyWith(
                color: netColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: HudTheme.bodyText.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _DiffSection extends StatelessWidget {
  final String title;
  final Color color;
  final List<ScanDiffEntry> entries;

  const _DiffSection({
    required this.title,
    required this.color,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(
          '$title (${entries.length})',
          style: HudTheme.bodyText.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        childrenPadding: EdgeInsets.zero,
        // ListView.builder keeps large change sets overflow-safe (never a DataTable).
        children: [
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: entries.length,
            itemBuilder: (context, i) =>
                _DiffRow(entry: entries[i], color: color),
          ),
        ],
      ),
    );
  }
}

class _DiffRow extends ConsumerWidget {
  final ScanDiffEntry entry;
  final Color color;

  const _DiffRow({required this.entry, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Folder icon → amber, file icon → green, per the project icon convention.
    final icon = entry.isDirectory ? Icons.folder : Icons.insert_drive_file;
    final iconColor = entry.isDirectory
        ? HudTheme.accentAmber
        : HudTheme.accentGreen;

    return InkWell(
      onTap: () => _jumpToExplorer(context, ref),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HudTheme.bodyText,
                  ),
                  Text(
                    entry.childCount != null
                        ? '${entry.parentPath}  ·  ${entry.childCount} items'
                        : entry.parentPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HudTheme.bodyText.copyWith(
                      color: HudTheme.textDim,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _formatSignedBytes(entry.deltaBytes),
              style: HudTheme.bodyText.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Jump into the directory explorer at this entry's parent (reuses the
  /// FIND IN EXPLORER navigation pattern).
  void _jumpToExplorer(BuildContext context, WidgetRef ref) {
    ref.read(directoryProvider.notifier).scanDirectory(entry.parentPath);
    ref.read(storageViewProvider.notifier).state = StorageView.analyzer;
    Navigator.of(context).pop();
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(color: HudTheme.accentCyan),
        const SizedBox(height: 16),
        Text('ANALYZING CHANGES...', style: HudTheme.labelMuted),
      ],
    );
  }
}

class _ErrorState extends ConsumerWidget {
  final Object error;

  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 409 (no scan cached) surfaces as DiffNoScanException → prompt to scan.
    if (error is DiffNoScanException) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('NO SCAN DATA — RUN A SCAN FIRST', style: HudTheme.labelMuted),
          const SizedBox(height: 16),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: HudTheme.accentCyan,
              side: const BorderSide(color: HudTheme.accentCyan),
            ),
            onPressed: () {
              // Return to Storage so the user can launch a scan.
              ref.read(storageViewProvider.notifier).state =
                  StorageView.drivePicker;
              Navigator.of(context).maybePop();
            },
            child: const Text('SCAN NOW'),
          ),
        ],
      );
    }

    return _CenteredMessage(
      text: 'DIFF UNAVAILABLE\n$error',
      color: HudTheme.accentRed,
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  final String text;
  final Color color;

  const _CenteredMessage({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: HudTheme.bodyText.copyWith(color: color),
        ),
      ),
    );
  }
}
