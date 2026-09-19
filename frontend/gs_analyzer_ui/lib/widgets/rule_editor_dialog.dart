import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/models/automation_rule.dart';
import 'package:gs_analyzer_ui/models/nuke_preview.dart';
import 'package:gs_analyzer_ui/providers/automation_provider.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/formatters.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';

class RuleEditorDialog extends ConsumerStatefulWidget {
  final AutomationRule? existingRule;

  const RuleEditorDialog({super.key, this.existingRule});

  @override
  ConsumerState<RuleEditorDialog> createState() => _RuleEditorDialogState();
}

class _RuleEditorDialogState extends ConsumerState<RuleEditorDialog> {
  int _currentStep = 0;

  late TextEditingController _nameController;
  late TextEditingController _rootController;
  late TextEditingController _olderThanDaysController;
  late TextEditingController _largerThanMbController;
  late TextEditingController _extensionsController;
  late TextEditingController _intervalHoursController;

  bool _recurseSubdirectories = true;
  AutomationScheduleKind _scheduleKind = AutomationScheduleKind.daily;
  TimeOfDay _timeOfDay = const TimeOfDay(hour: 3, minute: 0);
  int _dayOfWeek = 0; // 0=Sunday

  bool _isDryRunning = false;
  NukePreviewResponse? _dryRunPreview;
  String? _errorMessage;
  bool _armImmediately = true;

  @override
  void initState() {
    super.initState();
    final rule = widget.existingRule;
    _nameController = TextEditingController(text: rule?.name ?? 'TEMP CLEANUP');
    _rootController = TextEditingController(
      text: rule?.root ?? (Platform.isWindows ? (Platform.environment['TEMP'] ?? 'C:\\Temp') : '/tmp'),
    );
    _olderThanDaysController = TextEditingController(
      text: rule?.criteria.olderThanDays?.toString() ?? '7',
    );
    _largerThanMbController = TextEditingController(
      text: rule?.criteria.largerThanBytes != null
          ? (rule!.criteria.largerThanBytes! ~/ (1024 * 1024)).toString()
          : '',
    );
    _extensionsController = TextEditingController(
      text: rule?.criteria.extensionAllowlist?.join(', ') ?? '.tmp, .log',
    );
    _intervalHoursController = TextEditingController(
      text: rule?.schedule.intervalHours?.toString() ?? '24',
    );
    _recurseSubdirectories = rule?.criteria.recurseSubdirectories ?? true;
    _scheduleKind = rule?.schedule.kind ?? AutomationScheduleKind.daily;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rootController.dispose();
    _olderThanDaysController.dispose();
    _largerThanMbController.dispose();
    _extensionsController.dispose();
    _intervalHoursController.dispose();
    super.dispose();
  }

