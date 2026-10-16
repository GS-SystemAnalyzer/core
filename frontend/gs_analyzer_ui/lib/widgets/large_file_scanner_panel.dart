import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/storage_mode_provider.dart';
import 'package:gs_analyzer_ui/utils/nuke_protocol.dart';
import 'package:gs_analyzer_ui/providers/large_file_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';

class LargeFileScannerPanel extends ConsumerStatefulWidget {
  const LargeFileScannerPanel({super.key});

  @override
  _LargeFileScannerPanelState createState() => _LargeFileScannerPanelState();
}

class _LargeFileScannerPanelState extends ConsumerState<LargeFileScannerPanel> {
  late TextEditingController _pathController;
  late TextEditingController _topNController;

  @override
  void initState() {
    super.initState();
    _pathController = TextEditingController(text: 'C:/Users');
    _topNController = TextEditingController(text: '20');
  }

  @override
  void dispose() {
    _pathController.dispose();
    _topNController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final largeFileState = ref.watch(largeFileProvider);
    final largeFileNotifier = ref.read(largeFileProvider.notifier);
    final hud = context.hudTheme;
    return Container(
      color: hud.base,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: hud.panel,
              border: Border(bottom: BorderSide(color: hud.textMain.withValues(alpha: 0.1))),
            ),
            child: Row(
              children: [
                Icon(Icons.radar_outlined, color: hud.accentCyan),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'LARGE FILE HUNTER PROTOCOL',
                    style: TextStyle(
                      color: hud.accentCyan,
                      fontFamily: HudTheme.fontCore,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      ref.read(storageModeProvider.notifier).state =
                          StorageMode.diskAnalyzer,
                  icon: Icon(Icons.close, color: hud.textDim),
                  label: Text('CLOSE TOOL', style: hud.body),
                ),
              ],
            ),
          ),

          // Controls
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
                          color: hud.accentAmber,
                        ),
                      ),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hud.accentCyan,
                    foregroundColor: hud.textPaint,
                  ),
                  icon: const Icon(Icons.saved_search_outlined, size: 18),
                  label: const Text(
                    'INIT SCAN',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      fontFamily: HudTheme.fontCore,
                    ),
                  ),
                  onPressed: () {
                    int top = int.tryParse(_topNController.text) ?? 20;
                    largeFileNotifier.startScan(_pathController.text, top);
                  },
                ),
                if (largeFileState.largeFiles.isNotEmpty) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hud.accentRed.withValues(
                        alpha: 0.2,
                      ),
                      foregroundColor: hud.accentRed,
                      side: BorderSide(color: hud.accentRed),
                    ),
                    icon: const Icon(Icons.delete_forever_outlined, size: 18),
                    label: Text(
                      'NUKE ALL (${largeFileState.largeFiles.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        fontFamily: HudTheme.fontCore,
                      ),
                    ),
                    onPressed: () {
                      final allPaths = largeFileState.largeFiles
                          .map((f) => f.path)
                          .toList();
                      executeNukeProtocol(
                        context,
                        ref,
                        customPath: allPaths,
                        onComplete: () =>
                            largeFileNotifier.removeNukeFiles(allPaths),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
          // Result List
          Expanded(
            child: largeFileState.isLoading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          color: hud.accentCyan,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'SCANNING DEEP SECTORS...',
                          style: hud.statGreen,
                        ),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: () => largeFileNotifier.abortScan(),
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
                          ),
                        ),
                      ],
                    ),
                  )
                : largeFileState.errorMessage != null
                ? Center(
                    child: Text(
                      'ERROR: ${largeFileState.errorMessage}',
                      style: hud.actionRed,
                    ),
                  )
                : largeFileState.largeFiles.isEmpty
                ? Center(
                    child: Text(
                      'AWAITING LARGE FILE SCAN COMMAND....',
                      style: hud.body.copyWith(
                        color: hud.textDim,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: largeFileState.largeFiles.length,
                    itemBuilder: (context, index) {
                      final file = largeFileState.largeFiles[index];
                      return Container(
                        decoration: hud.listItemDecoration,
                        child: ListTile(
                          leading: Icon(
                            Icons.description_outlined,
                            color: hud.textDim,
                          ),
                          title: Text(
                            file.path,
                            style: hud.body.copyWith(
                              color: hud.textMain,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: hud.accentCyan.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: hud.accentCyan.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  file.sizeFormatted,
                                  style: hud.statGreen.copyWith(
                                    color: hud.accentCyan,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                icon: Icon(
                                  Icons.delete_forever_outlined,
                                  color: hud.accentRed,
                                ),
                                onPressed: () => executeNukeProtocol(
                                  context,
                                  ref,
                                  fileName: file.path
                                      .split(RegExp(r'[/\\]'))
                                      .last,
                                  filePath: file.path,
                                  onComplete: () => largeFileNotifier
                                      .removeNukeFiles([file.path]),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
