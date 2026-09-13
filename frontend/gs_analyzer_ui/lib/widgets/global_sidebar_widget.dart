import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/navigation_provider.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/utils/hud_theme.dart';

class GlobalSidebarWidget extends ConsumerStatefulWidget {
  const GlobalSidebarWidget({super.key});

  @override
  ConsumerState<GlobalSidebarWidget> createState() =>
      _GlobalSidebarWidgetState();
}

class _GlobalSidebarWidgetState extends ConsumerState<GlobalSidebarWidget> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final currentRoute = ref.watch(navigationProvider);
    final double width = _isExpanded ? 240.0 : 54.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: width,
      decoration: const BoxDecoration(
        color: Color(0xFF0F0F0F),
        border: Border(right: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(left: 7.0),
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(Icons.menu, color: HudTheme.textDim, size: 20),
              onPressed: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              },
              tooltip: _isExpanded ? 'Collapse Menu' : 'Expand Menu',
              splashRadius: 20,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
          ),
          const SizedBox(height: 12),

          if (_isExpanded) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'NODE_01',
                    style: TextStyle(
                      color: HudTheme.accentCyan,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFamily: HudTheme.fontCore,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'ONLINE',
                    style: TextStyle(
                      color: HudTheme.accentGreen,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: HudTheme.fontCore,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 8),
          ],

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildNavItem(
                    AppRoute.dashboard,
                    'DASHBOARD',
                    Icons.dashboard_outlined,
                    currentRoute,
                  ),
                  _buildNavItem(
                    AppRoute.process,
                    'PROCESS EXPLORER',
                    Icons.monitor_heart_outlined,
                    currentRoute,
                  ),
                  _buildNavItem(
                    AppRoute.cpuMetics,
                    'CPU METRICS',
                    Icons.memory_outlined,
                    currentRoute,
                  ),
                  _buildNavItem(
                    AppRoute.memory,
                    'MEMORY',
                    Icons.bar_chart_outlined,
                    currentRoute,
                  ),
                  _buildNavItem(
                    AppRoute.storage,
                    'STORAGE',
                    Icons.storage_outlined,
                    currentRoute,
                  ),
                  _buildNavItem(
                    AppRoute.startup,
                    'STARTUP',
                    Icons.rocket_launch_outlined,
                    currentRoute,
                  ),
                  _buildNavItem(
                    AppRoute.network,
                    'NETWORK',
                    Icons.account_tree_outlined,
                    currentRoute,
                  ),
                  _buildNavItem(
                    AppRoute.thermal,
                    'THERMAL',
                    Icons.thermostat_outlined,
                    currentRoute,
                  ),
                  _buildNavItem(
                    AppRoute.telemetryHistory,
                    'TELEMETRY HISTORY',
                    Icons.history_outlined,
                    currentRoute,
                  ),
                ],
              ),
            ),
          ),

          _buildSettingsNavItem(currentRoute),

          _buildNavItem(
            null,
            'HELP',
            Icons.help_outline_outlined,
            currentRoute,
            isAction: true,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    AppRoute? route,
    String title,
    IconData icon,
    AppRoute currentRoute, {
    bool isAction = false,
  }) {
    final isActive = route == currentRoute && !isAction;
    final color = isActive ? HudTheme.accentCyan : HudTheme.textDim;

    // Windows 11 style accent line
    final accentLine = Container(
      width: 3,
      height: 16,
      decoration: BoxDecoration(
        color: isActive ? HudTheme.accentCyan : Colors.transparent,
        borderRadius: BorderRadius.circular(2),
      ),
    );

    return InkWell(
      onTap: () {
        if (route != null) {
          ref.read(navigationProvider.notifier).state = route;
        }
      },
      hoverColor: Colors.white.withValues(alpha: 0.05),
      child: Container(
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            accentLine,
            const SizedBox(width: 8),
            Icon(icon, color: color, size: 20),
            if (_isExpanded) ...[
              const SizedBox(width: 10),
              Expanded(
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 0,
                    maxWidth: 250,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HudTheme.bodyText.copyWith(
                              color: color,
                              fontSize: 13,
                              fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (route == AppRoute.storage)
                          Padding(
                            padding: const EdgeInsets.only(left: 6.0),
                            child: Icon(Icons.lock, color: color, size: 14),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsNavItem(AppRoute currentRoute) {
    final bool isSelected = currentRoute == AppRoute.settings;
    final bool hasUnsavedChanges = ref
        .watch(settingsProvider)
        .hasUnsavedChanges;
    final color = isSelected ? HudTheme.accentCyan : HudTheme.textDim;

    final accentLine = Container(
      width: 3,
      height: 16,
      decoration: BoxDecoration(
        color: isSelected ? HudTheme.accentCyan : Colors.transparent,
        borderRadius: BorderRadius.circular(2),
      ),
    );

    return InkWell(
      onTap: () =>
          ref.read(navigationProvider.notifier).state = AppRoute.settings,
      hoverColor: Colors.white.withValues(alpha: 0.05),
      child: Container(
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            accentLine,
            const SizedBox(width: 8),
            Badge(
              isLabelVisible: hasUnsavedChanges,
              smallSize: 8,
              backgroundColor: Colors.amber, // Warning dot!
              child: Icon(Icons.settings_outlined, color: color, size: 20),
            ),
            if (_isExpanded) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'SETTINGS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: HudTheme.bodyText.copyWith(
                    color: color,
                    fontSize: 13,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    letterSpacing: 2.0,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
