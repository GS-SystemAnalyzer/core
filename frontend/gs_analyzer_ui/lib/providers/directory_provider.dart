import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/models/storage_node.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'dart:math';

String generateUuid() {
  final random = Random();
  final chars = '0123456789abcdef';
  String randomString(int length) => String.fromCharCodes(
    Iterable.generate(length, (_) => chars.codeUnitAt(random.nextInt(16))),
  );
  return '${randomString(8)}-${randomString(4)}-4${randomString(3)}-a${randomString(3)}-${randomString(12)}';
}

enum SortMethod { name, size, date }

class DirectoryState {
  final String currentPath;
  final List<StorageNode> allNodes;
  final List<StorageNode> displayNodes;
  final Set<String> selectedPath;
  final String searchQuery;
  final SortMethod sortMethod;
  final bool isAscending;
  final bool isLoading;
  final bool isSelectionMode;
  final String? errorMessage;
  final bool skipHiddenFiles;
  final bool skipSystemFiles;

  const DirectoryState({
    this.currentPath = 'C:/',
    this.allNodes = const [],
    this.displayNodes = const [],
    this.selectedPath = const {},
    this.searchQuery = '',
    this.sortMethod = SortMethod.name,
    this.isAscending = true,
    this.isLoading = true,
    this.isSelectionMode = false,
    this.errorMessage,
    this.skipHiddenFiles = true,
    this.skipSystemFiles = true,
  });

  DirectoryState copyWith({
    String? currentPath,
    List<StorageNode>? allNodes,
    List<StorageNode>? displayNodes,
    Set<String>? selectedPath,
    String? searchQuery,
    SortMethod? sortMethod,
    bool? isAscending,
    bool? isLoading,
    bool? isSelectionMode,
    String? errorMessage,
    bool? skipHiddenFiles,
    bool? skipSystemFiles,
  }) {
    return DirectoryState(
      currentPath: currentPath ?? this.currentPath,
      allNodes: allNodes ?? this.allNodes,
      displayNodes: displayNodes ?? this.displayNodes,
      selectedPath: selectedPath ?? this.selectedPath,
      searchQuery: searchQuery ?? this.searchQuery,
      sortMethod: sortMethod ?? this.sortMethod,
      isAscending: isAscending ?? this.isAscending,
      isLoading: isLoading ?? this.isLoading,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      errorMessage: errorMessage ?? this.errorMessage,
      skipHiddenFiles: skipHiddenFiles ?? this.skipHiddenFiles,
      skipSystemFiles: skipSystemFiles ?? this.skipSystemFiles,
    );
  }
}

class DirectoryNotifier extends StateNotifier<DirectoryState> {
  final ApiService _apiService = ApiService();
  final Map<String, List<StorageNode>> _sectorCache = {};
  final Map<String, StorageNode> _nodeIndex = {};
  Timer? _flushTimer;
  bool _hasPendingFlush = false;
  final Ref ref;

  DirectoryNotifier(this.ref) : super(const DirectoryState()) {
    scanDirectory('C:/');
    _listenToSettings();
  }

  void _listenToSettings() {
    ref.listen(settingsProvider, (previous, next) {
      final scanSettings =
          next.savedSettings?.scan; // ← use savedSettings (post-save)
      final prevScan = previous?.savedSettings?.scan;
      if (scanSettings == null) return;

      final hiddenChanged =
          scanSettings.skipHiddenFiles != state.skipHiddenFiles;
      final systemChanged =
          scanSettings.skipSystemFiles != state.skipSystemFiles;
      final excludedChanged =
          scanSettings.excludedPaths != prevScan?.excludedPaths;

      if (hiddenChanged || systemChanged) {
        state = state.copyWith(
          skipHiddenFiles: scanSettings.skipHiddenFiles,
          skipSystemFiles: scanSettings.skipSystemFiles,
        );
        scanDirectory(state.currentPath, forceRefresh: true);
      } else if (excludedChanged) {
        _applyFiltersAndSort();
      }
    });
  }

