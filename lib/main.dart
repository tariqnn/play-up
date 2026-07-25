import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:app_links/app_links.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
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
import 'package:uuid/uuid.dart';
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
    unawaited(_syncFcmToken());
    FirebaseAuth.instance.authStateChanges().listen((_) {
      unawaited(_syncFcmToken());
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      unawaited(_saveFcmToken(token));
    });
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // Foreground messages are intentionally handled in-app later by UI state.
    });
  } catch (_) {
    // Messaging can be unavailable on some debug targets; app startup should continue.
  }
}

Future<void> _syncFcmToken() async {
  try {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null && token.isNotEmpty) await _saveFcmToken(token);
  } catch (_) {
    // Token access depends on device services; failure should not block app use.
  }
}

Future<void> _saveFcmToken(String token) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || FirebaseAuth.instance.currentUser?.isAnonymous == true) {
    return;
  }
  try {
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'lastFcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    });
  } catch (_) {
    // Profiles can be created shortly after auth on first launch; retry happens
    // on token refresh or next startup.
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
      case 'configuration-not-found':
        return error.message ??
            'This sign-in provider is not configured for this app build.';
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
  static const _iosClientId =
      '634238605050-5tv31kt4cjhfg5ihif4kh4fsmn1uafm9.apps.googleusercontent.com';

  /// Apple requires an enabled Firebase provider plus Apple Developer
  /// credentials. Keep the button out of production builds until both exist.
  static bool get appleAvailable =>
      const bool.fromEnvironment('APPLE_SIGN_IN_ENABLED') &&
      defaultTargetPlatform == TargetPlatform.iOS;

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
      final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
      if (isIos && _iosClientId.isEmpty) {
        throw FirebaseAuthException(
          code: 'configuration-not-found',
          message:
              'Google sign-in needs the iOS OAuth client for com.playup.playu.',
        );
      }
      await signIn.initialize(
        clientId: isIos ? _iosClientId : null,
        serverClientId: _serverClientId,
      );
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
    final rawNonce = base64Url
        .encode(
          List<int>.generate(32, (_) => math.Random.secure().nextInt(256)),
        )
        .replaceAll('=', '');
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );
    final oauthCredential = OAuthProvider(
      'apple.com',
    ).credential(idToken: appleCredential.identityToken, rawNonce: rawNonce);
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
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            },
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.purple,
            brightness: Brightness.dark,
            primary: const Color(0xFF9B72FF),
            surface: const Color(0xFF0D0D0D),
            onSurface: const Color(0xFFECECEC),
            outline: const Color(0xFF343434),
            outlineVariant: const Color(0xFF242424),
          ),
          canvasColor: Colors.black,
          dialogTheme: const DialogThemeData(
            backgroundColor: Color(0xFF0D0D0D),
          ),
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: Color(0xFF0D0D0D),
            modalBackgroundColor: Color(0xFF0D0D0D),
          ),
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            fillColor: Color(0xFF111111),
          ),
          cardTheme: const CardThemeData(color: Color(0xFF0D0D0D)),
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
              TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            },
          ),
        ),
        themeMode: mode,
        home: const BiometricGate(child: AuthGate()),
      ),
    );
  }
}

