import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/root_tree_provider.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';
import 'package:gs_analyzer_ui/widgets/directory_node_widget.dart';
import 'package:gs_analyzer_ui/utils/hud_label.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';

class SideBarTreeWidget extends ConsumerWidget {
  final Function(String, String) onNuke;

  const SideBarTreeWidget({super.key, required this.onNuke});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rootNodeAsync = ref.watch(rootTreeProvider);
    final dirNotifier = ref.read(directoryProvider.notifier);
    final isExpanded = ref.watch(treeExpandedProvider);
    final excludedPaths = ref.watch(
      settingsProvider.select(
        (s) => s.savedSettings?.scan.excludedPaths ?? <String>[],
      ),
    );
    final hud = context.HudTheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: isExpanded ? 300.0 : 0.0,
      decoration: BoxDecoration(
        color: hud.base,
        border: Border(
          right: BorderSide(
            color: isExpanded ? hud.textMain.withValues(alpha: 0.1) : Colors.transparent,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: SizedBox(
          width: 300.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: hud.panel,
                  border: Border(bottom: BorderSide(color: hud.textMain.withValues(alpha: 0.1))),
                ),
                child: const HudLabel(
                  'DATA TREE',
                  overflow: TextOverflow.visible,
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: rootNodeAsync.when(
                    loading: () => Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: CircularProgressIndicator(
                          color: hud.border,
                        ),
                      ),
                    ),
                    error: (err, stack) => Center(
                      child: Text(
                        'FAILED TO LOAD TREE',
                        style: TextStyle(
                          color: hud.accentRed,
                          fontFamily: HudTheme.fontCore,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    data: (nodes) {
                      final visibleNodes = nodes.where((n) {
                        if (!n.isDirectory) return true;
                        final nodePath = n.path
                            .replaceAll('\\', '/')
                            .toLowerCase();
                        return !excludedPaths.any(
                          (ex) =>
                              nodePath ==
                              ex.replaceAll('\\', '/').toLowerCase(),
                        );
                      }).toList();
                      return Column(
                        children: visibleNodes
                            .map(
                              (node) => DirectoryNodeWidget(
                                node: node,
                                apiService: ApiService(),
                                onNuke: onNuke,
                                onNavigate: dirNotifier.scanDirectory,
                                depth: 0,
                                isTreeView: true,
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
