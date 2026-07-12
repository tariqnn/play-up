import 'dart:async';
import 'dart:math' as math;

import 'package:app_links/app_links.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'firebase_options.dart';
import 'catalog.dart';
import 'more_screens.dart';
import 'more_screens2.dart';
import 'more_screens3.dart';
import 'more_screens4.dart';
import 'booking_domain.dart';
import 'location_service.dart';
import 'tournament_screens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );
  const useEmulators = bool.fromEnvironment('USE_FIREBASE_EMULATORS');
  if (useEmulators) {
    final emulatorHost =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : '127.0.0.1';
    await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
    FirebaseFunctions.instanceFor(
      region: 'me-central1',
    ).useFunctionsEmulator(emulatorHost, 5001);
    const testEmail = String.fromEnvironment('UAT_TEST_EMAIL');
    const testPassword = String.fromEnvironment('UAT_TEST_PASSWORD');
    if (testEmail.isNotEmpty && testPassword.isNotEmpty) {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: testEmail,
        password: testPassword,
      );
    }
  }
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  await ThemeController.initialize();
  runApp(const PlayUpApp());
  unawaited(DeepLinkService.start());
  unawaited(LocationService.instance.initialize());
  if (!useEmulators) unawaited(_configureMessaging());
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> _configureMessaging() async {
  try {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // Foreground messages are intentionally handled in-app later by UI state.
    });
  } catch (_) {
    // Messaging can be unavailable on some debug targets; app startup should continue.
  }
}

class AppColors {
  static const background = Color(0xFFF7F8FB);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
  static const line = Color(0xFFE5E7EB);
  static const dark = Color(0xFF07111F);
  static const dark2 = Color(0xFF0B1628);
  static const purple = Color(0xFF7B3FF2);
  static const green = Color(0xFF62D84E);
  static const gold = Color(0xFFF5B942);
  static const danger = Color(0xFFFF4D4F);
}

Future<void> showAdaptiveMessage(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialog) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  } else {
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        icon: const Icon(Icons.info_outline),
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Maps raw Firebase/plugin errors to friendly, human messages.
String friendlyAuthError(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-email':
        return 'That email address doesn\'t look right. Please check it.';
      case 'user-not-found':
        return 'No account found with this email. Try creating one instead.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect. Please try again.';
      case 'email-already-in-use':
        return 'An account already exists with this email. Try signing in.';
      case 'weak-password':
        return 'Password is too weak — use at least 6 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'No internet connection. Check your network and try again.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      case 'requires-recent-login':
        return 'Please sign in again to confirm this action.';
      default:
        return error.message ?? 'Something went wrong. Please try again.';
    }
  }
  final text = error.toString();
  if (text.contains('canceled') || text.contains('cancelled')) {
    return 'Sign-in was cancelled.';
  }
  if (text.contains('network')) {
    return 'No internet connection. Check your network and try again.';
  }
  return 'Something went wrong. Please try again.';
}

/// Formats an integer with thousands separators, e.g. 3250 -> "3,250".
String formatThousands(int value) {
  final s = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
    buffer.write(s[i]);
  }
  return buffer.toString();
}

/// Real Google / Apple sign-in that federate into Firebase Auth.
class SocialAuth {
  static bool _googleReady = false;

  /// Web (server) OAuth client of the Firebase project — required so Google
  /// returns an ID token that Firebase Auth accepts.
  static const _serverClientId =
      '634238605050-qdp7hs2bsu4t1c7s8q9s34iajajamn7u.apps.googleusercontent.com';

  /// True only on iOS, where "Sign in with Apple" is native. Hidden elsewhere.
  static bool get appleAvailable => defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> signOutEverywhere() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Google may not have been initialised; ignore.
    }
    await FirebaseAuth.instance.signOut();
  }

  static Future<UserCredential> google() async {
    final signIn = GoogleSignIn.instance;
    if (!_googleReady) {
      await signIn.initialize(serverClientId: _serverClientId);
      _googleReady = true;
    }
    final account = await signIn.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw FirebaseAuthException(
        code: 'missing-id-token',
        message: 'Google sign-in could not complete. Please try again.',
      );
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    return FirebaseAuth.instance.signInWithCredential(credential);
  }

  static Future<UserCredential> apple() async {
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      accessToken: appleCredential.authorizationCode,
    );
    final result = await FirebaseAuth.instance.signInWithCredential(
      oauthCredential,
    );
    final displayName = [
      appleCredential.givenName,
      appleCredential.familyName,
    ].whereType<String>().join(' ').trim();
    if (displayName.isNotEmpty) {
      await result.user?.updateDisplayName(displayName);
    }
    return result;
  }
}

/// Enters the app as a guest. Tries anonymous auth first; if that is not
/// enabled in Firebase, falls back to local browsing so the app is always
/// usable for demos.
Future<void> enterAsGuest(BuildContext context) async {
  var signedIn = false;
  try {
    await FirebaseAuth.instance.signInAnonymously();
    signedIn = true;
  } catch (error) {
    debugPrint('Anonymous auth unavailable, entering local guest mode: $error');
  }
  if (!context.mounted) return;
  if (signedIn || FirebaseAuth.instance.currentUser != null) {
    // Real anonymous user: dismiss any pushed auth screens so the rebuilt
    // AuthGate (now showing MainShell) becomes visible.
    Navigator.of(context).popUntil((route) => route.isFirst);
  } else {
    // Anonymous auth disabled: fall back to local browsing.
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
  }
}

class PlayUpApp extends StatelessWidget {
  const PlayUpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) => MaterialApp(
        scaffoldMessengerKey: appMessengerKey,
        title: 'PlayUp',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: AppColors.background,
          fontFamily: 'SF Pro Display',
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.purple,
            brightness: Brightness.light,
            primary: AppColors.purple,
            surface: AppColors.surface,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF07111F),
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.purple,
            brightness: Brightness.dark,
            primary: const Color(0xFF9B72FF),
            surface: const Color(0xFF111B2B),
          ),
          inputDecorationTheme: const InputDecorationTheme(filled: true),
          cardTheme: const CardThemeData(color: Color(0xFF111B2B)),
        ),
        themeMode: mode,
        home: const BiometricGate(child: AuthGate()),
      ),
    );
  }
}

class ThemeController {
  static final mode = ValueNotifier<ThemeMode>(ThemeMode.system);
  static Future<void> initialize() async {
    final value =
        (await SharedPreferences.getInstance()).getString('theme_mode') ??
        'system';
    mode.value = ThemeMode.values.firstWhere(
      (item) => item.name == value,
      orElse: () => ThemeMode.system,
    );
  }

  static Future<void> set(ThemeMode value) async {
    mode.value = value;
    await (await SharedPreferences.getInstance()).setString(
      'theme_mode',
      value.name,
    );
  }
}

class ThemeModeTile extends StatelessWidget {
  const ThemeModeTile({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: ThemeController.mode,
    builder: (context, value, _) => ListTile(
      leading: const Icon(CupertinoIcons.moon_stars),
      title: const Text('Appearance'),
      subtitle: Text(
        value == ThemeMode.system
            ? 'Follow device'
            : value == ThemeMode.dark
            ? 'Dark mode'
            : 'Light mode',
      ),
      trailing: DropdownButton<ThemeMode>(
        value: value,
        items: const [
          DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
          DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
          DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
        ],
        onChanged: (mode) {
          if (mode != null) ThemeController.set(mode);
        },
      ),
    ),
  );
}

final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

class DeepLinkService {
  static const _pendingKey = 'pending_booking_invite';
  static final _links = AppLinks();
  static Future<void> start() async {
    final initial = await _links.getInitialLink();
    if (initial != null) await _handle(initial);
    _links.uriLinkStream.listen(_handle);
  }

  static Future<void> _handle(Uri uri) async {
    final parts = uri.pathSegments;
    String? token;
    if (uri.scheme == 'playup' && uri.host == 'booking' && parts.isNotEmpty) {
      token = parts.last;
    }
    if (parts.length >= 3 && parts[0] == 'join' && parts[1] == 'booking') {
      token = parts[2];
    }
    if (token == null || token.isEmpty) return;
    if (FirebaseAuth.instance.currentUser == null) {
      await (await SharedPreferences.getInstance()).setString(
        _pendingKey,
        token,
      );
      return;
    }
    await _join(token);
  }

  static Future<void> consumePending() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_pendingKey);
    if (token == null) return;
    await prefs.remove(_pendingKey);
    await _join(token);
  }

  static Future<void> _join(String token) async {
    try {
      await FirebaseFunctions.instanceFor(
        region: 'me-central1',
      ).httpsCallable('joinBookingInvite').call({'token': token});
      appMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('You joined the booking.')),
      );
    } catch (error) {
      appMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }
}

class BiometricService {
  static const _key = 'biometric_unlock_enabled';
  static final _auth = LocalAuthentication();
  static Future<bool> isEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(_key) ?? false;
  static Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setEnabled(bool value) async {
    if (value && !await authenticate()) {
      throw const DomainValidationException(
        'Biometric verification was not completed.',
      );
    }
    await (await SharedPreferences.getInstance()).setBool(_key, value);
  }

  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Unlock your PlayUp account',
        biometricOnly: true,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}

class BiometricGate extends StatefulWidget {
  const BiometricGate({super.key, required this.child});
  final Widget child;
  @override
  State<BiometricGate> createState() => _BiometricGateState();
}

class _BiometricGateState extends State<BiometricGate> {
  bool loading = true;
  bool unlocked = false;
  @override
  void initState() {
    super.initState();
    _unlock();
  }

