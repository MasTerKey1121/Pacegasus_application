import 'package:flutter/material.dart';
import '../home/main_shell.dart';
import '../onboarding/onboarding_basic_screen.dart';
import 'terms_screen.dart';

Widget authenticatedDestination(
    BuildContext context, Map<String, dynamic> user) {
  final Widget next = user['onboardingCompleted'] == true
      ? const MainShell()
      : const OnboardingBasicScreen();
  if (user['policyAccepted'] == true) return next;
  // Keep the navigator, because the Google button's route is removed before
  // the user accepts the terms. Its BuildContext is no longer valid then.
  final navigator = Navigator.of(context);
  return TermsConsentScreen(
    email: user['email'] as String,
    onAcceptedDirectly: () {
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => next),
        (route) => false,
      );
    },
  );
}