class PlayUpPageTransitionsBuilder extends PageTransitionsBuilder {
  const PlayUpPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.isFirst) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: Tween<double>(begin: .72, end: 1).animate(curved),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(.08, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
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
      await AppRepository.instance.joinBookingInvite(token);
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
        return FutureBuilder<void>(
          future: AppRepository.instance.ensureUserProfile(user),
          builder: (context, readySnapshot) {
            if (readySnapshot.connectionState == ConnectionState.waiting) {
              return const LaunchLoadingScreen();
            }
            return StreamBuilder<Map<String, dynamic>>(
              stream: AppRepository.instance.currentUserDoc(),
              builder: (context, profileSnapshot) {
                if (!profileSnapshot.hasData) {
                  return const LaunchLoadingScreen();
                }
                final profile = profileSnapshot.data!;
                if (profile['mustChangePassword'] == true) {
                  return const RequiredPasswordChangeScreen();
                }
                final role = profile['role']?.toString() ?? 'player';
                if (role == 'academyOwner' ||
                    role == 'courtOwner' ||
                    role == 'academyStaff') {
                  return const AcademyModeDashboard(standalone: true);
                }
                return const MainShell();
              },
            );
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
    // Guest mode is deliberately account-less. Do not create loyalty,
    // achievement, profile, or points data for anonymous visitors.
    if (user.isAnonymous) return;
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
      } else {
        await ref.set({
          'uid': user.uid,
          'displayName': name,
          'email': user.email,
          'isGuest': user.isAnonymous,
          'city':
              LocationService.instance.current.value?.label ??
              'Location not set',
          'level': 1,
          'rankTitle': 'Rookie',
          'xp': 0,
          'nextLevelXp': 500,
          'points': 100,
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
      }
      final existing = snap.data() ?? const <String, dynamic>{};
      await _db.collection('publicProfiles').doc(user.uid).set({
        'userId': user.uid,
        'displayName': name,
        'photoUrl': user.photoURL,
        'city':
            LocationService.instance.current.value?.label ??
            existing['city'] ??
            'Location not set',
        'level': existing['level'] ?? 1,
        'xp': existing['xp'] ?? 0,
        'sports': existing['sports'] ?? <String>[],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('ensureUserProfile skipped: $error');
    }
  }

  Future<Map<String, dynamic>> ensureAndLoadProfile(User user) async {
    if (user.isAnonymous) return const <String, dynamic>{'role': 'guest'};
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

  Stream<QuerySnapshot<Map<String, dynamic>>> myBookingParticipation() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _bookings
        .where('participants', arrayContains: uid)
        .orderBy('startUtc')
        .snapshots();
  }

  Future<bool> canCreateExternalMatches() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final profile = (await _users.doc(uid).get()).data() ?? const {};
    final permissions = List<String>.from(
      profile['permissions'] as List? ?? const [],
    );
    return profile['role'] == 'superAdmin' ||
        permissions.contains('matchmaking.manage');
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> openMatches() {
    return _matches
        .where('status', isEqualTo: 'open')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .snapshots();
  }

  Stream<List<OpenMatch>> myUpcomingMatches() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value(const []);
    return _matches
        .where('players', arrayContains: uid)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => OpenMatch.fromMap(doc.data(), id: doc.id))
              .where(
                (match) =>
                    match.startUtc == null ||
                    match.startUtc!.isAfter(DateTime.now()),
              )
              .toList(),
        );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> myMatches() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _matches.where('players', arrayContains: uid).snapshots();
  }

  Future<String> createBooking({
    required Court court,
    required bool matchmaking,
    required DateTime startUtc,
    required DateTime endUtc,
    required int playerCapacity,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw const DomainValidationException('Sign in to create a booking.');
    }
    if (court.id.isEmpty) {
      throw const DomainValidationException(
        'This court is not available for booking. Select a live court.',
      );
    }
    try {
      final response = await _functions.httpsCallable('createBooking').call({
        'courtId': court.id,
        'startUtc': startUtc.toIso8601String(),
        'endUtc': endUtc.toIso8601String(),
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
      if (error is FirebaseFunctionsException && _callableUnavailable(error)) {
        return _createBookingDirect(
          court: court,
          matchmaking: matchmaking,
          startUtc: startUtc,
          endUtc: endUtc,
          playerCapacity: playerCapacity,
        );
      }
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

  bool _callableUnavailable(FirebaseFunctionsException error) =>
      error.code == 'not-found' ||
      error.code == 'unimplemented' ||
      (error.message ?? '').toLowerCase().contains('not found');

  Future<String> _createBookingDirect({
    required Court court,
    required bool matchmaking,
    required DateTime startUtc,
    required DateTime endUtc,
    required int playerCapacity,
  }) async {
    final user = FirebaseAuth.instance.currentUser!;
    final start = startUtc.toUtc();
    final end = endUtc.toUtc();
    final durationMinutes = end.difference(start).inMinutes;
    if (durationMinutes < 30 ||
        durationMinutes > 240 ||
        durationMinutes % 30 != 0) {
      throw const DomainValidationException(
        'Choose a 30-minute to 4-hour time range.',
      );
    }
    final courtRef = _db.collection('courts').doc(court.id);
    final bookingRef = _bookings.doc();
    final starts = <DateTime>[
      for (
        var cursor = start;
        cursor.isBefore(end);
        cursor = cursor.add(const Duration(minutes: 30))
      )
        cursor,
    ];
    final lockRefs = starts
        .map(
          (slot) => _db
              .collection('bookingLocks')
              .doc(BookingPolicy.slotKey(court.id, slot)),
        )
        .toList();
    await _db.runTransaction((transaction) async {
      final liveCourt = (await transaction.get(courtRef)).data();
      if (liveCourt == null || liveCourt['active'] == false) {
        throw const DomainValidationException('Court is unavailable.');
      }
      for (final ref in lockRefs) {
        if ((await transaction.get(ref)).exists) {
          throw const DomainValidationException(
            'This time was just booked. Choose another slot.',
          );
        }
      }
      final subtotal = ((court.basePriceMinor * durationMinutes) / 60).round();
      final record = <String, dynamic>{
        'userId': user.uid,
        'academyId': court.academyId,
        'courtId': court.id,
        'courtName': court.name,
        'sport': court.sport,
        'startUtc': Timestamp.fromDate(start),
        'endUtc': Timestamp.fromDate(end),
        'durationMinutes': durationMinutes,
        'status': 'pending',
        'currency': court.currency,
        'subtotalMinor': subtotal,
        'discountMinor': 0,
        'totalMinor': subtotal,
        'paymentMethod': 'cash',
        'paymentStatus': 'pending',
        'matchmaking': matchmaking,
        'playerCapacity': playerCapacity,
        'participants': [user.uid],
        'lockIds': lockRefs.map((ref) => ref.id).toList(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      transaction.set(bookingRef, record);
      for (var i = 0; i < lockRefs.length; i++) {
        final slotStart = starts[i];
        transaction.set(lockRefs[i], {
          'bookingId': bookingRef.id,
          'userId': user.uid,
          'courtId': court.id,
          'startUtc': Timestamp.fromDate(slotStart),
          'endUtc': Timestamp.fromDate(
            slotStart.add(const Duration(minutes: 30)),
          ),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
    unawaited(
      _createBookingNotice(
        userId: user.uid,
        bookingId: bookingRef.id,
        courtName: court.name,
        startUtc: start,
        type: 'bookingCreated',
        title: 'Booking requested',
      ),
    );
    unawaited(
      _createBookingNotice(
        userId: user.uid,
        bookingId: bookingRef.id,
        courtName: court.name,
        startUtc: start,
        type: 'bookingReminder',
        title: 'Upcoming booking reminder',
      ),
    );
    return bookingRef.id;
  }

  Future<void> _createBookingNotice({
    required String userId,
    required String bookingId,
    required String courtName,
    required DateTime startUtc,
    required String type,
    required String title,
  }) async {
    try {
      await _db.collection('notifications').add({
        'userId': userId,
        'type': type,
        'title': title,
        'body':
            '$courtName at ${DateFormat('EEE, d MMM - h:mm a').format(startUtc.toLocal())}',
        'bookingId': bookingId,
        'startUtc': Timestamp.fromDate(startUtc),
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      debugPrint('booking notification skipped: $error');
    }
  }

  Future<String> createMatch({
    required String title,
    required String sport,
    required String type,
    required int capacity,
    required String skill,
    Court? court,
    required DateTime startUtc,
    bool externalVenue = false,
    String venueNote = '',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw const DomainValidationException('Sign in to create a match.');
    }
    if (externalVenue) {
      if (!await canCreateExternalMatches()) {
        throw const DomainValidationException(
          'This account is not enabled for external match hosting.',
        );
      }
      if (venueNote.trim().length < 3) {
        throw const DomainValidationException('Add the court or venue note.');
      }
      return _createMatchDirect(
        title: title,
        sport: sport,
        type: type,
        capacity: capacity,
        skill: skill,
        startUtc: startUtc,
        externalVenue: true,
        venueNote: venueNote,
      );
    }
    if (court == null) {
      throw const DomainValidationException('Choose an available court.');
    }
    try {
      final response = await _functions.httpsCallable('createMatch').call({
        'title': title,
        'sport': sport,
        'type': type,
        'skill': skill,
        'capacity': capacity,
        'courtId': court.id,
        'startUtc': startUtc.toUtc().toIso8601String(),
      });
      return (response.data as Map)['matchId'].toString();
    } catch (error) {
      if (error is FirebaseFunctionsException && _callableUnavailable(error)) {
        return _createMatchDirect(
          title: title,
          sport: sport,
          type: type,
          capacity: capacity,
          skill: skill,
          court: court,
          startUtc: startUtc,
        );
      }
      if (error is FirebaseFunctionsException) {
        throw DomainValidationException(
          error.message ?? 'The match could not be created.',
        );
      }
      rethrow;
    }
  }

  Future<String> _createMatchDirect({
    required String title,
    required String sport,
    required String type,
    required int capacity,
    required String skill,
    required DateTime startUtc,
    Court? court,
    bool externalVenue = false,
    String venueNote = '',
  }) async {
    final user = FirebaseAuth.instance.currentUser!;
    final start = startUtc.toUtc();
    final end = start.add(const Duration(hours: 1));
    if (!start.isAfter(DateTime.now().toUtc())) {
      throw const DomainValidationException('Choose a future match time.');
    }
    if (capacity < 2 || capacity > 30) {
      throw const DomainValidationException('Capacity must be 2-30 players.');
    }
    final profile = (await _users.doc(user.uid).get()).data() ?? const {};
    final hostName = (profile['displayName'] ?? user.displayName ?? 'Player')
        .toString();
    final matchRef = _matches.doc();
    if (externalVenue) {
      await matchRef.set({
        'hostId': user.uid,
        'hostName': hostName,
        'title': title,
        'sport': sport,
        'academyId': '',
        'courtId': '',
        'courtName': venueNote.trim(),
        'venueNote': venueNote.trim(),
        'source': 'external',
        'startUtc': Timestamp.fromDate(start),
        'skillRange': skill,
        'type': type == 'Competitive' ? 'Competitive' : 'Casual',
        'ranked': type == 'Competitive',
        'status': 'open',
        'capacity': capacity,
        'currency': 'JOD',
        'totalMinor': 0,
        'players': [user.uid],
        'playerNames': [hostName],
        'neededPlayers': capacity - 1,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return matchRef.id;
    }
    final selectedCourt = court!;
    final bookingRef = _bookings.doc();
    final lockRef = _db
        .collection('bookingLocks')
        .doc(BookingPolicy.slotKey(selectedCourt.id, start));
    await _db.runTransaction((transaction) async {
      final lock = await transaction.get(lockRef);
      if (lock.exists) {
        throw const DomainValidationException(
          'This court was just booked. Choose another time.',
        );
      }
      final price = selectedCourt.basePriceMinor;
      transaction.set(lockRef, {
        'bookingId': bookingRef.id,
        'userId': user.uid,
        'courtId': selectedCourt.id,
        'startUtc': Timestamp.fromDate(start),
        'endUtc': Timestamp.fromDate(end),
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(bookingRef, {
        'userId': user.uid,
        'academyId': selectedCourt.academyId,
        'courtId': selectedCourt.id,
        'courtName': selectedCourt.name,
        'sport': sport,
        'startUtc': Timestamp.fromDate(start),
        'endUtc': Timestamp.fromDate(end),
        'durationMinutes': 60,
        'status': 'pending',
        'currency': selectedCourt.currency,
        'subtotalMinor': price,
        'discountMinor': 0,
        'totalMinor': price,
        'paymentMethod': 'cash',
        'paymentStatus': 'pending',
        'matchmaking': true,
        'playerCapacity': capacity,
        'participants': [user.uid],
        'lockIds': [lockRef.id],
        'matchId': matchRef.id,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(matchRef, {
        'hostId': user.uid,
        'hostName': hostName,
        'title': title,
        'sport': sport,
        'academyId': selectedCourt.academyId,
        'courtId': selectedCourt.id,
        'courtName': selectedCourt.name,
        'bookingId': bookingRef.id,
        'source': 'playupCourt',
        'startUtc': Timestamp.fromDate(start),
        'skillRange': skill,
        'type': type == 'Competitive' ? 'Competitive' : 'Casual',
        'ranked': type == 'Competitive',
        'status': 'open',
        'capacity': capacity,
        'currency': selectedCourt.currency,
        'totalMinor': price,
        'players': [user.uid],
        'playerNames': [hostName],
        'neededPlayers': capacity - 1,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    unawaited(
      _createBookingNotice(
        userId: user.uid,
        bookingId: bookingRef.id,
        courtName: selectedCourt.name,
        startUtc: start,
        type: 'bookingReminder',
        title: 'Upcoming match reminder',
      ),
    );
    return matchRef.id;
  }

  Future<Set<String>> availableCourtIds({
    required String sport,
    required DateTime startUtc,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return const {};
    try {
      final response = await _functions
          .httpsCallable('listAvailableCourts')
          .call({
            'sport': sport,
            'startUtc': startUtc.toUtc().toIso8601String(),
          });
      return Set<String>.from(
        (response.data as Map)['courtIds'] as List? ?? const [],
      );
    } on FirebaseFunctionsException catch (error) {
      if (_callableUnavailable(error)) {
        final start = startUtc.toUtc();
        final end = start.add(const Duration(hours: 1));
        final courts = await _db
            .collection('courts')
            .where('active', isEqualTo: true)
            .where('sport', isEqualTo: sport)
            .get();
        final locks = await _db.collection('bookingLocks').get();
        return courts.docs
            .where((court) {
              return !locks.docs.any((lock) {
                final data = lock.data();
                if (data['courtId'] != court.id) return false;
                final lockStart = (data['startUtc'] as Timestamp?)
                    ?.toDate()
                    .toUtc();
                final lockEnd = (data['endUtc'] as Timestamp?)
                    ?.toDate()
                    .toUtc();
                return lockStart != null &&
                    lockEnd != null &&
                    start.isBefore(lockEnd) &&
                    end.isAfter(lockStart);
              });
            })
            .map((court) => court.id)
            .toSet();
      }
      throw DomainValidationException(
        error.message ?? 'Court availability could not be loaded.',
      );
    }
  }

  Future<void> joinExistingMatch(String matchId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw const DomainValidationException('Sign in to join a match.');
    }
    try {
      await _functions.httpsCallable('joinMatch').call({'matchId': matchId});
    } on FirebaseFunctionsException catch (error) {
      if (_callableUnavailable(error)) {
        final profile = (await _users.doc(user.uid).get()).data() ?? const {};
        final name = (profile['displayName'] ?? user.displayName ?? 'Player')
            .toString();
        await _db.runTransaction((transaction) async {
          final ref = _matches.doc(matchId);
          final snap = await transaction.get(ref);
          final data = snap.data();
          if (data == null || data['status'] != 'open') {
            throw const DomainValidationException('Match is not open.');
          }
          final players = List<String>.from(
            data['players'] as List? ?? const [],
          );
          if (players.contains(user.uid)) {
            throw const DomainValidationException(
              'You already joined this match.',
            );
          }
          final capacity = (data['capacity'] as num?)?.toInt() ?? 0;
          if (players.length >= capacity) {
            throw const DomainValidationException('Match is full.');
          }
          transaction.update(ref, {
            'players': FieldValue.arrayUnion([user.uid]),
            'playerNames': FieldValue.arrayUnion([name]),
            'neededPlayers': FieldValue.increment(-1),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        });
        return;
      }
      throw DomainValidationException(
        error.message ?? 'Could not join this match.',
      );
    }
  }

  Future<Map<String, dynamic>> redeemOffer(String offerId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw const DomainValidationException(
        'Create an account or sign in to redeem rewards.',
      );
    }
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

  Stream<QuerySnapshot<Map<String, dynamic>>> friendships() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('friendships')
        .where('members', arrayContains: uid)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> publicPlayers() => _db
      .collection('publicProfiles')
      .orderBy('xp', descending: true)
      .limit(50)
      .snapshots();

  Future<void> sendFriendRequest(String playerId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous || playerId == user.uid) {
      throw const DomainValidationException('Choose another player.');
    }
    final members = [user.uid, playerId]..sort();
    final ref = _db.collection('friendships').doc(members.join('_'));
    try {
      await _functions.httpsCallable('sendFriendRequest').call({
        'playerId': playerId,
      });
    } on FirebaseFunctionsException catch (error) {
      if (_callableUnavailable(error)) {
        await ref.set({
          'members': members,
          'requestedBy': user.uid,
          'requestedTo': playerId,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }
      throw DomainValidationException(
        error.message ?? 'Friend request could not be sent.',
      );
    }
  }

  Future<void> respondFriendRequest(String friendshipId, bool accept) async {
    try {
      await _functions.httpsCallable('respondFriendRequest').call({
        'friendshipId': friendshipId,
        'accept': accept,
      });
    } on FirebaseFunctionsException catch (error) {
      if (_callableUnavailable(error)) {
        await _db.collection('friendships').doc(friendshipId).update({
          'status': accept ? 'accepted' : 'declined',
          'respondedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }
      throw DomainValidationException(
        error.message ?? 'Friend request could not be updated.',
      );
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> matchMessages(String matchId) =>
      _matches
          .doc(matchId)
          .collection('messages')
          .orderBy('createdAt')
          .limitToLast(200)
          .snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> match(String matchId) =>
      _matches.doc(matchId).snapshots();

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
      if (_callableUnavailable(error)) {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null || user.isAnonymous) {
          throw const DomainValidationException(
            'Sign in to invite your friends.',
          );
        }
        final booking = await _bookings.doc(bookingId).get();
        final data = booking.data();
        if (data == null || data['userId'] != user.uid) {
          throw const DomainValidationException(
            'Only the booking owner can invite players.',
          );
        }
        final token = const Uuid().v4().replaceAll('-', '');
        await _db.collection('bookingInvites').doc(token).set({
          'token': token,
          'bookingId': bookingId,
          'createdBy': user.uid,
          'academyId': data['academyId'],
          'active': true,
          'uses': 0,
          'maxUses': ((data['playerCapacity'] as num?)?.toInt() ?? 20) - 1,
          'expiresAt': data['endUtc'],
          'createdAt': FieldValue.serverTimestamp(),
        });
        return 'https://playup.app/join/booking/$token';
      }
      throw DomainValidationException(
        error.message ?? 'Invite link could not be created.',
      );
    }
  }

  Future<void> joinBookingInvite(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw const DomainValidationException('Sign in to join this booking.');
    }
    try {
      await _functions.httpsCallable('joinBookingInvite').call({
        'token': token,
      });
      return;
    } on FirebaseFunctionsException catch (error) {
      if (!_callableUnavailable(error)) {
        throw DomainValidationException(
          error.message ?? 'Could not join this booking.',
        );
      }
    }
    final inviteRef = _db.collection('bookingInvites').doc(token);
    await _db.runTransaction((transaction) async {
      final invite = (await transaction.get(inviteRef)).data();
      if (invite == null || invite['active'] != true) {
        throw const DomainValidationException('Invite link is invalid.');
      }
      final bookingRef = _bookings.doc(invite['bookingId'].toString());
      final booking = (await transaction.get(bookingRef)).data();
      if (booking == null ||
          const ['cancelled', 'completed'].contains(booking['status'])) {
        throw const DomainValidationException('Booking is unavailable.');
      }
      final participants = List<String>.from(
        booking['participants'] ?? const <String>[],
      );
      if (participants.contains(user.uid)) {
        throw const DomainValidationException(
          'You already joined this booking.',
        );
      }
      final capacity = (booking['playerCapacity'] as num?)?.toInt() ?? 20;
      if (participants.length >= capacity) {
        throw const DomainValidationException('Booking is full.');
      }
      transaction.update(bookingRef, {
        'participants': FieldValue.arrayUnion([user.uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(inviteRef, {
        'uses': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(_db.collection('notifications').doc(), {
        'userId': user.uid,
        'type': 'bookingReminder',
        'title': 'Upcoming booking reminder',
        'body':
            '${booking['courtName'] ?? 'Court'} at ${DateFormat('EEE, d MMM - h:mm a').format((booking['startUtc'] as Timestamp).toDate().toLocal())}',
        'bookingId': bookingRef.id,
        'startUtc': booking['startUtc'],
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
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
    this.academyId = '',
    this.sport = 'Sport',
    this.currency = 'JOD',
    this.basePriceMinor = 0,
    this.address = '',
    this.active = true,
    this.openingHour = 6,
    this.closingHour = 23,
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
  final String academyId;
  final String sport;
  final String currency;
  final int basePriceMinor;
  final String address;
  final bool active;
  final int openingHour;
  final int closingHour;

  double? distanceKmFrom(AppLocation? location) {
    if (location == null || latitude == null || longitude == null) return null;
    const earthRadiusKm = 6371.0;
    final dLat = (latitude! - location.latitude) * math.pi / 180;
    final dLon = (longitude! - location.longitude) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(location.latitude * math.pi / 180) *
            math.cos(latitude! * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  String distanceFrom(AppLocation? location) {
    final km = distanceKmFrom(location);
    if (km == null) return 'Location needed';
    return km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';
  }

  bool isOpenAt(DateTime localTime) =>
      active && localTime.hour >= openingHour && localTime.hour < closingHour;
}

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
  bool _obscurePassword = true;
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
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(CupertinoIcons.back),
                ),
                const PlayUpMark(size: 38),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'PlayUp',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
                const _AuthThemeButton(),
              ],
            ),
            const SizedBox(height: 34),
            Text(
              _isSignUp ? 'Create your account' : 'Welcome back',
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isSignUp
                  ? 'Start booking courts and finding players.'
                  : 'Sign in to continue playing.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 16,
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
              obscureText: _obscurePassword,
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(
                  _obscurePassword
                      ? CupertinoIcons.eye
                      : CupertinoIcons.eye_slash,
                ),
              ),
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
                      icon: Icons.apple,
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

class _AuthThemeButton extends StatelessWidget {
  const _AuthThemeButton();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: ThemeController.mode,
    builder: (context, mode, _) => PopupMenuButton<ThemeMode>(
      tooltip: 'Appearance',
      initialValue: mode,
      onSelected: ThemeController.set,
      itemBuilder: (_) => const [
        PopupMenuItem(value: ThemeMode.system, child: Text('System theme')),
        PopupMenuItem(value: ThemeMode.light, child: Text('Light theme')),
        PopupMenuItem(value: ThemeMode.dark, child: Text('Dark theme')),
      ],
      icon: Icon(
        mode == ThemeMode.dark
            ? CupertinoIcons.moon_fill
            : mode == ThemeMode.light
            ? CupertinoIcons.sun_max_fill
            : CupertinoIcons.circle_lefthalf_fill,
      ),
    ),
  );
}

class RequiredPasswordChangeScreen extends StatefulWidget {
  const RequiredPasswordChangeScreen({super.key});

  @override
  State<RequiredPasswordChangeScreen> createState() =>
      _RequiredPasswordChangeScreenState();
}

class _RequiredPasswordChangeScreenState
    extends State<RequiredPasswordChangeScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text.length < 8) {
      setState(() => _error = 'Use at least 8 characters.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser!;
      await user.updatePassword(_password.text);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'mustChangePassword': false,
        'passwordChangedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseAuthException catch (error) {
      setState(() => _error = friendlyAuthError(error));
    } catch (_) {
      setState(() => _error = 'Password could not be changed. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AppScrollPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PlayUpMark(size: 48),
          const SizedBox(height: 32),
          const Text(
            'Choose your password',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Replace the temporary password before continuing.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          AppTextField(
            controller: _password,
            label: 'New password',
            icon: CupertinoIcons.lock,
            obscureText: true,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _confirm,
            label: 'Confirm password',
            icon: CupertinoIcons.lock_shield,
            obscureText: true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 20),
          PrimaryButton(
            label: _loading ? 'Saving...' : 'Set password',
            onPressed: _loading ? () {} : _save,
          ),
        ],
      ),
    ),
  );
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
                          'JOD 21 / hr',
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
  late final List<Widget> _pages;
  static const _guestPages = <Widget>[
    BookScreen(),
    PlayScreen(),
    GuestExitScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _pages = [
      HomeScreen(onTabChange: _selectTab),
      const BookScreen(),
      const PlayScreen(),
      const RewardsScreen(),
      const ProfileScreen(),
    ];
    unawaited(DeepLinkService.consumePending());
  }

  void _selectTab(int index) {
    if (_index != index) setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isGuest = user == null || user.isAnonymous;
    if (isGuest) {
      if (_index >= _guestPages.length) _index = 0;
      return Scaffold(
        body: _AnimatedTabStack(index: _index, children: _guestPages),
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: CardBox(
            radius: 28,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _TabItem(
                  icon: CupertinoIcons.calendar,
                  label: 'Book',
                  active: _index == 0,
                  onTap: () => _selectTab(0),
                ),
                _TabItem(
                  icon: CupertinoIcons.game_controller,
                  label: 'Play',
                  active: _index == 1,
                  onTap: () => _selectTab(1),
                ),
                _TabItem(
                  icon: CupertinoIcons.square_arrow_right,
                  label: 'Sign out',
                  active: _index == 2,
                  onTap: () => _selectTab(2),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body: _AnimatedTabStack(index: _index, children: _pages),
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
                onTap: () => _selectTab(0),
              ),
              _TabItem(
                icon: CupertinoIcons.calendar,
                label: 'Book',
                active: _index == 1,
                onTap: () => _selectTab(1),
              ),
              _TabItem(
                icon: CupertinoIcons.game_controller,
                label: 'Play',
                active: _index == 2,
                onTap: () => _selectTab(2),
              ),
              _TabItem(
                icon: CupertinoIcons.gift,
                label: 'Rewards',
                active: _index == 3,
                onTap: () => _selectTab(3),
              ),
              _TabItem(
                icon: CupertinoIcons.person,
                label: 'Profile',
                active: _index == 4,
                onTap: () => _selectTab(4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedTabStack extends StatelessWidget {
  const _AnimatedTabStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey(index),
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 150),
    curve: Curves.easeOutCubic,
    builder: (context, value, child) => Opacity(
      opacity: .82 + (.18 * value),
      child: Transform.translate(
        offset: Offset(12 * (1 - value), 0),
        child: child,
      ),
    ),
    child: IndexedStack(index: index, children: children),
  );
}

class GuestExitScreen extends StatelessWidget {
  const GuestExitScreen({super.key});

  @override
  Widget build(BuildContext context) => AppScrollPage(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 36),
        const Icon(
          CupertinoIcons.person_crop_circle_badge_plus,
          size: 58,
          color: AppColors.purple,
        ),
        const SizedBox(height: 18),
        const Text(
          'You are browsing as a guest',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        const Text(
          'Guests can explore courts and open matches. Sign in to book, join, chat, earn points, redeem gifts, and unlock achievements.',
          style: TextStyle(color: AppColors.muted, height: 1.5),
        ),
        const SizedBox(height: 28),
        PrimaryButton(
          label: 'Sign in or create account',
          onPressed: () async {
            await SocialAuth.signOutEverywhere();
            if (context.mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const AuthGate()),
                (_) => false,
              );
            }
          },
        ),
        const SizedBox(height: 12),
        SecondaryButton(
          label: 'Exit guest mode',
          onPressed: () async {
            await SocialAuth.signOutEverywhere();
            if (context.mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                (_) => false,
              );
            }
          },
        ),
      ],
    ),
  );
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
                      GestureDetector(
                        onTap: () => onTabChange(4),
                        child: Avatar(
                          name: firstName.isEmpty
                              ? 'A'
                              : firstName.characters.first.toUpperCase(),
                          size: 42,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          StreamBuilder<List<OpenMatch>>(
            stream: AppRepository.instance.myUpcomingMatches(),
            builder: (context, snapshot) {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              final now = DateTime.now();
              final matches =
                  (snapshot.data ?? const <OpenMatch>[])
                      .where(
                        (match) =>
                            uid != null &&
                            (match.hostId == uid ||
                                match.playerIds.contains(uid)) &&
                            (match.startUtc == null ||
                                match.startUtc!.isAfter(now)),
                      )
                      .toList()
                    ..sort(
                      (a, b) =>
                          (a.startUtc ?? now).compareTo(b.startUtc ?? now),
                    );
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CardBox(
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (matches.isEmpty) {
                return DarkFeatureCard(
                  title: 'Your next match',
                  subtitle: 'No upcoming match yet',
                  meta: 'Browse live matches available near you',
                  cta: 'Find match',
                  onPressed: () => onTabChange(2),
                );
              }
              final match = matches.first;
              return DarkFeatureCard(
                title: 'Your next match',
                subtitle: match.title,
                meta: '${match.time} • ${match.court}',
                cta: 'View',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MatchDetailsScreen(match: match),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 22),
          const SectionHeader(title: 'Quick Actions'),
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
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FriendsScreen()),
                  ),
                ),
              ),
            ],
          ),
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
                return ValueListenableBuilder<AppLocation?>(
                  valueListenable: LocationService.instance.current,
                  builder: (context, location, _) {
                    final list = CatalogService.instance.nearbyCourts(
                      snapshot.data ?? const <Court>[],
                      location,
                    );
                    if (list.isEmpty) {
                      return const CardBox(
                        child: Text(
                          'No nearby courts are available for this location.',
                        ),
                      );
                    }
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (_, index) =>
                          CourtCarouselCard(court: list[index]),
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 12),
                      itemCount: list.length,
                    );
                  },
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
              return ValueListenableBuilder<AppLocation?>(
                valueListenable: LocationService.instance.current,
                builder: (context, location, _) {
                  final list = CatalogService.instance.nearbyAcademies(
                    snapshot.data ?? const <Academy>[],
                    location,
                  );
                  if (list.isEmpty) {
                    return const CardBox(
                      child: Text(
                        'No nearby academies are available for this location.',
                      ),
                    );
                  }
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

class BookScreen extends StatefulWidget {
  const BookScreen({super.key});

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  final _search = TextEditingController();
  String _sport = 'All';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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
          SearchBox(controller: _search, onChanged: (_) => setState(() {})),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final sport in const [
                  'All',
                  'Basketball',
                  'Padel',
                  'Volleyball',
                  '3x3',
                ])
                  SportChip(
                    label: sport,
                    selected: _sport == sport,
                    onTap: () => setState(() => _sport = sport),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          SectionHeader(
            title: 'Nearby Courts',
            onSeeAll: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const MapViewScreen())),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<Court>>(
            stream: CatalogService.instance.courts(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              return ValueListenableBuilder<AppLocation?>(
                valueListenable: LocationService.instance.current,
                builder: (context, location, _) {
                  final list = CatalogService.instance.nearbyCourts(
                    snapshot.data ?? const <Court>[],
                    location,
                    sport: _sport,
                    query: _search.text,
                  );
                  if (list.isEmpty) {
                    return EmptyState(
                      icon: CupertinoIcons.sportscourt,
                      title: 'No courts found',
                      message:
                          'Try another sport, search, or update your location.',
                      action: 'Open map',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MapViewScreen(),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    itemBuilder: (_, index) =>
                        CourtListCard(court: list[index]),
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemCount: list.length,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class PlayScreen extends StatefulWidget {
  const PlayScreen({super.key});

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> {
  String _sport = 'All';

  @override
  Widget build(BuildContext context) {
    return AppScrollPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HeaderRow(
            title: 'Find your\nnext match',
            subtitle: 'Competitive and casual games near you',
            trailing: IconButton(
              tooltip: 'Filter matches',
              onPressed: () => _showFilters(context),
              icon: const Icon(CupertinoIcons.slider_horizontal_3, size: 26),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final sport in const [
                  'All',
                  'Basketball',
                  'Padel',
                  'Volleyball',
                ])
                  SportChip(
                    label: sport,
                    selected: _sport == sport,
                    onTap: () => setState(() => _sport = sport),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Create Match',
            icon: CupertinoIcons.plus,
            onPressed: () => _createMatch(context),
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
              final list = (snapshot.data ?? const <OpenMatch>[])
                  .where((m) => _sport == 'All' || m.sport == _sport)
                  .toList();
              if (list.isEmpty) {
                return const CardBox(
                  child: Text(
                    'No open matches yet. Create the first live match.',
                  ),
                );
              }
              return Column(
                children: [
                  DarkFeatureCard(
                    title: 'Recommended live match',
                    subtitle: list.first.title,
                    meta:
                        '${list.first.sport} • ${list.first.skill} • ${list.first.time}',
                    cta: 'View',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MatchDetailsScreen(match: list.first),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
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

  Future<void> _showFilters(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              const SizedBox(
                width: double.infinity,
                child: Text(
                  'Filter by sport',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                ),
              ),
              for (final sport in const [
                'All',
                'Basketball',
                'Padel',
                'Volleyball',
              ])
                SelectablePill(
                  label: sport,
                  selected: _sport == sport,
                  onTap: () {
                    setState(() => _sport = sport);
                    Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createMatch(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      await showAdaptiveMessage(
        context,
        title: 'Account required',
        message: 'Sign in to reserve a court and publish a match.',
      );
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CreateMatchScreen()));
  }
}

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  String _filter = 'All Offers';

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
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final filter in const [
                  'All Offers',
                  'Academy',
                  'Sponsors',
                  'My Coupons',
                ])
                  SportChip(
                    label: filter,
                    selected: _filter == filter,
                    dark: true,
                    onTap: () => setState(() => _filter = filter),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (_filter == 'My Coupons')
            const WalletScreen(embedded: true)
          else
            StreamBuilder<List<Offer>>(
              stream: CatalogService.instance.offers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = (snapshot.data ?? const <Offer>[])
                    .where(
                      (offer) =>
                          _filter == 'All Offers' ||
                          offer.category.toLowerCase() == _filter.toLowerCase(),
                    )
                    .toList();
                if (list.isEmpty) {
                  return const CardBox(
                    child: Text('No rewards are available right now.'),
                  );
                }
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
          SectionHeader(
            title: 'Your Progress',
            onSeeAll: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LevelDetailScreen()),
            ),
          ),
          const SizedBox(height: 12),
          const ProgressSummaryCard(),
          const SizedBox(height: 22),
          SectionHeader(
            title: 'My Sports',
            onSeeAll: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SportsSelectionScreen()),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SportsSelectionScreen()),
            ),
            child: StreamBuilder<Map<String, dynamic>>(
              stream: AppRepository.instance.currentUserDoc(),
              builder: (context, snapshot) {
                final selected = List<String>.from(
                  snapshot.data?['sports'] as List? ?? const [],
                );
                if (selected.isEmpty) {
                  return const CardBox(
                    child: Text('Tap to choose the sports you play.'),
                  );
                }
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final sport in selected)
                      SizedBox(
                        width: 92,
                        child: SportSquare(
                          icon:
                              kSportOptions
                                  .where((option) => option.label == sport)
                                  .map((option) => option.icon)
                                  .firstOrNull ??
                              CupertinoIcons.sportscourt,
                          label: sport,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 22),
          SectionHeader(
            title: 'Recent Achievements',
            onSeeAll: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AchievementsScreen()),
            ),
          ),
          const SizedBox(height: 12),
          const LiveAchievementBadges(),
          const SizedBox(height: 22),
          SettingsTile(
            icon: CupertinoIcons.calendar,
            title: 'My Bookings',
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const MyBookingsScreen())),
          ),
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
            const SectionHeader(title: 'Booking hours'),
            const SizedBox(height: 12),
            CardBox(
              child: Text(
                'Open daily from ${court.openingHour.toString().padLeft(2, '0')}:00 to ${court.closingHour.toString().padLeft(2, '0')}:00. Choose a date to see live availability.',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
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
    final localStart = widget.startUtc.toLocal();
    final localEnd = widget.endUtc.toLocal();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Booking Setup',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            const StepIndicator(active: 1),
            const SizedBox(height: 18),
            CardBox(
              color: AppColors.dark,
              borderColor: AppColors.dark,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.court.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${DateFormat('EEE, d MMM').format(localStart)} - ${DateFormat.jm().format(localStart)} to ${DateFormat.jm().format(localEnd)}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .72),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Play mode',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            for (final option in const [
              (
                'self',
                CupertinoIcons.person,
                'Solo booking',
                'You manage players yourself',
              ),
              (
                'invite',
                CupertinoIcons.person_2,
                'Invite friends',
                'Share a link after booking',
              ),
              (
                'matchmaking',
                CupertinoIcons.sparkles,
                'Find players',
                'Publish it as an open match',
              ),
            ]) ...[
              GestureDetector(
                onTap: () => setState(() => _mode = option.$1),
                child: OptionTile(
                  icon: option.$2,
                  title: option.$3,
                  subtitle: option.$4,
                  selected: _mode == option.$1,
                ),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 10),
            CardBox(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Players',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Maximum people in this booking',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CounterButton(
                    icon: CupertinoIcons.minus,
                    onTap: () =>
                        setState(() => _players = math.max(1, _players - 1)),
                  ),
                  SizedBox(
                    width: 48,
                    child: Center(
                      child: Text(
                        '$_players',
                        style: const TextStyle(
                          fontSize: 20,
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
            ),
            const SizedBox(height: 112),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: PrimaryButton(
          label: 'Review Booking',
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
                              value: 'JOD 21',
                            ),
                          ),
                          Expanded(
                            child: PriceBlock(
                              label: 'Per Player',
                              value: 'JOD 5.25',
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
            startUtc: widget.startUtc,
            endUtc: widget.endUtc,
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
    final localStart = widget.startUtc.toLocal();
    final localEnd = widget.endUtc.toLocal();
    final total =
        ((widget.court.basePriceMinor *
                    widget.endUtc.difference(widget.startUtc).inMinutes) /
                60)
            .round();
    final totalLabel = total > 0
        ? '${widget.court.currency} ${(total / 100).toStringAsFixed(2)}'
        : widget.court.price;
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Review',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            const StepIndicator(active: 2),
            const SizedBox(height: 18),
            CardBox(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SportImageCard(
                    height: 144,
                    icon: widget.court.icon,
                    gradient: widget.court.gradient,
                    imageUrl: widget.court.imageUrl,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        DetailRow(label: 'Court', value: widget.court.name),
                        DetailRow(
                          label: 'Date',
                          value: DateFormat('EEE, d MMM').format(localStart),
                        ),
                        DetailRow(
                          label: 'Time',
                          value:
                              '${DateFormat.jm().format(localStart)} - ${DateFormat.jm().format(localEnd)}',
                        ),
                        DetailRow(
                          label: 'Players',
                          value: '${widget.playerCapacity}',
                        ),
                        DetailRow(label: 'Total', value: totalLabel),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const OptionTile(
              icon: CupertinoIcons.money_dollar,
              title: 'Cash at venue',
              subtitle: 'Academy staff collect payment at check-in',
              selected: true,
            ),
            const SizedBox(height: 112),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: PrimaryButton(
          label: _loading ? 'Confirming...' : 'Confirm Booking',
          onPressed: _loading ? () {} : _confirm,
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
    this.startUtc,
    this.endUtc,
  });

  final String bookingId;
  final Court court;
  final DateTime? startUtc;
  final DateTime? endUtc;

  @override
  Widget build(BuildContext context) {
    final localStart = startUtc?.toLocal();
    final localEnd = endUtc?.toLocal();
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
                  DetailRow(
                    label: 'Date',
                    value: localStart == null
                        ? 'Pending'
                        : DateFormat('EEE, d MMM').format(localStart),
                  ),
                  DetailRow(
                    label: 'Time',
                    value: localStart == null || localEnd == null
                        ? 'Pending'
                        : '${DateFormat.jm().format(localStart)} - ${DateFormat.jm().format(localEnd)}',
                  ),
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
              stream: AppRepository.instance.myBookingParticipation(),
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
                    final court = Court(
                      id: (data['courtId'] ?? '').toString(),
                      academyId: (data['academyId'] ?? '').toString(),
                      name: (data['courtName'] ?? 'Court').toString(),
                      subtitle: (data['sport'] ?? 'Sports court').toString(),
                      sport: (data['sport'] ?? 'Sport').toString(),
                      rating: '—',
                      distance: '',
                      price:
                          '${data['currency'] ?? 'JOD'} ${(((data['totalMinor'] as num?)?.toInt() ?? 0) / 100).toStringAsFixed(2)}',
                      currency: (data['currency'] ?? 'JOD').toString(),
                      basePriceMinor:
                          (data['totalMinor'] as num?)?.toInt() ?? 0,
                      gradient: const [Color(0xFF102A43), Color(0xFF1F7A8C)],
                      icon: CupertinoIcons.sportscourt,
                    );
                    return GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BookingDetailsScreen(court: court),
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
    final user = FirebaseAuth.instance.currentUser;
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
            if (widget.matchId == null || user == null || user.isAnonymous)
              const CardBox(
                child: Text(
                  'Sign in and join a live match to use its group chat.',
                ),
              )
            else
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: AppRepository.instance.match(widget.matchId!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const CardBox(
                      child: Text('The match could not be loaded. Try again.'),
                    );
                  }
                  final players = List<String>.from(
                    snapshot.data?.data()?['players'] as List? ?? const [],
                  );
                  if (!players.contains(user.uid)) {
                    return const CardBox(
                      child: Text(
                        'Chat becomes available after you join this match.',
                      ),
                    );
                  }
                  return _ParticipantChat(
                    matchId: widget.matchId!,
                    controller: _message,
                    sending: _sending,
                    onSend: _send,
                  );
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

  Future<void> _send() async {
    final body = _message.text.trim();
    if (body.isEmpty || widget.matchId == null || _sending) return;
    setState(() => _sending = true);
    try {
      await AppRepository.instance.sendMatchMessage(widget.matchId!, body);
      _message.clear();
    } catch (error) {
      if (mounted) {
        await showAdaptiveMessage(
          context,
          title: 'Message not sent',
          message: error.toString().replaceFirst(
            'DomainValidationException: ',
            '',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

class _ParticipantChat extends StatelessWidget {
  const _ParticipantChat({
    required this.matchId,
    required this.controller,
    required this.sending,
    required this.onSend,
  });
  final String matchId;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: AppRepository.instance.matchMessages(matchId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const CardBox(
              child: Text('Messages could not be loaded. Try again.'),
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
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: mine
                        ? AppColors.purple
                        : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    data['body']?.toString() ?? '',
                    style: TextStyle(
                      color: mine
                          ? Colors.white
                          : Theme.of(context).colorScheme.onSurface,
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
        controller: controller,
        label: 'Message the players',
        icon: CupertinoIcons.chat_bubble,
      ),
      const SizedBox(height: 12),
      PrimaryButton(
        label: sending ? 'Sending...' : 'Send',
        onPressed: sending ? null : onSend,
      ),
    ],
  );
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
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PaymentMethodsScreen()),
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

  // ignore: unused_element
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
  const SectionHeader({super.key, required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

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
        if (onSeeAll != null)
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
        ? const Color(0xFF0D0D0D)
        : color;
    final effectiveBorder = dark && borderColor == AppColors.line
        ? const Color(0xFF242424)
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
    this.onTap,
  });

  final String label;
  final bool selected;
  final bool dark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? (dark ? AppColors.dark : AppColors.purple)
                : scheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? Colors.transparent : scheme.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : scheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
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
            value: 'Amman Sports City',
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
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SportImageCard(
                  height: 156,
                  icon: court.icon,
                  gradient: court.gradient,
                  imageUrl: court.imageUrl,
                ),
                Positioned(
                  top: 10,
                  right: 10,
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
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          court.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        court.price,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    court.subtitle,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        CupertinoIcons.star_fill,
                        color: AppColors.gold,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        court.rating,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 12),
                      const Icon(
                        CupertinoIcons.location_solid,
                        color: AppColors.muted,
                        size: 15,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          court.distanceFrom(
                            LocationService.instance.current.value,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
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
  const SearchBox({super.key, this.controller, this.onChanged});

  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search courts or academies',
        prefixIcon: const Icon(CupertinoIcons.search),
        suffixIcon: controller?.text.isNotEmpty == true
            ? IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  controller!.clear();
                  onChanged?.call('');
                },
                icon: const Icon(CupertinoIcons.clear_circled_solid),
              )
            : null,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
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
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: scheme.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.outlineVariant),
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

class PaymentMethodsScreen extends StatelessWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Payment Methods',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            const Text(
              'Available now',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            const CardBox(
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.money_dollar_circle_fill,
                    color: AppColors.green,
                    size: 32,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pay at the venue',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          'Your booking is reserved and the academy records payment at check-in.',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    CupertinoIcons.checkmark_seal_fill,
                    color: AppColors.green,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const CardBox(
              child: Text(
                'No card or wallet is stored by PlayUp. Online payments will only appear here after a payment provider is securely configured.',
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
    final scheme = Theme.of(context).colorScheme;
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
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant),
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
    final start = (data['startUtc'] as Timestamp?)?.toDate().toLocal();
    final end = (data['endUtc'] as Timestamp?)?.toDate().toLocal();
    final status = (data['status'] ?? 'confirmed').toString();
    final timeLabel = start == null
        ? 'Time pending'
        : '${DateFormat('EEE, d MMM').format(start)} - ${DateFormat.jm().format(start)}${end == null ? '' : ' to ${DateFormat.jm().format(end)}'}';
    final startsSoon =
        start != null &&
        start.isAfter(DateTime.now()) &&
        start.difference(DateTime.now()).inMinutes <= 90;
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
                  timeLabel,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  startsSoon ? 'STARTING SOON' : status.toUpperCase(),
                  style: TextStyle(
                    color: startsSoon ? AppColors.gold : AppColors.green,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Open chat',
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
    final scheme = Theme.of(context).colorScheme;
    return CardBox(
      borderColor: selected ? AppColors.purple : scheme.outlineVariant,
      child: Row(
        children: [
          Icon(icon, color: selected ? AppColors.purple : scheme.onSurface),
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
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            selected
                ? CupertinoIcons.checkmark_circle_fill
                : CupertinoIcons.chevron_right,
            color: selected ? AppColors.purple : scheme.onSurfaceVariant,
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
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: List.generate(labels.length, (index) {
        final selected = index == active;
        return Expanded(
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: selected
                    ? AppColors.purple
                    : scheme.surfaceContainerHighest,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: selected ? Colors.white : scheme.onSurfaceVariant,
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
                  color: selected ? AppColors.purple : scheme.onSurfaceVariant,
                ),
              ),
              if (index < labels.length - 1)
                Expanded(
                  child: Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: scheme.outlineVariant,
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
                  'Needs 2 players  •  JOD 5.25 each',
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
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'View',
                style: TextStyle(
                  color: AppColors.purple,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(width: 4),
              Icon(
                CupertinoIcons.chevron_right,
                color: AppColors.purple,
                size: 16,
              ),
            ],
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
    this.booked = false,
  });

  final String time;
  final String price;
  final bool selected;
  final bool booked;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = booked
        ? AppColors.danger.withValues(alpha: .14)
        : selected
        ? AppColors.purple
        : scheme.surface;
    final border = booked
        ? AppColors.danger
        : selected
        ? AppColors.purple
        : scheme.outlineVariant;
    final foreground = booked
        ? AppColors.danger
        : selected
        ? Colors.white
        : scheme.onSurface;
    return Container(
      width: 82,
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        children: [
          Text(
            time,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            booked ? 'Booked' : price,
            style: TextStyle(
              color: booked
                  ? AppColors.danger
                  : selected
                  ? Colors.white70
                  : scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: booked ? FontWeight.w800 : FontWeight.w400,
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: light ? Colors.white60 : scheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: light ? Colors.white : scheme.onSurface,
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
