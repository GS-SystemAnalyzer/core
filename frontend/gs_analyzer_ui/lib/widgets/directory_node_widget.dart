import 'package:gs_analyzer_ui/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/models/storage_node.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'dart:math';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';
import 'package:gs_analyzer_ui/utils/hud_label.dart';
import 'package:gs_analyzer_ui/widgets/age_heatmap_overlay.dart';
import '../providers/age_heatmap_provider.dart';
import '../providers/directory_provider.dart';
import '../providers/settings_provider.dart';

String formatBytes(int bytes) {
  if (bytes < 0) return "--";
  if (bytes == 0) return "0 B";
  const suffixes = ["B", "KB", "MB", "GB", "TB"];
  var i = (log(bytes) / log(1024)).floor();
  return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
}

class DirectoryNodeWidget extends ConsumerStatefulWidget {
  final StorageNode node;
  final ApiService apiService;
  final int depth;
  final Function(String, String) onNuke;
  final Function(String) onNavigate;
  final bool isTreeView;

  const DirectoryNodeWidget({
    Key? key,
    required this.node,
    required this.apiService,
    required this.onNuke,
    required this.onNavigate,
    this.depth = 0,
    this.isTreeView = false,
  }) : super(key: key);

  @override
  ConsumerState<DirectoryNodeWidget> createState() =>
      _DirectoryNodeWidgetState();
}

class _DirectoryNodeWidgetState extends ConsumerState<DirectoryNodeWidget> {
  bool _isExpanded = false;
  bool _isLoading = false;
  List<StorageNode>? _children;

