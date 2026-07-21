import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/onboarding_data.dart';

class OnboardingNotifier extends ChangeNotifier {
  OnboardingData data = OnboardingData();

  void update(void Function(OnboardingData d) mutate) {
    mutate(data);
    notifyListeners();
  }

  void reset() {
    data = OnboardingData();
    notifyListeners();
  }
}

final onboardingProvider = ChangeNotifierProvider<OnboardingNotifier>((ref) => OnboardingNotifier());
