import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gs_analyzer_ui/models/drive_info.dart';
import 'package:gs_analyzer_ui/models/file_type_model.dart';
import 'package:gs_analyzer_ui/models/storage_node.dart';
import 'package:gs_analyzer_ui/providers/directory_provider.dart';
import 'package:gs_analyzer_ui/providers/drive_stats_provider.dart';
import 'package:gs_analyzer_ui/providers/duplicate_provider.dart';
import 'package:gs_analyzer_ui/providers/file_type_provider.dart';
import 'package:gs_analyzer_ui/providers/telemetry_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_extension.dart';
import 'package:gs_analyzer_ui/widgets/_directory_search_widget.dart';
import 'package:gs_analyzer_ui/widgets/directory_node_widget.dart';
import 'package:gs_analyzer_ui/widgets/directory_table_header.dart';
import 'package:gs_analyzer_ui/widgets/drive_telemetry_widget.dart';
import 'package:gs_analyzer_ui/widgets/duplicate_scanner_pannel.dart';
import 'package:gs_analyzer_ui/widgets/file_type_analyzer_panel.dart';
import 'package:gs_analyzer_ui/widgets/telemetry_hud_widget.dart';
import 'package:mocktail/mocktail.dart';

class MockApiService extends Mock implements ApiService {}

