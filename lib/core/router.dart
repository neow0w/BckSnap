import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';

import '../features/auth/edit_profile_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/privacy_notice.dart';
import '../features/auth/profile_screen.dart';
import '../features/auth/reset_confirm_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/landing/landing_screen.dart';
import '../features/receptionist/inbox_screen.dart';
import '../features/receptionist/patient_chat_screen.dart';
import '../features/receptionist/staff_appointments_screen.dart';
import '../features/receptionist/clinic_account_screen.dart';
import '../features/screening/camera_capture_screen.dart';
import '../features/screening/photo_screen.dart';
import '../features/screening/result_screen.dart';
import '../features/screening/measurement_screen.dart';
import '../features/user/appointment_booking_screen.dart';
import '../features/user/appointments_screen.dart';
import '../features/user/clinic_details_screen.dart';
import '../features/user/clinic_discovery_screen.dart';
import '../features/user/home_screen.dart';
import '../features/user/message_screen.dart';
import '../services/auth_service.dart';
import 'screen_placeholder.dart';
import '../features/screening/screening_result.dart';

/// Where each role lands after login (connectors A, B, C in the SFD).
String homeFor(String role) {
  switch (role) {
    case 'receptionist':
      return '/reception'; // connector B
    case 'doctor':
      return '/doctor'; // connector C
    default:
      return '/home'; // connector A
  }
}

// Screens that need a real (non-guest) account.
const _protected = [
  '/home',
  '/clinics',
  '/appointments',
  '/notifications',
  '/message',
  '/reception',
  '/doctor',
  '/profile',
];

// Screens a logged-in user should never see again.
const _entryScreens = ['/', '/login', '/signup', '/reset', '/reset/confirm'];

bool _under(String loc, String prefix) =>
    loc == prefix || loc.startsWith('$prefix/');

/// Which protected screens each role may open.
bool _roleAllowed(String role, String loc) {
  if (_under(loc, '/profile')) return true;
  switch (role) {
    case 'receptionist':
      return _under(loc, '/reception');
    case 'doctor':
      return _under(loc, '/doctor');
    default:
      return _under(loc, '/home') ||
          _under(loc, '/clinics') ||
          _under(loc, '/appointments') ||
          _under(loc, '/notifications') ||
          _under(loc, '/message');
  }
}

int _id(GoRouterState s, String name) =>
    int.tryParse(s.pathParameters[name] ?? '') ?? 0;

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  // Runs before every navigation. AuthService is a singleton, so we read
  // the current user directly; screens still call context.go() after
  // login/logout, which triggers this check.
  redirect: (context, state) {
    final auth = AuthService();
    final user = auth.currentUser;
    final isClinicLoggedIn = auth.isClinicLoggedIn;
    final loggedIn = isClinicLoggedIn || (user != null && !user.isGuest);
    final loc = state.matchedLocation;

    const clinicRoute = '/clinic-account';
    final isClinicRoute = loc == clinicRoute;

    // Clinic accounts should use the Clinic Accounts screen.
    if (isClinicLoggedIn) {
      if (loc == '/login' || loc == '/') {
        return clinicRoute;
      }
      if (loc == clinicRoute) return null;

      // Do not let clinic tokens access patient or staff screens.
      return clinicRoute;
    }

    // Clinic Accounts is not available to patient or guest sessions.
    // Clinic Accounts is not available to patient or guest sessions.
    if (isClinicRoute) {
      if (!loggedIn || user == null || user.isGuest) {
        return '/login';
      }
      return homeFor(user.role);
    }

    final isProtected = _protected.any((p) => _under(loc, p));

    if (!loggedIn) {
      return isProtected ? '/login' : null;
    }

    if (_entryScreens.contains(loc)) {
      return homeFor(user!.role);
    }

    if (isProtected && !_roleAllowed(user!.role, loc)) {
      return homeFor(user.role);
    }

    return null;
  },

  routes: [
    // Figure 7: landing, login, sign-up, reset, screening
    GoRoute(
      path: '/clinic-account',
      builder: (c, s) => const ClinicAccountScreen(),
    ),
    GoRoute(path: '/', builder: (c, s) => const LandingScreen()),
    GoRoute(path: '/login', builder: (c, s) => const LoginScreen()),
    GoRoute(path: '/reset', builder: (c, s) => const ResetPasswordScreen()),
    GoRoute(
      path: '/reset/confirm',
      builder: (c, s) => ResetConfirmScreen(
        email: s.extra is String ? s.extra as String : null,
      ),
    ),
    GoRoute(
      path: '/signup',
      builder: (c, s) => SignUpScreen(next: s.uri.queryParameters['next']),
    ),
    GoRoute(path: '/privacy', builder: (c, s) => const PrivacyNoticeScreen()),
    GoRoute(
      path: '/screening/photo',
      builder: (c, s) =>
          kIsWeb ? const PhotoScreen() : const CameraCaptureScreen(),
    ),
    GoRoute(path: '/screening/upload', builder: (c, s) => const PhotoScreen()),
    GoRoute(
      path: '/screening/test',
      builder: (c, s) => const MeasurementScreen(),
    ),
    GoRoute(
      path: '/screening/result',
      builder: (c, s) {
        final e = s.extra;
        final data = e is ResultData
            ? e
            : ResultData.fromAtr(e is double ? e : 0.0);
        return ResultScreen(data: data);
      },
    ),

    // Profile (all roles)
    GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen()),
    GoRoute(
      path: '/profile/edit',
      builder: (c, s) => const EditProfileScreen(),
    ),

    // Figure 8: user side (connector A)
    GoRoute(path: '/home', builder: (c, s) => const HomeScreen()),
    GoRoute(path: '/clinics', builder: (c, s) => const ClinicDiscoveryScreen()),
    GoRoute(
      path: '/clinics/:id',
      builder: (c, s) => ClinicDetailsScreen(clinicId: _id(s, 'id')),
    ),
    GoRoute(
      path: '/clinics/:id/book',
      builder: (c, s) => AppointmentBookingScreen(clinicId: _id(s, 'id')),
    ),
    GoRoute(
      path: '/appointments',
      builder: (c, s) => const AppointmentsScreen(),
    ),
    GoRoute(
      path: '/appointments/:id',
      builder: (c, s) => AppointmentDetailsScreen(appointmentId: _id(s, 'id')),
    ),
    GoRoute(
      path: '/notifications',
      builder: (c, s) => const NotificationsScreen(),
    ),
    GoRoute(path: '/message', builder: (c, s) => const MessageScreen()),

    // Figure 9: receptionist (connector B)
    GoRoute(
      path: '/reception',
      builder: (c, s) => const StaffAppointmentsScreen(isReception: true),
    ),
    GoRoute(path: '/reception/inbox', builder: (c, s) => const InboxScreen()),
    GoRoute(
      path: '/reception/chat/:patientId',
      builder: (c, s) => PatientChatScreen(
        patientId: _id(s, 'patientId'),
        patientName: s.extra is String ? s.extra as String : null,
      ),
    ),

    // Figure 10: doctor (connector C)
    GoRoute(
      path: '/doctor',
      builder: (c, s) => const StaffAppointmentsScreen(isReception: false),
    ),
    GoRoute(
      path: '/doctor/patient',
      builder: (c, s) => const PlaceholderScreen('Patient Profile'),
    ),
  ],
);
