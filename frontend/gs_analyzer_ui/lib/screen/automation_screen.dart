import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:gs_analyzer_ui/models/automation_rule.dart';
import 'package:gs_analyzer_ui/providers/automation_provider.dart';
import 'package:gs_analyzer_ui/providers/hud_density_provider.dart';
import 'package:gs_analyzer_ui/utils/formatters.dart';
import 'package:gs_analyzer_ui/utils/hud_theme.dart';
import 'package:gs_analyzer_ui/widgets/rule_editor_dialog.dart';

class AutomationScreen extends ConsumerStatefulWidget {
  const AutomationScreen({super.key});

  @override
  ConsumerState<AutomationScreen> createState() => _AutomationScreenState();
}

class _AutomationScreenState extends ConsumerState<AutomationScreen> {
  @override
  Widget build(BuildContext context) {
    final rulesAsync = ref.watch(automationRulesProvider);
    final auditAsync = ref.watch(automationAuditProvider);
    final d = ref.watch(hudDensityProvider);

    return Material(
      color: HudTheme.bgBase,
      child: Container(
        color: HudTheme.bgBase,
        padding: EdgeInsets.all(d.panelPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            children: [
              const Icon(
                Icons.auto_mode_outlined,
                color: HudTheme.accentCyan,
                size: 22,
              ),
              const SizedBox(width: 10),
              const Text('AUTOMATION PROTOCOL', style: HudTheme.headerCyan),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16, color: HudTheme.accentCyan),
                label: const Text(
                  '+ NEW RULE',
                  style: TextStyle(
                    fontFamily: HudTheme.fontCore,
                    color: HudTheme.accentCyan,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: HudTheme.accentCyan.withValues(alpha: 0.15),
                  side: const BorderSide(color: HudTheme.accentCyan),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                onPressed: () => _openRuleEditor(context),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, color: HudTheme.textDim, size: 20),
                tooltip: 'Refresh',
                onPressed: () {
                  ref.read(automationRulesProvider.notifier).reload();
                  ref.read(auditRefreshTriggerProvider.notifier).state++;
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'SCHEDULED BACKGROUND CLEANUP & AUDIT LOG',
            style: HudTheme.labelMuted,
          ),
          SizedBox(height: d.gap * 2),

          // Main panels
          Expanded(
            flex: 5,
            child: _buildRulesPanel(rulesAsync),
          ),
          SizedBox(height: d.gap * 2),
          Expanded(
            flex: 5,
            child: _buildAuditPanel(auditAsync),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildRulesPanel(AsyncValue<List<AutomationRule>> rulesAsync) {
    return Container(
      decoration: HudTheme.hudPanelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.rule_outlined, color: HudTheme.accentCyan, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'RULES',
                      style: TextStyle(
                        fontFamily: HudTheme.fontCore,
                        color: HudTheme.accentCyan,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _openRuleEditor(context),
                  child: const Text(
                    '+ NEW RULE',
                    style: TextStyle(
                      fontFamily: HudTheme.fontCore,
                      color: HudTheme.accentCyan,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: rulesAsync.when(
              data: (rules) {
                if (rules.isEmpty) {
                  return const Center(
                    child: Text(
                      'NO AUTOMATION RULES CONFIGURED — CLICK + NEW RULE TO ADD ONE',
                      style: TextStyle(
                        fontFamily: HudTheme.fontCore,
                        color: HudTheme.textDim,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: rules.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _buildRuleCard(rules[index]),
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: HudTheme.accentCyan),
              ),
              error: (err, _) => Center(
                child: Text(
                  'ERROR: $err',
                  style: const TextStyle(
                    fontFamily: HudTheme.fontCore,
                    color: HudTheme.accentRed,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleCard(AutomationRule rule) {
    final scheduleLabel = rule.schedule.kind.toSerializedString().toUpperCase();
    final criteriaSummary = rule.criteria.olderThanDays != null
        ? '> ${rule.criteria.olderThanDays}d'
        : (rule.criteria.largerThanBytes != null
            ? '> ${formatBytes(rule.criteria.largerThanBytes!)}'
            : 'ALL FILES');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: HudTheme.bgBase,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: !rule.isArmed
              ? HudTheme.accentAmber.withValues(alpha: 0.5)
              : (rule.isEnabled
                  ? HudTheme.accentCyan.withValues(alpha: 0.3)
                  : Colors.white10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                rule.isEnabled ? Icons.circle : Icons.circle_outlined,
                color: rule.isEnabled ? HudTheme.accentGreen : HudTheme.textDim,
                size: 12,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  rule.name.toUpperCase(),
                  style: const TextStyle(
                    fontFamily: HudTheme.fontCore,
                    color: HudTheme.textMain,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Text(
                '${rule.root} · $criteriaSummary',
                style: const TextStyle(
                  fontFamily: HudTheme.fontCore,
                  color: HudTheme.textDim,
                  fontSize: 11,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: HudTheme.bgPanel,
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(
                    color: HudTheme.accentCyan.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  scheduleLabel,
                  style: const TextStyle(
                    fontFamily: HudTheme.fontCore,
                    color: HudTheme.accentCyan,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildRuleActionsMenu(rule),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (!rule.isArmed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: HudTheme.accentAmber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color: HudTheme.accentAmber.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.warning_amber,
                        color: HudTheme.accentAmber,
                        size: 12,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'NOT ARMED — REVIEW DRY RUN',
                        style: TextStyle(
                          fontFamily: HudTheme.fontCore,
                          color: HudTheme.accentAmber,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  rule.lastRunUtc != null
                      ? 'Last run: ${DateFormat('yyyy-MM-dd HH:mm').format(rule.lastRunUtc!.toLocal())}'
                      : 'Never run',
                  style: const TextStyle(
                    fontFamily: HudTheme.fontCore,
                    color: HudTheme.textDim,
                    fontSize: 11,
                  ),
                ),
              if (rule.nextRunUtc != null && rule.isArmed)
                Text(
                  'Next run: ${DateFormat('yyyy-MM-dd HH:mm').format(rule.nextRunUtc!.toLocal())}',
                  style: const TextStyle(
                    fontFamily: HudTheme.fontCore,
                    color: HudTheme.textDim,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRuleActionsMenu(AutomationRule rule) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz, color: HudTheme.textDim, size: 18),
      color: HudTheme.bgPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: HudTheme.primaryBorder.withValues(alpha: 0.3)),
      ),
      onSelected: (val) async {
        final notifier = ref.read(automationRulesProvider.notifier);
        switch (val) {
          case 'run':
            _showSnackBar('Triggering rule run for "${rule.name}"...');
            await notifier.runNow(rule.id);
            break;
          case 'dryrun':
            _showSnackBar('Starting dry-run preview for "${rule.name}"...');
            await notifier.dryRun(rule.id);
            break;
          case 'arm':
            await notifier.arm(rule.id);
            _showSnackBar('Rule "${rule.name}" has been ARMED');
            break;
          case 'edit':
            _openRuleEditor(context, rule);
            break;
          case 'delete':
            await notifier.deleteRule(rule.id);
            _showSnackBar('Deleted rule "${rule.name}"');
            break;
        }
      },
      itemBuilder: (context) => [
        if (rule.isArmed)
          const PopupMenuItem(
            value: 'run',
            child: Row(
              children: [
                Icon(Icons.play_arrow, color: HudTheme.accentGreen, size: 16),
                SizedBox(width: 8),
                Text(
                  'RUN NOW',
                  style: TextStyle(
                    fontFamily: HudTheme.fontCore,
                    color: HudTheme.textMain,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'dryrun',
          child: Row(
            children: [
              Icon(Icons.remove_red_eye_outlined, color: HudTheme.accentCyan, size: 16),
              SizedBox(width: 8),
              Text(
                'DRY RUN PREVIEW',
                style: TextStyle(
                  fontFamily: HudTheme.fontCore,
                  color: HudTheme.textMain,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        if (!rule.isArmed)
          const PopupMenuItem(
            value: 'arm',
            child: Row(
              children: [
                Icon(Icons.security, color: HudTheme.accentAmber, size: 16),
                SizedBox(width: 8),
                Text(
                  'ARM RULE',
                  style: TextStyle(
                    fontFamily: HudTheme.fontCore,
                    color: HudTheme.accentAmber,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit, color: HudTheme.accentCyan, size: 16),
              SizedBox(width: 8),
              Text(
                'EDIT',
                style: TextStyle(
                  fontFamily: HudTheme.fontCore,
                  color: HudTheme.textMain,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline, color: HudTheme.accentRed, size: 16),
              SizedBox(width: 8),
              Text(
                'DELETE',
                style: TextStyle(
                  fontFamily: HudTheme.fontCore,
                  color: HudTheme.accentRed,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAuditPanel(AsyncValue<List<AutomationAuditEntry>> auditAsync) {
    return Container(
      decoration: HudTheme.hudPanelDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.history_outlined, color: HudTheme.accentCyan, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'AUDIT LOG',
                      style: TextStyle(
                        fontFamily: HudTheme.fontCore,
                        color: HudTheme.accentCyan,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                Consumer(
                  builder: (context, ref, _) {
                    final days = ref.watch(auditDaysProvider);
                    return DropdownButton<int>(
                      value: days,
                      dropdownColor: HudTheme.bgPanel,
                      underline: const SizedBox.shrink(),
                      style: const TextStyle(
                        fontFamily: HudTheme.fontCore,
                        color: HudTheme.accentCyan,
                        fontSize: 11,
                      ),
                      icon: const Icon(
                        Icons.arrow_drop_down,
                        color: HudTheme.accentCyan,
                        size: 18,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 7,
                          child: Text(
                            'PAST 7 DAYS',
                            style: TextStyle(fontFamily: HudTheme.fontCore),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 30,
                          child: Text(
                            'PAST 30 DAYS',
                            style: TextStyle(fontFamily: HudTheme.fontCore),
                          ),
                        ),
                        DropdownMenuItem(
                          value: 90,
                          child: Text(
                            'PAST 90 DAYS',
                            style: TextStyle(fontFamily: HudTheme.fontCore),
                          ),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          ref.read(auditDaysProvider.notifier).state = val;
                        }
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: auditAsync.when(
              data: (entries) {
                if (entries.isEmpty) {
                  return const Center(
                    child: Text(
                      'NO AUDIT ENTRIES RECORDED',
                      style: TextStyle(
                        fontFamily: HudTheme.fontCore,
                        color: HudTheme.textDim,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) =>
                      const Divider(color: Colors.white10, height: 8),
                  itemBuilder: (context, index) {
                    final e = entries[index];
                    final dateStr = DateFormat('dd MMM HH:mm')
                        .format(e.startedUtc.toLocal())
                        .toUpperCase();
                    final bytesStr = formatBytes(e.bytesFreed);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            dateStr,
                            style: const TextStyle(
                              fontFamily: HudTheme.fontCore,
                              color: HudTheme.textDim,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              e.ruleName.toUpperCase(),
                              style: const TextStyle(
                                fontFamily: HudTheme.fontCore,
                                color: HudTheme.textMain,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Text(
                            e.isDryRun
                                ? 'DRY-RUN: ${e.matchedCount} files · $bytesStr'
                                : (e.wasAborted
                                    ? 'ABORTED — ${e.abortReason ?? 'FAILED'}'
                                    : '${e.deletedCount} files · $bytesStr'),
                            style: TextStyle(
                              fontFamily: HudTheme.fontCore,
                              color: e.wasAborted
                                  ? HudTheme.accentRed
                                  : (e.isDryRun
                                      ? HudTheme.accentCyan
                                      : HudTheme.textDim),
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            e.wasAborted
                                ? Icons.warning_amber
                                : Icons.check_circle_outline,
                            color: e.wasAborted
                                ? HudTheme.accentAmber
                                : HudTheme.accentGreen,
                            size: 16,
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(color: HudTheme.accentCyan),
              ),
              error: (err, _) => Center(
                child: Text(
                  'ERROR: $err',
                  style: const TextStyle(
                    fontFamily: HudTheme.fontCore,
                    color: HudTheme.accentRed,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openRuleEditor(BuildContext context, [AutomationRule? existing]) {
    showDialog(
      context: context,
      builder: (_) => RuleEditorDialog(existingRule: existing),
    );
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(
            fontFamily: HudTheme.fontCore,
            color: HudTheme.textMain,
          ),
        ),
        backgroundColor: HudTheme.bgPanel,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: HudTheme.primaryBorder.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(4),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
