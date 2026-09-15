import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/models/extension_breakdown_model.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';

// State Providers for Filtering and Sorting
final ebSearchQueryProvider = StateProvider<String>((ref) => '');
final ebSelectedCategoriesProvider = StateProvider<Set<String>>((ref) => {});
final ebSortColumnProvider = StateProvider<String>((ref) => 'totalBytes');
final ebSortAscendingProvider = StateProvider<bool>((ref) => false);

// Refresh trigger provider
final ebRefreshTriggerProvider = StateProvider.family<int, String>(
  (ref, root) => 0,
);

// Future Provider for fetching data
final extensionBreakdownProvider =
    FutureProvider.family<ExtensionBreakdownResult, String>((ref, root) async {
      final refreshCount = ref.watch(ebRefreshTriggerProvider(root));
      return await ApiService().getExtensionBreakdown(root, refresh: refreshCount > 0);
    });

// Computed Provider for filtering and sorting
final filteredExtensionBreakdownProvider =
    Provider.family<List<ExtensionBreakdownItem>, String>((ref, root) {
      final asyncResult = ref.watch(extensionBreakdownProvider(root));

      return asyncResult.maybeWhen(
        data: (result) {
          final items = result.extensions;
          final query = ref.watch(ebSearchQueryProvider).toLowerCase();
          final selectedCategories = ref.watch(ebSelectedCategoriesProvider);
          final sortColumn = ref.watch(ebSortColumnProvider);
          final isAscending = ref.watch(ebSortAscendingProvider);

          // Filtering
          var filtered = items.where((item) {
            if (query.isNotEmpty && !item.ext.toLowerCase().contains(query)) {
              return false;
            }
            if (selectedCategories.isNotEmpty &&
                !selectedCategories.contains(item.category)) {
              return false;
            }
            return true;
          }).toList();

          // Sorting
          filtered.sort((a, b) {
            int cmp;
            switch (sortColumn) {
              case 'ext':
                cmp = a.ext.compareTo(b.ext);
                break;
              case 'category':
                cmp = a.category.compareTo(b.category);
                break;
              case 'fileCount':
                cmp = a.fileCount.compareTo(b.fileCount);
                break;
              case 'totalBytes':
                cmp = a.totalBytes.compareTo(b.totalBytes);
                break;
              case 'averageFileSizeBytes':
                cmp = a.averageFileSizeBytes.compareTo(b.averageFileSizeBytes);
                break;
              case 'percentOfDisk':
                cmp = a.percentOfDisk.compareTo(b.percentOfDisk);
                break;
              default:
                cmp = 0;
            }
            return isAscending ? cmp : -cmp;
          });

          return filtered;
        },
        orElse: () => [],
      );
    });
