import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/models/storage_node.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/providers/drive_stats_provider.dart';

final rootTreeProvider = Provider<AsyncValue<List<StorageNode>>>((ref) {
  final currentDrive = ref.watch(currentDriveProvider);
  final dirState = ref.watch(directoryProvider);

  if (dirState.errorMessage != null && dirState.displayNodes.isEmpty) {
    return AsyncValue.error(dirState.errorMessage!, StackTrace.current);
  }

  final activeRoot = currentDrive?.name.replaceAll('\\', '/') ?? 'C:/';
  String safeRoot = activeRoot;
  if (!safeRoot.endsWith('/')) {
    safeRoot = '$safeRoot/';
  }

  String current = dirState.currentPath.replaceAll('\\', '/');
  if (!current.endsWith('/')) {
    current = '$current/';
  }

  // 1. If currently browsing the root directory, stream directly from active directoryProvider
  if (current.toLowerCase() == safeRoot.toLowerCase()) {
    final rootDirs = dirState.displayNodes.where((n) => n.isDirectory).toList();
    return AsyncValue.data(rootDirs);
  }

  // 2. If navigated into a subfolder, retrieve cached root directory items
  final cached = ref.read(directoryProvider.notifier).getCachedNodes(activeRoot) ??
      ref.read(directoryProvider.notifier).getCachedNodes(safeRoot);
  if (cached != null && cached.isNotEmpty) {
    return AsyncValue.data(cached.where((n) => n.isDirectory).toList());
  }

  return const AsyncValue.data(<StorageNode>[]);
});
