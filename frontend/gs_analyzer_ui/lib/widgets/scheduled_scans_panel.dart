import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/models/scheduled_scan_model.dart';
import 'package:gs_analyzer_ui/providers/schedule_provider.dart';
import 'package:gs_analyzer_ui/providers/settings_provider.dart';
import 'package:gs_analyzer_ui/providers/drive_stats_provider.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';
import 'package:intl/intl.dart';

class ScheduledScansPanel extends ConsumerWidget {
  const ScheduledScansPanel({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(settingsProvider);
    final isMasterEnabled = settingsState.currentSettings?.monitoring.enableScheduledScans ?? false;
    final hud = context.HudTheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: hud.panel,
        border: Border.all(color: hud.textMain.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('SCHEDULED SCANS', style: hud.header),
              if (isMasterEnabled)
                TextButton.icon(
                  onPressed: () => _showScheduleDialog(context, ref),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('ADD SCHEDULE'),
                  style: TextButton.styleFrom(
                    foregroundColor: hud.accentCyan,
                    textStyle: TextStyle(
                      fontFamily: HudTheme.fontCore,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (!isMasterEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Text(
                'SCHEDULED SCANS DISABLED — ENABLE IN SETTINGS',
                style: TextStyle(
                  fontFamily: HudTheme.fontCore,
                  color: hud.textDim,
                  fontSize: 12,
                  letterSpacing: 1.0,
                ),
              ),
            )
          else
            _buildScheduleList(ref, context),
        ],
      ),
    );
  }

  Widget _buildScheduleList(WidgetRef ref, BuildContext context) {
    final scheduleAsync = ref.watch(scheduleProvider);
    final hud = context.HudTheme;

    return scheduleAsync.when(
      data: (schedules) {
        if (schedules.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Text(
              'NO SCHEDULES — ADD ONE TO AUTO-SCAN',
              style: TextStyle(
                fontFamily: HudTheme.fontCore,
                color: hud.textMain.withValues(alpha: 0.54),
                fontSize: 12,
                letterSpacing: 1.0,
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: schedules.length,
          itemBuilder: (context, index) {
            return _buildScheduleRow(context, ref, schedules[index]);
          },
        );
      },
      loading: () => Center(child: Padding(
        padding: EdgeInsets.all(16.0),
        child: CircularProgressIndicator(color: hud.accentCyan),
      )),
      error: (e, st) => Text('Error: $e', style: TextStyle(color: hud.accentRed)),
    );
  }

  Widget _buildScheduleRow(BuildContext context, WidgetRef ref, ScheduledScan scan) {
    final hud = context.HudTheme;
    final timeFormat = DateFormat('HH:mm');
    final String whenStr = scan.kind == 'Interval'
        ? 'EVERY ${scan.intervalMinutes} MIN'
        : 'CRON ${scan.cron}';
    
    final String lastRunStr = scan.lastRun != null
        ? timeFormat.format(scan.lastRun!.toLocal())
        : '—';
    
    final String nextRunStr = scan.nextRun != null
        ? timeFormat.format(scan.nextRun!.toLocal())
        : '—';

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: hud.textMain.withValues(alpha: 0.1))),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Switch(
            value: scan.enabled,
            onChanged: (val) {
              ref.read(scheduleProvider.notifier).toggleEnabled(scan.id, val);
            },
            activeThumbColor: hud.accentCyan,
            // activeColor: hud.accentCyan,
            activeTrackColor: hud.accentCyan.withValues(alpha: 0.3),
            inactiveThumbColor: hud.textMain.withValues(alpha: 0.3),
            inactiveTrackColor: hud.textMain.withValues(alpha: 0.1),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              scan.path.toUpperCase(),
              style: TextStyle(
                fontFamily: HudTheme.fontCore,
                color: scan.enabled ? hud.accentCyan : hud.textDim,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              scan.type.toUpperCase(),
              style: TextStyle(
                fontFamily: HudTheme.fontCore,
                color: scan.enabled ? hud.textMain.withValues(alpha: 0.70) : hud.textDim,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              whenStr,
              style: TextStyle(
                fontFamily: HudTheme.fontCore,
                color: scan.enabled ? hud.textMain.withValues(alpha: 0.7) : hud.textDim,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              scan.enabled ? 'LAST: $lastRunStr' : '—',
              style: TextStyle(
                fontFamily: HudTheme.fontCore,
                color: scan.enabled ? hud.textMain.withValues(alpha: 0.7) : hud.textDim,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              scan.enabled ? 'NEXT: $nextRunStr' : '—',
              style: TextStyle(
                fontFamily: HudTheme.fontCore,
                color: scan.enabled ? hud.accentCyan : hud.textDim,
                fontSize: 12,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: hud.accentCyan,
            onPressed: () => _showScheduleDialog(context, ref, scan),
            tooltip: 'Edit Schedule',
          ),
          IconButton(
            icon: const Icon(Icons.play_arrow, size: 20),
            color: scan.enabled ? hud.accentCyan : hud.textDim,
            onPressed: scan.enabled ? () => _runNow(context, ref, scan) : null,
            tooltip: 'Run Now',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            color: hud.accentRed.withValues(alpha: 0.8),
            onPressed: () => _confirmDelete(context, ref, scan),
            tooltip: 'Delete Schedule',
          ),
        ],
      ),
    );
  }

  void _runNow(BuildContext context, WidgetRef ref, ScheduledScan scan) async {
    try {
      await ref.read(scheduleProvider.notifier).runNow(scan.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: context.HudTheme.accentRed,
          ),
        );
      }
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, ScheduledScan scan) {
    final hud = context.HudTheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: hud.panel,
        title: Text('DELETE SCHEDULE', style: hud.header),
        content: Text(
          'Delete scheduled scan for ${scan.path}?',
          style: TextStyle(color: hud.textMain.withValues(alpha: 0.7), fontFamily: HudTheme.fontCore),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: TextStyle(color: hud.textMain.withValues(alpha: 0.54))),
          ),
          TextButton(
            onPressed: () {
              ref.read(scheduleProvider.notifier).deleteSchedule(scan.id);
              Navigator.pop(ctx);
            },
            child: Text('DELETE', style: TextStyle(color: hud.accentRed)),
          ),
        ],
      ),
    );
  }

  void _showScheduleDialog(BuildContext context, WidgetRef ref, [ScheduledScan? existingScan]) {
    showDialog(
      context: context,
      builder: (ctx) => _ScheduleDialog(existingScan: existingScan),
    );
  }
}

