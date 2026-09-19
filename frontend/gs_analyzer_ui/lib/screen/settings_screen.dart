import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/models/app_settings.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';
import 'package:gs_analyzer_ui/utils/hud_label.dart';
import 'package:gs_analyzer_ui/utils/globals.dart';
import 'package:gs_analyzer_ui/widgets/scheduled_scans_panel.dart';
import 'package:intl/intl.dart';
import 'package:gs_analyzer_ui/providers/cache_stats_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(cacheStatsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    if (state.isLoading && state.currentSettings == null) {
      return Scaffold(
        backgroundColor: HudTheme.bgBase,
        body: Center(
          child: CircularProgressIndicator(color: HudTheme.accentCyan),
        ),
      );
    }

    if (state.currentSettings == null) {
      return Scaffold(
        backgroundColor: HudTheme.bgBase,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'FAILED TO LOAD CONFIGURATION',
                style: HudTheme.headerCyan.copyWith(color: Colors.redAccent),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => notifier.resetToDefaults(),
                child: const Text('RETRY / RESET TO DEFAULTS'),
              ),
            ],
          ),
        ),
      );
    }

    final settings = state.currentSettings!;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('DEFENSE GRID CONFIG', style: HudTheme.headerCyan),
        actions: [
          if (state.hasUnsavedChanges)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Text(
                  '● UNSAVED CHANGES',
                  style: HudTheme.bodyText.copyWith(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildScanSection(settings.scan, state, notifier, context),
              const SizedBox(height: 16),
              _buildAlertsSection(settings.alerts, state, notifier),
              const SizedBox(height: 16),
              _buildMonitoringSection(settings.monitoring, state, notifier),
              const SizedBox(height: 16),
              _buildCacheSection(settings.cache, state, notifier, context, ref),
              const SizedBox(height: 16),
              _buildAppearanceSection(settings.appearance, state, notifier),
              const SizedBox(height: 16),
              _buildAdvancedSection(settings.advanced, state, notifier),
              const SizedBox(height: 32),
              _buildActionButtons(context, state, notifier),
              const SizedBox(height: 64), // Bottom scroll clearance
            ],
          ),

          if (state.isLoading)
            Container(
              color: Colors.black54,
              child: Center(
                child: CircularProgressIndicator(color: HudTheme.accentCyan),
              ),
            ),
        ],
      ),
    );
  }

  // SECTION BUILDERS

  Widget _buildScanSection(
    ScanSettings scan,
    SettingsState state,
    SettingsNotifier notifier,
    BuildContext context,
  ) {
    return _SettingsSection(
      title: 'SCAN PARAMETERS',
      errorFilter: 'Scan',
      state: state,
      child: Column(
        children: [
          _buildSlider('DEPTH', scan.depth.toDouble(), 1, 50, '', (val) {
            scan.depth = val.toInt();
            notifier.updateUI();
          }),
          _buildToggle('FOLLOW SYMLINKS', scan.followSymlinks, (val) {
            scan.followSymlinks = val;
            notifier.updateUI();
          }),
          _buildToggle('SKIP HIDDEN', scan.skipHiddenFiles, (val) {
            scan.skipHiddenFiles = val;
            notifier.updateUI();
          }),
          _buildToggle('SKIP SYSTEM', scan.skipSystemFiles, (val) {
            scan.skipSystemFiles = val;
            notifier.updateUI();
          }),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: HudLabel('EXCLUDED PATHS'),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...scan.excludedPaths.map(
                (path) => Chip(
                  label: Text(path, style: HudTheme.bodyText),
                  backgroundColor: Colors.white10,
                  deleteIcon: const Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.white70,
                  ),
                  onDeleted: () {
                    scan.excludedPaths.remove(path);
                    notifier.updateUI();
                  },
                ),
              ),
              ActionChip(
                label: Text(
                  '+ ADD',
                  style: HudTheme.bodyText.copyWith(color: HudTheme.accentCyan),
                ),
                backgroundColor: HudTheme.accentCyan.withValues(alpha: 0.1),
                side: BorderSide(color: HudTheme.accentCyan),
                onPressed: () => _showAddPathDialog(context, scan, notifier),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsSection(
    AlertSettings alerts,
    SettingsState state,
    SettingsNotifier notifier,
  ) {
    return _SettingsSection(
      title: 'ALERTS & THRESHOLDS',
      errorFilter: 'Threshold',
      state: state,
      child: Column(
        children: [
          _buildSlider(
            'DISK THRESHOLD',
            alerts.diskThresholdPercent.toDouble(),
            1,
            100,
            '%',
            (val) {
              alerts.diskThresholdPercent = val.toInt();
              notifier.updateUI();
            },
          ),
          _buildSlider(
            'RAM THRESHOLD',
            alerts.ramThresholdPercent.toDouble(),
            1,
            100,
            '%',
            (val) {
              alerts.ramThresholdPercent = val.toInt();
              notifier.updateUI();
            },
          ),
          _buildSlider(
            'RAM MIN FREE',
            alerts.ramMinimumFreeMb.toDouble(),
            256,
            16384, // Up to 16GB
            ' MB',
            (val) {
              alerts.ramMinimumFreeMb = val.toInt();
              notifier.updateUI();
            },
          ),
          _buildSlider(
            'CPU THRESHOLD',
            alerts.cpuThresholdPercent.toDouble(),
            1,
            100,
            '%',
            (val) {
              alerts.cpuThresholdPercent = val.toInt();
              notifier.updateUI();
            },
          ),
          _buildSlider(
            'THERMAL LIMIT',
            alerts.thermalThresholdCelsius.toDouble(),
            40,
            110,
            '°C',
            (val) {
              alerts.thermalThresholdCelsius = val.toInt();
              notifier.updateUI();
            },
          ),
          _buildToggle('DESKTOP NOTIFS', alerts.enableDesktopNotifications, (
            val,
          ) {
            alerts.enableDesktopNotifications = val;
            notifier.updateUI();
          }),
        ],
      ),
    );
  }

  Widget _buildMonitoringSection(
    MonitoringSettings mon,
    SettingsState state,
    SettingsNotifier notifier,
  ) {
    return _SettingsSection(
      title: 'RADAR MONITORING',
      errorFilter: 'Poll',
      state: state,
      child: Column(
        children: [
          _buildSlider(
            'CPU POLL',
            mon.cpuPollIntervalMs.toDouble(),
            500,
            60000,
            ' ms',
            (val) {
              mon.cpuPollIntervalMs = val.toInt();
              notifier.updateUI();
            },
          ),
          _buildSlider(
            'RAM POLL',
            mon.ramPollIntervalMs.toDouble(),
            500,
            60000,
            ' ms',
            (val) {
              mon.ramPollIntervalMs = val.toInt();
              notifier.updateUI();
            },
          ),
          _buildSlider(
            'THERMAL POLL',
            mon.thermalPollIntervalMs.toDouble(),
            500,
            60000,
            ' ms',
            (val) {
              mon.thermalPollIntervalMs = val.toInt();
              notifier.updateUI();
            },
          ),
          _buildSlider(
            'NETWORK POLL',
            mon.networkPollIntervalMs.toDouble(),
            500,
            60000,
            ' ms',
            (val) {
              mon.networkPollIntervalMs = val.toInt();
              notifier.updateUI();
            },
          ),
          _buildSlider(
            'DISK I/O POLL',
            mon.diskIoPollIntervalMs.toDouble(),
            500,
            60000,
            ' ms',
            (val) {
              mon.diskIoPollIntervalMs = val.toInt();
              notifier.updateUI();
            },
          ),
          _buildToggle('SCHEDULED SCANS', mon.enableScheduledScans, (val) {
            mon.enableScheduledScans = val;
            notifier.updateUI();
          }),
          if (mon.enableScheduledScans)
            _buildSlider(
              'SCAN INTERVAL',
              mon.scheduledScanIntervalMinutes.toDouble(),
              1,
              1440,
              ' min',
              (val) {
                mon.scheduledScanIntervalMinutes = val.toInt();
                notifier.updateUI();
              },
            ),
          const ScheduledScansPanel(),
        ],
      ),
    );
  }

  Widget _buildCacheSection(
    CacheSettings cache,
    SettingsState state,
    SettingsNotifier notifier,
    BuildContext context,
    WidgetRef ref,
  ) {
    final statsAsync = ref.watch(cacheStatsProvider);

    return _SettingsSection(
      title: 'MEMORY & CACHE',
      errorFilter: 'Cache',
      state: state,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSlider(
            'SCAN CACHE TTL',
            cache.scanCacheTtlMinutes.toDouble(),
            1,
            1440,
            ' min',
            (val) {
              cache.scanCacheTtlMinutes = val.toInt();
              notifier.updateUI();
            },
          ),
          _buildSlider(
            'MAX CACHED SCANS',
            cache.maxCacheScans.toDouble(),
            1,
            50,
            '',
            (val) {
              cache.maxCacheScans = val.toInt();
              notifier.updateUI();
            },
          ),
          _buildSlider(
            'MAX CACHED NODES',
            cache.maxCachedNodes.toDouble(),
            1000,
            500000,
            '',
            (val) {
              cache.maxCachedNodes = val.toInt();
              notifier.updateUI();
            },
            divisions: 499,
            valueDisplay: NumberFormat('#,###').format(cache.maxCachedNodes),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: HudTheme.accentRed,
              ),
              onPressed: () async {
                final success = await notifier.clearCache();
                ref.invalidate(cacheStatsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: success
                          ? Colors.green.shade900
                          : Colors.red.shade900,
                      content: Text(
                        success
                            ? 'Cache cleared. Run a new Directory Scan to repopulate.'
                            : 'Failed to clear cache. Is the backend running?',
                        style: HudTheme.bodyText,
                      ),
                    ),
                  );
                }
              },
              child: const Text(
                'CLEAR CACHE NOW',
                style: TextStyle(letterSpacing: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Row(
              children: [
                Expanded(
                  child: statsAsync.when(
                    data: (stats) {
                      final nodes = stats != null
                          ? NumberFormat('#,###').format(stats.activeEntries)
                          : '0';
                      final memory = stats?.formattedMemory ?? '0 MB';
                      final hitRate = stats?.formattedHitRate ?? '0%';
                      return Text(
                        'CACHED: $nodes NODES · $memory · HIT RATE $hitRate',
                        style: HudTheme.bodyText.copyWith(
                          color: Colors.white38,
                          fontSize: 11,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                    loading: () => Text(
                      'CACHED: FETCHING STATS...',
                      style: HudTheme.bodyText.copyWith(
                        color: Colors.white38,
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    error: (_, __) => Text(
                      'CACHED: STATS OFFLINE',
                      style: HudTheme.bodyText.copyWith(
                        color: Colors.white38,
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                _CacheRefreshButton(
                  onRefresh: () => ref.refresh(cacheStatsProvider),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceSection(
    AppearanceSettings app,
    SettingsState state,
    SettingsNotifier notifier,
  ) {
    final currentTheme = app.theme.toLowerCase();
    final isLight = currentTheme == 'cyber_light' || currentTheme == 'light';
    final isSystem = currentTheme == 'system';
    final isDark =
        (currentTheme == 'cyber_dark' || currentTheme == 'dark') ||
        (!isLight && !isSystem);

    return _SettingsSection(
      title: 'APPEARANCE',
      errorFilter: 'Appearance',
      state: state,
      child: Column(
        children: [
          _buildToggle('COMPACT MODE', app.compactMode, (val) {
            app.compactMode = val;
            notifier.updateUI();
          }),
          _buildToggle('ANIMATIONS', app.showAnimations, (val) {
            app.showAnimations = val;
            notifier.updateUI();
          }),
          _buildToggle('DARK MODE', isDark, (val) {
            if (val) {
              app.theme = 'cyber_dark';
            }
            notifier.updateUI();
          }),
          _buildToggle('LIGHT MODE', isLight, (val) {
            if (val) {
              app.theme = 'cyber_light';
            }
            notifier.updateUI();
          }),
          _buildToggle('SYSTEM MODE', isSystem, (val) {
            if (val) {
              app.theme = 'system';
            }
            notifier.updateUI();
          }),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: HudLabel('ACCENT COLOR'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _colorSwatch('cyan', Colors.cyan, app, notifier),
              _colorSwatch('green', Colors.greenAccent, app, notifier),
              _colorSwatch('amber', Colors.amber, app, notifier),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedSection(
    AdvancedSettings adv,
    SettingsState state,
    SettingsNotifier notifier,
  ) {
    // Read the *saved* port so we can detect unsaved port changes
    final savedPort = state.savedSettings?.advanced.backendPort ?? 5200;
    final portChanged = adv.backendPort != savedPort;

    return Container(
      decoration: HudTheme.hudPanelDecoration,
      child: Material(
        color: Colors.transparent,
        child: Theme(
          data: ThemeData(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Text(
              'ADVANCED ▾',
              style: HudTheme.bodyText.copyWith(color: HudTheme.textDim),
            ),
            childrenPadding: const EdgeInsets.all(16),
          children: [
            if (_hasError(state, 'Port') || _hasError(state, 'SignalR'))
              _buildErrorMessage(state, 'Port'),

            // ↓ ADD THIS — amber warning when port has been changed
            if (portChanged)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  border: Border.all(color: Colors.amber),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.amber,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Port change requires a full backend restart to take effect.',
                        style: HudTheme.bodyText.copyWith(
                          color: Colors.amber,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ↑ END OF NEW BLOCK
            _buildSlider(
              'BACKEND PORT',
              adv.backendPort.toDouble(),
              1024,
              65535,
              '',
              (val) {
                adv.backendPort = val.toInt();
                notifier.updateUI();
              },
            ),
            _buildSlider(
              'RECONNECT DELAY',
              adv.signalrReconnectDelaysMs.toDouble(),
              500,
              30000,
              ' ms',
              (val) {
                adv.signalrReconnectDelaysMs = val.toInt();
                notifier.updateUI();
              },
            ),
            _buildSlider(
              'MAX RETRIES',
              adv.maxSignalrRetries.toDouble(),
              1,
              100,
              '',
              (val) {
                adv.maxSignalrRetries = val.toInt();
                notifier.updateUI();
              },
            ),
            _buildToggle('DEBUG LOGS', adv.enableDebugLogs, (val) {
              adv.enableDebugLogs = val;
              notifier.updateUI();
            }),
          ],
        ),
      ),
      ),
    );
  }

  // HELPER WIDGETS
  Widget _buildActionButtons(
    BuildContext context,
    SettingsState state,
    SettingsNotifier notifier,
  ) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 45,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: state.hasUnsavedChanges
                  ? HudTheme.accentCyan
                  : Colors.white10,
              foregroundColor: state.hasUnsavedChanges
                  ? Colors.black
                  : Colors.white54,
            ),
            onPressed: state.hasUnsavedChanges
                ? () async {
                    final success = await notifier.saveChanges();
                    if (success) {
                      snackbarKey.currentState?.showSnackBar(
                        SnackBar(
                          content: Text(
                            'SETTINGS SAVED SUCESSFULLY',
                            style: HudTheme.bodyText.copyWith(
                              color: Colors.black,
                            ),
                          ),
                          backgroundColor: HudTheme.accentCyan,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  }
                : null,
            child: const Text(
              'SAVE CHANGES',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 45,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.redAccent),
              foregroundColor: Colors.redAccent,
            ),
            onPressed: () => _confirmReset(context, notifier),
            child: const Text(
              'RESET TO DEFAULTS',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
            ),
          ),
        ),
      ],
    );
  }

  void _confirmReset(BuildContext context, SettingsNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HudTheme.bgBase,
        title: Text(
          'INITIATE RESET?',
          style: HudTheme.headerCyan.copyWith(color: Colors.redAccent),
        ),
        content: Text(
          'This will wipe all configurations and restore factory defaults',
          style: HudTheme.bodyText,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: HudTheme.bodyText),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await notifier.resetToDefaults();
              if (success) {
                snackbarKey.currentState?.showSnackBar(
                  SnackBar(
                    content: Text(
                      'RESTORED TO FACTORY DEFAULTS',
                      style: HudTheme.bodyText.copyWith(color: Colors.white),
                    ),
                    backgroundColor: Colors.redAccent,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text(
              'CONFIRM OVERWRITE ',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddPathDialog(
    BuildContext context,
    ScanSettings scan,
    SettingsNotifier notifier,
  ) {
    String input = '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HudTheme.bgBase,
        title: Text('ADD EXCLUSION PATH', style: HudTheme.headerCyan),
        content: TextField(
          style: HudTheme.bodyText,
          decoration: InputDecoration(
            hintText: 'C:/My/Secret/Folder',
            hintStyle: HudTheme.bodyText.copyWith(color: HudTheme.textDim),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: HudTheme.accentCyan),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: HudTheme.accentCyan),
            ),
          ),
          onChanged: (v) => input = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: HudTheme.bodyText),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: HudTheme.accentCyan,
            ),
            onPressed: () {
              if (input.isNotEmpty && !scan.excludedPaths.contains(input)) {
                scan.excludedPaths.add(input.replaceAll('\\', '/'));
                notifier.updateUI();
              }
              Navigator.pop(ctx);
            },
            child: const Text('ADD', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Widget _colorSwatch(
    String id,
    Color color,
    AppearanceSettings app,
    SettingsNotifier notifier,
  ) {
    bool isSelected = app.accentColor == id;
    return GestureDetector(
      onTap: () {
        app.accentColor = id;
        notifier.updateUI();
      },
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
          boxShadow: isSelected
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]
              : null,
        ),
      ),
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max,
    String unit,
    Function(double) onChanged, {
    int? divisions,
    String? valueDisplay,
  }) {
    final clampedVal = value.clamp(min, max);
    return Row(
      children: [
        SizedBox(width: 140, child: HudLabel(label)),
        Expanded(
          child: Slider(
            value: clampedVal,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: HudTheme.accentCyan,
            inactiveColor: Colors.white12,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 80,
          child: Text(
            valueDisplay ?? '${clampedVal.toInt()}$unit',
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildToggle(String label, bool value, Function(bool) onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            HudLabel(label),
            Switch(
              value: value,
              activeThumbColor: HudTheme.accentCyan,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  bool _hasError(SettingsState state, String keyword) {
    return state.validationErrors.any(
      (e) => e.toLowerCase().contains(keyword.toLowerCase()),
    );
  }

  Widget _buildErrorMessage(SettingsState state, String keyword) {
    var errors = state.validationErrors
        .where((e) => e.toLowerCase().contains(keyword.toLowerCase()))
        .toList();
    if (errors.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: errors
          .map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                e,
                style: HudTheme.bodyText.copyWith(
                  color: Colors.redAccent,
                  fontSize: 12,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final Widget child;
  final String errorFilter;
  final SettingsState state;

  const _SettingsSection({
    required this.title,
    required this.child,
    required this.errorFilter,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: HudTheme.hudPanelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: HudTheme.headerCyan.copyWith(letterSpacing: 2)),
          const Divider(color: Colors.white10, height: 24, thickness: 1),

          if (state.validationErrors.any(
            (e) => e.toLowerCase().contains(errorFilter.toLowerCase()),
          ))
            ...state.validationErrors
                .where(
                  (e) => e.toLowerCase().contains(errorFilter.toLowerCase()),
                )
                .map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      e,
                      style: HudTheme.bodyText.copyWith(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
          child,
        ],
      ),
    );
  }
}

class _CacheRefreshButton extends StatefulWidget {
  final VoidCallback onRefresh;

  const _CacheRefreshButton({required this.onRefresh});

  @override
  State<_CacheRefreshButton> createState() => _CacheRefreshButtonState();
}

class _CacheRefreshButtonState extends State<_CacheRefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward(from: 0.0);
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Refresh cache diagnostics',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _handleTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: Colors.white10,
          child: Padding(
            padding: const EdgeInsets.all(6.0),
            child: RotationTransition(
              turns: _controller,
              child: const Icon(
                Icons.refresh,
                size: 15,
                color: HudTheme.accentCyan,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

