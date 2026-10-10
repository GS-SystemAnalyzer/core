import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';

class DirectorySearchWidget extends ConsumerStatefulWidget {
  const DirectorySearchWidget({super.key});

  @override
  ConsumerState<DirectorySearchWidget> createState() =>
      _DirectorySearchWidget();
}

class _DirectorySearchWidget extends ConsumerState<DirectorySearchWidget> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dirState = ref.watch(directoryProvider);
    final dirNotifier = ref.read(directoryProvider.notifier);
    final hud = context.hudTheme;

    return TextField(
      controller: _searchController,
      style: hud.body.copyWith(color: hud.accentCyan),
      decoration: InputDecoration(
        prefixIcon: Icon(Icons.search_outlined, color: hud.textDim),
        suffixIcon: dirState.searchQuery.isNotEmpty
            ? IconButton(
                icon: Icon(
                  Icons.clear_outlined,
                  color: hud.accentRed,
                ),
                onPressed: () {
                  _searchController.clear();
                  dirNotifier.updateSearchQuery('');
                },
              )
            : null,
        hintText: 'QUERY DIRECTORY....',
        hintStyle: hud.label,
        filled: true,
        fillColor: hud.panel,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (value) {
        dirNotifier.updateSearchQuery(value);
      },
    );
  }
}
