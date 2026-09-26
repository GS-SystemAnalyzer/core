// frontend/gs_analyzer_ui/lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/screen/master_layout.dart';
import 'package:gs_analyzer_ui/providers/window_provider.dart';
import 'package:gs_analyzer_ui/utils/globals.dart';
import 'package:gs_analyzer_ui/services/notification_service.dart';
import 'package:gs_analyzer_ui/providers/navigation_provider.dart';
import 'package:gs_analyzer_ui/providers/drive_stats_provider.dart';
import 'package:gs_analyzer_ui/providers/storage_view_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_color.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:window_manager/window_manager.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';

const kCompactSize = Size(900, 640);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await NotificationService().initialize();

  const opts = WindowOptions(
    size: kCompactSize,
    minimumSize: Size(720, 520),
    center: true,
    titleBarStyle: TitleBarStyle.normal,
  );
  windowManager.waitUntilReadyToShow(opts, () async {
    await windowManager.setSize(kCompactSize);
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ProviderScope(child: GSAnalyzerApp()));
}

class GSAnalyzerApp extends ConsumerStatefulWidget {
  const GSAnalyzerApp({super.key});

  @override
  ConsumerState<GSAnalyzerApp> createState() => _GSAnalyzerAppState();
}

class _GSAnalyzerAppState extends ConsumerState<GSAnalyzerApp>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkInitialState();
    _initNotifications();
  }

  void _initNotifications() {
    NotificationService().setOnSelectNotification(
      (payload) {
        if (payload != null && payload.startsWith('storage:')) {
          final driveName = payload.substring('storage:'.length);
          ref.read(navigationProvider.notifier).state = AppRoute.storage;
          if (driveName.isNotEmpty) {
            ref.read(selectedDriveNameProvider.notifier).state = driveName;
          }
          ref.read(storageViewProvider.notifier).state = StorageView.drivePicker;
        } else if (payload == 'memory') {
          ref.read(navigationProvider.notifier).state = AppRoute.memory;
        }
      },
    );
  }

  Future<void> _checkInitialState() async {
    final isMax = await windowManager.isMaximized();
    ref.read(windowMaximizedProvider.notifier).state = isMax;
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    ref.read(windowMaximizedProvider.notifier).state = true;
  }

  @override
  void onWindowUnmaximize() {
    ref.read(windowMaximizedProvider.notifier).state = false;
    windowManager.setSize(kCompactSize);
    windowManager.center();
  }

  @override
  Widget build(BuildContext context) {


    final theme = ref.watch(
      settingsProvider.select((s) => s.currentSettings?.appearance.theme),
    );
    final accentKey = ref.watch(
      settingsProvider.select((s) => s.currentSettings?.appearance.accentColor),
    );

    final accentColor = HudColor.resolveAccent(accentKey);
    final themeMode = HudTheme.resolveThemeMode(theme);

    return MaterialApp(
      scaffoldMessengerKey: snackbarKey,
      debugShowCheckedModeBanner: false,
      theme: HudTheme.lightTheme(accentColor),
      darkTheme: HudTheme.darkTheme(accentColor),
      themeMode: themeMode,
      home: const MasterLayout(),
    );
  }
}