  Future<void> _performDryRunPreview() async {
    setState(() {
      _isDryRunning = true;
      _errorMessage = null;
    });

    try {
      final api = ref.read(apiServiceProvider);
      if (widget.existingRule != null) {
        final preview = await api.dryRunAutomationRule(widget.existingRule!.id);
        setState(() {
          _dryRunPreview = preview;
        });
      } else {
        final paths = [_rootController.text.trim()];
        final preview = await api.previewNuke(paths);
        setState(() {
          _dryRunPreview = preview;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      setState(() {
        _isDryRunning = false;
      });
    }
  }

  Future<void> _saveRule() async {
    final name = _nameController.text.trim();
    final root = _rootController.text.trim();
    final olderDays = int.tryParse(_olderThanDaysController.text.trim());
    final largerMb = int.tryParse(_largerThanMbController.text.trim());
    final largerBytes = largerMb != null ? largerMb * 1024 * 1024 : null;
    final exts = _extensionsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final timeString = '${_timeOfDay.hour.toString().padLeft(2, '0')}:${_timeOfDay.minute.toString().padLeft(2, '0')}:00';

    final request = {
      'name': name,
      'isEnabled': true,
      'root': root,
      'criteria': {
        'olderThanDays': olderDays,
        'largerThanBytes': largerBytes,
        'extensionAllowlist': exts.isNotEmpty ? exts : null,
        'pathContainsAny': null,
        'recurseSubdirectories': _recurseSubdirectories,
      },
      'schedule': {
        'kind': _scheduleKind.toSerializedString(),
        'intervalHours': int.tryParse(_intervalHoursController.text.trim()) ?? 24,
        'timeOfDay': timeString,
        'dayOfWeek': _dayOfWeek,
      }
    };

    try {
      final notifier = ref.read(automationRulesProvider.notifier);
      AutomationRule saved;
      if (widget.existingRule != null) {
        saved = await notifier.updateRule(widget.existingRule!.id, request);
      } else {
        saved = await notifier.createRule(request);
      }

      if (_armImmediately) {
        await notifier.arm(saved.id);
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: HudTheme.bgPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: HudTheme.primaryBorder.withValues(alpha: 0.5)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildStepIndicator(),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: _buildStepBody(),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: const TextStyle(
                    fontFamily: HudTheme.fontCore,
                    color: HudTheme.accentRed,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _buildNavigationButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Icon(Icons.security, color: HudTheme.accentCyan, size: 20),
            const SizedBox(width: 8),
            Text(
              widget.existingRule != null ? 'EDIT_AUTOMATION_RULE' : 'NEW_AUTOMATION_RULE',
              style: HudTheme.headerCyan,
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.close, color: HudTheme.textDim, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildStepIndicator() {
    final steps = ['ROOT', 'CRITERIA', 'SCHEDULE', 'DRY_RUN', 'ARM'];
    return Row(
      children: List.generate(steps.length, (index) {
        final isActive = index == _currentStep;
        final isDone = index < _currentStep;
        return Expanded(
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone
                      ? HudTheme.accentGreen
                      : (isActive ? HudTheme.accentCyan : Colors.transparent),
                  border: Border.all(
                    color: isDone
                        ? HudTheme.accentGreen
                        : (isActive ? HudTheme.accentCyan : HudTheme.textDim),
                  ),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontFamily: HudTheme.fontCore,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: (isActive || isDone) ? HudTheme.bgBase : HudTheme.textDim,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  steps[index],
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: HudTheme.fontCore,
                    fontSize: 10,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    color: isActive ? HudTheme.accentCyan : HudTheme.textDim,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              if (index < steps.length - 1)
                Container(
                  width: 12,
                  height: 1,
                  color: HudTheme.textDim.withValues(alpha: 0.3),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildStepBody() {
    switch (_currentStep) {
      case 0:
        return _buildStepRoot();
      case 1:
        return _buildStepCriteria();
      case 2:
        return _buildStepSchedule();
      case 3:
        return _buildStepDryRun();
      case 4:
      default:
        return _buildStepArm();
    }
  }

  Widget _buildStepRoot() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'RULE NAME',
          style: HudTheme.labelMuted,
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _nameController,
          style: const TextStyle(
            fontFamily: HudTheme.fontCore,
            color: HudTheme.textMain,
            fontSize: 13,
          ),
          decoration: _inputDecoration('e.g. TEMP CLEANUP'),
        ),
        const SizedBox(height: 16),
        const Text(
          'CLEANUP ROOT PATH',
          style: HudTheme.labelMuted,
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _rootController,
          style: const TextStyle(
            fontFamily: HudTheme.fontCore,
            color: HudTheme.textMain,
            fontSize: 13,
          ),
          decoration: _inputDecoration('e.g. C:\\Users\\User\\AppData\\Local\\Temp'),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            _presetChip('Platform %TEMP%', Platform.isWindows ? (Platform.environment['TEMP'] ?? 'C:\\Temp') : '/tmp'),
            _presetChip('User .cache', Platform.isWindows ? 'C:\\Users\\User\\.cache' : '~/.cache'),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: HudTheme.accentAmber.withValues(alpha: 0.1),
            border: Border.all(color: HudTheme.accentAmber.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(
            children: [
              Icon(Icons.shield_outlined, color: HudTheme.accentAmber, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'SAFETY RAIL: Root paths are strictly allowlist-checked. Drive roots (C:\\), Windows, and Program Files are rejected outright.',
                  style: TextStyle(
                    fontFamily: HudTheme.fontCore,
                    color: HudTheme.accentAmber,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _presetChip(String label, String path) {
    return ActionChip(
      backgroundColor: HudTheme.bgBase,
      side: BorderSide(color: HudTheme.accentCyan.withValues(alpha: 0.4)),
      label: Text(
        label,
        style: const TextStyle(
          fontFamily: HudTheme.fontCore,
          color: HudTheme.accentCyan,
          fontSize: 11,
        ),
      ),
      onPressed: () {
        setState(() {
          _rootController.text = path;
        });
      },
    );
  }

  Widget _buildStepCriteria() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('OLDER THAN (DAYS)', style: HudTheme.labelMuted),
        const SizedBox(height: 4),
        TextField(
          controller: _olderThanDaysController,
          keyboardType: TextInputType.number,
          style: const TextStyle(
            fontFamily: HudTheme.fontCore,
            color: HudTheme.textMain,
            fontSize: 13,
          ),
          decoration: _inputDecoration('e.g. 7 (days)'),
        ),
        const SizedBox(height: 14),
        const Text('MINIMUM SIZE (MB, OPTIONAL)', style: HudTheme.labelMuted),
        const SizedBox(height: 4),
        TextField(
          controller: _largerThanMbController,
          keyboardType: TextInputType.number,
          style: const TextStyle(
            fontFamily: HudTheme.fontCore,
            color: HudTheme.textMain,
            fontSize: 13,
          ),
          decoration: _inputDecoration('e.g. 10 (leave empty for any size)'),
        ),
        const SizedBox(height: 14),
        const Text('EXTENSION ALLOWLIST (COMMA SEPARATED)', style: HudTheme.labelMuted),
        const SizedBox(height: 4),
        TextField(
          controller: _extensionsController,
          style: const TextStyle(
            fontFamily: HudTheme.fontCore,
            color: HudTheme.textMain,
            fontSize: 13,
          ),
          decoration: _inputDecoration('e.g. .tmp, .log, .bak'),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'RECURSE SUBDIRECTORIES',
              style: TextStyle(
                fontFamily: HudTheme.fontCore,
                color: HudTheme.textMain,
                fontSize: 12,
              ),
            ),
            Switch(
              value: _recurseSubdirectories,
              activeColor: HudTheme.accentCyan,
              onChanged: (val) => setState(() => _recurseSubdirectories = val),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStepSchedule() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('RUN FREQUENCY', style: HudTheme.labelMuted),
        const SizedBox(height: 8),
        DropdownButtonFormField<AutomationScheduleKind>(
          value: _scheduleKind,
          dropdownColor: HudTheme.bgPanel,
          style: const TextStyle(
            fontFamily: HudTheme.fontCore,
            color: HudTheme.textMain,
            fontSize: 13,
          ),
          decoration: _inputDecoration('Frequency'),
          items: const [
            DropdownMenuItem(
              value: AutomationScheduleKind.daily,
              child: Text('DAILY', style: TextStyle(fontFamily: HudTheme.fontCore)),
            ),
            DropdownMenuItem(
              value: AutomationScheduleKind.weekly,
              child: Text('WEEKLY', style: TextStyle(fontFamily: HudTheme.fontCore)),
            ),
            DropdownMenuItem(
              value: AutomationScheduleKind.intervalHours,
              child: Text('HOURLY INTERVAL', style: TextStyle(fontFamily: HudTheme.fontCore)),
            ),
            DropdownMenuItem(
              value: AutomationScheduleKind.onAppStart,
              child: Text('ON APP START', style: TextStyle(fontFamily: HudTheme.fontCore)),
            ),
          ],
          onChanged: (val) {
            if (val != null) setState(() => _scheduleKind = val);
          },
        ),
        const SizedBox(height: 16),
        if (_scheduleKind == AutomationScheduleKind.daily || _scheduleKind == AutomationScheduleKind.weekly) ...[
          const Text('TIME OF DAY (UTC)', style: HudTheme.labelMuted),
          const SizedBox(height: 8),
          ListTile(
            tileColor: HudTheme.bgBase,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(color: HudTheme.textDim.withValues(alpha: 0.3)),
            ),
            title: Text(
              '${_timeOfDay.hour.toString().padLeft(2, '0')}:${_timeOfDay.minute.toString().padLeft(2, '0')} UTC',
              style: const TextStyle(
                fontFamily: HudTheme.fontCore,
                color: HudTheme.accentCyan,
                fontWeight: FontWeight.bold,
              ),
            ),
            trailing: const Icon(Icons.schedule, color: HudTheme.accentCyan),
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: _timeOfDay);
              if (picked != null) setState(() => _timeOfDay = picked);
            },
          ),
        ],
        if (_scheduleKind == AutomationScheduleKind.intervalHours) ...[
          const Text('INTERVAL HOURS', style: HudTheme.labelMuted),
          const SizedBox(height: 4),
          TextField(
            controller: _intervalHoursController,
            keyboardType: TextInputType.number,
            style: const TextStyle(
              fontFamily: HudTheme.fontCore,
              color: HudTheme.textMain,
              fontSize: 13,
            ),
            decoration: _inputDecoration('e.g. 24'),
          ),
        ],
      ],
    );
  }

  Widget _buildStepDryRun() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MANDATORY DRY-RUN PREVIEW',
          style: TextStyle(
            fontFamily: HudTheme.fontCore,
            color: HudTheme.accentAmber,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Every automated rule must execute a dry-run preview on real paths from your machine before it can be armed. No files will be deleted during this step.',
          style: TextStyle(
            fontFamily: HudTheme.fontCore,
            color: HudTheme.textDim,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 16),
        if (_dryRunPreview == null && !_isDryRunning)
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.play_circle_outline, size: 18, color: HudTheme.accentCyan),
              label: const Text(
                'RUN DRY-RUN PREVIEW NOW',
                style: TextStyle(
                  fontFamily: HudTheme.fontCore,
                  color: HudTheme.accentCyan,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: HudTheme.accentCyan.withValues(alpha: 0.15),
                side: const BorderSide(color: HudTheme.accentCyan),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              onPressed: _performDryRunPreview,
            ),
          )
        else if (_isDryRunning)
          const Center(
            child: CircularProgressIndicator(color: HudTheme.accentCyan),
          )
        else if (_dryRunPreview != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: HudTheme.bgBase,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: HudTheme.accentGreen.withValues(alpha: 0.6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: HudTheme.accentGreen, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'PREVIEW RESULT: WOULD DELETE ${_dryRunPreview!.totalFiles} FILES (${formatBytes(_dryRunPreview!.totalBytes)})',
                      style: const TextStyle(
                        fontFamily: HudTheme.fontCore,
                        color: HudTheme.accentGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Scope evaluated on ${_rootController.text.trim()}',
                  style: const TextStyle(
                    fontFamily: HudTheme.fontCore,
                    color: HudTheme.textDim,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStepArm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CONFIRM AND ARM RULE',
          style: TextStyle(
            fontFamily: HudTheme.fontCore,
            color: HudTheme.accentCyan,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: HudTheme.bgBase,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: HudTheme.primaryBorder.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RULE: ${_nameController.text.trim()}',
                style: const TextStyle(
                  fontFamily: HudTheme.fontCore,
                  color: HudTheme.textMain,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'ROOT: ${_rootController.text.trim()}',
                style: const TextStyle(
                  fontFamily: HudTheme.fontCore,
                  color: HudTheme.textDim,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'SCHEDULE: ${_scheduleKind.toSerializedString()}',
                style: const TextStyle(
                  fontFamily: HudTheme.fontCore,
                  color: HudTheme.textDim,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Divider(color: HudTheme.textDim.withValues(alpha: 0.2)),
              const SizedBox(height: 4),
              const Text(
                'MANDATORY RECYCLE BIN: Automated runs are moved to the OS recycle bin for safe recovery.',
                style: TextStyle(
                  fontFamily: HudTheme.fontCore,
                  color: HudTheme.accentGreen,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          value: _armImmediately,
          activeColor: HudTheme.accentGreen,
          tileColor: HudTheme.bgBase,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          title: const Text(
            'ARM THIS RULE IMMEDIATELY',
            style: TextStyle(
              fontFamily: HudTheme.fontCore,
              color: HudTheme.textMain,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: const Text(
            'Rule will run automatically on its schedule. If unchecked, rule remains un-armed until reviewed.',
            style: TextStyle(
              fontFamily: HudTheme.fontCore,
              color: HudTheme.textDim,
              fontSize: 11,
            ),
          ),
          onChanged: (val) => setState(() => _armImmediately = val ?? true),
        ),
      ],
    );
  }

  Widget _buildNavigationButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (_currentStep > 0)
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: HudTheme.textDim.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            onPressed: () => setState(() => _currentStep--),
            child: const Text(
              'BACK',
              style: TextStyle(
                fontFamily: HudTheme.fontCore,
                color: HudTheme.textMuted,
              ),
            ),
          )
        else
          const SizedBox.shrink(),
        Row(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'CANCEL',
                style: TextStyle(
                  fontFamily: HudTheme.fontCore,
                  color: HudTheme.textDim,
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (_currentStep < 4)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: HudTheme.accentCyan.withValues(alpha: 0.15),
                  side: const BorderSide(color: HudTheme.accentCyan),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                onPressed: () {
                  if (_currentStep == 0 && _rootController.text.trim().isEmpty) return;
                  if (_currentStep == 3 && _dryRunPreview == null) {
                    _performDryRunPreview();
                    return;
                  }
                  setState(() => _currentStep++);
                },
                child: Text(
                  _currentStep == 3 && _dryRunPreview == null ? 'PREVIEW' : 'NEXT',
                  style: const TextStyle(
                    fontFamily: HudTheme.fontCore,
                    color: HudTheme.accentCyan,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 16, color: HudTheme.accentGreen),
                label: const Text(
                  'SAVE & FINISH',
                  style: TextStyle(
                    fontFamily: HudTheme.fontCore,
                    color: HudTheme.accentGreen,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: HudTheme.accentGreen.withValues(alpha: 0.15),
                  side: const BorderSide(color: HudTheme.accentGreen),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                onPressed: _saveRule,
              ),
          ],
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontFamily: HudTheme.fontCore,
        color: HudTheme.textDim.withValues(alpha: 0.5),
        fontSize: 12,
      ),
      filled: true,
      fillColor: HudTheme.bgBase,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: HudTheme.textDim.withValues(alpha: 0.3)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(4)),
        borderSide: BorderSide(color: HudTheme.accentCyan),
      ),
    );
  }
}