  Future<void> _toggleExpand() async {
    if (!widget.node.isDirectory) return;

    setState(() {
      _isExpanded = !_isExpanded;
    });

    if (_isExpanded && _children == null) {
      setState(() {
        _isLoading = true;
      });

      try {
        final dirNotifier = ref.read(directoryProvider.notifier);
        final children = await dirNotifier.fetchChildrenForTree(
          widget.node.path,
        );

        final excluded =
            ref.read(settingsProvider).currentSettings?.scan.excludedPaths ??
            [];

        final filtered = children.where((n) {
          if (!n.isDirectory) return true;
          return !excluded.any(
            (ex) =>
                n.path.toLowerCase() == ex.toLowerCase() ||
                n.path.toLowerCase().startsWith(
                  ex.toLowerCase().endsWith('\\')
                      ? ex.toLowerCase()
                      : '${ex.toLowerCase()}\\',
                ),
          );
        }).toList();
        if (mounted) {
          setState(() {
            _children = filtered;
            _isLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        appLogger.i('Error Loading Children: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      settingsProvider.select((s) => s.savedSettings?.scan.excludedPaths),
      (previous, next) {
        if (previous != next && _children != null) {
          setState(() {
            _children = null;
            _isExpanded = false;
          });
        }
      },
    );

    final double leftPadding = widget.depth * 20.0;
    final isDir = widget.node.isDirectory;

    if (widget.isTreeView) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: isDir ? _toggleExpand : null,
            onDoubleTap: isDir
                ? () => widget.onNavigate(widget.node.path)
                : null,
            hoverColor: HudTheme.accentCyan.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: Row(
                children: [
                  SizedBox(width: leftPadding),
                  SizedBox(
                    width: 24,
                    child: isDir
                        ? AnimatedRotation(
                            turns: _isExpanded ? 0.25 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(
                              Icons.keyboard_arrow_right_outlined,
                              color: HudTheme.accentCyan,
                              size: 16,
                            ),
                          )
                        : const SizedBox(),
                  ),
                  Icon(
                    isDir
                        ? Icons.folder_outlined
                        : Icons.insert_drive_file_outlined,
                    color: isDir ? HudTheme.accentAmber : HudTheme.accentGreen,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.node.name,
                      style: HudTheme.bodyText,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            if (_isLoading)
              Padding(
                padding: EdgeInsets.only(
                  left: leftPadding + 32,
                  top: 4,
                  bottom: 4,
                ),
                child: const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1,
                    color: HudTheme.primaryBorder,
                  ),
                ),
              )
            else if (_children != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _children!
                    .where((n) => n.isDirectory)
                    .map(
                      (child) => DirectoryNodeWidget(
                        node: child,
                        apiService: widget.apiService,
                        onNuke: widget.onNuke,
                        onNavigate: widget.onNavigate,
                        depth: widget.depth + 1,
                        isTreeView: true,
                      ),
                    )
                    .toList(),
              ),
          ],
        ],
      );
    }

    // ── Heatmap overlay lookup ──
    final heatmapEnabled = ref.watch(ageHeatmapEnabledProvider);
    String? nodeBucket;
    if (heatmapEnabled) {
      final currentPath = ref.watch(directoryProvider).currentPath;
      final heatmapAsync = ref.watch(ageHeatmapProvider(currentPath));
      final normalizedNodePath = widget.node.path
          .replaceAll('\\', '/')
          .toLowerCase();
      heatmapAsync.whenData((result) {
        final match = result.lookupByPath[normalizedNodePath];
        if (match != null) nodeBucket = match.ageBucket;
      });
    }
    final Color? heatmapColor = nodeBucket != null
        ? bucketColor(nodeBucket!)
        : null;
    final bool showReviewBadge =
        nodeBucket == 'stale' && isDir && widget.node.sizeBytes > 1073741824;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: isDir ? () => widget.onNavigate(widget.node.path) : null,
          hoverColor: HudTheme.accentCyan.withValues(alpha: 0.05),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            decoration: HudTheme.listItemDecoration,
            child: Row(
              children: [
                // Left color bar (heatmap overlay)
                if (heatmapColor != null)
                  Container(
                    width: 4,
                    height: 32,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: heatmapColor,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: heatmapColor.withValues(alpha: 0.4),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                // Checkbox for select
                if (ref.watch(directoryProvider).isSelectionMode)
                  Checkbox(
                    value: ref
                        .watch(directoryProvider)
                        .selectedPath
                        .contains(widget.node.path),
                    onChanged: (bool? value) {
                      ref
                          .read(directoryProvider.notifier)
                          .toggleSelection(widget.node.path);
                    },
                    activeColor: HudTheme.accentCyan,
                    side: BorderSide(color: HudTheme.textDim),
                  ),
                // NAME Column
                Expanded(
                  flex: 4,
                  child: Row(
                    children: [
                      if (heatmapColor == null) const SizedBox(width: 32),
                      Icon(
                        isDir ? Icons.folder : Icons.insert_drive_file_outlined,
                        color: isDir
                            ? HudTheme.accentAmber
                            : HudTheme.accentGreen,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.node.name,
                          style: HudTheme.bodyText.copyWith(
                            color: HudTheme.textMain,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // ⚠ REVIEW badge for stale directories > 1 GB
                      if (showReviewBadge)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: HudTheme.accentAmber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: HudTheme.accentAmber.withValues(
                                alpha: 0.4,
                              ),
                            ),
                          ),
                          child: const Text(
                            '⚠ REVIEW',
                            style: TextStyle(
                              fontFamily: HudTheme.fontCore,
                              color: HudTheme.accentAmber,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // DATE Column
                Expanded(
                  flex: 3,
                  child: Text(
                    widget.node.lastModified.toString().split('.')[0],
                    style: HudTheme.bodyText,
                    textAlign: TextAlign.center,
                  ),
                ),
                // TYPE Column
                Expanded(
                  flex: 2,
                  child: Center(child: HudLabel(widget.node.type)),
                ),
                // SIZE Column — colored by bucket when heatmap is active
                Expanded(
                  flex: 2,
                  child: Text(
                    formatBytes(widget.node.sizeBytes),
                    style: HudTheme.statGreen.copyWith(
                      color: heatmapColor ?? HudTheme.accentCyan,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                // ACTION Column
                Expanded(
                  flex: 1,
                  child: Center(
                    child: IconButton(
                      icon: Icon(
                        isDir
                            ? Icons.folder_delete_outlined
                            : Icons.delete_forever_outlined,
                        color: HudTheme.accentRed,
                        size: 20,
                      ),
                      onPressed: () =>
                          widget.onNuke(widget.node.name, widget.node.path),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_isExpanded) ...[
          if (_isLoading)
            Padding(
              padding: EdgeInsets.only(
                left: leftPadding + 64,
                top: 8,
                bottom: 8,
              ),
              child: const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: HudTheme.primaryBorder,
                ),
              ),
            )
          else if (_children != null)
            ..._children!.map(
              (childNode) => DirectoryNodeWidget(
                node: childNode,
                apiService: widget.apiService,
                onNuke: widget.onNuke,
                onNavigate: widget.onNavigate,
                depth: widget.depth + 1,
              ),
            ),
        ],
      ],
    );
  }
}
