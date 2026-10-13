import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gs_analyzer_ui/models/extension_breakdown_model.dart';
import 'package:gs_analyzer_ui/models/watcher_event.dart';
import 'package:gs_analyzer_ui/utils/theme/hud_theme_context.dart';

class CsvExporter {
  static Future<void> exportExtensionBreakdown(
    BuildContext context,
    List<ExtensionBreakdownItem> items,
  ) async {
    try {
      final hud = context.hudTheme;
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile == null) {
        throw Exception('Could not locate user profile directory.');
      }

      var targetDir = Directory('$userProfile\\Downloads');
      if (!await targetDir.exists()) {
        targetDir = Directory('$userProfile\\Desktop');
        if (!await targetDir.exists()) {
          throw Exception('Could not locate Downloads or Desktop folder.');
        }
      }

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File('${targetDir.path}\\ExtensionBreakdown_$timestamp.csv');

      final buffer = StringBuffer();
      // CSV Header
      buffer.writeln(
        'Extension,Category,File Count,Total Size (Bytes),Size Formatted,% of Disk,Avg Size (Bytes),Avg Size Formatted,Largest File Bytes,Largest Size Formatted,Largest File Path',
      );

      // CSV Rows
      for (final item in items) {
        final row = [
          _escape(item.ext),
          _escape(item.category),
          item.fileCount,
          item.totalBytes,
          _escape(item.sizeFormatted),
          item.percentOfDisk,
          item.averageFileSizeBytes,
          _escape(item.averageSizeFormatted),
          item.largestFileBytes,
          _escape(item.largestSizeFormatted),
          _escape(item.largestFilePath),
        ];
        buffer.writeln(row.join(','));
      }

      await file.writeAsString(buffer.toString());

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to ${file.path}', style: hud.body),
            backgroundColor: hud.panel,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final hud = context.hudTheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to export CSV: $e',
              style: hud.actionRed,
            ),
            backgroundColor: hud.panel,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  static Future<void> exportWatcherEventLog(
    BuildContext context,
    List<WatcherEvent> events,
  ) async {
    try {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile == null) {
        throw Exception('Could not locate user profile directory.');
      }

      var targetDir = Directory('$userProfile\\Downloads');
      if (!await targetDir.exists()) {
        targetDir = Directory('$userProfile\\Desktop');
        if (!await targetDir.exists()) {
          throw Exception('Could not locate Downloads or Desktop folder.');
        }
      }

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File('${targetDir.path}\\WatcherEventLog_$timestamp.csv');

      final buffer = StringBuffer();
      // CSV Header
      buffer.writeln('Timestamp,Kind,Path,OldPath,IsDirectory,Occurrences');

      // CSV Rows
      for (final event in events) {
        final row = [
          _escape(event.timestamp.toUtc().toIso8601String()),
          _escape(event.kind.name),
          _escape(event.path),
          _escape(event.oldPath ?? ''),
          event.isDirectory.toString(),
          event.occurrences.toString(),
        ];
        buffer.writeln(row.join(','));
      }

      await file.writeAsString(buffer.toString());

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to ${file.path}', style: context.hudTheme.body),
            backgroundColor: context.hudTheme.panel,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to export CSV: $e',
              style: context.hudTheme.actionRed,
            ),
            backgroundColor: context.hudTheme.panel,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  static String _escape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
