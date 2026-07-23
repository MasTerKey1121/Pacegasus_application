import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/wellness_data.dart';
import '../services/wellness_api.dart';
import 'auth_provider.dart';

final wellnessApiProvider = Provider<WellnessApi>(
  (ref) => WellnessApi(ref.read(apiClientProvider)),
);

class WellnessNotifier extends ChangeNotifier {
  final WellnessApi api;

  WellnessNotifier(this.api);

  WellnessEntry entry = WellnessEntry();

  bool completedToday = false;
  bool isSaving = false;
  String? errorMessage;

  void update(void Function(WellnessEntry e) mutate) {
    mutate(entry);
    notifyListeners();
  }

  void reset() {
    entry = WellnessEntry();
    completedToday = false;
    errorMessage = null;
    notifyListeners();
  }

  Future<bool> submit() async {
    isSaving = true;
    errorMessage = null;
    notifyListeners();

    try {
      if (completedToday) {
        await api.update(entry.toApiJson());
      } else {
        await api.create(entry.toApiJson());
        completedToday = true;
      }

      isSaving = false;
      notifyListeners();

      return true;
    } catch (e) {
      errorMessage = e.toString();
      isSaving = false;
      notifyListeners();

      return false;
    }
  }
}

final wellnessProvider =
    ChangeNotifierProvider<WellnessNotifier>(
  (ref) => WellnessNotifier(
    ref.read(wellnessApiProvider),
  ),
);