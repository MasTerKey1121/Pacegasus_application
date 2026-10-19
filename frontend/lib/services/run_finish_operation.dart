import 'dart:async';
import 'package:flutter/foundation.dart';

/// One monotonic deadline shared by local work, HTTP, auth and recovery.
/// Future.timeout does not cancel an HTTP request, so every later dispatch
/// must also check this scope before sending anything else.
class RunFinishOperation {
  RunFinishOperation({
    this.limit = const Duration(seconds: 120),
    required this.isCurrent,
    this.onStage,
    void Function(String)? logger,
  }) : _logger = logger ?? debugPrint {
    _clock.start();
  }
  static final _zoneKey = Object();
  static RunFinishOperation? get current => Zone.current[_zoneKey];
  static int _sequence = 0;
  final String reference = 'finish-${++_sequence}';
  final Duration limit;
  final bool Function() isCurrent;
  final void Function(String)? onStage;
  final void Function(String) _logger;
  final Stopwatch _clock = Stopwatch();
  bool _closed = false;
  Duration get remaining => limit - _clock.elapsed;
  void check() {
    if (_closed || !isCurrent()) throw StateError('การบันทึกรอบนี้ถูกยกเลิก');
    if (remaining <= Duration.zero) {
      throw TimeoutException('หมดเวลารอการบันทึก');
    }
  }

  void log(String stage, {int? status}) => _logger(
      '[RunFinish] ref=$reference stage=$stage elapsedMs=${_clock.elapsedMilliseconds}'
      '${status == null ? '' : ' status=$status'}');
  void stage(String name) {
    check();
    log(name);
    onStage?.call(name);
  }

  Future<T> wait<T>(Future<T> Function() action, {Duration? cap}) async {
    check();
    final left = remaining;
    final timeout = cap != null && cap < left ? cap : left;
    final value = await action().timeout(timeout);
    check();
    return value;
  }

  Future<T> run<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_zoneKey: this});
  void close() => _closed = true;
}
