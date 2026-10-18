import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:playup/main.dart';
import 'package:playup/design_system.dart';
import 'package:playup/test_data_seed.dart';

void main() {
  test('native map tile layer accepts the PlayUp request headers', () {
    final layer = TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.playup.playup',
      tileProvider: NetworkTileProvider(
        headers: {
          'User-Agent':
              'PlayUp/1.0.0 (+https://play-up.fit; contact: info@creativnetworks.com)',
        },
      ),
    );

    expect(layer, isA<TileLayer>());
  });

  test('release builds reject Firebase emulator configuration', () {
    expect(
      () => validateFirebaseEnvironment(useEmulators: true, isRelease: true),
      throwsA(isA<StateError>()),
    );
    expect(
      () => validateFirebaseEnvironment(useEmulators: true, isRelease: false),
      returnsNormally,
    );
  });

  test('demo venues cover every home sport and activity category', () {
    const expectedCategories = {
      'Padel',
      'Football',
      'Tennis',
      'Basketball',
      'Volleyball',
      'Sea Sports',
      'Dodgeball',
      'Kayaking',
      'Hiking',
      'Climbing',
      'Badminton',
      'Fitness',
    };
    final demoCategories = kTestCourts.map((venue) => venue.sport).toSet();

    expect(demoCategories, containsAll(expectedCategories));
    expect(kTestCourts.every((venue) => venue.imageUrl.isNotEmpty), isTrue);
    expect(
      kTestCourts.every((venue) => venue.galleryImages.length >= 3),
      isTrue,
    );

    final academySports = kTestAcademies
        .map((academy) => academy.sports.toLowerCase())
        .join(' ');
    for (final category in expectedCategories) {
      expect(
        academySports,
        contains(category.toLowerCase()),
        reason: '$category needs demo training or academy data',
      );
    }

    final activityTitles = kSportActivities
        .map((activity) => activity.title.toLowerCase())
        .join(' ');
    expect(activityTitles, contains('kayak'));
    expect(activityTitles, contains('hiking'));
    expect(activityTitles, contains('climbing'));
  });

  test('emulator mode is disabled in the production app configuration', () {
    expect(useFirebaseEmulators, isFalse);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'welcome supports narrow screens and large text in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: playUpTheme(brightness),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: const WelcomeScreen(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Continue as Guest'));
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('PlayUp welcome screen renders', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));

    expect(find.text('PlayUp'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Continue as Guest'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName ==
                'assets/images/sports/basketball_action.png',
      ),
      findsOneWidget,
    );
  });

  testWidgets('sports and adventure carousel moves without playback controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(
          body: SizedBox(width: 390, child: HomeSportCarousel()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Explore Sports & Adventure'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);
    expect(find.text('Play'), findsNothing);
    expect(find.text('Motion off'), findsNothing);
    expect(find.text('Football'), findsWidgets);
    expect(find.text('Basketball'), findsWidgets);
    expect(find.text('Volleyball'), findsWidgets);
    expect(find.text('Infinity Sports'), findsNothing);

    final pageView = tester.widget<PageView>(find.byType(PageView));
    final initialPage = pageView.controller!.page!;
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 450));
    expect(pageView.controller!.page!, greaterThan(initialPage));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
