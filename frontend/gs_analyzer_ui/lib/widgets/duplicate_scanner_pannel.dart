import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/duplicate_provider.dart';
import 'package:gs_analyzer_ui/providers/storage_mode_provider.dart';
import 'package:gs_analyzer_ui/utils/nuke_protocol.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';

class DuplicateScannerPanel extends ConsumerStatefulWidget {
  const DuplicateScannerPanel({super.key});

  @override
  _DuplicateScannerPanelState createState() => _DuplicateScannerPanelState();
}

class _DuplicateScannerPanelState extends ConsumerState<DuplicateScannerPanel> {
  late TextEditingController _pathController;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: 'C:/Users');
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dupState = ref.watch(duplicateProvider);
    final dupNotifier = ref.read(duplicateProvider.notifier);
    final hud = context.hudTheme;

    return Container(
      color: hud.base,
      child: Column(
        children: [
          // Action Screen Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: hud.panel,
              border: Border(bottom: BorderSide(color: hud.textMain.withValues(alpha: 0.1))),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.difference_outlined,
                  color: hud.accentAmber,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'DUPLICATE HUNTER PROTOCOL',
                    style: TextStyle(
                      color: hud.accentAmber,
                      fontFamily: HudTheme.fontCore,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // The back button to close the action layer
                TextButton.icon(
                  onPressed: () {
                    ref.read(storageModeProvider.notifier).state =
                        StorageMode.diskAnalyzer;
                  },
                  icon: Icon(Icons.close, color: hud.textDim),
                  label: Text('CLOSE TOOL', style: hud.body),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: hud.textMain.withValues(alpha: 0.1))),
            ),
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _pathController,
                    style: hud.body.copyWith(
                      color: hud.accentCyan,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      prefixIcon: Icon(
                        Icons.folder_outlined,
                        color: hud.textDim,
                        size: 20,
                      ),
                      labelText: 'TARGET SECTOR',
                      labelStyle: hud.label,
                      isDense: true,
                      filled: true,
                      fillColor: hud.textPaint.withValues(alpha: 0.26),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: hud.textMain.withValues(alpha: 0.1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(color: hud.textMain.withValues(alpha: 0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide(
                          color: hud.accentCyan,
                        ),
                      ),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hud.accentAmber,
                    foregroundColor: hud.textPaint,
                  ),
                  icon: const Icon(Icons.radar_outlined, size: 18),
                  label: const Text(
                    'INIT SCAN',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFamily: HudTheme.fontCore,
                      fontSize: 12,
                    ),
                  ),
                  onPressed: () => dupNotifier.startScan(_pathController.text),
                ),
                if (dupState.duplicateGroups.isNotEmpty) ...[
                  Text(
                    'WASTED: ${dupState.totalWastedSpaceFormatted}',
                    style: hud.actionRed.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: hud.accentCyan,
                      side: BorderSide(color: hud.accentCyan),
                    ),
                    icon: const Icon(Icons.auto_fix_high, size: 18),
                    label: const Text(
                      'SMART SELECT',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: HudTheme.fontCore,
                        fontSize: 12,
                      ),
                    ),
                    onPressed: () => dupNotifier.smartSelectAll(),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hud.accentRed.withValues(
                        alpha: 0.2,
                      ),
                      foregroundColor: hud.accentRed,
                      side: BorderSide(color: hud.accentRed),
                    ),
                    icon: const Icon(Icons.delete_forever, size: 18),
                    label: Text(
                      'NUKE (${dupState.pathsToNuke.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: HudTheme.fontCore,
                        fontSize: 12,
                      ),
                    ),
                    onPressed: dupState.pathsToNuke.isEmpty
                        ? null
                        : () {
                            executeNukeProtocol(
                              context,
                              ref,
                              customPath: dupState.pathsToNuke,
                              onComplete: () => dupNotifier.clearNukedFiles(),
                            );
                          },
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: dupState.isLoading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: hud.accentAmber,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'HUNTING DUPLICATE SECTORS...',
                          style: TextStyle(
                            color: hud.accentAmber,
                            fontFamily: HudTheme.fontCore,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: () => dupNotifier.abortScan(),
                          icon: Icon(
                            Icons.dangerous,
                            color: hud.accentRed,
                          ),
                          label: Text(
                            'ABORT SCAN',
                            style: hud.actionRed,
                          ),
                          style: TextButton.styleFrom(
                            backgroundColor: hud.accentRed.withValues(
                              alpha: 0.1,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            side: BorderSide(
                              color: hud.accentRed,
                              width: 1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : dupState.duplicateGroups.isEmpty
                ? Center(
                    child: Text(
                      'AWAITING BACKEND SCAN COMMAND...',
                      style: hud.body.copyWith(
                        color: hud.textDim,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: dupState.duplicateGroups.length,
                    itemBuilder: (context, index) {
                      final group = dupState.duplicateGroups[index];
                      return ExpansionTile(
                        collapsedIconColor: hud.accentAmber,
                        iconColor: hud.accentAmber,
                        title: Text(
                          'GROUP HASH: ${group.fileHash.substring(0, 12)}...',
                          style: TextStyle(
                            color: hud.accentAmber,
                            fontFamily: HudTheme.fontCore,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          'Wasted Space: ${(group.wastedSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB',
                          style: TextStyle(
                            color: hud.accentRed,
                            fontFamily: HudTheme.fontCore,
                          ),
                        ),
                        children: group.files.map((file) {
                          return CheckboxListTile(
                            activeColor: hud.accentRed,
                            checkColor: hud.textPaint,
                            title: Text(
                              file.path,
                              style: TextStyle(
                                color: hud.textMain.withValues(alpha: 0.70),
                                fontSize: 12,
                              ),
                            ),
                            subtitle: Text(
                              'Modified: ${file.lastModified.toString().split('.')[0]}',
                              style: TextStyle(
                                color: hud.textMain.withValues(alpha: 0.38),
                                fontSize: 11,
                              ),
                            ),
                            value: file.isSelected,
                            onChanged: (bool? value) {
                              dupNotifier.toggleFileSelection(
                                group.fileHash,
                                file.path,
                              );
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
