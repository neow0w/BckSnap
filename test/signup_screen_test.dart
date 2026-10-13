import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bcksnap/features/auth/signup_screen.dart';

void main() {
  testWidgets('signup form presents all required account sections', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SignUpScreen()));

    expect(find.text('Create your BckSnap account'), findsOneWidget);
    expect(find.text('Personal information'), findsOneWidget);
    expect(find.text('Contact information'), findsOneWidget);
    expect(find.text('Account security'), findsOneWidget);
    expect(find.text('Last Name'), findsOneWidget);
    expect(find.text('First Name'), findsOneWidget);
    expect(find.text('Select Birthdate'), findsOneWidget);
    expect(find.text('Address'), findsOneWidget);
    expect(find.text('Gender'), findsOneWidget);
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Contact Number'), findsOneWidget);
    expect(find.text('Confirm Password'), findsOneWidget);
  });

  testWidgets('required name and password validation prevents submission', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SignUpScreen()));
    final submit = find.widgetWithText(FilledButton, 'Create Account');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('Last name is required.'), findsOneWidget);
    expect(find.text('First name is required.'), findsOneWidget);
    expect(
      find.text('Password must be at least 8 characters.'),
      findsOneWidget,
    );
    expect(find.text('Please select your gender.'), findsOneWidget);
  });
}
