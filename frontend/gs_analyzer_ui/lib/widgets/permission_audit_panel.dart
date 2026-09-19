import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gs_analyzer_ui/models/permission_audit_models.dart';
import 'package:gs_analyzer_ui/providers/drive_stats_provider.dart';
import 'package:gs_analyzer_ui/providers/permission_audit_provider.dart';
import 'package:gs_analyzer_ui/core/theme/hudd_theme.dart';

class PermissionAuditPanel extends ConsumerWidget {
  const PermissionAuditPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auditState = ref.watch(permissionAuditProvider);
    final currentDrive = ref.watch(currentDriveProvider);

    return Container(
      padding: const EdgeInsets.all(16.0),
      child: auditState.when(
        data: (result) {
          if (result == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.security_outlined,
                    size: 48,
                    color: HudTheme.textDim,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'SECURITY AUDIT OFFLINE',
                    style: HudTheme.headerCyan.copyWith(
                      color: HudTheme.textDim,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scan for world-writable paths and orphaned executables.',
                    style: HudTheme.labelMuted,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      side: const BorderSide(color: HudTheme.accentCyan),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () {
                      if (currentDrive != null) {
                        ref
                            .read(permissionAuditProvider.notifier)
                            .runAudit(currentDrive.name);
                      }
                    },
                    icon: const Icon(
                      Icons.play_arrow,
                      color: HudTheme.accentCyan,
                    ),
                    label: Text(
                      'START SCAN',
                      style: HudTheme.bodyText.copyWith(
                        color: HudTheme.accentCyan,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return _buildResultList(context, result);
        },
        loading: () {
          final progress = ref.watch(auditProgressProvider);
          final scanned = progress?['scanned'] ?? 0;
          final issues = progress?['issues'] ?? 0;

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('AUDITING PERMISSIONS...', style: HudTheme.headerCyan),
                const SizedBox(height: 24),
                const SizedBox(
                  width: 250,
                  child: LinearProgressIndicator(
                    color: HudTheme.accentCyan,
                    backgroundColor: Colors.white10,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('SCANNED: ', style: HudTheme.labelMuted),
                    Text('$scanned', style: HudTheme.statCyan),
                    const SizedBox(width: 16),
                    Text('ISSUES: ', style: HudTheme.labelMuted),
                    Text(
                      '$issues',
                      style: HudTheme.statCyan.copyWith(
                        color: issues > 0
                            ? HudTheme.accentAmber
                            : HudTheme.statCyan.color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: HudTheme.accentRed),
                  ),
                  onPressed: () {
                    ref.read(permissionAuditProvider.notifier).cancelAudit();
                  },
                  icon: const Icon(Icons.close, color: HudTheme.accentRed),
                  label: Text('CANCEL SCAN', style: HudTheme.actionRed),
                ),
              ],
            ),
          );
        },
        error: (err, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: HudTheme.accentRed,
              ),
              const SizedBox(height: 16),
              Text('AUDIT FAILED', style: HudTheme.actionRed),
              const SizedBox(height: 8),
              Text(
                err.toString(),
                style: HudTheme.bodyText.copyWith(color: HudTheme.accentRed),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  side: const BorderSide(color: HudTheme.accentCyan),
                ),
                onPressed: () {
                  ref.read(permissionAuditProvider.notifier).reset();
                },
                icon: const Icon(Icons.refresh, color: HudTheme.accentCyan),
                label: Text(
                  'RESET',
                  style: HudTheme.bodyText.copyWith(color: HudTheme.accentCyan),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultList(BuildContext context, PermissionAuditResult result) {
    if (result.issues.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 48,
              color: HudTheme.accentGreen,
            ),
            const SizedBox(height: 16),
            Text(
              'NO ISSUES FOUND — PERMISSIONS LOOK CLEAN',
              style: HudTheme.headerCyan.copyWith(color: HudTheme.accentGreen),
            ),
          ],
        ),
      );
    }

    int high = result.issues.where((i) => i.severity == 'high').length;
    int medium = result.issues.where((i) => i.severity == 'medium').length;
    int low = result.issues.where((i) => i.severity == 'low').length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white10,
          child: Row(
            children: [
              Text(
                '${result.issues.length} ISSUES FOUND — ',
                style: HudTheme.bodyText.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                '$high HIGH, ',
                style: HudTheme.bodyText.copyWith(
                  color: HudTheme.accentRed,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$medium MEDIUM, ',
                style: HudTheme.bodyText.copyWith(
                  color: HudTheme.accentAmber,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '$low LOW',
                style: HudTheme.bodyText.copyWith(
                  color: HudTheme.accentGreen,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.separated(
            itemCount: result.issues.length,
            separatorBuilder: (context, index) =>
                const Divider(color: Colors.white10, height: 1),
            itemBuilder: (context, index) {
              final issue = result.issues[index];
              final Color badgeColor = _getSeverityColor(issue.severity);

              return ListTile(
                onTap: () => _showIssueDetailSheet(context, issue),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                leading: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(
                  issue.type.toUpperCase(),
                  style: HudTheme.bodyText.copyWith(
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
                subtitle: Text(
                  issue.path,
                  style: HudTheme.labelMuted,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: HudTheme.textDim,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'high':
        return HudTheme.accentRed;
      case 'medium':
        return HudTheme.accentAmber;
      case 'low':
      default:
        return HudTheme.accentGreen;
    }
  }

  void _showIssueDetailSheet(BuildContext context, PermissionIssue issue) {
    final badgeColor = _getSeverityColor(issue.severity);

    showModalBottomSheet(
      context: context,
      backgroundColor: HudTheme.bgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: badgeColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${issue.severity.toUpperCase()} SEVERITY',
                    style: HudTheme.headerCyan.copyWith(color: badgeColor),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('TYPE', style: HudTheme.labelMuted),
              const SizedBox(height: 4),
              Text(issue.type.toUpperCase(), style: HudTheme.bodyText),

              const SizedBox(height: 16),
              Text('DESCRIPTION', style: HudTheme.labelMuted),
              const SizedBox(height: 4),
              Text(issue.description, style: HudTheme.bodyText),

              const SizedBox(height: 16),
              Text('PATH', style: HudTheme.labelMuted),
              const SizedBox(height: 4),
              Text(issue.path, style: HudTheme.bodyText),

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    side: const BorderSide(color: HudTheme.accentCyan),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: issue.path));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Path copied to clipboard',
                          style: HudTheme.bodyText.copyWith(
                            color: HudTheme.bgBase,
                          ),
                        ),
                        backgroundColor: HudTheme.accentCyan,
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, color: HudTheme.accentCyan),
                  label: Text(
                    'COPY PATH',
                    style: HudTheme.bodyText.copyWith(
                      color: HudTheme.accentCyan,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
