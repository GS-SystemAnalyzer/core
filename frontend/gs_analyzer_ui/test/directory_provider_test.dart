import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mock_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('DirectoryNotifier Sorting Engine Tests', () {
    test(
      'Sorting by Size should put largest file at the top (Ascending = true)',
      () {
        final container = ProviderContainer();
        final notifier = container.read(directoryProvider.notifier);

        final fakeChunk = MockFactory.generateFakeChunk(4, 'C:/');

        fakeChunk[0] = MockFactory.createFakeNodeMap(
          name: 'big_movie.mp4',
          path: 'C:/big_movie.mp4',
          size: 5000000,
        );
        fakeChunk[1] = MockFactory.createFakeNodeMap(
          name: 'small_file.txt',
          path: 'C:/small_file.txt',
          size: 250000,
        );
        fakeChunk[2] = MockFactory.createFakeNodeMap(
          name: 'medium_image.png',
          path: 'C:/medium_image.png',
          size: 250000,
        );
        fakeChunk[3] = MockFactory.createFakeNodeMap(
          name: 'icon.png',
          path: 'C:/icon.png',
          size: 1050,
        );

        notifier.receiveStreamChunk(null, 'C:/', fakeChunk);

        notifier.finalizeStream(null, 'C:/');

        notifier.setSortMethod(SortMethod.size);

        final resultList = notifier.state.displayNodes;
        expect(
          resultList.isNotEmpty,
          true,
          reason: 'The display list should not be empty!',
        );

        expect(resultList[0].name, 'big_movie.mp4');
        expect(resultList[2].name, 'medium_image.png');
        expect(resultList[3].name, 'icon.png');
        expect(resultList[1].name, 'small_file.txt');
      },
    );
  });

  group('Enterprise First-Load Experience Tests', () {
    test(
      'Test 1: No Forever Loading on First Load (isLoading must be false)',
      () async {
        final container = ProviderContainer();
        final notifier = container.read(directoryProvider.notifier);

        await notifier.scanDirectory('C:/TestSector');
        notifier.finalizeStream(null, 'C:/TestSector');

        expect(
          notifier.state.isLoading,
          false,
          reason:
              'CRITICAL FAILURE: isLoading remained true. The HUD will spin forever!',
        );
      },
    );

    test(
      'Test 2: Correct Info on First Load (Files show actual size, not 0 bytes)',
      () {
        final container = ProviderContainer();
        final notifier = container.read(directoryProvider.notifier);

        notifier.state = notifier.state.copyWith(currentPath: 'C:/Downloads');

        final firstLoadChunk = MockFactory.generateFakeChunk(3, 'C:/Downloads');

        firstLoadChunk[0]['name'] = 'Siren-S1E1-1080.mp4';
        firstLoadChunk[0] = MockFactory.createFakeNodeMap(
          name: 'Siren-S1E1-1080.mp4',
          path: 'C:/Downloads/S1',
          size: 250000000,
        );
        firstLoadChunk[1] = MockFactory.createFakeNodeMap(
          name: 'Siren-S1E3-1080.mp4',
          path: 'C:/Downloads/S3',
          size: 20000000,
        );
        firstLoadChunk[2] = MockFactory.createFakeNodeMap(
          name: 'Siren-S1E4-1080.mp4',
          path: 'C:/Downloads/S4',
          size: 200000000,
        );

        notifier.receiveStreamChunk(null, 'c:/downloads', firstLoadChunk);
        notifier.finalizeStream(null, 'c:/downloads');

        final loadedFile = notifier.state.displayNodes;

        expect(loadedFile[0].type, 'File');
        expect(
          loadedFile[0].sizeBytes,
          250000000,
          reason:
              'CRITICAL FAILURE: The file size parsed as 0 bytes on first load!',
        );
        expect(loadedFile[1].type, 'File');
        expect(
          loadedFile[1].sizeBytes,
          20000000,
          reason:
              'CRITICAL FAILURE: The file size parsed as 0 bytes on first load!',
        );
        expect(loadedFile[2].type, 'File');
        expect(
          loadedFile[2].sizeBytes,
          200000000,
          reason:
              'CRITICAL FAILURE: The file size parsed as 0 bytes on first load!',
        );
      },
    );

    test(
      'Test 3: No Blank Screen on First Load (Data paints without needing a refresh)',
      () {
        final container = ProviderContainer();
        final notifier = container.read(directoryProvider.notifier);

        notifier.state = notifier.state.copyWith(currentPath: 'C:/Documents');

        final firstLoadChunk = MockFactory.generateFakeChunk(2, 'C:/Documents');

        firstLoadChunk[0] = MockFactory.createFakeNodeMap(
          name: 'PCD_Report.pdf',
          path: 'C:/Documents/PCD_Report.pdf',
          size: 15000,
        );
        firstLoadChunk[1] = MockFactory.createFakeNodeMap(
          name: 'small_file.txt',
          path: 'C:/Documents/small_file.txt',
          size: 150,
        );

        notifier.receiveStreamChunk(null, 'c:/documents', firstLoadChunk);
        notifier.finalizeStream(null, 'c:/documents');

        expect(
          notifier.state.displayNodes.isNotEmpty,
          true,
          reason:
              'CRITICAL FAILURE: displayNodes is empty! The screen is blank until the user hits refresh!',
        );

        expect(notifier.state.displayNodes.length, 2);
      },
    );
  });

  group('Incremental Directory Streaming Tests (Issue #239)', () {
    test('Progressive upserting updates existing node and prevents duplicate entries', () {
      final container = ProviderContainer();
      final notifier = container.read(directoryProvider.notifier);

      notifier.state = notifier.state.copyWith(currentPath: 'C:/Projects');

      final chunk1 = [
        {
          'name': 'Core',
          'path': 'C:/Projects/Core',
          'parentPath': 'C:/Projects',
          'type': 'Directory',
          'sizeBytes': 0,
          'lastModified': DateTime.now().toIso8601String(),
          'isHidden': false,
          'isSystem': false,
          'ownBytes': 0,
          'recursiveBytes': 0,
          'recursiveBytesFinal': false,
        },
        {
          'name': 'readme.txt',
          'path': 'C:/Projects/readme.txt',
          'parentPath': 'C:/Projects',
          'type': 'File',
          'sizeBytes': 512,
          'lastModified': DateTime.now().toIso8601String(),
          'isHidden': false,
          'isSystem': false,
          'ownBytes': 512,
          'recursiveBytes': 512,
          'recursiveBytesFinal': true,
        }
      ];

      notifier.receiveStreamChunk(null, 'C:/Projects', chunk1);

      final chunk2 = [
        {
          'name': 'Core',
          'path': 'C:/Projects/Core',
          'parentPath': 'C:/Projects',
          'type': 'Directory',
          'sizeBytes': 1048576,
          'lastModified': DateTime.now().toIso8601String(),
          'isHidden': false,
          'isSystem': false,
          'ownBytes': 4096,
          'recursiveBytes': 1048576,
          'recursiveBytesFinal': true,
        }
      ];

      notifier.receiveStreamChunk(null, 'C:/Projects', chunk2);
      notifier.finalizeStream(null, 'C:/Projects', recursiveBytesFinal: true);

      final nodes = notifier.state.displayNodes;
      expect(nodes.length, 2, reason: 'Duplicate nodes must not be created during streaming!');

      final coreNode = nodes.firstWhere((n) => n.name == 'Core');
      expect(coreNode.sizeBytes, 1048576);
      expect(coreNode.isRecursiveFinal, true);
    });

    test('finalizeStream marks all nodes isRecursiveFinal and resets isLoading', () {
      final container = ProviderContainer();
      final notifier = container.read(directoryProvider.notifier);

      notifier.state = notifier.state.copyWith(currentPath: 'C:/Work', isLoading: true);

      final chunk = [
        {
          'name': 'PendingFolder',
          'path': 'C:/Work/PendingFolder',
          'parentPath': 'C:/Work',
          'type': 'Directory',
          'sizeBytes': 2048,
          'lastModified': DateTime.now().toIso8601String(),
          'isHidden': false,
          'isSystem': false,
          'ownBytes': 0,
          'recursiveBytes': 2048,
          'recursiveBytesFinal': false,
        }
      ];

      notifier.receiveStreamChunk(null, 'C:/Work', chunk);
      notifier.finalizeStream(null, 'C:/Work', recursiveBytesFinal: true);

      expect(notifier.state.isLoading, false);
      expect(notifier.state.displayNodes.length, 1);
      expect(notifier.state.displayNodes.first.isRecursiveFinal, true);
    });
  });
}
