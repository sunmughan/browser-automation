import 'package:flutter/foundation.dart';

class AutomationDiagnostics {
  AutomationDiagnostics._();

  static const int _maxEntries = 1200;
  static final List<String> _entries = <String>[];
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static void record(String message, {Object? error, StackTrace? stackTrace}) {
    final timestamp = DateTime.now().toIso8601String();
    final buffer = StringBuffer('[$timestamp] $message');
    if (error != null) buffer.write('\nERROR: $error');
    if (stackTrace != null) buffer.write('\nSTACK: $stackTrace');
    _entries.add(buffer.toString());
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
    revision.value++;
    debugPrint('[BrowserAutomation] $message');
    if (error != null) debugPrint('[BrowserAutomation] ERROR: $error');
    if (stackTrace != null) debugPrintStack(stackTrace: stackTrace);
  }

  static List<String> get entries => List.unmodifiable(_entries);

  static String exportText() => _entries.isEmpty
      ? 'No diagnostic events captured yet.'
      : _entries.join('\n\n');

  static void clear() {
    _entries.clear();
    revision.value++;
    record('Diagnostic log cleared');
  }
}
