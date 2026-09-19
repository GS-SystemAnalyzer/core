import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/core/theme/hud_colors.dart';
import 'package:gs_analyzer_ui/core/theme/hud_text_theme.dart';
import 'package:gs_analyzer_ui/providers/navigation_provider.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';

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
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: width,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.only(left: 7.0),
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: Icon(Icons.menu, color: theme.colorScheme.surfaceDim, size: 20),
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
                  Text(
                    'NODE_01',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFamily: HudTextTheme.fontCore,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ONLINE',
                    style: TextStyle(
                      color: theme.colorScheme.secondary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: HudTextTheme.fontCore,
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
                    AppRoute.diskIo,
                    'DISK I/O',
                    Icons.speed_outlined,
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
                  _buildNavItem(
                    AppRoute.automation,
                    'AUTOMATION',
                    Icons.auto_mode_outlined,
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
    final theme = Theme.of(context);
    final isActive = route == currentRoute && !isAction;
    final color = isActive ? theme.colorScheme.onPrimary : theme.colorScheme.surfaceDim;

    // Windows 11 style accent line
    final accentLine = Container(
      width: 3,
      height: 16,
      decoration: BoxDecoration(
        color: isActive ? theme.colorScheme.onPrimary : Colors.transparent,
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
                            style: theme.textTheme.bodySmall?.copyWith(
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
        final theme = Theme.of(context);
    final color = isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.surfaceDim;

    final accentLine = Container(
      width: 3,
      height: 16,
      decoration: BoxDecoration(
        color: isSelected ? theme.colorScheme.onPrimary : Colors.transparent,
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
                  style: theme.textTheme.bodySmall?.copyWith(
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
