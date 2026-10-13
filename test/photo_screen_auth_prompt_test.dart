import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bcksnap/features/screening/photo_screen.dart';

void main() {
  testWidgets('first photo action offers account, login, guest, and cancel', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: PhotoScreen()));
    await tester.tap(find.text('Take Photo'));
    await tester.pumpAndSettle();

    expect(find.text('Create Account'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Continue as guest'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Before you begin'), findsNothing);
  });
}
