import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playup/main.dart';

void main() {
  testWidgets('PlayUp welcome screen renders', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));

    expect(find.text('PlayUp'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('Continue as Guest'), findsOneWidget);
  });
}
