import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/onboarding_data.dart';

class OnboardingNotifier extends ChangeNotifier {
  OnboardingData data = OnboardingData();
  bool isSubmitting = false;
  String? errorMessage;

  void update(void Function(OnboardingData d) mutate) {
    mutate(data);
    notifyListeners();
  }

  Future<bool> submitStep(
  Future<void> Function() request,
) async {
  isSubmitting = true;
  errorMessage = null;
  notifyListeners();

  try {
    await request();

    isSubmitting = false;
    notifyListeners();
    return true;
  } catch (e) {
    errorMessage = e.toString();

    isSubmitting = false;
    notifyListeners();

    return false;
  }
}

  void reset() {
    data = OnboardingData();
    notifyListeners();
  }
}

final onboardingProvider = ChangeNotifierProvider<OnboardingNotifier>((ref) => OnboardingNotifier());