  Future<void> _unlock() async {
    final required =
        FirebaseAuth.instance.currentUser != null &&
        await BiometricService.isEnabled();
    final ok = !required || await BiometricService.authenticate();
    if (mounted) {
      setState(() {
        loading = false;
        unlocked = ok;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const LaunchLoadingScreen();
    if (unlocked) return widget.child;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.lock_shield_fill,
                  size: 64,
                  color: AppColors.purple,
                ),
                const SizedBox(height: 18),
                const Text(
                  'PlayUp is locked',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Verify with your device biometrics to continue.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                PrimaryButton(label: 'Unlock', onPressed: _unlock),
                const SizedBox(height: 10),
                SecondaryButton(
                  label: 'Sign out instead',
                  onPressed: () async {
                    await SocialAuth.signOutEverywhere();
                    if (mounted) setState(() => unlocked = true);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BiometricSettingsTile extends StatefulWidget {
  const BiometricSettingsTile({super.key});
  @override
  State<BiometricSettingsTile> createState() => _BiometricSettingsTileState();
}

class _BiometricSettingsTileState extends State<BiometricSettingsTile> {
  bool loading = true, available = false, enabled = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      BiometricService.isAvailable(),
      BiometricService.isEnabled(),
    ]);
    if (mounted) {
      setState(() {
        available = values[0];
        enabled = values[1];
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    value: enabled,
    onChanged: !available || loading
        ? null
        : (value) async {
            try {
              await BiometricService.setEnabled(value);
              if (!mounted) return;
              setState(() => enabled = value);
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(error.toString())));
              }
            }
          },
    secondary: const Icon(CupertinoIcons.lock_shield),
    title: const Text('Biometric unlock'),
    subtitle: Text(
      available
          ? 'Use Face ID, Touch ID, or Android biometrics'
          : 'No device biometrics are enrolled',
    ),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LaunchLoadingScreen();
        }
        final user = snapshot.data;
        if (user == null) return const WelcomeScreen();
        return FutureBuilder<Map<String, dynamic>>(
          future: AppRepository.instance.ensureAndLoadProfile(user),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const LaunchLoadingScreen();
            }
            final role = profileSnapshot.data?['role']?.toString() ?? 'player';
            if (role == 'academyOwner' || role == 'academyStaff') {
              return const AcademyModeDashboard(standalone: true);
            }
            return const MainShell();
          },
        );
      },
    );
  }
}

class AppRepository {
  AppRepository._();

  static final instance = AppRepository._();
  final _db = FirebaseFirestore.instance;
  final _functions = FirebaseFunctions.instanceFor(region: 'me-central1');

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _bookings =>
      _db.collection('bookings');
  CollectionReference<Map<String, dynamic>> get _matches =>
      _db.collection('matches');
  CollectionReference<Map<String, dynamic>> get _supportTickets =>
      _db.collection('supportTickets');

  Future<void> ensureUserProfile(User user) async {
    // Best-effort profile sync. Never blocks app entry if Firestore is
    // unreachable or rules reject the write (e.g. offline demo mode).
    try {
      final ref = _users.doc(user.uid);
      final snap = await ref.get();
      final name = displayNameFor(user);
      if (snap.exists) {
        await ref.set({
          'lastSeenAt': FieldValue.serverTimestamp(),
          if (user.email != null) 'email': user.email,
          'displayName': name,
        }, SetOptions(merge: true));
        return;
      }
      // New players start at the bottom of the ladder — everything they see
      // afterwards is earned, not fake.
      await ref.set({
        'uid': user.uid,
        'displayName': name,
        'email': user.email,
        'isGuest': user.isAnonymous,
        'city': 'Dubai, UAE',
        'level': 1,
        'rankTitle': 'Rookie',
        'xp': 0,
        'nextLevelXp': 500,
        'points': 100, // welcome bonus
        'rating': 0.0,
        'reliability': 100,
        'matches': 0,
        'winRate': 0,
        'sports': <String>[],
        'role': 'player',
        'permissions': <String>[],
        'suspended': false,
        'createdAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      debugPrint('ensureUserProfile skipped: $error');
    }
  }

  Future<Map<String, dynamic>> ensureAndLoadProfile(User user) async {
    await ensureUserProfile(user);
    final snapshot = await _users.doc(user.uid).get();
    return snapshot.data() ?? const <String, dynamic>{'role': 'player'};
  }

  /// Resolves a sensible display name for any auth type.
  static String displayNameFor(User user) {
    final name = user.displayName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    final email = user.email ?? '';
    if (email.contains('@')) {
      final prefix = email.split('@').first.replaceAll(RegExp(r'[._-]+'), ' ');
      return prefix
          .split(' ')
          .where((w) => w.isNotEmpty)
          .map((w) => w[0].toUpperCase() + w.substring(1))
          .join(' ');
    }
    return 'Guest Player';
  }

  /// Live snapshot of the signed-in user's profile document.
  Stream<Map<String, dynamic>> currentUserDoc() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(const {});
    return _users.doc(uid).snapshots().map((s) => s.data() ?? const {});
  }

  /// Persists the user's chosen city/area so every screen updates live.
  Future<void> updateCity(String city) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || city.trim().isEmpty) return;
    try {
      await _users.doc(uid).set({'city': city.trim()}, SetOptions(merge: true));
    } catch (error) {
      debugPrint('updateCity skipped: $error');
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> myBookings() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _bookings
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> openMatches() {
    return _matches
        .where('status', isEqualTo: 'open')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots();
  }

  Future<String> createBooking({
    required Court court,
    required bool matchmaking,
    required DateTime startUtc,
    required DateTime endUtc,
    required int playerCapacity,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const DomainValidationException('Sign in to create a booking.');
    }
    if (court.id.isEmpty) {
      throw const DomainValidationException(
        'This sample court is not bookable. Select a live academy court.',
      );
    }
    try {
      final response = await _functions.httpsCallable('createBooking').call({
        'courtId': court.id,
        'startUtc': startUtc.toIso8601String(),
        'endUtc': startUtc.add(const Duration(hours: 1)).toIso8601String(),
        'matchmaking': matchmaking,
        'playerCapacity': playerCapacity,
      });
      final bookingId = (response.data as Map)['bookingId']?.toString();
      if (bookingId == null || bookingId.isEmpty) {
        throw const DomainValidationException(
          'The server returned an invalid booking confirmation.',
        );
      }
      return bookingId;
    } catch (error) {
      if (error is DomainValidationException) rethrow;
      if (error is FirebaseFunctionsException) {
        throw DomainValidationException(
          error.message ?? 'Booking could not be confirmed.',
        );
      }
      throw const DomainValidationException(
        'Booking could not be confirmed. Check your connection and try again.',
      );
    }
  }

  Future<String> joinMatch(
    String title, {
    String sport = 'Basketball',
    String type = 'Casual',
    int neededPlayers = 2,
    String skill = 'Intermediate',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const DomainValidationException('Sign in to create a match.');
    }
    try {
      final response = await _functions.httpsCallable('createMatch').call({
        'title': title,
        'sport': sport,
        'type': type,
        'skill': skill,
        'capacity': neededPlayers,
        'courtId': 'uat-court-a1',
        'startUtc': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 3))
            .toIso8601String(),
      });
      return (response.data as Map)['matchId'].toString();
    } catch (error) {
      if (error is FirebaseFunctionsException) {
        throw DomainValidationException(
          error.message ?? 'The match could not be created.',
        );
      }
      rethrow;
    }
  }

  Future<void> joinExistingMatch(String matchId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const DomainValidationException('Sign in to join a match.');
    }
    try {
      await _functions.httpsCallable('joinMatch').call({'matchId': matchId});
    } on FirebaseFunctionsException catch (error) {
      throw DomainValidationException(
        error.message ?? 'Could not join this match.',
      );
    }
  }

  Future<Map<String, dynamic>> redeemOffer(String offerId) async {
    try {
      final result = await _functions.httpsCallable('redeemOffer').call({
        'offerId': offerId,
      });
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (error) {
      throw DomainValidationException(
        error.message ?? 'Could not redeem this offer.',
      );
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> pointsLedger() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _users
        .doc(uid)
        .collection('pointsLedger')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> matchMessages(String matchId) =>
      _matches
          .doc(matchId)
          .collection('messages')
          .orderBy('createdAt')
          .limitToLast(200)
          .snapshots();

  Future<void> sendMatchMessage(String matchId, String body) async {
    try {
      await _functions.httpsCallable('sendMatchMessage').call({
        'matchId': matchId,
        'body': body,
      });
    } on FirebaseFunctionsException catch (error) {
      throw DomainValidationException(
        error.message ?? 'Message could not be sent.',
      );
    }
  }

  Future<String> createBookingInvite(String bookingId) async {
    try {
      final result = await _functions.httpsCallable('createBookingInvite').call(
        {'bookingId': bookingId},
      );
      return (result.data as Map)['url'].toString();
    } on FirebaseFunctionsException catch (error) {
      throw DomainValidationException(
        error.message ?? 'Invite link could not be created.',
      );
    }
  }

  Future<void> submitSupportTicket(String category, String message) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await _supportTickets.add({
        'userId': user?.uid,
        'category': category,
        'message': message,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      debugPrint('submitSupportTicket skipped: $error');
    }
  }

  Future<void> submitRating(
    int rating,
    List<String> tags,
    String comment,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      await _db.collection('reviews').add({
        'userId': user?.uid,
        'rating': rating,
        'tags': tags,
        'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (user != null) {
        await _users.doc(user.uid).set({
          'xp': FieldValue.increment(150),
          'points': FieldValue.increment(40),
        }, SetOptions(merge: true));
      }
    } catch (error) {
      debugPrint('submitRating skipped: $error');
    }
  }

  Stream<bool> isFavorite(String courtId) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || courtId.isEmpty) return Stream.value(false);
    return _users
        .doc(uid)
        .collection('favorites')
        .doc(courtId)
        .snapshots()
        .map((snapshot) => snapshot.exists);
  }

  Future<void> toggleFavorite(Court court, bool favorite) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw const DomainValidationException('Sign in to save favorite courts.');
    }
    if (court.id.isEmpty) {
      throw const DomainValidationException('This court cannot be saved yet.');
    }
    final ref = _users.doc(uid).collection('favorites').doc(court.id);
    if (favorite) {
      await ref.set({
        'courtId': court.id,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.delete();
    }
  }
}

class Court {
  const Court({
    required this.name,
    required this.subtitle,
    required this.rating,
    required this.distance,
    required this.price,
    required this.gradient,
    required this.icon,
    this.imageUrl = '',
    this.id = '',
    this.latitude,
    this.longitude,
  });

