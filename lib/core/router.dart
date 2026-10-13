import 'package:go_router/go_router.dart';

import '../features/appointments/appointments_screen.dart';
import '../features/appointments/staff_appointments_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/clinics/appointment_booking_screen.dart';
import '../features/clinics/clinic_details_screen.dart';
import '../features/clinics/clinic_discovery_screen.dart';
import '../features/landing/landing_screen.dart';
import '../features/landing/home_screen.dart';
import '../features/screening/photo_screen.dart';
import '../features/screening/result_screen.dart';
import '../features/screening/scoliometer_screen.dart';
import 'auth_destination.dart';
import '../services/screening_service.dart';
import 'screen_placeholder.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    // Figure 7: landing, login, sign-up, screening
    GoRoute(path: '/', builder: (c, s) => const LandingScreen()),
    GoRoute(
      path: '/login',
      builder: (c, s) => LoginScreen(
        nextRoute: authDestination(s.uri.queryParameters['next']),
      ),
    ),
    GoRoute(path: '/reset', builder: (c, s) => const ResetPasswordScreen()),
    GoRoute(
      path: '/signup',
      builder: (c, s) => SignUpScreen(
        nextRoute: authDestination(s.uri.queryParameters['next']),
      ),
    ),
    GoRoute(path: '/screening/photo', builder: (c, s) => const PhotoScreen()),
    GoRoute(
      path: '/screening/test',
      builder: (c, s) => const ScoliometerScreen(),
    ),
    GoRoute(
      path: '/screening/result',
      redirect: (c, s) {
        final extra = s.extra;
        final angle = extra is ScreeningSubmission ? extra.angle : extra;
        if (angle is! double || !angle.isFinite || angle < 0 || angle > 90) {
          return '/';
        }
        return null;
      },
      builder: (c, s) {
        final extra = s.extra;
        return ResultScreen(
          angle: extra is ScreeningSubmission ? extra.angle : extra! as double,
          submission: extra is ScreeningSubmission ? extra : null,
        );
      },
    ),

    // Figure 8: user side (connector A)
    GoRoute(path: '/home', builder: (c, s) => const HomeScreen()),
    GoRoute(path: '/book', redirect: (c, s) => '/clinics'),
    GoRoute(path: '/clinics', builder: (c, s) => const ClinicDiscoveryScreen()),
    GoRoute(
      path: '/clinics/:clinicId',
      builder: (c, s) => ClinicDetailsScreen(
        clinicId: int.parse(s.pathParameters['clinicId']!),
      ),
    ),
    GoRoute(
      path: '/clinics/:clinicId/book',
      builder: (c, s) => AppointmentBookingScreen(
        clinicId: int.parse(s.pathParameters['clinicId']!),
      ),
    ),
    GoRoute(
      path: '/appointments',
      builder: (c, s) => const AppointmentsScreen(),
    ),
    GoRoute(
      path: '/appointments/:appointmentId',
      builder: (c, s) => AppointmentDetailsScreen(
        appointmentId: int.parse(s.pathParameters['appointmentId']!),
      ),
    ),
    GoRoute(
      path: '/notifications',
      builder: (c, s) => const NotificationsScreen(),
    ),
    GoRoute(
      path: '/message',
      builder: (c, s) => const PlaceholderScreen('Message Clinic'),
    ),

    // Figure 9: receptionist (connector B)
    GoRoute(
      path: '/reception',
      builder: (c, s) => const StaffAppointmentsScreen(isReception: true),
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

    // Connector D: online breakout room
    GoRoute(
      path: '/room',
      builder: (c, s) => const PlaceholderScreen('Breakout Room'),
    ),
  ],
);
