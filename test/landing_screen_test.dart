import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bcksnap/features/landing/landing_screen.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('landing page keeps screening and login without clinic button', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const LandingScreen()),
        GoRoute(
          path: '/screening/photo',
          builder: (_, _) => const Scaffold(body: Text('Photo screening')),
        ),
        GoRoute(
          path: '/login',
          builder: (_, _) => const Scaffold(body: Text('Login page')),
        ),
        GoRoute(
          path: '/clinics',
          builder: (_, _) => const Scaffold(body: Text('Clinic discovery')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(find.text('Scoliosis Screening'), findsOneWidget);
    expect(find.text('Find a clinic'), findsNothing);
    expect(find.text('Start Screening'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);

    await tester.tap(find.text('Start Screening'));
    await tester.pumpAndSettle();
    expect(find.text('Photo screening'), findsOneWidget);
  });
}
