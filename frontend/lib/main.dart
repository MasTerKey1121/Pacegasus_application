import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_theme.dart';
import 'navigation/home_route_observer.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/auth_destination.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const ProviderScope(child: PacegasusApp()));
}

class PacegasusApp extends StatelessWidget {
  const PacegasusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pacegasus',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      navigatorObservers: [homeRouteObserver],
      home: const AuthGate(),
    );
  }
}

/// เช็ค session ค้าง (refreshToken) ตอนเปิดแอป ก่อนตัดสินใจว่าจะพาไป
/// หน้า Login หรือเข้า MainShell (Home) เลย
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(authProvider.notifier).init());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authProvider, (previous, next) {
      if (previous?.user?['id'] != null &&
          previous?.user?['id'] != next.user?['id']) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        });
      }
    });
    final auth = ref.watch(authProvider);
    final status = auth.status;

    switch (status) {
      case AuthStatus.checking:
        return const Scaffold(
          body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('กำลังเชื่อมต่อและตรวจสอบการเข้าสู่ระบบ…'),
            Text('การเปิดเซิร์ฟเวอร์ครั้งแรกอาจใช้เวลาสักครู่'),
          ])),
        );
      case AuthStatus.connectionRequired:
        return Scaffold(
            body: Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                          auth.connectionMessage ??
                              'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: () =>
                              ref.read(authProvider.notifier).init(),
                          child: const Text('ลองเชื่อมต่อใหม่')),
                      TextButton(
                          onPressed: () =>
                              ref.read(authProvider.notifier).logout(),
                          child: const Text('ออกจากระบบ')),
                    ]))));
      case AuthStatus.authenticated:
        return authenticatedDestination(context, auth.user!);
      case AuthStatus.unauthenticated:
        return const LoginScreen();
    }
  }
}
