import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/run_result.dart';

/// Drives the "กำลังวิ่ง" screen. Since there's no GPS/backend yet, distance
/// is simulated at a plausible easy-run pace so the UI has real numbers to
/// animate with.
class RunSessionNotifier extends ChangeNotifier {
  Timer? _timer;
  bool isRunning = false;
  bool isPaused = false;
  int elapsedSeconds = 0;
  double distanceKm = 0;

  final double goalDistanceKm = 5.0;
  final String goalPace = '7 min/km';

  RunResult? lastResult;

  void start() {
    isRunning = true;
    isPaused = false;
    elapsedSeconds = 0;
    distanceKm = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isPaused) return;
      elapsedSeconds += 1;
      // ~8.5 km/h mock easy pace.
      distanceKm += 8.5 / 3600;
      if (distanceKm >= goalDistanceKm) distanceKm = goalDistanceKm;
      notifyListeners();
    });
    notifyListeners();
  }

  void togglePause() {
    isPaused = !isPaused;
    notifyListeners();
  }

  RunResult stop() {
    _timer?.cancel();
    isRunning = false;
    final duration = Duration(seconds: elapsedSeconds);
    final paceMinPerKm = distanceKm > 0 ? (elapsedSeconds / 60) / distanceKm : 0;
    final mm = paceMinPerKm.floor();
    final ss = ((paceMinPerKm - mm) * 60).round().toString().padLeft(2, '0');
    lastResult = RunResult(
      distanceKm: double.parse(distanceKm.toStringAsFixed(2)),
      duration: duration,
      avgPace: distanceKm > 0 ? '$mm:$ss' : '--:--',
      calories: (distanceKm * 62).round(),
    );
    notifyListeners();
    return lastResult!;
  }

  String get elapsedLabel {
    final m = (elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final runProvider = ChangeNotifierProvider<RunSessionNotifier>((ref) => RunSessionNotifier());
