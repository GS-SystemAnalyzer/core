import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/features/dashboard/screens/dashboard_screen.dart';
import 'package:gs_analyzer_ui/providers/navigation_provider.dart';
import 'package:gs_analyzer_ui/screen/analyzer_dashboard.dart';
import 'package:gs_analyzer_ui/screen/ram_scannner_screen.dart';
import 'package:gs_analyzer_ui/screen/settings_screen.dart';
import 'package:gs_analyzer_ui/screen/thermal_module_screen.dart';
import 'package:gs_analyzer_ui/widgets/coming_soon.dart';
import 'package:gs_analyzer_ui/widgets/global_sidebar_widget.dart';
import 'package:gs_analyzer_ui/screen/storage_screen.dart';
import 'package:gs_analyzer_ui/providers/storage_view_provider.dart';
import 'package:gs_analyzer_ui/providers/telemetry_provider.dart';
import 'package:gs_analyzer_ui/screen/process_explorer_screen.dart';
import 'package:gs_analyzer_ui/screen/network_module_screen.dart';
import 'package:gs_analyzer_ui/screen/startup_manager_screen.dart';
import 'package:gs_analyzer_ui/providers/cache_stats_provider.dart';
import 'package:gs_analyzer_ui/screen/telemetry_history_screen.dart';
import 'package:gs_analyzer_ui/screen/disk_io_screen.dart';
import 'package:gs_analyzer_ui/screen/automation_screen.dart';
import 'cpu_metrics_screen.dart';

class MasterLayout extends ConsumerWidget {
  const MasterLayout({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentRoute = ref.watch(navigationProvider);
    ref.watch(telemetryProvider);

    ref.listen<AppRoute>(navigationProvider, (prev, next) {
      if (next == AppRoute.storage && prev != AppRoute.storage) {
        ref.read(storageViewProvider.notifier).state = StorageView.drivePicker;
      }
      if (next == AppRoute.settings && prev != AppRoute.settings) {
        ref.invalidate(cacheStatsProvider);
      }
    });

    return Scaffold(
      // backgroundColor: Theme.,
      body: Row(
        children: [
          const GlobalSidebarWidget(),

          Expanded(child: _buildActiveScreen(currentRoute)),
        ],
      ),
    );
  }

  Widget _buildActiveScreen(AppRoute route) {
    switch (route) {
      case AppRoute.storage:
        return const StorageRouter();

      case AppRoute.memory:
        return const RamScannerScreen();

      case AppRoute.diskIo:
        return const DiskIoScreen();

      case AppRoute.cpuMetics:
        return const CpuMetricsScreen();

      case AppRoute.network:
        return const NetworkModuleScreen();

      case AppRoute.startup:
        return const StartupManagerScreen();

      case AppRoute.thermal:
        return const ThermalModuleScreen();

      case AppRoute.telemetryHistory:
        return const TelemetryHistoryScreen();

      case AppRoute.process:
        return const ProcessExplorerScreen();

      case AppRoute.settings:
        return const SettingsScreen();

      case AppRoute.automation:
        return const AutomationScreen();

      case AppRoute.dashboard:
        return const DashboardScreen();
        
    }
  }
}

class StorageRouter extends ConsumerWidget {
  const StorageRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(storageViewProvider);
    return ComingSoon(
      child: view == StorageView.analyzer
          ? const AnalyzerDashboard()
          : const StorageScreen(),
    );
  }
}
