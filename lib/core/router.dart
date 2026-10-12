import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/landing/landing_screen.dart';
import '../features/screening/photo_screen.dart';
import '../features/screening/result_screen.dart';
import '../features/screening/scoliometer_screen.dart';
import 'screen_placeholder.dart';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../features/screening/camera_capture_screen.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    // Figure 7: landing, login, sign-up, screening
    GoRoute(path: '/', builder: (c, s) => const LandingScreen()),
    GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
    GoRoute(path: '/reset', builder: (c, s) => const ResetPasswordScreen()),
    GoRoute(path: '/signup', builder: (c, s) => const SignUpScreen()),
    GoRoute(
      path: '/screening/photo',
      builder: (c, s) =>
          kIsWeb ? const PhotoScreen() : const CameraCaptureScreen(),
    ),
    GoRoute(path: '/screening/upload', builder: (c, s) => const PhotoScreen()),
    GoRoute(
      path: '/screening/test',
      builder: (c, s) => const ScoliometerScreen(),
    ),
    GoRoute(
      path: '/screening/result',
      builder: (c, s) {
        final angle = s.extra is double ? s.extra as double : 0.0;
        return ResultScreen(angle: angle);
      },
    ),

    // Figure 8: user side (connector A)
    GoRoute(
      path: '/home',
      builder: (c, s) => const PlaceholderScreen('User Home'),
    ),
    GoRoute(
      path: '/book',
      builder: (c, s) => const PlaceholderScreen('Book Appointment'),
    ),
    GoRoute(
      path: '/message',
      builder: (c, s) => const PlaceholderScreen('Message Clinic'),
    ),

    // Figure 9: receptionist (connector B)
    GoRoute(
      path: '/reception',
      builder: (c, s) => const PlaceholderScreen('Receptionist Home'),
    ),

    // Figure 10: doctor (connector C)
    GoRoute(
      path: '/doctor',
      builder: (c, s) => const PlaceholderScreen('Doctor Home'),
    ),
    GoRoute(
      path: '/doctor/patient',
      builder: (c, s) => const PlaceholderScreen('Patient Profile'),
    ),

    // Connector D: online breakout room
    GoRoute(
      path: '/room',
      builder: (c, s) => const PlaceholderScreen('Breakout Room'),
    ),
  ],
);
