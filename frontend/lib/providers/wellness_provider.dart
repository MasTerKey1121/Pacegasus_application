import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/wellness_data.dart';

class WellnessNotifier extends ChangeNotifier {
  WellnessEntry entry = WellnessEntry();
  bool completedToday = false;

  void update(void Function(WellnessEntry e) mutate) {
    mutate(entry);
    notifyListeners();
  }

  void markComplete() {
    completedToday = true;
    notifyListeners();
  }
}

final wellnessProvider = ChangeNotifierProvider<WellnessNotifier>((ref) => WellnessNotifier());
