#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "upstream"
APP = ROOT / "apps/weblibre/lib"
main_app = APP / "presentation/main_app.dart"
main_dart = APP / "main.dart"

def replace_once(path: Path, old: str, new: str):
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Expected exactly one patch anchor in {path}, found {count}: {old!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")

# The diagnostics overlay is attached only to the debug build's router child.
replace_once(
    main_app,
    "import 'package:weblibre/presentation/utils/app_initialization_l10n.dart';",
    "import 'package:weblibre/presentation/utils/app_initialization_l10n.dart';\n"
    "import 'package:weblibre/features/automation/automation_debug_overlay.dart';",
)
replace_once(
    main_app,
    "child: child ?? const SizedBox.shrink(),",
    "child: AutomationDebugOverlay(child: child ?? const SizedBox.shrink()),",
)

# Preserve WebLibre's existing handlers while duplicating each failure into our
# bounded in-memory diagnostic log for easy copy/export from the overlay.
replace_once(
    main_dart,
    "import 'package:weblibre/core/logger.dart';",
    "import 'package:weblibre/core/logger.dart';\n"
    "import 'package:weblibre/features/automation/automation_diagnostics.dart';",
)
replace_once(
    main_dart,
    "FlutterError.onError = (e) {\n    logger.e(e.toString(), error: e.exception, stackTrace: e.stack);\n  };",
    "FlutterError.onError = (e) {\n"
    "    AutomationDiagnostics.record('Flutter framework error', error: e.exception, stackTrace: e.stack);\n"
    "    logger.e(e.toString(), error: e.exception, stackTrace: e.stack);\n"
    "  };",
)
replace_once(
    main_dart,
    "PlatformDispatcher.instance.onError = (error, stack) {\n    logger.e('Unhandled Error', error: error, stackTrace: stack);\n    return true;\n  };",
    "PlatformDispatcher.instance.onError = (error, stack) {\n"
    "    AutomationDiagnostics.record('Unhandled platform error', error: error, stackTrace: stack);\n"
    "    logger.e('Unhandled Error', error: error, stackTrace: stack);\n"
    "    return true;\n"
    "  };",
)
print("Applied Browser Automation debug overlay and global error capture.")