  final String name;
  final String subtitle;
  final String rating;
  final String distance;
  final String price;
  final List<Color> gradient;
  final IconData icon;
  final String imageUrl;
  final String id;
  final double? latitude;
  final double? longitude;

  String distanceFrom(AppLocation? location) {
    if (location == null || latitude == null || longitude == null) {
      return 'Location needed';
    }
    const earthRadiusKm = 6371.0;
    final dLat = (latitude! - location.latitude) * math.pi / 180;
    final dLon = (longitude! - location.longitude) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(location.latitude * math.pi / 180) *
            math.cos(latitude! * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final km = earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';
  }
}

const courts = [
  Court(
    name: 'Infinity Sports Center',
    subtitle: 'Indoor Basketball',
    rating: '4.8 (128)',
    distance: '1.2 km',
    price: 'AED 210 / hr',
    gradient: [Color(0xFF102A43), Color(0xFF1F7A8C)],
    icon: CupertinoIcons.sportscourt,
  ),
  Court(
    name: 'Dubai Sports World',
    subtitle: 'Indoor Basketball',
    rating: '4.7 (96)',
    distance: '2.1 km',
    price: 'AED 180 / hr',
    gradient: [Color(0xFF281B44), Color(0xFF7B3FF2)],
    icon: CupertinoIcons.circle_grid_hex,
  ),
  Court(
    name: 'Hoops Basketball Academy',
    subtitle: 'Indoor Academy',
    rating: '4.6 (74)',
    distance: '2.8 km',
    price: 'AED 200 / hr',
    gradient: [Color(0xFF18230F), Color(0xFF62D84E)],
    icon: CupertinoIcons.person_3_fill,
  ),
];

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DarkGradient(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              PlayUpMark(size: 42),
                              SizedBox(width: 12),
                              Text(
                                'PlayUp',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Center(
                            child: SizedBox(
                              width: 260,
                              height: 260,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: 230,
                                    height: 230,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: RadialGradient(
                                        colors: [
                                          AppColors.purple.withValues(
                                            alpha: .45,
                                          ),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                  Transform.rotate(
                                    angle: -.4,
                                    child: const Icon(
                                      CupertinoIcons.sportscourt,
                                      size: 150,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Positioned(
                                    top: 22,
                                    left: 20,
                                    child: _GlowBall(color: AppColors.gold),
                                  ),
                                  Positioned(
                                    bottom: 30,
                                    right: 36,
                                    child: _GlowBall(
                                      color: AppColors.green,
                                      size: 54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Spacer(),
                          const Text(
                            'Book. Play.\nLevel Up.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'The ultimate sports booking and matchmaking experience.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .74),
                              fontSize: 16,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 28),
                          PrimaryButton(
                            label: 'Get Started',
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AuthScreen(),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => enterAsGuest(context),
                            child: const Center(
                              child: Text(
                                'Continue as Guest',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class LaunchLoadingScreen extends StatelessWidget {
  const LaunchLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DarkGradient(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PlayUpMark(size: 74)
                  .animate(onPlay: (controller) => controller.repeat())
                  .scale(
                    begin: const Offset(.92, .92),
                    end: const Offset(1.08, 1.08),
                    duration: 900.ms,
                    curve: Curves.easeInOut,
                  )
                  .then()
                  .scale(
                    begin: const Offset(1.08, 1.08),
                    end: const Offset(.92, .92),
                    duration: 900.ms,
                    curve: Curves.easeInOut,
                  ),
              const SizedBox(height: 20),
              const Text(
                'PlayUp',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _isSignUp = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Client-side validation before hitting the network.
    final email = _email.text.trim();
    if (_isSignUp && _name.text.trim().isEmpty) {
      setState(() => _error = 'Please enter your full name.');
      return;
    }
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    if (_password.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      UserCredential credential;
      if (_isSignUp) {
        credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
        await credential.user?.updateDisplayName(_name.text.trim());
      } else {
        credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
      final user = credential.user;
      if (user != null) {
        await AppRepository.instance.ensureUserProfile(user);
      }
      if (!mounted) return;
      if (_isSignUp) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SportsSelectionScreen()),
        );
      } else {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } on FirebaseAuthException catch (error) {
      setState(() => _error = friendlyAuthError(error));
    } catch (error) {
      setState(() => _error = friendlyAuthError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: _isSignUp ? 'Create Account' : 'Welcome Back',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            AuthHeroBanner(
              caption: _isSignUp ? 'Join the game' : 'Welcome back, champion',
            ),
            const SizedBox(height: 20),
            Text(
              _isSignUp
                  ? 'Create your player profile'
                  : 'Sign in to book, play, and level up.',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                height: 1.08,
              ),
            ),
            const SizedBox(height: 22),
            if (_isSignUp) ...[
              AppTextField(
                controller: _name,
                label: 'Full name',
                icon: CupertinoIcons.person,
              ),
              const SizedBox(height: 12),
            ],
            AppTextField(
              controller: _email,
              label: 'Email',
              icon: CupertinoIcons.mail,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _password,
              label: 'Password',
              icon: CupertinoIcons.lock,
              obscureText: true,
            ),
            if (!_isSignUp)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ForgotPasswordScreen(),
                    ),
                  ),
                  child: const Text('Forgot password?'),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 18),
            PrimaryButton(
              label: _loading
                  ? 'Please wait...'
                  : (_isSignUp ? 'Create Account' : 'Sign In'),
              onPressed: _loading ? () {} : _submit,
            ),
            const SizedBox(height: 14),
            SecondaryButton(
              label: _isSignUp
                  ? 'I already have an account'
                  : 'New here? Create account',
              onPressed: () => setState(() {
                _isSignUp = !_isSignUp;
                _error = null;
              }),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                // Apple sign-in is native to iOS only — hidden on Android.
                if (SocialAuth.appleAvailable) ...[
                  Expanded(
                    child: ProviderButton(
                      label: 'Continue with Apple',
                      icon: CupertinoIcons.device_phone_portrait,
                      onTap: _loading ? () {} : () => _social(SocialAuth.apple),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: ProviderButton(
                    label: 'Continue with Google',
                    icon: CupertinoIcons.globe,
                    leading: Image.asset(
                      'assets/images/google_g.png',
                      width: 20,
                      height: 20,
                    ),
                    onTap: _loading ? () {} : () => _social(SocialAuth.google),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextButton(
              onPressed: () => enterAsGuest(context),
              child: const Center(child: Text('Continue as Guest')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _social(Future<UserCredential> Function() provider) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final credential = await provider();
      final user = credential.user;
      if (user != null) {
        await AppRepository.instance.ensureUserProfile(user);
      }
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (error) {
      setState(() => _error = friendlyAuthError(error));
    } catch (error) {
      setState(() => _error = friendlyAuthError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == 2) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 22),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const MainShell()),
                  ),
                  child: const Text('Skip'),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: (value) => setState(() => _page = value),
                  children: const [
                    BookCourtsOnboarding(),
                    MatchmakingOnboarding(),
                    RewardsOnboarding(),
                  ],
                ),
              ),
              Row(
                children: [
                  ...List.generate(
                    3,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: index == _page ? 18 : 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 7),
                      decoration: BoxDecoration(
                        color: index == _page
                            ? AppColors.purple
                            : const Color(0xFFD4D7DE),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 58,
                    height: 58,
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.purple,
                        shape: const CircleBorder(),
                      ),
                      child: const Icon(CupertinoIcons.arrow_right),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BookCourtsOnboarding extends StatelessWidget {
  const BookCourtsOnboarding({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingLayout(
      title: 'Book Any Court',
      accent: 'Any Court',
      subtitle: 'Explore top academies and book in just a few taps.',
      footer: const Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          SportChip(label: 'Basketball', selected: true),
          SportChip(label: 'Padel'),
          SportChip(label: 'Volleyball'),
          SportChip(label: '3x3'),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const SportImageCard(height: 250, icon: CupertinoIcons.sportscourt),
          Positioned(
            left: -4,
            right: -4,
            bottom: -46,
            child: CardBox(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const SportImageThumb(size: 76),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Infinity Sports',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Basketball Court',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'AED 210 / hr',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MatchmakingOnboarding extends StatelessWidget {
  const MatchmakingOnboarding({super.key});

  @override
  Widget build(BuildContext context) {
    return const OnboardingLayout(
      title: 'Find Players\nMatch & Play',
      accent: 'Match & Play',
      subtitle: 'Join open matches or let us find the perfect players for you.',
      child: MatchQualityCard(compact: false),
    );
  }
}

class RewardsOnboarding extends StatelessWidget {
  const RewardsOnboarding({super.key});

  @override
  Widget build(BuildContext context) {
    return const OnboardingLayout(
      title: 'Earn. Level Up.\nGet Rewards.',
      accent: 'Level Up.',
      subtitle: 'Gain XP, climb the leaderboard and unlock amazing offers.',
      child: LevelCard(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Populate the catalog on first run (no-op if already seeded or if
    // write rules reject it — the UI falls back to bundled data either way).
    CatalogService.instance.seedIfEmpty();
    unawaited(DeepLinkService.consumePending());
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onTabChange: (index) => setState(() => _index = index)),
      const BookScreen(),
      const PlayScreen(),
      const RewardsScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: CardBox(
          radius: 28,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _TabItem(
                icon: CupertinoIcons.house_fill,
                label: 'Home',
                active: _index == 0,
                onTap: () => setState(() => _index = 0),
              ),
              _TabItem(
                icon: CupertinoIcons.calendar,
                label: 'Book',
                active: _index == 1,
                onTap: () => setState(() => _index = 1),
              ),
              _TabItem(
                icon: CupertinoIcons.game_controller,
                label: 'Play',
                active: _index == 2,
                onTap: () => setState(() => _index = 2),
              ),
              _TabItem(
                icon: CupertinoIcons.gift,
                label: 'Rewards',
                active: _index == 3,
                onTap: () => setState(() => _index = 3),
              ),
              _TabItem(
                icon: CupertinoIcons.person,
                label: 'Profile',
                active: _index == 4,
                onTap: () => setState(() => _index = 4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onTabChange});

  final ValueChanged<int> onTabChange;

  @override
  Widget build(BuildContext context) {
    return AppScrollPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StreamBuilder<Map<String, dynamic>>(
            stream: AppRepository.instance.currentUserDoc(),
            builder: (context, snapshot) {
              final data = snapshot.data ?? const {};
              final fullName = (data['displayName'] ?? '').toString().trim();
              final firstName = fullName.isEmpty
                  ? 'Champion'
                  : fullName.split(' ').first;
              return ValueListenableBuilder<AppLocation?>(
                valueListenable: LocationService.instance.current,
                builder: (context, location, _) => HeaderRow(
                  title: 'Good Morning,\n$firstName',
                  subtitle: location?.label ?? 'Choose your location',
                  onLocationTap: () async {
                    await Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const LocationPickerScreen(),
                      ),
                    );
                  },
                  trailing: Row(
                    children: [
                      IconButton.filledTonal(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const NotificationsScreen(),
                          ),
                        ),
                        icon: const Icon(CupertinoIcons.bell),
                      ),
                      const SizedBox(width: 8),
                      Avatar(
                        name: firstName.isEmpty
                            ? 'A'
                            : firstName.characters.first.toUpperCase(),
                        size: 42,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          DarkFeatureCard(
            title: 'Next Match',
            subtitle: 'Basketball 5v5',
            meta: 'Today, 8:00 PM  •  Dubai Sports World',
            cta: 'Join',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const MatchFoundScreen())),
          ),
          const SizedBox(height: 22),
          SectionHeader(title: 'Quick Actions', onSeeAll: () {}),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: QuickAction(
                  icon: CupertinoIcons.calendar_badge_plus,
                  label: 'Book Court',
                  onTap: () => onTabChange(1),
                ),
              ),
              Expanded(
                child: QuickAction(
                  icon: CupertinoIcons.person_2,
                  label: 'Join Match',
                  onTap: () => onTabChange(2),
                ),
              ),
              Expanded(
                child: QuickAction(
                  icon: CupertinoIcons.plus_app,
                  label: 'Create Match',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CreateMatchScreen(),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: QuickAction(
                  icon: CupertinoIcons.paperplane,
                  label: 'Invite Friends',
                  onTap: () {},
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          SectionHeader(title: 'Your Progress', onSeeAll: () {}),
          const SizedBox(height: 12),
          const ProgressSummaryCard(),
          const SizedBox(height: 22),
          SectionHeader(
            title: 'Recommended Courts',
            onSeeAll: () => onTabChange(1),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: StreamBuilder<List<Court>>(
              stream: CatalogService.instance.courts(),
              builder: (context, snapshot) {
                final list = (snapshot.hasData && snapshot.data!.isNotEmpty)
                    ? snapshot.data!
                    : kFallbackCourts;
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (_, index) =>
                      CourtCarouselCard(court: list[index]),
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 12),
                  itemCount: list.length,
                );
              },
            ),
          ),
          const SizedBox(height: 22),
          SectionHeader(
            title: 'Sponsored Academies',
            onSeeAll: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AcademiesListScreen()),
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<Academy>>(
            stream: CatalogService.instance.academies(),
            builder: (context, snapshot) {
              final list = (snapshot.hasData && snapshot.data!.isNotEmpty)
                  ? snapshot.data!
                  : kFallbackAcademies;
              return Column(
                children: [
                  for (final academy in list.take(2))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: AcademyHomeCard(academy: academy),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Compact sponsored academy card used on the Home tab.
class AcademyHomeCard extends StatelessWidget {
  const AcademyHomeCard({super.key, required this.academy});

  final Academy academy;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AcademyProfileScreen(academy: academy),
        ),
      ),
      child: CardBox(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: academy.gradient),
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: academy.imageUrl.isEmpty
                    ? Icon(
                        academy.icon,
                        color: Colors.white.withValues(alpha: .7),
                        size: 30,
                      )
                    : CachedNetworkImage(
                        imageUrl: academy.imageUrl,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Icon(
                          academy.icon,
                          color: Colors.white.withValues(alpha: .7),
                          size: 30,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          academy.name,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (academy.featured) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.gold.withValues(alpha: .18),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Featured',
                            style: TextStyle(
                              color: Color(0xFFB8860B),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    academy.sports,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_right,
              color: AppColors.muted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class BookScreen extends StatelessWidget {
  const BookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScrollPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ValueListenableBuilder<AppLocation?>(
            valueListenable: LocationService.instance.current,
            builder: (context, location, _) => HeaderRow(
              title: 'Book a Court',
              subtitle: location?.label ?? 'Choose your location',
              onLocationTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
              ),
              trailing: IconButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MapViewScreen()),
                ),
                icon: const Icon(CupertinoIcons.map, size: 24),
              ),
            ),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchResultsScreen()),
            ),
            child: const SearchBox(),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: const [
                SportChip(label: 'All'),
                SportChip(label: 'Basketball', selected: true),
                SportChip(label: 'Padel'),
                SportChip(label: 'Volleyball'),
                SportChip(label: '3x3'),
              ],
            ),
          ),
          const SizedBox(height: 22),
          SectionHeader(title: 'Nearby Courts', onSeeAll: () {}),
          const SizedBox(height: 12),
          StreamBuilder<List<Court>>(
            stream: CatalogService.instance.courts(),
            builder: (context, snapshot) {
              final list = (snapshot.hasData && snapshot.data!.isNotEmpty)
                  ? snapshot.data!
                  : kFallbackCourts;
              return ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemBuilder: (_, index) => CourtListCard(court: list[index]),
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemCount: list.length,
              );
            },
          ),
        ],
      ),
    );
  }
}

class PlayScreen extends StatelessWidget {
  const PlayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScrollPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HeaderRow(
            title: 'Find your\nnext match',
            subtitle: 'Ranked and casual games near you',
            trailing: Icon(CupertinoIcons.slider_horizontal_3, size: 26),
          ),
          const SizedBox(height: 18),
          DarkFeatureCard(
            title: 'Best match for you',
            subtitle: '95% Match Quality',
            meta: 'Basketball 5v5  •  Intermediate  •  1.2 km',
            cta: 'View',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const MatchFoundScreen())),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Create Match',
            icon: CupertinoIcons.plus,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CreateMatchScreen()),
            ),
          ),
          const SizedBox(height: 10),
          SecondaryButton(
            label: 'Browse Tournaments',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TournamentsScreen()),
            ),
          ),
          const SizedBox(height: 22),
          SectionHeader(
            title: 'Open Matches',
            onSeeAll: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OpenMatchesScreen()),
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<OpenMatch>>(
            stream: openMatchesStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final list = snapshot.data ?? const <OpenMatch>[];
              if (list.isEmpty) {
                return const CardBox(
                  child: Text(
                    'No open matches yet. Create the first live match.',
                  ),
                );
              }
              return Column(
                children: [
                  for (final match in list.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OpenMatchCard(match: match),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class RewardsScreen extends StatelessWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScrollPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              'Your Rewards',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 22),
          GestureDetector(
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const WalletScreen())),
            child: const RewardsPointsCard(),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: const [
                SportChip(label: 'All Offers', selected: true, dark: true),
                SportChip(label: 'Academy'),
                SportChip(label: 'Sponsors'),
                SportChip(label: 'My Coupons'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          StreamBuilder<List<Offer>>(
            stream: CatalogService.instance.offers(),
            builder: (context, snapshot) {
              final list = (snapshot.hasData && snapshot.data!.isNotEmpty)
                  ? snapshot.data!
                  : kFallbackOffers;
              return Column(
                children: [
                  for (final offer in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => OfferDetailsScreen(
                              offerId: offer.id,
                              title: offer.title,
                              partner: offer.partner,
                              points: offer.points,
                              colors: offer.colors,
                            ),
                          ),
                        ),
                        child: OfferCard(
                          title: offer.title,
                          partner: offer.partner,
                          points: offer.points,
                          colors: offer.colors,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScrollPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                ),
                icon: const Icon(CupertinoIcons.pencil),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                icon: const Icon(CupertinoIcons.gear_alt),
              ),
            ],
          ),
          StreamBuilder<Map<String, dynamic>>(
            stream: AppRepository.instance.currentUserDoc(),
            builder: (context, snapshot) {
              final data = snapshot.data ?? const {};
              final name = (data['displayName'] ?? 'Guest Player').toString();
              final rank = (data['rankTitle'] ?? 'Rookie').toString();
              final level = (data['level'] as num?)?.toInt() ?? 1;
              final matches = (data['matches'] as num?)?.toInt() ?? 0;
              final winRate = (data['winRate'] as num?)?.toInt() ?? 0;
              final ratingValue = (data['rating'] as num?)?.toDouble() ?? 0;
              final rating = ratingValue <= 0
                  ? '—'
                  : ratingValue.toStringAsFixed(1);
              final points = formatThousands(
                (data['points'] as num?)?.toInt() ?? 0,
              );
              return Column(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LevelDetailScreen(),
                      ),
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Avatar(
                                name: name.isEmpty
                                    ? 'A'
                                    : name.characters.first.toUpperCase(),
                                size: 92,
                              ),
                              Positioned(
                                right: -6,
                                bottom: 2,
                                child: LevelBadge(text: '$level', size: 34),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            rank,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PlayerStatsScreen(),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: StatCard(value: '$matches', label: 'Matches'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StatCard(
                            value: '$winRate%',
                            label: 'Win Rate',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StatCard(value: rating, label: 'Rating'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StatCard(value: points, label: 'Points'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          const Text(
            'My Sports',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Expanded(
                child: SportSquare(
                  icon: Icons.sports_basketball,
                  label: 'Basketball',
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: SportSquare(icon: CupertinoIcons.circle, label: 'Padel'),
              ),
              SizedBox(width: 10),
              Expanded(
                child: SportSquare(
                  icon: CupertinoIcons.sportscourt,
                  label: 'Volleyball',
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: SportSquare(icon: CupertinoIcons.person_3, label: '3x3'),
              ),
            ],
          ),
          const SizedBox(height: 22),
          SectionHeader(
            title: 'Recent Achievements',
            onSeeAll: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AchievementsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              AchievementBadge(
                icon: CupertinoIcons.shield_lefthalf_fill,
                color: AppColors.green,
              ),
              AchievementBadge(
                icon: CupertinoIcons.flame_fill,
                color: AppColors.gold,
              ),
              AchievementBadge(
                icon: CupertinoIcons.star_fill,
                color: Color(0xFF3B82F6),
              ),
              AchievementBadge(
                icon: CupertinoIcons.bolt_fill,
                color: AppColors.purple,
              ),
            ],
          ),
          const SizedBox(height: 22),
          SettingsTile(
            icon: CupertinoIcons.chart_bar_alt_fill,
            title: 'Leaderboard',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
            ),
          ),
          SettingsTile(
            icon: CupertinoIcons.person_2_fill,
            title: 'Friends',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const FriendsScreen())),
          ),
          SettingsTile(
            icon: CupertinoIcons.creditcard_fill,
            title: 'Wallet',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const WalletScreen())),
          ),
          SettingsTile(
            icon: CupertinoIcons.star_lefthalf_fill,
            title: 'My Reviews',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PlayerReviewsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class CourtDetailsScreen extends StatelessWidget {
  const CourtDetailsScreen({super.key, required this.court});

  final Court court;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        topPadding: 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SportImageCard(
                  height: 260,
                  icon: court.icon,
                  gradient: court.gradient,
                  imageUrl: court.imageUrl,
                ),
                Positioned(
                  top: 18,
                  left: 10,
                  child: SafeArea(
                    child: CircleIconButton(
                      icon: CupertinoIcons.arrow_left,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
                Positioned(
                  top: 18,
                  right: 10,
                  child: SafeArea(
                    child: StreamBuilder<bool>(
                      stream: AppRepository.instance.isFavorite(court.id),
                      builder: (context, snapshot) {
                        final favorite = snapshot.data ?? false;
                        return CircleIconButton(
                          icon: favorite
                              ? CupertinoIcons.heart_fill
                              : CupertinoIcons.heart,
                          onTap: court.id.isEmpty
                              ? null
                              : () => AppRepository.instance.toggleFavorite(
                                  court,
                                  !favorite,
                                ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              court.name,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              '${court.subtitle}  •  ${court.distanceFrom(LocationService.instance.current.value)}',
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  CupertinoIcons.star_fill,
                  color: AppColors.gold,
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(
                  court.rating,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Row(
              children: [
                Facility(icon: CupertinoIcons.house, label: 'Indoor'),
                Facility(icon: CupertinoIcons.car_detailed, label: 'Parking'),
                Facility(icon: CupertinoIcons.drop, label: 'Shower'),
                Facility(icon: Icons.local_cafe_outlined, label: 'Cafe'),
                Facility(icon: CupertinoIcons.lock, label: 'Locker'),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              'About',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Professional indoor court with wooden floor, premium lighting, lockers, and easy parking. Perfect for training, ranked games, and weekend matches.',
              style: TextStyle(
                color: AppColors.muted,
                height: 1.45,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 22),
            SectionHeader(title: 'Available Slots', onSeeAll: () {}),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SlotChip(time: '6:00 PM', price: 'AED 210'),
                SlotChip(time: '7:00 PM', price: 'AED 210'),
                SlotChip(time: '8:00 PM', price: 'AED 210', selected: true),
                SlotChip(time: '9:00 PM', price: 'AED 210'),
              ],
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Price per hour',
                        style: TextStyle(color: AppColors.muted),
                      ),
                      Text(
                        court.price,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PrimaryButton(
                    label: 'Book Now',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SlotSelectionScreen(court: court),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class BookingSetupScreen extends StatefulWidget {
  const BookingSetupScreen({
    super.key,
    required this.court,
    required this.startUtc,
    required this.endUtc,
  });

  final Court court;
  final DateTime startUtc;
  final DateTime endUtc;

  @override
  State<BookingSetupScreen> createState() => _BookingSetupScreenState();
}

class _BookingSetupScreenState extends State<BookingSetupScreen> {
  int _players = 4;
  String _mode = 'invite';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'New Booking',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            const StepIndicator(active: 1),
            const SizedBox(height: 22),
            const Text(
              'How do you want to play?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => setState(() => _mode = 'self'),
              child: OptionTile(
                icon: CupertinoIcons.person,
                title: 'Book for Myself',
                subtitle: 'I will bring my own players',
                selected: _mode == 'self',
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => setState(() => _mode = 'invite'),
              child: OptionTile(
                icon: CupertinoIcons.person_2,
                title: 'Invite Friends',
                subtitle: 'Create a shareable link after booking',
                selected: _mode == 'invite',
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => setState(() => _mode = 'matchmaking'),
              child: OptionTile(
                icon: CupertinoIcons.sparkles,
                title: 'Find Players (Matchmaking)',
                subtitle: 'Publish this booking to eligible players',
                selected: _mode == 'matchmaking',
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Match Details',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            CardBox(
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Players Needed',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      CounterButton(
                        icon: CupertinoIcons.minus,
                        onTap: () => setState(
                          () => _players = math.max(1, _players - 1),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Center(
                          child: Text(
                            '$_players',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      CounterButton(
                        icon: CupertinoIcons.plus,
                        onTap: () => setState(() => _players++),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const SelectRow(label: 'Skill Range', value: 'Intermediate'),
                  const SizedBox(height: 12),
                  const SelectRow(label: 'Match Type', value: 'Competitive'),
                ],
              ),
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              label: 'Continue to Payment',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PaymentScreen(
                    court: widget.court,
                    startUtc: widget.startUtc,
                    endUtc: widget.endUtc,
                    playerCapacity: _players,
                    matchmaking: _mode == 'matchmaking',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FindingPlayersScreen extends StatefulWidget {
  const FindingPlayersScreen({super.key, required this.matchId});
  final String matchId;

  @override
  State<FindingPlayersScreen> createState() => _FindingPlayersScreenState();
}

class _FindingPlayersScreenState extends State<FindingPlayersScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DarkGradient(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 28),
                const Text(
                  'Finding Players',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please wait while we find the perfect players for your match.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .72),
                    height: 1.4,
                  ),
                ),
                const Spacer(),
                const OrbitFinder(),
                const Spacer(),
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('matches')
                      .doc(widget.matchId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final data = snapshot.data?.data();
                    final joined = (data?['players'] as List?)?.length ?? 1;
                    final capacity = (data?['capacity'] as num?)?.toInt() ?? 1;
                    return Column(
                      children: [
                        ChecklistItem(
                          done: snapshot.hasData,
                          text: 'Match published',
                        ),
                        ChecklistItem(
                          done: joined > 1,
                          text: '$joined of $capacity players joined',
                        ),
                        ChecklistItem(
                          done: joined >= capacity,
                          text: joined >= capacity
                              ? 'Team complete'
                              : 'Waiting for eligible players',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'This screen updates live. You can leave it and return from My Matches.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .65),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: .12),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Continue browsing'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MatchFoundScreen extends StatelessWidget {
  const MatchFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DarkGradient(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleIconButton(
                  icon: CupertinoIcons.arrow_left,
                  dark: true,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: 12),
                const Center(
                  child: Column(
                    children: [
                      Text(
                        'Match Found!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        '95% Match Quality',
                        style: TextStyle(
                          color: AppColors.green,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: const [
                    Expanded(
                      child: PlayerMatchCard(name: 'You', level: 'Level 12'),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: PlayerMatchCard(name: 'Omar', level: 'Level 11'),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: PlayerMatchCard(name: 'Zayd', level: 'Level 10'),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: PlayerMatchCard(name: 'Mareo', level: 'Level 12'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                CardBox(
                  color: Colors.white.withValues(alpha: .05),
                  borderColor: Colors.white.withValues(alpha: .08),
                  child: const Column(
                    children: [
                      DetailRow(
                        label: 'Sport',
                        value: 'Basketball 5v5',
                        light: true,
                      ),
                      DetailRow(
                        label: 'Date',
                        value: 'Today, 20 May',
                        light: true,
                      ),
                      DetailRow(
                        label: 'Time',
                        value: '8:00 PM - 9:00 PM',
                        light: true,
                      ),
                      DetailRow(
                        label: 'Court',
                        value: 'Infinity Sports Center',
                        light: true,
                      ),
                      Divider(color: Colors.white12, height: 26),
                      Row(
                        children: [
                          Expanded(
                            child: PriceBlock(
                              label: 'Total Price',
                              value: 'AED 210',
                            ),
                          ),
                          Expanded(
                            child: PriceBlock(
                              label: 'Per Player',
                              value: 'AED 52.5',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        label: 'Not Now',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Join Match',
                        onPressed: () => Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({
    super.key,
    required this.court,
    required this.startUtc,
    required this.endUtc,
    required this.playerCapacity,
    required this.matchmaking,
  });

  final Court court;
  final DateTime startUtc;
  final DateTime endUtc;
  final int playerCapacity;
  final bool matchmaking;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  bool _loading = false;

  Future<void> _confirm() async {
    setState(() => _loading = true);
    try {
      final bookingId = await AppRepository.instance.createBooking(
        court: widget.court,
        matchmaking: widget.matchmaking,
        startUtc: widget.startUtc,
        endUtc: widget.endUtc,
        playerCapacity: widget.playerCapacity,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => BookingConfirmationScreen(
            bookingId: bookingId,
            court: widget.court,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Review booking',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 22),
            CardBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Booking Summary',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 14),
                  DetailRow(label: 'Court', value: widget.court.name),
                  DetailRow(
                    label: 'Date',
                    value: DateFormat(
                      'EEE, d MMM',
                    ).format(widget.startUtc.toLocal()),
                  ),
                  DetailRow(
                    label: 'Time',
                    value:
                        '${DateFormat.jm().format(widget.startUtc.toLocal())} - ${DateFormat.jm().format(widget.endUtc.toLocal())}',
                  ),
                  DetailRow(label: 'Price', value: widget.court.price),
                ],
              ),
            ),
            const SizedBox(height: 16),
            CardBox(
              child: Column(
                children: [
                  const OptionTile(
                    icon: CupertinoIcons.money_dollar,
                    title: 'Cash at venue',
                    subtitle:
                        'Payment remains pending until academy staff collect cash',
                    selected: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: _loading ? 'Confirming...' : 'Confirm Booking',
              onPressed: _loading ? () {} : _confirm,
            ),
          ],
        ),
      ),
    );
  }
}

class BookingConfirmationScreen extends StatelessWidget {
  const BookingConfirmationScreen({
    super.key,
    required this.bookingId,
    required this.court,
  });

  final String bookingId;
  final Court court;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          children: [
            const SizedBox(height: 32),
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.green.withValues(alpha: .14),
              ),
              child: const Icon(
                CupertinoIcons.checkmark_alt_circle_fill,
                color: AppColors.green,
                size: 62,
              ),
            ).animate().scale(duration: 320.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 22),
            const Text(
              'Booking Requested',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'Booking #${bookingId.substring(0, math.min(6, bookingId.length)).toUpperCase()}',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 22),
            CardBox(
              child: Column(
                children: [
                  DetailRow(label: 'Court', value: court.name),
                  const DetailRow(label: 'Date', value: 'Today, 20 May'),
                  const DetailRow(label: 'Time', value: '8:00 PM - 9:00 PM'),
                  const DetailRow(label: 'Payment', value: 'Cash - Pending'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Invite Players',
              onPressed: () async {
                try {
                  final url = await AppRepository.instance.createBookingInvite(
                    bookingId,
                  );
                  await SharePlus.instance.share(
                    ShareParams(
                      text: 'Join my PlayUp booking at ${court.name}: $url',
                      subject: 'Join my PlayUp booking',
                    ),
                  );
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                }
              },
            ),
            const SizedBox(height: 10),
            SecondaryButton(
              label: 'View My Bookings',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MyBookingsScreen()),
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              icon: const Icon(CupertinoIcons.house_fill),
              label: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}

class MyBookingsScreen extends StatelessWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'My Bookings',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: AppRepository.instance.myBookings(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CupertinoActivityIndicator());
                }
                if (docs.isEmpty) {
                  return EmptyState(
                    icon: CupertinoIcons.calendar,
                    title: 'No bookings yet',
                    message: 'Book a court and it will appear here.',
                    action: 'Book a Court',
                    onTap: () => Navigator.of(context).pop(),
                  );
                }
                return ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: docs.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    return GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              BookingDetailsScreen(court: courts.first),
                        ),
                      ),
                      child: BookingTile(data: data),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Notifications',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            if (uid == null)
              const CardBox(child: Text('Sign in to view notifications.'))
            else
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('notifications')
                    .where('userId', isEqualTo: uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data?.docs.toList() ?? [];
                  docs.sort((a, b) {
                    final at =
                        (a.data()['createdAt'] as Timestamp?)
                            ?.millisecondsSinceEpoch ??
                        0;
                    final bt =
                        (b.data()['createdAt'] as Timestamp?)
                            ?.millisecondsSinceEpoch ??
                        0;
                    return bt.compareTo(at);
                  });
                  if (docs.isEmpty) {
                    return const CardBox(child: Text('No notifications yet.'));
                  }
                  return Column(
                    children: docs.map((doc) {
                      final item = doc.data();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: CardBox(
                          child: Row(
                            children: [
                              const Icon(
                                CupertinoIcons.bell_fill,
                                color: AppColors.purple,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['title']?.toString() ??
                                          'PlayUp update',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      item['body']?.toString() ??
                                          item['type']?.toString() ??
                                          '',
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class MatchChatScreen extends StatefulWidget {
  const MatchChatScreen({super.key, this.matchId});
  final String? matchId;

  @override
  State<MatchChatScreen> createState() => _MatchChatScreenState();
}

class _MatchChatScreenState extends State<MatchChatScreen> {
  final _message = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Match Chat',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            if (widget.matchId == null)
              const CardBox(
                child: Text(
                  'Open a live match you joined to use its group chat.',
                ),
              )
            else
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: AppRepository.instance.matchMessages(widget.matchId!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return CardBox(
                      child: Text('Chat unavailable. ${snapshot.error}'),
                    );
                  }
                  final messages = snapshot.data?.docs ?? const [];
                  if (messages.isEmpty) {
                    return const CardBox(
                      child: Text('No messages yet. Start the conversation.'),
                    );
                  }
                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  return Column(
                    children: messages.map((doc) {
                      final data = doc.data();
                      final mine = data['userId'] == uid;
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: mine ? AppColors.purple : Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Text(
                            data['body']?.toString() ?? '',
                            style: TextStyle(
                              color: mine ? Colors.white : AppColors.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _message,
              label: 'Message the players',
              icon: CupertinoIcons.chat_bubble,
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: _sending ? 'Sending...' : 'Send',
              onPressed: () async {
                final body = _message.text.trim();
                if (body.isEmpty || widget.matchId == null || _sending) return;
                setState(() => _sending = true);
                try {
                  await AppRepository.instance.sendMatchMessage(
                    widget.matchId!,
                    body,
                  );
                  _message.clear();
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                } finally {
                  if (mounted) setState(() => _sending = false);
                }
              },
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Report or Block Player',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const SupportScreen(category: 'Report player'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PostMatchRatingScreen extends StatefulWidget {
  const PostMatchRatingScreen({super.key});

  @override
  State<PostMatchRatingScreen> createState() => _PostMatchRatingScreenState();
}

class _PostMatchRatingScreenState extends State<PostMatchRatingScreen> {
  int _rating = 5;
  final _comment = TextEditingController();
  final _tags = <String>{'Good teamwork', 'On time'};

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allTags = [
      'Good teamwork',
      'On time',
      'Fair play',
      'Skilled',
      'Friendly',
      'No show',
    ];
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Rate Match',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            const Text(
              'How was the game?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            Row(
              children: List.generate(
                5,
                (index) => IconButton(
                  onPressed: () => setState(() => _rating = index + 1),
                  icon: Icon(
                    index < _rating
                        ? CupertinoIcons.star_fill
                        : CupertinoIcons.star,
                    color: AppColors.gold,
                    size: 34,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: allTags.map((tag) {
                final selected = _tags.contains(tag);
                return GestureDetector(
                  onTap: () => setState(() {
                    selected ? _tags.remove(tag) : _tags.add(tag);
                  }),
                  child: SportChip(label: tag, selected: selected),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _comment,
              label: 'Optional comment',
              icon: CupertinoIcons.text_bubble,
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Submit Rating',
              onPressed: () async {
                await AppRepository.instance.submitRating(
                  _rating,
                  _tags.toList(),
                  _comment.text.trim(),
                );
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Settings',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            SettingsTile(
              icon: CupertinoIcons.calendar,
              title: 'My Bookings',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MyBookingsScreen()),
              ),
            ),
            SettingsTile(
              icon: CupertinoIcons.chat_bubble_2,
              title: 'Match Chat',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MatchChatScreen()),
              ),
            ),
            SettingsTile(
              icon: CupertinoIcons.star,
              title: 'Post-Match Rating',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PostMatchRatingScreen(),
                ),
              ),
            ),
            SettingsTile(
              icon: CupertinoIcons.person_crop_circle,
              title: 'Edit Profile',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              ),
            ),
            SettingsTile(
              icon: CupertinoIcons.person_2,
              title: 'Friends',
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const FriendsScreen())),
            ),
            SettingsTile(
              icon: CupertinoIcons.question_circle,
              title: 'Help Center',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HelpCenterScreen()),
              ),
            ),
            SettingsTile(
              icon: CupertinoIcons.bell,
              title: 'Notification Settings',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen(),
                ),
              ),
            ),
            SettingsTile(
              icon: CupertinoIcons.lock_shield,
              title: 'Privacy Settings',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PrivacySettingsScreen(),
                ),
              ),
            ),
            const BiometricSettingsTile(),
            const ThemeModeTile(),
            SettingsTile(
              icon: CupertinoIcons.creditcard,
              title: 'Payment Methods',
              onTap: () => _simpleSheet(
                context,
                'Card and wallet management will connect to your payment provider.',
              ),
            ),
            const SizedBox(height: 18),
            SecondaryButton(
              label: 'Sign Out',
              onPressed: () => _signOut(context),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton(
                onPressed: () => _confirmDelete(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Delete Account',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _simpleSheet(BuildContext context, String message) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            style: const TextStyle(fontSize: 16, height: 1.4),
          ),
        ),
      ),
    );
  }

  /// Resets the whole navigation stack back to the auth gate. Works whether the
  /// user reached the app via real auth or the local guest fallback (where
  /// MainShell is the root route and popUntil would not reach the welcome page).
  void _resetToAuth(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await SocialAuth.signOutEverywhere();
    } catch (_) {
      // Ignore provider sign-out errors; always fall through to auth reset.
    }
    if (context.mounted) _resetToAuth(context);
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This removes your account from Firebase Auth. Firestore profile cleanup can be handled by a Cloud Function.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Delete'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirebaseAuth.instance.currentUser?.delete();
    } on FirebaseAuthException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.message ?? 'Please sign in again before deleting.',
            ),
          ),
        );
      }
    }
    await SocialAuth.signOutEverywhere();
    if (context.mounted) _resetToAuth(context);
  }
}

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, required this.category});

  final String category;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: widget.category,
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 20),
            const Text(
              'How can we help?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _message,
              label: 'Describe the issue',
              icon: CupertinoIcons.text_bubble,
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: 'Submit Ticket',
              onPressed: () async {
                await AppRepository.instance.submitSupportTicket(
                  widget.category,
                  _message.text.trim(),
                );
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class AppScrollPage extends StatelessWidget {
  const AppScrollPage({super.key, required this.child, this.topPadding = 18});

  final Widget child;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: topPadding > 0,
      child: ListView(
        padding: EdgeInsets.fromLTRB(18, topPadding, 18, 110),
        children: [child],
      ),
    );
  }
}

class OnboardingLayout extends StatelessWidget {
  const OnboardingLayout({
    super.key,
    required this.title,
    required this.accent,
    required this.subtitle,
    required this.child,
    this.footer,
  });

  final String title;
  final String accent;
  final String subtitle;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 28,
              height: 1.1,
              fontWeight: FontWeight.w900,
            ),
            children: _accentTitle(title, accent),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppColors.muted,
            height: 1.45,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 32),
        child,
        const SizedBox(height: 62),
        footer ?? const SizedBox.shrink(),
      ],
    );
  }
}

List<TextSpan> _accentTitle(String title, String accent) {
  final index = title.indexOf(accent);
  if (index < 0) return [TextSpan(text: title)];
  return [
    TextSpan(text: title.substring(0, index)),
    TextSpan(
      text: accent,
      style: const TextStyle(color: AppColors.purple),
    ),
    TextSpan(text: title.substring(index + accent.length)),
  ];
}

class HeaderRow extends StatelessWidget {
  const HeaderRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onLocationTap,
  });

  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onLocationTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 24,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: onLocationTap,
                child: Row(
                  children: [
                    const Icon(
                      CupertinoIcons.location_solid,
                      size: 14,
                      color: AppColors.muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                    if (onLocationTap != null) ...[
                      const SizedBox(width: 2),
                      const Icon(
                        CupertinoIcons.chevron_down,
                        size: 12,
                        color: AppColors.muted,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        trailing,
      ],
    );
  }
}

class PageTopBar extends StatelessWidget {
  const PageTopBar({super.key, required this.title, this.onBack});

  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null)
          CircleIconButton(icon: CupertinoIcons.arrow_left, onTap: onBack!)
        else
          const SizedBox(width: 46),
        Expanded(
          child: Center(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ),
        ),
        const SizedBox(width: 46),
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, required this.onSeeAll});

  final String title;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ),
        TextButton(onPressed: onSeeAll, child: const Text('See All')),
      ],
    );
  }
}

class CardBox extends StatelessWidget {
  const CardBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.color = AppColors.surface,
    this.borderColor = AppColors.line,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final effectiveColor = dark && color == AppColors.surface
        ? const Color(0xFF111B2B)
        : color;
    final effectiveBorder = dark && borderColor == AppColors.line
        ? const Color(0xFF263449)
        : borderColor;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: effectiveColor,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: effectiveBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .06),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class DarkFeatureCard extends StatelessWidget {
  const DarkFeatureCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.cta,
    required this.onPressed,
  });

  final String title;
  final String subtitle;
  final String meta;
  final String cta;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (title == 'Best match for you') {
      return StreamBuilder<List<OpenMatch>>(
        stream: openMatchesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final matches = snapshot.data ?? const <OpenMatch>[];
          if (matches.isEmpty) {
            return const CardBox(
              child: Text(
                'No live match recommendation yet. Create a match to start matchmaking.',
              ),
            );
          }
          final match = matches.first;
          return DarkFeatureCard(
            title: 'Recommended live match',
            subtitle: match.title,
            meta: '${match.sport} - ${match.skill} - ${match.court}',
            cta: 'View',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MatchDetailsScreen(match: match),
              ),
            ),
          );
        },
      );
    }
    return CardBox(
      radius: 24,
      padding: const EdgeInsets.all(18),
      color: AppColors.dark,
      borderColor: const Color(0xFF153020),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -44,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.purple.withValues(alpha: .42),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .72),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      meta,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .72),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 104,
                child: FilledButton(
                  onPressed: onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(70, 46),
                  ),
                  child: Text(cta),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final leadingIcon = icon;
    void handlePress() {
      HapticFeedback.selectionClick();
      onPressed?.call();
    }

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: onPressed == null ? null : handlePress,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.purple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (leadingIcon != null) ...[
              Icon(leadingIcon, size: 18),
              const SizedBox(width: 8),
            ],
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    void handlePress() {
      HapticFeedback.selectionClick();
      onPressed();
    }

    return SizedBox(
      height: 56,
      child: FilledButton(
        onPressed: handlePress,
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surface,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class SportImageCard extends StatelessWidget {
  const SportImageCard({
    super.key,
    required this.height,
    required this.icon,
    this.gradient = const [Color(0xFF102A43), Color(0xFF1F7A8C)],
    this.imageUrl = '',
  });

  final double height;
  final IconData icon;
  final List<Color> gradient;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) =>
                    CustomPaint(painter: CourtLinesPainter()),
              )
            else ...[
              CustomPaint(painter: CourtLinesPainter()),
              Center(
                child: Icon(
                  icon,
                  color: Colors.white.withValues(alpha: .86),
                  size: 92,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class SportImageThumb extends StatelessWidget {
  const SportImageThumb({
    super.key,
    this.size = 72,
    this.gradient,
    this.imageUrl = '',
  });

  final double size;
  final List<Color>? gradient;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: gradient ?? const [Color(0xFF102A43), Color(0xFF1F7A8C)],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: imageUrl.isEmpty
            ? const Icon(CupertinoIcons.sportscourt, color: Colors.white)
            : CachedNetworkImage(
                imageUrl: imageUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) =>
                    const Icon(CupertinoIcons.sportscourt, color: Colors.white),
              ),
      ),
    );
  }
}

class CourtLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * .14,
        size.height * .18,
        size.width * .72,
        size.height * .64,
      ),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * .5, size.height * .18),
      Offset(size.width * .5, size.height * .82),
      paint,
    );
    canvas.drawCircle(
      Offset(size.width * .5, size.height * .5),
      size.width * .12,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SportChip extends StatelessWidget {
  const SportChip({
    super.key,
    required this.label,
    this.selected = false,
    this.dark = false,
  });

  final String label;
  final bool selected;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      decoration: BoxDecoration(
        color: selected
            ? (dark ? AppColors.dark : AppColors.purple)
            : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected ? Colors.transparent : AppColors.line,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : AppColors.ink,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

class MatchQualityCard extends StatelessWidget {
  const MatchQualityCard({super.key, required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      color: AppColors.dark,
      borderColor: const Color(0xFF153020),
      radius: 24,
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          const Text(
            'Match Found!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '92% Match Quality',
            style: TextStyle(
              color: AppColors.green,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Avatar(name: 'A', size: 38),
              Avatar(name: 'O', size: 38),
              Avatar(name: 'Z', size: 38),
              Avatar(name: 'M', size: 38),
              SizedBox(width: 8),
              Text(
                '+2',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const Divider(height: 32, color: Colors.white12),
          const DetailRow(label: 'Sport', value: 'Basketball 5v5', light: true),
          const DetailRow(
            label: 'Level Range',
            value: 'Intermediate',
            light: true,
          ),
          const DetailRow(label: 'Time', value: 'Today, 8:00 PM', light: true),
          const DetailRow(
            label: 'Location',
            value: 'Dubai Sports World',
            light: true,
          ),
        ],
      ),
    );
  }
}

class LevelCard extends StatelessWidget {
  const LevelCard({super.key});

  @override
  Widget build(BuildContext context) {
    return CardBox(
      color: AppColors.dark,
      borderColor: const Color(0xFF153020),
      radius: 24,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LevelBadge(text: '12'),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Level',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .62),
                      ),
                    ),
                    const Text(
                      'Court Commander',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const ProgressBar(value: .92),
                    const SizedBox(height: 5),
                    Text(
                      '7,430 / 8,000 XP',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Row(
            children: [
              Expanded(
                child: DarkMetric(
                  icon: CupertinoIcons.money_dollar_circle_fill,
                  value: '3,250',
                  label: 'Points',
                  color: AppColors.gold,
                ),
              ),
              Expanded(
                child: DarkMetric(
                  icon: CupertinoIcons.shield_fill,
                  value: '68',
                  label: 'Badges',
                  color: AppColors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          CardBox(
            color: Colors.white.withValues(alpha: .05),
            borderColor: Colors.white.withValues(alpha: .08),
            padding: const EdgeInsets.all(12),
            child: const Row(
              children: [
                AchievementBadge(
                  icon: CupertinoIcons.flame_fill,
                  color: AppColors.gold,
                  small: true,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Recent Achievement\nSharpshooter',
                    style: TextStyle(
                      color: Colors.white,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProgressSummaryCard extends StatelessWidget {
  const ProgressSummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: AppRepository.instance.currentUserDoc(),
      builder: (context, snapshot) {
        final data = snapshot.data ?? const {};
        final level = (data['level'] as num?)?.toInt() ?? 1;
        final rank = (data['rankTitle'] ?? 'Rookie').toString();
        final xp = (data['xp'] as num?)?.toInt() ?? 0;
        final next = (data['nextLevelXp'] as num?)?.toInt() ?? 500;
        final progress = next <= 0 ? 0.0 : (xp / next).clamp(0.0, 1.0);
        return CardBox(
          child: Row(
            children: [
              LevelBadge(text: '$level', size: 58),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Level $level',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(rank, style: const TextStyle(color: AppColors.muted)),
                    const SizedBox(height: 12),
                    ProgressBar(value: progress, dark: false),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${formatThousands(xp)} / ${formatThousands(next)} XP',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}

class RewardsPointsCard extends StatelessWidget {
  const RewardsPointsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: AppRepository.instance.currentUserDoc(),
      builder: (context, snapshot) {
        final points = (snapshot.data?['points'] as num?)?.toInt() ?? 0;
        return CardBox(
          color: AppColors.dark,
          borderColor: const Color(0xFF153020),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Points',
                      style: TextStyle(
                        color: AppColors.gold.withValues(alpha: .9),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      formatThousands(points),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Earned through real PlayUp activity',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .68),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  CupertinoIcons.gift_fill,
                  color: AppColors.gold,
                  size: 54,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class CourtListCard extends StatelessWidget {
  const CourtListCard({super.key, required this.court});

  final Court court;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CourtDetailsScreen(court: court)),
      ),
      child: CardBox(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            SportImageThumb(
              size: 92,
              gradient: court.gradient,
              imageUrl: court.imageUrl,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    court.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    court.subtitle,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '★ ${court.rating}   ${court.distanceFrom(LocationService.instance.current.value)}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    court.price,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
            StreamBuilder<bool>(
              stream: AppRepository.instance.isFavorite(court.id),
              builder: (context, snapshot) {
                final favorite = snapshot.data ?? false;
                return IconButton(
                  tooltip: favorite ? 'Remove favorite' : 'Save favorite',
                  onPressed: court.id.isEmpty
                      ? null
                      : () => AppRepository.instance.toggleFavorite(
                          court,
                          !favorite,
                        ),
                  icon: Icon(
                    favorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
                    color: favorite ? AppColors.danger : AppColors.ink,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class CourtCarouselCard extends StatelessWidget {
  const CourtCarouselCard({super.key, required this.court});

  final Court court;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CourtDetailsScreen(court: court)),
        ),
        child: CardBox(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SportImageCard(
                height: 96,
                icon: court.icon,
                gradient: court.gradient,
                imageUrl: court.imageUrl,
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      court.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${court.rating}  •  ${court.distanceFrom(LocationService.instance.current.value)}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      court.price,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QuickAction extends StatelessWidget {
  const QuickAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.purple.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: AppColors.purple),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: active ? AppColors.purple : AppColors.muted,
                size: 21,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: active ? AppColors.purple : AppColors.muted,
                  fontWeight: active ? FontWeight.w900 : FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SearchBox extends StatelessWidget {
  const SearchBox({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF1F5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Icon(CupertinoIcons.search, color: AppColors.muted, size: 20),
          SizedBox(width: 10),
          Text(
            'Search for courts or academies',
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onChanged: onChanged,
      minLines: label.contains('Describe') ? 4 : 1,
      maxLines: label.contains('Describe') ? 6 : 1,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.purple, width: 2),
        ),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: .3)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AppColors.danger,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Lively branded banner shown on the auth screens (image + gradient + brand).
class AuthHeroBanner extends StatelessWidget {
  const AuthHeroBanner({super.key, required this.caption});

  final String caption;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 156,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/images/auth_hero.jpg', fit: BoxFit.cover),
            // Branded purple + legibility scrim over the photo.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xE67B3FF2),
                    Color(0x998B5CF6),
                    Color(0xE6120826),
                  ],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      PlayUpMark(size: 26),
                      SizedBox(width: 8),
                      Text(
                        'PlayUp',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    caption,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProviderButton extends StatelessWidget {
  const ProviderButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.leading,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Optional custom logo widget shown instead of [icon] (e.g. Google mark).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leading ?? Icon(icon, size: 19),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      child: Column(
        children: [
          Icon(icon, color: AppColors.purple, size: 42),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          PrimaryButton(label: action, onPressed: onTap),
        ],
      ),
    );
  }
}

class BookingTile extends StatelessWidget {
  const BookingTile({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      child: Row(
        children: [
          const SportImageThumb(size: 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (data['courtName'] ?? 'Court').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${data['date'] ?? 'Today'}  •  ${data['time'] ?? '8:00 PM'}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  (data['status'] ?? 'confirmed').toString().toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const MatchChatScreen())),
            icon: const Icon(CupertinoIcons.chat_bubble_2),
          ),
        ],
      ),
    );
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CardBox(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                Icon(icon, color: AppColors.purple),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const Icon(
                  CupertinoIcons.chevron_right,
                  color: AppColors.muted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OptionTile extends StatelessWidget {
  const OptionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      borderColor: selected ? AppColors.purple : AppColors.line,
      child: Row(
        children: [
          Icon(icon, color: selected ? AppColors.purple : AppColors.ink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          Icon(
            selected
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.chevron_right,
            color: selected ? AppColors.purple : AppColors.muted,
          ),
        ],
      ),
    );
  }
}

class StepIndicator extends StatelessWidget {
  const StepIndicator({super.key, required this.active});

  final int active;

  @override
  Widget build(BuildContext context) {
    final labels = ['Court', 'Players', 'Payment'];
    return Row(
      children: List.generate(labels.length, (index) {
        final selected = index == active;
        return Expanded(
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: selected ? AppColors.purple : AppColors.line,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                labels[index],
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                  color: selected ? AppColors.purple : AppColors.muted,
                ),
              ),
              if (index < labels.length - 1)
                Expanded(
                  child: Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: AppColors.line,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }
}

class SelectRow extends StatelessWidget {
  const SelectRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              const Icon(CupertinoIcons.chevron_down, size: 14),
            ],
          ),
        ),
      ],
    );
  }
}

class CounterButton extends StatelessWidget {
  const CounterButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 17),
      ),
    );
  }
}

class OrbitFinder extends StatelessWidget {
  const OrbitFinder({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ...[88.0, 134.0].map(
            (size) => Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: .12)),
              ),
            ),
          ),
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.purple, Color(0xFF3A1B78)],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.purple.withValues(alpha: .42),
                  blurRadius: 30,
                ),
              ],
            ),
            child: const PlayUpMark(size: 42),
          ),
          for (var i = 0; i < 6; i++)
            Positioned(
              left: 112 + math.cos(i * math.pi / 3) * 92,
              top: 112 + math.sin(i * math.pi / 3) * 92,
              child: Avatar(name: 'AOMRZK'[i], size: 38),
            ),
        ],
      ),
    );
  }
}

class ChecklistItem extends StatelessWidget {
  const ChecklistItem({super.key, required this.done, required this.text});

  final bool done;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            done ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
            color: done ? AppColors.green : Colors.white54,
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class PlayerMatchCard extends StatelessWidget {
  const PlayerMatchCard({super.key, required this.name, required this.level});

  final String name;
  final String level;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      color: Colors.white.withValues(alpha: .05),
      borderColor: AppColors.gold.withValues(alpha: .25),
      padding: const EdgeInsets.all(10),
      radius: 18,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: const [
              Avatar(name: 'A', size: 42),
              Positioned(
                right: -4,
                bottom: -2,
                child: Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  color: AppColors.green,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          Text(
            level,
            style: const TextStyle(
              color: AppColors.gold,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class MatchTile extends StatelessWidget {
  const MatchTile({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      child: Row(
        children: [
          const SportImageThumb(size: 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Needs 2 players  •  AED 52.5 each',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const MatchFoundScreen())),
            style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }
}

class OfferCard extends StatelessWidget {
  const OfferCard({
    super.key,
    required this.title,
    required this.partner,
    required this.points,
    required this.colors,
  });

  final String title;
  final String partner;
  final String points;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          SportImageThumb(size: 72, gradient: colors),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(partner, style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      CupertinoIcons.money_dollar_circle_fill,
                      size: 16,
                      color: AppColors.gold,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      points,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: () {},
            style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
            child: const Text('Redeem'),
          ),
        ],
      ),
    );
  }
}

class Facility extends StatelessWidget {
  const Facility({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: AppColors.line),
            ),
            child: Icon(icon, size: 20),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class SlotChip extends StatelessWidget {
  const SlotChip({
    super.key,
    required this.time,
    required this.price,
    this.selected = false,
  });

  final String time;
  final String price;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 82,
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: selected ? AppColors.purple : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: selected ? AppColors.purple : AppColors.line),
      ),
      child: Column(
        children: [
          Text(
            time,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            price,
            style: TextStyle(
              color: selected ? Colors.white70 : AppColors.muted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.light = false,
  });

  final String label;
  final String value;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: light ? Colors.white60 : AppColors.muted),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: light ? Colors.white : AppColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class PriceBlock extends StatelessWidget {
  const PriceBlock({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
      ],
    );
  }
}

class DarkMetric extends StatelessWidget {
  const DarkMetric({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

class LevelBadge extends StatelessWidget {
  const LevelBadge({super.key, required this.text, this.size = 66});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.gold, width: 3),
        color: AppColors.dark2,
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.gold,
          fontWeight: FontWeight.w900,
          fontSize: size * .34,
        ),
      ),
    );
  }
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.dark = true});

  final double value;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        minHeight: 7,
        value: value,
        backgroundColor: dark ? Colors.white12 : AppColors.line,
        color: AppColors.gold,
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar({super.key, required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFFFFB36A), Color(0xFF4B2D82)],
        ),
        border: Border.all(color: Colors.white, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        name,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: size * .34,
        ),
      ),
    );
  }
}

class AchievementBadge extends StatelessWidget {
  const AchievementBadge({
    super.key,
    required this.icon,
    required this.color,
    this.small = false,
  });

  final IconData icon;
  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final size = small ? 46.0 : 58.0;
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: .15),
        border: Border.all(color: color.withValues(alpha: .5), width: 2),
      ),
      child: Icon(icon, color: color, size: small ? 24 : 30),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      radius: 16,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class SportSquare extends StatelessWidget {
  const SportSquare({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      radius: 16,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        children: [
          Icon(icon, color: AppColors.purple, size: 24),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.dark = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: dark
              ? Colors.white.withValues(alpha: .1)
              : Colors.white.withValues(alpha: .92),
          border: Border.all(color: dark ? Colors.white12 : AppColors.line),
        ),
        child: Icon(icon, color: dark ? Colors.white : AppColors.ink, size: 20),
      ),
    );
  }
}

class PlayUpMark extends StatelessWidget {
  const PlayUpMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: PlayUpMarkPainter()),
    );
  }
}

class PlayUpMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final green = Paint()
      ..color = AppColors.green
      ..style = PaintingStyle.fill;
    final purple = Paint()
      ..color = AppColors.purple
      ..style = PaintingStyle.fill;
    final r = Radius.circular(size.width * .18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          0,
          size.height * .18,
          size.width * .72,
          size.height * .24,
        ),
        r,
      ),
      green,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .28,
          size.height * .44,
          size.width * .62,
          size.height * .24,
        ),
        r,
      ),
      purple,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DarkGradient extends StatelessWidget {
  const DarkGradient({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF07110E), AppColors.dark, Color(0xFF0B1628)],
        ),
      ),
      child: child,
    );
  }
}

class _GlowBall extends StatelessWidget {
  const _GlowBall({required this.color, this.size = 48});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: .88),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: .42), blurRadius: 22),
        ],
      ),
    );
  }
}