class MockDirectoryNotifier extends StateNotifier<DirectoryState>
    implements DirectoryNotifier {
  MockDirectoryNotifier([DirectoryState state = const DirectoryState()])
      : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockDuplicateNotifier extends StateNotifier<DuplicateState>
    implements DuplicateNotifier {
  MockDuplicateNotifier([DuplicateState? state])
      : super(state ?? DuplicateState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockTelemetryNotifier extends StateNotifier<TelemetryState>
    implements TelemetryNotifier {
  MockTelemetryNotifier([TelemetryState state = const TelemetryState()])
      : super(state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Storage Panel Widgets Theme Adaptation Tests', () {
    testWidgets('DirectoryTableHeader adapts panel background and bottom border between themes',
        (tester) async {
      // 1. Light Mode
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
          home: const Scaffold(
            body: DirectoryTableHeader(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(DirectoryTableHeader),
          matching: find.byType(Container),
        ).first,
      );
      final lightDec = lightContainer.decoration as BoxDecoration;
      expect(lightDec.color, equals(HudColor.lightBgPanel));
      expect(
        (lightDec.border as Border).bottom.color,
        equals(HudColor.lightTextMain.withValues(alpha: 0.10)),
      );

      // 2. Dark Mode
      await tester.pumpWidget(
        MaterialApp(
          theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
          home: const Scaffold(
            body: DirectoryTableHeader(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(DirectoryTableHeader),
          matching: find.byType(Container),
        ).first,
      );
      final darkDec = darkContainer.decoration as BoxDecoration;
      expect(darkDec.color, equals(HudColor.darkBgPanel));
      expect(
        (darkDec.border as Border).bottom.color,
        equals(HudColor.darkTextMain.withValues(alpha: 0.10)),
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('DirectorySearchWidget adapts text style, prefix icon, and panel fill between themes',
        (tester) async {
      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryProvider.overrideWith((ref) => MockDirectoryNotifier(
                  const DirectoryState(searchQuery: ''),
                )),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: DirectorySearchWidget(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightTextField = tester.widget<TextField>(find.byType(TextField));
      expect(lightTextField.decoration?.fillColor, equals(HudColor.lightBgPanel));
      expect(lightTextField.style?.color, equals(HudColor.lightAccentCyan));

      final lightPrefixIcon = tester.widget<Icon>(find.byIcon(Icons.search_outlined));
      expect(lightPrefixIcon.color, equals(HudColor.lightTextDim));

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            directoryProvider.overrideWith((ref) => MockDirectoryNotifier(
                  const DirectoryState(searchQuery: ''),
                )),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: DirectorySearchWidget(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkTextField = tester.widget<TextField>(find.byType(TextField));
      expect(darkTextField.decoration?.fillColor, equals(HudColor.darkBgPanel));
      expect(darkTextField.style?.color, equals(HudColor.darkAccentCyan));

      final darkPrefixIcon = tester.widget<Icon>(find.byIcon(Icons.search_outlined));
      expect(darkPrefixIcon.color, equals(HudColor.darkTextDim));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('DirectoryNodeWidget adapts folder/file icons, text styling, and delete action between themes',
        (tester) async {
      final mockApi = MockApiService();
      final dirNode = StorageNode(
        name: 'TargetFolder',
        path: 'C:/TargetFolder',
        type: 'Directory',
        sizeBytes: 1048576,
        lastModified: DateTime(2026, 1, 1),
      );
      final fileNode = StorageNode(
        name: 'Report.pdf',
        path: 'C:/TargetFolder/Report.pdf',
        type: 'File',
        sizeBytes: 2048,
        lastModified: DateTime(2026, 1, 1),
      );

      // 1. Light Mode - Directory Node
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: Scaffold(
              body: DirectoryNodeWidget(
                node: dirNode,
                apiService: mockApi,
                onNuke: (_, __) {},
                onNavigate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightFolderIcon = tester.widget<Icon>(find.byIcon(Icons.folder));
      expect(lightFolderIcon.color, equals(HudColor.lightAccentAmber));

      final lightDirNameText = tester.widget<Text>(find.text('TargetFolder'));
      expect(lightDirNameText.style?.color, equals(HudColor.lightTextMain));

      final lightDeleteDirIcon = tester.widget<Icon>(find.byIcon(Icons.folder_delete_outlined));
      expect(lightDeleteDirIcon.color, equals(HudColor.lightAccentRed));

      // 1b. Light Mode - File Node
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: Scaffold(
              body: DirectoryNodeWidget(
                node: fileNode,
                apiService: mockApi,
                onNuke: (_, __) {},
                onNavigate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightFileIcon = tester.widget<Icon>(find.byIcon(Icons.insert_drive_file_outlined));
      expect(lightFileIcon.color, equals(HudColor.lightAccentGreen));

      // 2. Dark Mode - Directory Node
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: Scaffold(
              body: DirectoryNodeWidget(
                node: dirNode,
                apiService: mockApi,
                onNuke: (_, __) {},
                onNavigate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkFolderIcon = tester.widget<Icon>(find.byIcon(Icons.folder));
      expect(darkFolderIcon.color, equals(HudColor.darkAccentAmber));

      final darkDirNameText = tester.widget<Text>(find.text('TargetFolder'));
      expect(darkDirNameText.style?.color, equals(HudColor.darkTextMain));

      final darkDeleteDirIcon = tester.widget<Icon>(find.byIcon(Icons.folder_delete_outlined));
      expect(darkDeleteDirIcon.color, equals(HudColor.darkAccentRed));

      // 2b. Dark Mode - File Node
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: Scaffold(
              body: DirectoryNodeWidget(
                node: fileNode,
                apiService: mockApi,
                onNuke: (_, __) {},
                onNavigate: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkFileIcon = tester.widget<Icon>(find.byIcon(Icons.insert_drive_file_outlined));
      expect(darkFileIcon.color, equals(HudColor.darkAccentGreen));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('DriveTelemetryWidget adapts container base and capacity stats between themes',
        (tester) async {
      final mockDrive = DriveInfo(
        name: 'C:\\',
        label: 'Local Disk',
        type: 'fixed',
        format: 'NTFS',
        totalBytes: 100000000000,
        freeBytes: 60000000000,
        usedBytes: 40000000000,
        percentageFree: 60.0,
        percentageUsed: 40.0,
      );

      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentDriveProvider.overrideWithValue(mockDrive),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: DriveTelemetryWidget(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(DriveTelemetryWidget),
          matching: find.byType(Container),
        ).first,
      );
      final lightDec = lightContainer.decoration as BoxDecoration;
      expect(lightDec.color, equals(HudColor.lightBgBase));
      expect(
        (lightDec.border as Border).top.color,
        equals(HudColor.lightTextMain.withValues(alpha: 0.1)),
      );

      final lightFreeText = tester.widget<Text>(find.text('60.0% FREE'));
      expect(lightFreeText.style?.color, equals(HudColor.lightAccentGreen));

      final lightProgress = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(lightProgress.color, equals(HudColor.lightAccentGreen));

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentDriveProvider.overrideWithValue(mockDrive),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: DriveTelemetryWidget(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(DriveTelemetryWidget),
          matching: find.byType(Container),
        ).first,
      );
      final darkDec = darkContainer.decoration as BoxDecoration;
      expect(darkDec.color, equals(HudColor.darkBgBase));
      expect(
        (darkDec.border as Border).top.color,
        equals(HudColor.darkTextMain.withValues(alpha: 0.1)),
      );

      final darkFreeText = tester.widget<Text>(find.text('60.0% FREE'));
      expect(darkFreeText.style?.color, equals(HudColor.darkAccentGreen));

      final darkProgress = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(darkProgress.color, equals(HudColor.darkAccentGreen));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('TelemetryHudWidget adapts panel decoration, indicators, and abort styling between themes',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const scanningState = TelemetryState(
        status: 'SCANNING',
        completed: 40,
        total: 100,
        percentComplete: 40.0,
        target: 'C:/Windows',
      );

      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            telemetryProvider.overrideWith((ref) => MockTelemetryNotifier(scanningState)),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: TelemetryHudWidget(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final lightCircular = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      expect(lightCircular.color, equals(HudColor.lightAccentCyan));

      final lightLinear = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(lightLinear.color, equals(HudColor.lightAccentGreen));

      final lightStatusText = tester.widget<Text>(find.text('SCANNING...'));
      expect(lightStatusText.style?.color, equals(HudColor.lightAccentCyan));

      final lightSectorsText = tester.widget<Text>(find.text('SECTORS SCANNED: 40 / 100'));
      expect(lightSectorsText.style?.color, equals(HudColor.lightAccentGreen));

      final lightAbortText = tester.widget<Text>(find.text('ABORT SCAN'));
      expect(lightAbortText.style?.color, equals(HudColor.lightAccentRed));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            telemetryProvider.overrideWith((ref) => MockTelemetryNotifier(scanningState)),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: TelemetryHudWidget(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final darkCircular = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      expect(darkCircular.color, equals(HudColor.darkAccentCyan));

      final darkLinear = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
      expect(darkLinear.color, equals(HudColor.darkAccentGreen));

      final darkStatusText = tester.widget<Text>(find.text('SCANNING...'));
      expect(darkStatusText.style?.color, equals(HudColor.darkAccentCyan));

      final darkSectorsText = tester.widget<Text>(find.text('SECTORS SCANNED: 40 / 100'));
      expect(darkSectorsText.style?.color, equals(HudColor.darkAccentGreen));

      final darkAbortText = tester.widget<Text>(find.text('ABORT SCAN'));
      expect(darkAbortText.style?.color, equals(HudColor.darkAccentRed));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('DuplicateScannerPanel adapts root base, header panel, and scan button between themes',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            duplicateProvider.overrideWith((ref) => MockDuplicateNotifier(
                  DuplicateState(isLoading: false, duplicateGroups: []),
                )),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: DuplicateScannerPanel(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightRootContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(DuplicateScannerPanel),
          matching: find.byType(Container),
        ).first,
      );
      expect(lightRootContainer.color, equals(HudColor.lightBgBase));

      final lightAwaitingText = tester.widget<Text>(find.text('AWAITING BACKEND SCAN COMMAND...'));
      expect(lightAwaitingText.style?.color, equals(HudColor.lightTextDim));

      final lightScanBtnFinder = find.widgetWithText(ElevatedButton, 'INIT SCAN');
      final lightScanBtn = tester.widget<ElevatedButton>(lightScanBtnFinder);
      expect(
        lightScanBtn.style?.backgroundColor?.resolve({}),
        equals(HudColor.lightAccentAmber),
      );
      expect(
        lightScanBtn.style?.foregroundColor?.resolve({}),
        equals(HudColor.lightTextPaint),
      );

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            duplicateProvider.overrideWith((ref) => MockDuplicateNotifier(
                  DuplicateState(isLoading: false, duplicateGroups: []),
                )),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: DuplicateScannerPanel(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkRootContainer = tester.widget<Container>(
        find.descendant(
          of: find.byType(DuplicateScannerPanel),
          matching: find.byType(Container),
        ).first,
      );
      expect(darkRootContainer.color, equals(HudColor.darkBgBase));

      final darkAwaitingText = tester.widget<Text>(find.text('AWAITING BACKEND SCAN COMMAND...'));
      expect(darkAwaitingText.style?.color, equals(HudColor.darkTextDim));

      final darkScanBtnFinder = find.widgetWithText(ElevatedButton, 'INIT SCAN');
      final darkScanBtn = tester.widget<ElevatedButton>(darkScanBtnFinder);
      expect(
        darkScanBtn.style?.backgroundColor?.resolve({}),
        equals(HudColor.darkAccentAmber),
      );
      expect(
        darkScanBtn.style?.foregroundColor?.resolve({}),
        equals(HudColor.darkTextPaint),
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    testWidgets('FileTypeAnalyzerPanel adapts base background, matrix title, and category colors between themes',
        (tester) async {
      const mockResult = FileTypeResult(
        root: 'C:\\',
        totalScannedFormatted: '15.5 GB',
        categories: [
          FileTypeCategory(
            name: 'media',
            totalBytes: 5000000000,
            sizeFormatted: '5.0 GB',
            fileCount: 120,
            percentOfDisk: 32.2,
            extensions: [],
          ),
          FileTypeCategory(
            name: 'documents',
            totalBytes: 3000000000,
            sizeFormatted: '3.0 GB',
            fileCount: 450,
            percentOfDisk: 19.3,
            extensions: [],
          ),
        ],
      );

      // 1. Light Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fileTypesProvider('C:\\').overrideWith((ref) async => mockResult),
          ],
          child: MaterialApp(
            theme: HudTheme.lightTheme(HudColor.lightAccentCyan),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: FileTypeAnalyzerPanel(driveName: 'C:\\'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lightTitleText = tester.widget<Text>(find.text('FILE TYPE MATRIX'));
      expect(lightTitleText.style?.color, equals(HudColor.lightTextMain));

      final lightHeaderIcon = tester.widget<Icon>(find.byIcon(Icons.grid_view_rounded));
      expect(lightHeaderIcon.color, equals(HudColor.lightAccentCyan));

      final lightExpTile = tester.widget<ExpansionTile>(find.byType(ExpansionTile).first);
      expect(lightExpTile.collapsedBackgroundColor, equals(HudColor.lightBgBase));

      // 2. Dark Mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fileTypesProvider('C:\\').overrideWith((ref) async => mockResult),
          ],
          child: MaterialApp(
            theme: HudTheme.darkTheme(HudColor.darkAccentCyan),
            home: const Scaffold(
              body: SingleChildScrollView(
                child: FileTypeAnalyzerPanel(driveName: 'C:\\'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final darkTitleText = tester.widget<Text>(find.text('FILE TYPE MATRIX'));
      expect(darkTitleText.style?.color, equals(HudColor.darkTextMain));

      final darkHeaderIcon = tester.widget<Icon>(find.byIcon(Icons.grid_view_rounded));
      expect(darkHeaderIcon.color, equals(HudColor.darkAccentCyan));

      final darkExpTile = tester.widget<ExpansionTile>(find.byType(ExpansionTile).first);
      expect(darkExpTile.collapsedBackgroundColor, equals(HudColor.darkBgBase));

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  });
}
