import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/duplicate_provider.dart';
import 'package:gs_analyzer_ui/providers/storage_mode_provider.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';
import 'package:gs_analyzer_ui/utils/nuke_protocol.dart';

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

    return Container(
      color: HudTheme.bgBase,
      child: Column(
        children: [
          // Action Screen Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: const BoxDecoration(
              color: HudTheme.bgPanel,
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.difference_outlined,
                  color: HudTheme.accentAmber,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'DUPLICATE HUNTER PROTOCOL',
                    style: TextStyle(
                      color: HudTheme.accentAmber,
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
                  icon: const Icon(Icons.close, color: HudTheme.textDim),
                  label: Text('CLOSE TOOL', style: HudTheme.bodyText),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
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
                    style: HudTheme.bodyText.copyWith(
                      color: HudTheme.accentCyan,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(
                        Icons.folder_outlined,
                        color: HudTheme.textDim,
                        size: 20,
                      ),
                      labelText: 'TARGET SECTOR',
                      labelStyle: HudTheme.labelMuted,
                      isDense: true,
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Colors.white10),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(color: Colors.white10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(
                          color: HudTheme.accentCyan,
                        ),
                      ),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HudTheme.accentAmber,
                    foregroundColor: Colors.black,
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
                    style: HudTheme.actionRed.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HudTheme.accentCyan,
                      side: const BorderSide(color: HudTheme.accentCyan),
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
                      backgroundColor: HudTheme.accentRed.withValues(
                        alpha: 0.2,
                      ),
                      foregroundColor: HudTheme.accentRed,
                      side: const BorderSide(color: HudTheme.accentRed),
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
                        const CircularProgressIndicator(
                          color: HudTheme.accentAmber,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'HUNTING DUPLICATE SECTORS...',
                          style: TextStyle(
                            color: HudTheme.accentAmber,
                            fontFamily: HudTheme.fontCore,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: () => dupNotifier.abortScan(),
                          icon: const Icon(
                            Icons.dangerous,
                            color: HudTheme.accentRed,
                          ),
                          label: const Text(
                            'ABORT SCAN',
                            style: HudTheme.actionRed,
                          ),
                          style: TextButton.styleFrom(
                            backgroundColor: HudTheme.accentRed.withValues(
                              alpha: 0.1,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            side: const BorderSide(
                              color: HudTheme.accentRed,
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
                      style: HudTheme.bodyText.copyWith(
                        color: HudTheme.textDim,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: dupState.duplicateGroups.length,
                    itemBuilder: (context, index) {
                      final group = dupState.duplicateGroups[index];
                      return ExpansionTile(
                        collapsedIconColor: HudTheme.accentAmber,
                        iconColor: HudTheme.accentAmber,
                        title: Text(
                          'GROUP HASH: ${group.fileHash.substring(0, 12)}...',
                          style: const TextStyle(
                            color: HudTheme.accentAmber,
                            fontFamily: HudTheme.fontCore,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          'Wasted Space: ${(group.wastedSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB',
                          style: const TextStyle(
                            color: HudTheme.accentRed,
                            fontFamily: HudTheme.fontCore,
                          ),
                        ),
                        children: group.files.map((file) {
                          return CheckboxListTile(
                            activeColor: HudTheme.accentRed,
                            checkColor: Colors.black,
                            title: Text(
                              file.path,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            subtitle: Text(
                              'Modified: ${file.lastModified.toString().split('.')[0]}',
                              style: const TextStyle(
                                color: Colors.white38,
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