  void _applyFiltersAndSort({
    List<StorageNode>? nodes,
    String? searchQuery,
    SortMethod? sortMethod,
    bool? isAscending,
  }) {
    final activeNodes = nodes ?? state.allNodes;
    final activeSearchQuery = searchQuery ?? state.searchQuery;
    final activeSortMethod = sortMethod ?? state.sortMethod;
    final activeIsAscending = isAscending ?? state.isAscending;

    List<StorageNode> filteredNodes = activeSearchQuery.isEmpty
        ? List.from(activeNodes)
        : activeNodes
              .where(
                (n) => n.name.toLowerCase().contains(
                  activeSearchQuery.toLowerCase(),
                ),
              )
              .toList();

    final excluded =
        ref.read(settingsProvider).savedSettings?.scan.excludedPaths ?? [];

    if (excluded.isNotEmpty) {
      filteredNodes = filteredNodes.where((n) {
        final nodePath = n.path.replaceAll('\\', '/').toLowerCase();
        return !excluded.any((ex) {
          final exPath = ex.replaceAll('\\', '/').toLowerCase();
          return nodePath == exPath;
        });
      }).toList();
    }

    filteredNodes.sort((a, b) {
      int comparison;
      switch (activeSortMethod) {
        case SortMethod.name:
          comparison = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          break;
        case SortMethod.size:
          comparison = b.sizeBytes.compareTo(a.sizeBytes);
          break;
        case SortMethod.date:
          comparison = b.lastModified.compareTo(a.lastModified);
          break;
      }
      return activeIsAscending ? comparison : -comparison;
    });

    state = state.copyWith(
      allNodes: activeNodes,
      displayNodes: filteredNodes,
      searchQuery: activeSearchQuery,
      sortMethod: activeSortMethod,
      isAscending: activeIsAscending,
    );
  }

  String? _currentScanId;
  String? get currentScanId => _currentScanId;

