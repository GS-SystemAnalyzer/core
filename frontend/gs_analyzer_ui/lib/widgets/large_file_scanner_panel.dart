import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/storage_mode_provider.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';
import 'package:gs_analyzer_ui/utils/nuke_protocol.dart';
import 'package:gs_analyzer_ui/providers/large_file_provider.dart';

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
    return Container(
      color: HudTheme.bgBase,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: const BoxDecoration(
              color: HudTheme.bgPanel,
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                const Icon(Icons.radar_outlined, color: HudTheme.accentCyan),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'LARGE FILE HUNTER PROTOCOL',
                    style: TextStyle(
                      color: HudTheme.accentCyan,
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
                  icon: const Icon(Icons.close, color: HudTheme.textDim),
                  label: const Text('CLOSE TOOL', style: HudTheme.bodyText),
                ),
              ],
            ),
          ),

          // Controls
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
                          color: HudTheme.accentAmber,
                        ),
                      ),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: HudTheme.accentCyan,
                    foregroundColor: Colors.black,
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
                      backgroundColor: HudTheme.accentRed.withValues(
                        alpha: 0.2,
                      ),
                      foregroundColor: HudTheme.accentRed,
                      side: const BorderSide(color: HudTheme.accentRed),
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
                        const CircularProgressIndicator(
                          color: HudTheme.accentCyan,
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'SCANNING DEEP SECTORS...',
                          style: HudTheme.statGreen,
                        ),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: () => largeFileNotifier.abortScan(),
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
                          ),
                        ),
                      ],
                    ),
                  )
                : largeFileState.errorMessage != null
                ? Center(
                    child: Text(
                      'ERROR: ${largeFileState.errorMessage}',
                      style: HudTheme.actionRed,
                    ),
                  )
                : largeFileState.largeFiles.isEmpty
                ? Center(
                    child: Text(
                      'AWAITING LARGE FILE SCAN COMMAND....',
                      style: HudTheme.bodyText.copyWith(
                        color: HudTheme.textDim,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: largeFileState.largeFiles.length,
                    itemBuilder: (context, index) {
                      final file = largeFileState.largeFiles[index];
                      return Container(
                        decoration: HudTheme.listItemDecoration,
                        child: ListTile(
                          leading: const Icon(
                            Icons.description_outlined,
                            color: HudTheme.textDim,
                          ),
                          title: Text(
                            file.path,
                            style: HudTheme.bodyText.copyWith(
                              color: Colors.white,
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
                                  color: HudTheme.accentCyan.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: HudTheme.accentCyan.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  file.sizeFormatted,
                                  style: HudTheme.statGreen.copyWith(
                                    color: HudTheme.accentCyan,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_forever_outlined,
                                  color: HudTheme.accentRed,
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
