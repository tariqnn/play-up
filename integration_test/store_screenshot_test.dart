import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:playup/main.dart' as app;

const _deviceLabel = String.fromEnvironment(
  'STORE_SCREENSHOT_DEVICE',
  defaultValue: 'iphone',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture the real PlayUp venue browser', (tester) async {
    addTearDown(() async {
      final user = FirebaseAuth.instance.currentUser;
      if (user?.isAnonymous == true) await user!.delete();
    });

    await app.main();
    await _pumpUntil(
      tester,
      () => find.text('Continue as Guest').evaluate().isNotEmpty,
    );
    expect(find.text('Continue as Guest'), findsOneWidget);

    await tester.tap(find.text('Continue as Guest'));
    await _pumpUntil(
      tester,
      () => find.text('Find your venue').evaluate().isNotEmpty,
    );
    expect(find.text('Find your venue'), findsOneWidget);

    // Store captures must show the real production listing, not an empty state
    // or emulator fixture. Wait for the venue stream before taking the image.
    await _pumpUntil(
      tester,
      () => find.text('FIBA Approved 3x3 Court').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 45),
    );
    expect(find.text('Available venues'), findsOneWidget);
    expect(find.text('FIBA Approved 3x3 Court'), findsOneWidget);

    await binding.takeScreenshot('playup-$_deviceLabel-venues');
  });
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}