class _ScheduleDialog extends ConsumerStatefulWidget {
  final ScheduledScan? existingScan;

  const _ScheduleDialog({this.existingScan});

  @override
  _ScheduleDialogState createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends ConsumerState<_ScheduleDialog> {
  String _selectedKind = 'Interval';
  String _selectedType = 'Directory';
  String? _selectedPath;
  double _intervalMinutes = 15;
  late TextEditingController _cronController;

  @override
  void initState() {
    super.initState();
    if (widget.existingScan != null) {
      final s = widget.existingScan!;
      _selectedKind = s.kind;
      _selectedType = s.type;
      _selectedPath = s.path.replaceAll('/', '\\');
      _intervalMinutes = (s.intervalMinutes ?? 15).toDouble();
      _cronController = TextEditingController(text: s.cron ?? '0 3 * * *');
    } else {
      _cronController = TextEditingController(text: '0 3 * * *');
    }
  }

  @override
  void dispose() {
    _cronController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final drives = ref.watch(drivesProvider);
    final hud = context.HudTheme;
    
    if (_selectedPath == null && drives.isNotEmpty) {
      _selectedPath = drives.first.name;
    }

    return AlertDialog(
      backgroundColor: hud.panel,
      title: Text(widget.existingScan == null ? 'ADD SCHEDULE' : 'EDIT SCHEDULE', style: hud.header),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DRIVE', style: TextStyle(color: hud.textMain.withValues(alpha: 0.54), fontSize: 12)),
            DropdownButton<String>(
              value: _selectedPath,
              isExpanded: true,
              dropdownColor: hud.panel,
              style: TextStyle(color: hud.textMain, fontFamily: HudTheme.fontCore),
              items: drives.map((d) {
                return DropdownMenuItem(value: d.name, child: Text(d.name));
              }).toList(),
              onChanged: widget.existingScan == null 
                  ? (val) => setState(() => _selectedPath = val)
                  : null, // Disable changing drive on edit
            ),
            const SizedBox(height: 16),
            Text('SCAN TYPE', style: TextStyle(color: hud.textMain.withValues(alpha: 0.54), fontSize: 12)),
            DropdownButton<String>(
              value: _selectedType,
              isExpanded: true,
              dropdownColor: hud.panel,
              style: TextStyle(color: hud.textMain, fontFamily: HudTheme.fontCore),
              items: ['Directory', 'LargeFiles', 'Duplicates'].map((t) {
                return DropdownMenuItem(value: t, child: Text(t.toUpperCase()));
              }).toList(),
              onChanged: (val) => setState(() => _selectedType = val!),
            ),
            const SizedBox(height: 16),
            Text('SCHEDULE KIND', style: TextStyle(color: hud.textMain.withValues(alpha: 0.54), fontSize: 12)),
            DropdownButton<String>(
              value: _selectedKind,
              isExpanded: true,
              dropdownColor: hud.panel,
              style: TextStyle(color: hud.textMain, fontFamily: HudTheme.fontCore),
              items: const [
                DropdownMenuItem(value: 'Interval', child: Text('INTERVAL')),
                DropdownMenuItem(value: 'Cron', child: Text('CRON')),
              ],
              onChanged: (val) => setState(() => _selectedKind = val!),
            ),
            const SizedBox(height: 16),
            if (_selectedKind == 'Interval') ...[
              Text('INTERVAL: ${_intervalMinutes.toInt()} MIN', style: TextStyle(color: hud.textMain.withValues(alpha: 0.54), fontSize: 12)),
              Slider(
                value: _intervalMinutes,
                min: 1,
                max: 1440,
                divisions: 1439,
                activeColor: hud.accentCyan,
                inactiveColor: hud.textMain.withValues(alpha: 0.1),
                onChanged: (val) => setState(() => _intervalMinutes = val),
              ),
            ] else ...[
              Text('CRON EXPRESSION', style: TextStyle(color: hud.textMain.withValues(alpha: 0.54), fontSize: 12)),
              TextField(
                controller: _cronController,
                style: TextStyle(color: hud.textMain, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: hud.textMain.withValues(alpha: 0.3))),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: hud.accentCyan)),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('CANCEL', style: TextStyle(color: hud.textMain.withValues(alpha: 0.54))),
        ),
        TextButton(
          onPressed: _save,
          child: Text('SAVE', style: TextStyle(color: hud.accentCyan, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  void _save() {
    if (_selectedPath == null) return;
    
    final data = <String, dynamic>{
      'path': _selectedPath,
      'type': _selectedType,
      'kind': _selectedKind,
      'enabled': widget.existingScan?.enabled ?? true,
    };
    
    if (_selectedKind == 'Interval') {
      data['intervalMinutes'] = _intervalMinutes.toInt();
    } else {
      data['cron'] = _cronController.text;
    }
    
    final future = widget.existingScan == null
        ? ref.read(scheduleProvider.notifier).createSchedule(data)
        : ref.read(scheduleProvider.notifier).updateSchedule(widget.existingScan!.id, data);

    future.then((_) {
      if (mounted) Navigator.pop(context);
    }).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: context.HudTheme.accentRed),
        );
      }
    });
  }
}