  Future<void> scanDirectory(
    String targetPath, {
    bool forceRefresh = false,
  }) async {
    String safePath = targetPath.replaceAll('\\', '/');
    final scanId = generateUuid();
    _currentScanId = scanId;

    if (!forceRefresh && _sectorCache.containsKey(safePath)) {
      _applyFiltersAndSort(nodes: _sectorCache[safePath]);
      state = state.copyWith(
        currentPath: safePath,
        isLoading: false,
        errorMessage: null,
      );

      _apiService
          .scanDirectory(safePath, scanId)
          .then((freshNodes) {
            _sectorCache[safePath] = freshNodes;
            if (state.currentPath == safePath)
              _applyFiltersAndSort(nodes: freshNodes);
          })
          .catchError((_) {});
      return;
    }

    _sectorCache[safePath] = [];
    _nodeIndex.clear();
    _flushTimer?.cancel();
    _flushTimer = null;
    _hasPendingFlush = false;
    if (forceRefresh) {
      final keysToRemove = _sectorCache.keys
          .where((k) => k.toLowerCase().startsWith(safePath.toLowerCase()))
          .toList();
      for (final key in keysToRemove) {
        _sectorCache.remove(key);
      }
    }

    state = state.copyWith(
      currentPath: safePath,
      isLoading: true,
      searchQuery: '',
      errorMessage: null,
      allNodes: [],
      displayNodes: [],
    );

    try {
      await _apiService.requestDirectoryStream(safePath, scanId);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  void receiveStreamChunk(
    String? scanId,
    String path,
    List<dynamic> chunkData,
  ) {
    if (scanId != null && scanId != _currentScanId) return;

    String incomingPath = path.replaceAll('\\', '/').toLowerCase();
    String currentPath = state.currentPath.replaceAll('\\', '/').toLowerCase();
    if (incomingPath.endsWith('/'))
      incomingPath = incomingPath.substring(0, incomingPath.length - 1);
    if (currentPath.endsWith('/'))
      currentPath = currentPath.substring(0, currentPath.length - 1);

    if (incomingPath != currentPath) return;

    final parsedChunk = chunkData
        .map((json) => StorageNode.fromJson(json as Map<String, dynamic>))
        .toList();

    for (final node in parsedChunk) {
      final key = node.path.replaceAll('\\', '/').toLowerCase();
      _nodeIndex[key] = node;
    }
    _hasPendingFlush = true;

    if (state.displayNodes.isEmpty) {
      _flushBufferedNodes();
    } else {
      _flushTimer ??= Timer(const Duration(milliseconds: 64), _flushBufferedNodes);
    }
  }

  void _flushBufferedNodes() {
    _flushTimer = null;
    if (!_hasPendingFlush) return;
    _hasPendingFlush = false;

    final activeNodes = _nodeIndex.values.toList();
    _sectorCache[state.currentPath] = activeNodes;
    _applyFiltersAndSort(nodes: activeNodes);
  }

  void finalizeStream(
    String? scanId,
    String path, {
    String? parentPath,
    int? ownBytes,
    int? recursiveBytes,
    bool recursiveBytesFinal = true,
  }) async {
    if (scanId != null && scanId != _currentScanId) return;

    String incomingPath = path.replaceAll('\\', '/').toLowerCase();
    String currentPath = state.currentPath.replaceAll('\\', '/').toLowerCase();

    if (incomingPath.endsWith('/'))
      incomingPath = incomingPath.substring(0, incomingPath.length - 1);
    if (currentPath.endsWith('/'))
      currentPath = currentPath.substring(0, currentPath.length - 1);

    if (incomingPath == currentPath) {
      _flushTimer?.cancel();
      _flushTimer = null;
      _hasPendingFlush = false;

      if (recursiveBytesFinal) {
        for (final entry in _nodeIndex.entries.toList()) {
          if (!entry.value.isRecursiveFinal) {
            _nodeIndex[entry.key] = entry.value.copyWith(isRecursiveFinal: true);
          }
        }
      }

      final activeNodes = _nodeIndex.values.toList();
      _sectorCache[state.currentPath] = activeNodes;
      _applyFiltersAndSort(nodes: activeNodes);

      state = state.copyWith(isLoading: false);
    }
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    super.dispose();
  }

  Future<List<StorageNode>> fetchChildrenForTree(String path) async {
    String safePath = path.replaceAll('\\', '/');
    if (_sectorCache.containsKey(safePath)) {
      return _sectorCache[safePath]!;
    }
    final nodes = await _apiService.scanDirectory(safePath, generateUuid());
    _sectorCache[safePath] = nodes;
    return nodes;
  }

  // Navigate to previous Directory
  void navigateUp() {
    String normalized = state.currentPath.replaceAll('\\', '/');
    if (normalized == 'C:/' || normalized == 'C:' || normalized.isEmpty) return;

    List<String> parts = normalized.split('/');
    parts.removeWhere((part) => part.isEmpty);

    if (parts.length > 1) {
      parts.removeLast();
      String newPath = parts.join('/');
      if (newPath.endsWith(':')) newPath += '/';
      scanDirectory(newPath);
    } else {
      scanDirectory('C:/');
    }
  }

  // Filter and Sort
  void setSortMethod(SortMethod method) {
    _applyFiltersAndSort(sortMethod: method);
  }

  //Search Query
  void updateSearchQuery(String query) {
    _applyFiltersAndSort(searchQuery: query);
  }

  // Direction of sorting
  void setAscending(bool ascending) {
    _applyFiltersAndSort(isAscending: ascending);
  }

  // Select Multiple
  void toggleSelection(String path) {
    final currentSelection = Set<String>.from(state.selectedPath);

    if (currentSelection.contains(path)) {
      currentSelection.remove(path);
    } else {
      currentSelection.add(path);
    }

    state = state.copyWith(selectedPath: currentSelection);
  }

  // Toggle Selection Mode
  void toggleSelectionMode() {
    if (state.isSelectionMode) {
      state = state.copyWith(isSelectionMode: false, selectedPath: {});
    } else {
      state = state.copyWith(isSelectionMode: true);
    }
  }

  void purgeStaleCache() {
    String current = state.currentPath.replaceAll('\\', '/');
    _sectorCache.remove(current);
    state = state.copyWith(allNodes: [], displayNodes: [], isLoading: false);
  }
}

final directoryProvider =
    StateNotifierProvider<DirectoryNotifier, DirectoryState>((ref) {
      return DirectoryNotifier(ref);
    });

final treeExpandedProvider = StateProvider<bool>((ref) => true);
