import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/training_date.dart';

class TrainingDay extends StateNotifier<String> with WidgetsBindingObserver {
  TrainingDay({String Function()? today})
      : _today = today ?? (() => trainingDateKey(trainingToday())!),
        super((today ?? (() => trainingDateKey(trainingToday())!))()) {
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => check());
  }
  Timer? _timer;
  final String Function() _today;
  void check() {
    final next = _today();
    if (state != next) state = next;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) check();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

final trainingDayProvider =
    StateNotifierProvider<TrainingDay, String>((ref) => TrainingDay());
