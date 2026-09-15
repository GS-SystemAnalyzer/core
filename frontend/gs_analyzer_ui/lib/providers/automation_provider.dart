import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:gs_analyzer_ui/models/automation_rule.dart';
import 'package:gs_analyzer_ui/models/nuke_preview.dart';
import 'package:gs_analyzer_ui/services/api_service.dart';
import 'package:gs_analyzer_ui/utils/logger.dart';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

class AutomationRulesNotifier extends AsyncNotifier<List<AutomationRule>> {
  ApiService get _api => ref.read(apiServiceProvider);

  @override
  FutureOr<List<AutomationRule>> build() async {
    return fetchRules();
  }

  Future<List<AutomationRule>> fetchRules() async {
    try {
      return await _api.getAutomationRules();
    } catch (e) {
      appLogger.e('Failed to load automation rules: $e');
      rethrow;
    }
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => fetchRules());
  }

  Future<AutomationRule> createRule(Map<String, dynamic> data) async {
    try {
      final created = await _api.createAutomationRule(data);
      await reload();
      return created;
    } catch (e) {
      appLogger.e('Failed to create automation rule: $e');
      rethrow;
    }
  }

  Future<AutomationRule> updateRule(String id, Map<String, dynamic> data) async {
    try {
      final updated = await _api.updateAutomationRule(id, data);
      await reload();
      return updated;
    } catch (e) {
      appLogger.e('Failed to update automation rule: $e');
      rethrow;
    }
  }

  Future<void> deleteRule(String id) async {
    try {
      await _api.deleteAutomationRule(id);
      await reload();
    } catch (e) {
      appLogger.e('Failed to delete automation rule: $e');
      rethrow;
    }
  }

  Future<NukePreviewResponse> dryRun(String id) async {
    try {
      final preview = await _api.dryRunAutomationRule(id);
      ref.read(auditRefreshTriggerProvider.notifier).state++;
      return preview;
    } catch (e) {
      appLogger.e('Failed to dry-run rule: $e');
      rethrow;
    }
  }

  Future<AutomationRule> arm(String id) async {
    try {
      final armed = await _api.armAutomationRule(id);
      await reload();
      return armed;
    } catch (e) {
      appLogger.e('Failed to arm rule: $e');
      rethrow;
    }
  }

  Future<AutomationAuditEntry> runNow(String id) async {
    try {
      final result = await _api.runAutomationRule(id);
      await reload();
      ref.read(auditRefreshTriggerProvider.notifier).state++;
      return result;
    } catch (e) {
      appLogger.e('Failed to run rule now: $e');
      rethrow;
    }
  }
}

final automationRulesProvider =
    AsyncNotifierProvider<AutomationRulesNotifier, List<AutomationRule>>(
  AutomationRulesNotifier.new,
);

final auditDaysProvider = StateProvider<int>((ref) => 30);
final auditRefreshTriggerProvider = StateProvider<int>((ref) => 0);

final automationAuditProvider = FutureProvider<List<AutomationAuditEntry>>((ref) async {
  ref.watch(auditRefreshTriggerProvider);
  final days = ref.watch(auditDaysProvider);
  final api = ref.watch(apiServiceProvider);
  return api.getAutomationAudit(days);
});
