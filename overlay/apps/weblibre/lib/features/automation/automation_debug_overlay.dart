import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:weblibre/core/routing/routes.dart';
import 'automation_diagnostics.dart';

class AutomationDebugOverlay extends ConsumerWidget {
  final Widget child;
  const AutomationDebugOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const automationEnabled = bool.fromEnvironment('BROWSER_AUTOMATION_ENABLED', defaultValue: false);
    if (!kDebugMode && !automationEnabled) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Keep browser/GeckoView content in its own raster layer so the
        // diagnostics FAB and its transient animations do not invalidate the
        // full browser surface on every frame.
        RepaintBoundary(child: child),
        Positioned(

          right: 14,
          bottom: 92,
          child: SafeArea(
            child: RepaintBoundary(
              child: FloatingActionButton.extended(
              heroTag: 'browser-automation-debug',
              tooltip: 'Automation',
              onPressed: () {
                AutomationDiagnostics.record('Dashboard button tapped');
                // Use this overlay's current browser-page context. Resolving the
                // router's root navigator context here can attach the sheet to the
                // wrong route and make the tap appear to leave the active page.
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => const _AutomationDashboard(),
                );
              },
                icon: const Icon(Icons.smart_toy_outlined),
                label: const Text('Automation'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AutomationDashboard extends StatefulWidget {
  const _AutomationDashboard();

  @override
  State<_AutomationDashboard> createState() => _AutomationDashboardState();
}

class _AutomationDashboardState extends State<_AutomationDashboard> {
  final TextEditingController _urlController =
      TextEditingController(text: 'https://innovatecg.in/voting');
  bool _busy = false;
  String _csvSummary = 'No CSV imported';
  int? _csvRows;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _openUrl() async {
    final raw = _urlController.text.trim();
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'https://$raw');
    if (uri == null || !uri.hasAuthority ||
        !{'http', 'https'}.contains(uri.scheme)) {
      AutomationDiagnostics.record('Open URL rejected: invalid URL');
      _message('Enter a valid http/https URL');
      return;
    }
    AutomationDiagnostics.record('Open URL tapped: ${uri.host}');
    try {
      if (!mounted) return;
      final router = GoRouter.of(context);
      final location = SearchRoute(
        tabType: TabType.regular,
        searchText: uri.toString(),
        autoSubmitSearch: true,
      ).location;
      Navigator.of(context).pop();
      router.go(location);
      AutomationDiagnostics.record('Browser navigation requested: ${uri.host}');
    } catch (error, stack) {
      AutomationDiagnostics.record('Browser navigation failed', error: error, stackTrace: stack);
      _message('Navigation failed: $error');
    }
  }

  Future<void> _importCsv() async {
    AutomationDiagnostics.record('CSV import tapped');
    setState(() => _busy = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );
      if (files.isEmpty) {
        AutomationDiagnostics.record('CSV import cancelled');
        return;
      }
      final file = files.single;
      final bytes = await file.readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: false);
      final rows = _parseCsv(text);
      if (rows.isEmpty) throw const FormatException('CSV is empty');
      final headers = rows.first.map((v) => v.trim().toLowerCase()).toList();
      final missing = const ['name', 'email', 'phone']
          .where((required) => !headers.contains(required)).toList();
      if (missing.isNotEmpty) {
        throw FormatException('Required columns missing: ${missing.join(', ')}');
      }
      final nonEmpty = rows.skip(1).where((r) => r.any((v) => v.trim().isNotEmpty)).length;
      _csvRows = nonEmpty;
      _csvSummary = '${file.name} • $nonEmpty data rows • required columns present';
      AutomationDiagnostics.record('CSV inspected: ${file.name}; rows=$nonEmpty; headers=${headers.join(',')}');
      if (mounted) setState(() {});
    } catch (error, stack) {
      AutomationDiagnostics.record('CSV import/parse failed', error: error, stackTrace: stack);
      _message('CSV error: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<List<String>> _parseCsv(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (quoted) {
        if (c == '"' && i + 1 < input.length && input[i + 1] == '"') {
          cell.write('"');
          i++;
        } else if (c == '"') {
          quoted = false;
        } else {
          cell.write(c);
        }
      } else if (c == '"' && cell.isEmpty) {
        quoted = true;
      } else if (c == ',') {
        row.add(cell.toString());
        cell.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
        row.add(cell.toString());
        cell.clear();
        if (row.any((v) => v.isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        cell.write(c);
      }
    }
    if (quoted) throw const FormatException('Unclosed quoted CSV field');
    row.add(cell.toString());
    if (row.any((v) => v.isNotEmpty)) rows.add(row);
    return rows;
  }

  Future<void> _copyLogs() async {
    AutomationDiagnostics.record('Copy logs tapped');
    await Clipboard.setData(ClipboardData(text: AutomationDiagnostics.exportText()));
    if (mounted) _message('Logs copied to clipboard');
  }

  Future<void> _shareLogs() async {
    AutomationDiagnostics.record('Export logs tapped');
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/browser-automation-${DateTime.now().millisecondsSinceEpoch}.log');
      await file.writeAsString(AutomationDiagnostics.exportText(), flush: true);
      await SharePlus.instance.share(ShareParams(
        title: 'Browser Automation diagnostics',
        text: 'Debug diagnostics log',
        files: [XFile(file.path, mimeType: 'text/plain')],
      ));
    } catch (error, stack) {
      AutomationDiagnostics.record('Log export failed', error: error, stackTrace: stack);
      if (mounted) _message('Log export failed: $error');
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, scrollController) => Material(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: [
            Center(child: Container(width: 42, height: 4,
              decoration: BoxDecoration(color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(8)))),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.bug_report_outlined),
              const SizedBox(width: 10),
              Expanded(child: Text('Browser Automation',
                style: theme.textTheme.titleLarge)),
              const Chip(label: Text('CI BUILD')),
            ]),
            const SizedBox(height: 16),
            Text('Open website', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'https://example.com',
                prefixIcon: Icon(Icons.link),
              ),
              onSubmitted: (_) => _openUrl(),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _openUrl,
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Open in browser'),
            ),
            const Divider(height: 28),
            Text('CSV structure check', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('Reads the CSV locally and checks required headers only. It does not submit or transmit contact records.'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _importCsv,
              icon: const Icon(Icons.upload_file),
              label: Text(_busy ? 'Reading CSV…' : 'Choose CSV'),
            ),
            Text(_csvSummary, style: theme.textTheme.bodySmall),
            if (_csvRows != null) Text('Rows detected: $_csvRows'),
            const Divider(height: 28),
            Row(children: [
              Expanded(child: Text('Diagnostic log', style: theme.textTheme.titleMedium)),
              IconButton(tooltip: 'Copy logs', onPressed: _copyLogs,
                icon: const Icon(Icons.copy)),
              IconButton(tooltip: 'Export log file', onPressed: _shareLogs,
                icon: const Icon(Icons.ios_share)),
            ]),
            ValueListenableBuilder<int>(
              valueListenable: AutomationDiagnostics.revision,
              builder: (context, _, __) {
                final entries = AutomationDiagnostics.entries.reversed.take(80).toList();
                return Container(
                  constraints: const BoxConstraints(minHeight: 110, maxHeight: 300),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: entries.isEmpty
                      ? const Text('No events captured.')
                      : SelectableText(entries.join('\n\n'),
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                );
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                AutomationDiagnostics.clear();
                setState(() {});
              },
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Clear log'),
            ),
          ],
        ),
      ),
    );
  }
}
