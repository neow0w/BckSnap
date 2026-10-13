import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bcksnap/services/api_client.dart';
import 'package:flutter_bcksnap/services/screening_service.dart';
import 'package:flutter_bcksnap/features/screening/result_screen.dart';

void main() {
  testWidgets(
    'completed result offers general clinic discovery after next steps',
    (tester) async {
      final router = GoRouter(
        initialLocation: '/result',
        routes: [
          GoRoute(
            path: '/result',
            builder: (_, _) => const ResultScreen(angle: 8),
          ),
          GoRoute(
            path: '/clinics',
            builder: (_, _) => const Scaffold(body: Text('Clinic discovery')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      expect(find.text('Possible scoliosis detected'), findsOneWidget);
      expect(find.text('Recommended next step'), findsOneWidget);
      expect(find.text('Find a Clinic'), findsOneWidget);
      expect(find.text('Find Clinics'), findsOneWidget);
      expect(
        find.textContaining('does not identify a medical specialty'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Find Clinics'));
      await tester.tap(find.text('Find Clinics'));
      await tester.pumpAndSettle();
      expect(find.text('Clinic discovery'), findsOneWidget);
    },
  );

  testWidgets(
    'non-elevated result retains a general, non-specialty clinic action',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ResultScreen(angle: 3)));

      expect(find.text('No sign of scoliosis detected'), findsOneWidget);
      expect(find.text('Find Clinics'), findsOneWidget);
      expect(find.text('Continue to clinic referral'), findsNothing);
      expect(find.text('Yes, proceed to referral'), findsNothing);
    },
  );

  testWidgets('failed save keeps result and allows retry with same attempt', (
    tester,
  ) async {
    final submission = ScreeningSubmission.create(angle: 8.5);
    var attempts = 0;
    final seenSubmissions = <ScreeningSubmission>[];

    await tester.pumpWidget(
      MaterialApp(
        home: ResultScreen(
          angle: submission.angle,
          submission: submission,
          saveAction: (attempt) async {
            attempts++;
            seenSubmissions.add(attempt);
            if (attempts == 1) {
              throw ApiException(408, 'Request timed out.');
            }
            return 42;
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('8.5°'), findsOneWidget);
    expect(find.text('Not yet saved'), findsOneWidget);
    expect(find.text('Retry Save'), findsOneWidget);
    expect(find.text('Find a Clinic'), findsOneWidget);

    await tester.ensureVisible(find.text('Retry Save'));
    await tester.tap(find.text('Retry Save'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Saved'), findsOneWidget);
    expect(attempts, 2);
    expect(seenSubmissions[0].idempotencyKey, submission.idempotencyKey);
    expect(seenSubmissions[1].idempotencyKey, submission.idempotencyKey);
  });
}
