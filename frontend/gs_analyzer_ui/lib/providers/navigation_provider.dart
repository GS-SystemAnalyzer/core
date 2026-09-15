import 'package:flutter_riverpod/legacy.dart';

enum AppRoute {
  dashboard,
  process,
  cpuMetics,
  memory,
  diskIo,
  storage,
  startup,
  network,
  thermal,
  telemetryHistory,
  automation,
  settings,
}

final navigationProvider = StateProvider<AppRoute>((ref) => AppRoute.dashboard);
