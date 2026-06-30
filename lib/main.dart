import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/student_home_screen.dart';
import 'screens/admin_dashboard.dart';
import 'screens/session_screen.dart';
import 'services/notification_service.dart';
import 'services/session_watcher.dart';
import 'navigator_key.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.initialize();
  SessionWatcher.start();
  runApp(const EasySitApp());
}

class EasySitApp extends StatelessWidget {
  const EasySitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(360, 780),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'EasySit',
          theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
          initialRoute: '/splash',
          routes: {
            '/splash': (context) => const SplashScreen(),
            '/login': (context) => const LoginScreen(),
            '/student_home': (context) => const StudentHomeScreen(),
            '/admin_dashboard': (context) => const AdminDashboardScreen(),
            '/session': (context) => const SessionScreen(),
          },
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
