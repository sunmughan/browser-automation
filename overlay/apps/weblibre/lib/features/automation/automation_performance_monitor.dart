import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'automation_diagnostics.dart';

/// Debug-only, low-overhead frame-jank sampler.
class AutomationPerformanceMonitor {
  AutomationPerformanceMonitor._();
  static Timer? _reportTimer;
  static int _slowFrames = 0, _severeFrames = 0;
  static int _maxFrameMs = 0, _maxBuildMs = 0, _maxRasterMs = 0;

  static void start() {
    if (!kDebugMode || _reportTimer != null) return;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _reportTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_slowFrames == 0) return;
      AutomationDiagnostics.record(
        'PERF 15s: slow_frames=$_slowFrames (>32ms), '
        'severe_frames=$_severeFrames (>50ms), '
        'max_frame=${_maxFrameMs}ms, max_build=${_maxBuildMs}ms, '
        'max_raster=${_maxRasterMs}ms',
      );
      _slowFrames = 0; _severeFrames = 0;
      _maxFrameMs = 0; _maxBuildMs = 0; _maxRasterMs = 0;
    });
    AutomationDiagnostics.record('Performance sampler started (debug only)');
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final frameMs = timing.totalSpan.inMilliseconds;
      if (frameMs <= 32) continue;
      _slowFrames++;
      if (frameMs > 50) _severeFrames++;
      if (frameMs > _maxFrameMs) _maxFrameMs = frameMs;
      final buildMs = timing.buildDuration.inMilliseconds;
      final rasterMs = timing.rasterDuration.inMilliseconds;
      if (buildMs > _maxBuildMs) _maxBuildMs = buildMs;
      if (rasterMs > _maxRasterMs) _maxRasterMs = rasterMs;
    }
  }
}