import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/models/file_type_model.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';

class FileTypeNoScanException implements Exception {
  const FileTypeNoScanException();
}

final selectedCategoryProvider = StateProvider<String?>((ref) => null);

/// Counter used to trigger manual cache invalidations with `refresh: true`.
final fileTypesRefreshTriggerProvider = StateProvider.family<int, String>(
  (ref, root) => 0,
);

/// Fetches file type breakdown for [root].
/// Throws [FileTypeNoScanException] when no Directory scan has run yet.
final fileTypesProvider = FutureProvider.autoDispose
    .family<FileTypeResult, String>((ref, root) async {
      final refreshCount = ref.watch(fileTypesRefreshTriggerProvider(root));
      return ApiService().getFileTypes(root, refresh: refreshCount > 0);
    });

final scanRootProvider = StateProvider.family<String, String>(
  (ref, driveName) => driveName,
);
