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
  return TermsConsentScreen(
    email: user['email'] as String,
    onAcceptedDirectly: () {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => next),
        (route) => false,
      );
    },
  );
}
