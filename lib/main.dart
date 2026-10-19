import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:app_links/app_links.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show
        defaultTargetPlatform,
        kIsWeb,
        TargetPlatform,
        kDebugMode,
        kReleaseMode;
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
import 'package:url_launcher/url_launcher.dart';
import 'firebase_options.dart';
import 'catalog.dart';
import 'more_screens.dart';
import 'more_screens2.dart';
import 'more_screens3.dart';
import 'more_screens4.dart';
import 'booking_domain.dart';
import 'booking_presentation.dart';
import 'deep_link_routes.dart';
import 'design_system.dart';
import 'location_service.dart';
import 'map_links.dart';
import 'tournament_screens.dart';
import 'test_data_seed.dart';
import 'sport_activities_screen.dart';
import 'sport_hub_screen.dart';

const useFirebaseEmulators = bool.fromEnvironment('USE_FIREBASE_EMULATORS');

void validateFirebaseEnvironment({
  required bool useEmulators,
  required bool isRelease,
}) {
  if (useEmulators && isRelease) {
    throw StateError(
      'Release builds cannot connect to Firebase emulators or use UAT credentials.',
    );
  }
}

const privacyPolicyUrl = String.fromEnvironment(
  'PRIVACY_POLICY_URL',
  defaultValue: 'https://play-up.fit/privacy',
);
const termsOfServiceUrl = String.fromEnvironment(
  'TERMS_OF_SERVICE_URL',
  defaultValue: 'https://play-up.fit/terms',
);
const firebaseAppCheckWebKey = String.fromEnvironment(
  'FIREBASE_APP_CHECK_WEB_KEY',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  validateFirebaseEnvironment(
    useEmulators: useFirebaseEmulators,
    isRelease: kReleaseMode,
  );
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _configureAppCheck();
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );
  if (useFirebaseEmulators) {
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
  if (!useFirebaseEmulators) unawaited(_configureMessaging());
}

Future<void> _configureAppCheck() async {
  if (useFirebaseEmulators || kDebugMode) return;
  if (kIsWeb) {
    if (firebaseAppCheckWebKey.isNotEmpty) {
      await FirebaseAppCheck.instance.activate(
        providerWeb: ReCaptchaV3Provider(firebaseAppCheckWebKey),
      );
    }
    return;
  }
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: const AndroidPlayIntegrityProvider(),
      providerApple: const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
  }
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
  static const background = Color(0xFFF7F9F8);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF101614);
  static const muted = Color(0xFF66736D);
  static const line = Color(0xFFE4EAE7);
  static const dark = Color(0xFF071A15);
  static const dark2 = Color(0xFF0D251E);
  // Compatibility alias: legacy screens use `purple` as their primary token.
  static const purple = Color(0xFF16C784);
  static const green = Color(0xFF16C784);
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
        return 'Email or password is incorrect. Please try again.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect. Please try again.';
      case 'email-already-in-use':
        return 'An account already exists with this email. Try signing in.';
      case 'weak-password':
        return 'Password is too weak — use at least 8 characters.';
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
  static const _iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  static bool get googleAvailable =>
      kIsWeb ||
      defaultTargetPlatform != TargetPlatform.iOS ||
      _iosClientId.isNotEmpty;

  /// Apple requires an enabled Firebase provider plus Apple Developer
  /// credentials. Keep the button out of production builds until both exist.
  static bool get appleAvailable =>
      const bool.fromEnvironment('APPLE_SIGN_IN_ENABLED') &&
      defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> signOutEverywhere() async {
    await AppRepository.instance.removeCurrentPushToken();
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

/// Enters the app with a real Firebase anonymous session. Guest access fails
/// closed when anonymous authentication is not configured.
Future<void> enterAsGuest(BuildContext context) async {
  try {
    await FirebaseAuth.instance.signInAnonymously();
  } catch (error) {
    if (!context.mounted) return;
    await showAdaptiveMessage(
      context,
      title: 'Guest access unavailable',
      message:
          'Guest browsing is temporarily unavailable. Sign in or create an account to continue.',
    );
    return;
  }
  if (!context.mounted) return;
  Navigator.of(context).popUntil((route) => route.isFirst);
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
        theme: playUpTheme(Brightness.light),
        darkTheme: playUpTheme(Brightness.dark),
        themeMode: mode,
        home: const PlatformStatusGate(child: BiometricGate(child: AuthGate())),
      ),
    );
  }
}

class PlatformStatusGate extends StatelessWidget {
  const PlatformStatusGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('platformConfig')
          .doc('general')
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        if (data?['maintenanceMode'] == true) {
          return MaintenanceScreen(
            message:
                data?['maintenanceMessage']?.toString().trim().isNotEmpty ==
                    true
                ? data!['maintenanceMessage'].toString()
                : 'PlayUp is receiving a scheduled update. Please try again shortly.',
            supportEmail: data?['supportEmail']?.toString() ?? '',
          );
        }
        return child;
      },
    );
  }
}

class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({
    super.key,
    required this.message,
    required this.supportEmail,
  });

  final String message;
  final String supportEmail;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const PlayUpMark(size: 64),
                    const SizedBox(height: 24),
                    Text(
                      'We will be right back',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        height: 1.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (supportEmail.trim().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      SelectableText(
                        supportEmail,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
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
  static const _pendingBookingKey = 'pending_booking_invite';
  static const _pendingMatchKey = 'pending_match_invite';
  static final _links = AppLinks();
  static StreamSubscription<User?>? _authChanges;

  static Future<void> start() async {
    final initial = await _links.getInitialLink();
    if (initial != null) await _handle(initial);
    _links.uriLinkStream.listen(_handle);
    _authChanges ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && !user.isAnonymous) unawaited(consumePending());
    });
  }

  static Future<void> _handle(Uri uri) async {
    final invite = parsePlayUpInvite(uri);
    if (invite == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      final prefs = await SharedPreferences.getInstance();
      final key = invite.type == PlayUpInviteType.booking
          ? _pendingBookingKey
          : _pendingMatchKey;
      await prefs.setString(key, invite.id);
      return;
    }
    switch (invite.type) {
      case PlayUpInviteType.booking:
        await _joinBooking(invite.id);
        break;
      case PlayUpInviteType.match:
        await _joinMatch(invite.id);
        break;
    }
  }

  static Future<void> consumePending() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    final prefs = await SharedPreferences.getInstance();
    final bookingToken = prefs.getString(_pendingBookingKey);
    if (bookingToken != null && await _joinBooking(bookingToken)) {
      await prefs.remove(_pendingBookingKey);
    }
    final matchId = prefs.getString(_pendingMatchKey);
    if (matchId != null && await _joinMatch(matchId)) {
      await prefs.remove(_pendingMatchKey);
    }
  }

  static Future<bool> _joinBooking(String token) async {
    try {
      await AppRepository.instance.joinBookingInvite(token);
      appMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('You joined the booking.')),
      );
      return true;
    } catch (error) {
      appMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
      return false;
    }
  }

  static Future<bool> _joinMatch(String matchId) async {
    try {
      await AppRepository.instance.joinExistingMatch(matchId);
      appMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('You joined the match.')),
      );
      return true;
    } catch (error) {
      appMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
      return false;
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
            if (readySnapshot.hasError) {
              return const StartupErrorScreen();
            }
            return StreamBuilder<Map<String, dynamic>>(
              stream: AppRepository.instance.currentUserDoc(),
              builder: (context, profileSnapshot) {
                if (profileSnapshot.hasError) {
                  return const StartupErrorScreen();
                }
                if (!profileSnapshot.hasData) {
                  return const LaunchLoadingScreen();
                }
                final profile = profileSnapshot.data!;
                if (profile['mustChangePassword'] == true) {
                  return const RequiredPasswordChangeScreen();
                }
                final role = profile['role']?.toString() ?? 'player';
                if (!user.isAnonymous && !user.emailVerified) {
                  return const EmailVerificationScreen();
                }
                if (role == 'academyOwner' ||
                    role == 'courtOwner' ||
                    role == 'academyStaff') {
                  return const AcademyModeDashboard(standalone: true);
                }
                if (!user.isAnonymous && profile['setupComplete'] != true) {
                  return const SportsSelectionScreen();
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
  CollectionReference<Map<String, dynamic>> get _userBlocks =>
      _db.collection('userBlocks');

  Future<void> ensureUserProfile(User user) async {
    // Guest mode is deliberately account-less. Do not create loyalty,
    // achievement, profile, or points data for anonymous visitors.
    if (user.isAnonymous) return;
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
            LocationService.instance.current.value?.label ?? 'Location not set',
        'level': 1,
        'rankTitle': 'Rookie',
        'xp': 0,
        'nextLevelXp': 500,
        'points': 0,
        'rating': 0.0,
        'reliability': 100,
        'matches': 0,
        'winRate': 0,
        'sports': <String>[],
        'setupComplete': false,
        'notificationPreferences': <String, bool>{
          'bookingReminders': true,
          'matchInvites': true,
          'rewardsAndOffers': true,
          'academyAnnouncements': false,
          'systemUpdates': true,
        },
        'privacyPreferences': <String, bool>{
          'publicProfile': true,
          'showActivity': true,
          'allowInvites': true,
        },
        'role': 'player',
        'permissions': <String>[],
        'suspended': false,
        'createdAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      });
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

  Future<void> updatePreferences({
    Map<String, bool>? notifications,
    Map<String, bool>? privacy,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw const DomainValidationException(
        'Sign in to save your preferences.',
      );
    }
    await _users.doc(user.uid).set({
      'notificationPreferences': ?notifications,
      'privacyPreferences': ?privacy,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeCurrentPushToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous || kIsWeb) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await _users.doc(user.uid).update({
        'fcmTokens': FieldValue.arrayRemove([token]),
        'lastFcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // Signing out must still work when push services are unavailable.
    }
  }

  Future<void> deleteMyAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw const DomainValidationException('No account is signed in.');
    }
    try {
      await _functions.httpsCallable('deleteMyAccount').call();
    } on FirebaseFunctionsException catch (error) {
      throw DomainValidationException(
        error.message ?? 'Your account could not be deleted.',
      );
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

  Future<Map<String, dynamic>> quoteBooking({
    required Court court,
    required DateTime startUtc,
    required DateTime endUtc,
    String? promotionCode,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw const DomainValidationException('Sign in to review this booking.');
    }
    try {
      final response = await _functions.httpsCallable('quoteBooking').call({
        'courtId': court.id,
        'startUtc': startUtc.toIso8601String(),
        'endUtc': endUtc.toIso8601String(),
        if (promotionCode?.trim().isNotEmpty ?? false)
          'promotionCode': promotionCode!.trim().toUpperCase(),
      });
      return Map<String, dynamic>.from(response.data as Map);
    } on FirebaseFunctionsException catch (error) {
      if (useFirebaseEmulators && _callableUnavailable(error)) {
        final durationMinutes = endUtc.difference(startUtc).inMinutes;
        final durationHours = durationMinutes / 60.0;
        final hour = startUtc.toLocal().hour;
        final hourlyRateMinor = court.effectiveHourlyRateMinor(hour);
        final totalMinor = (hourlyRateMinor * durationHours).round();
        return {
          'courtId': court.id,
          'currency': court.currency,
          'subtotalMinor': totalMinor,
          'discountMinor': 0,
          'totalMinor': totalMinor,
          'ratePerHalfHourMinor': (hourlyRateMinor / 2).round(),
          'durationMinutes': durationMinutes,
          'isPeak': court.isPeakHour(hour),
          'paymentMethod': 'cash',
        };
      }
      throw DomainValidationException(
        error.message ?? 'The booking price could not be verified.',
      );
    } catch (error) {
      if (error is DomainValidationException) rethrow;
      if (useFirebaseEmulators) {
        final durationMinutes = endUtc.difference(startUtc).inMinutes;
        final durationHours = durationMinutes / 60.0;
        final hour = startUtc.toLocal().hour;
        final hourlyRateMinor = court.effectiveHourlyRateMinor(hour);
        final totalMinor = (hourlyRateMinor * durationHours).round();
        return {
          'courtId': court.id,
          'currency': court.currency,
          'subtotalMinor': totalMinor,
          'discountMinor': 0,
          'totalMinor': totalMinor,
          'ratePerHalfHourMinor': (hourlyRateMinor / 2).round(),
          'durationMinutes': durationMinutes,
          'isPeak': court.isPeakHour(hour),
          'paymentMethod': 'cash',
        };
      }
      throw const DomainValidationException(
        'The booking price could not be verified. Check your connection.',
      );
    }
  }

  Future<String> createBooking({
    required Court court,
    required bool matchmaking,
    required DateTime startUtc,
    required DateTime endUtc,
    required int playerCapacity,
    String? promotionCode,
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
        if (promotionCode?.trim().isNotEmpty ?? false)
          'promotionCode': promotionCode!.trim().toUpperCase(),
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

  Future<void> cancelBooking(String bookingId, String reason) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw const DomainValidationException('Sign in to cancel a booking.');
    }
    try {
      await _functions.httpsCallable('transitionBooking').call({
        'bookingId': bookingId,
        'status': 'cancelled',
        'reason': reason.trim(),
      });
    } on FirebaseFunctionsException catch (error) {
      throw DomainValidationException(
        error.message ?? 'The booking could not be cancelled.',
      );
    }
  }

  bool _callableUnavailable(FirebaseFunctionsException error) =>
      error.code == 'not-found' ||
      error.code == 'unimplemented' ||
      (error.message ?? '').toLowerCase().contains('not found');

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
      try {
        final response = await _functions
            .httpsCallable('createExternalMatch')
            .call({
              'title': title,
              'sport': sport,
              'type': type,
              'capacity': capacity,
              'skill': skill,
              'startUtc': startUtc.toUtc().toIso8601String(),
              'venueNote': venueNote.trim(),
            });
        return (response.data as Map)['matchId'].toString();
      } on FirebaseFunctionsException catch (error) {
        throw DomainValidationException(
          error.message ?? 'The match could not be created.',
        );
      }
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
      if (error is FirebaseFunctionsException) {
        throw DomainValidationException(
          error.message ?? 'The match could not be created.',
        );
      }
      rethrow;
    }
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
      if (useFirebaseEmulators && _callableUnavailable(error)) {
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

  Future<Set<int>> unavailableCourtSlotStarts({
    required String courtId,
    required DateTime rangeStartUtc,
    required DateTime rangeEndUtc,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw const DomainValidationException(
        'Sign in to check court availability.',
      );
    }
    try {
      final response = await _functions
          .httpsCallable('listCourtUnavailableSlots')
          .call({
            'courtId': courtId,
            'rangeStartUtc': rangeStartUtc.toUtc().toIso8601String(),
            'rangeEndUtc': rangeEndUtc.toUtc().toIso8601String(),
          });
      final values = (response.data as Map)['unavailableStartUtc'] as List?;
      return {
        for (final value in values ?? const [])
          DateTime.parse(value.toString()).toUtc().millisecondsSinceEpoch,
      };
    } on FirebaseFunctionsException catch (error) {
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
      if (useFirebaseEmulators && _callableUnavailable(error)) {
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

  Future<void> leaveExistingMatch(String matchId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw const DomainValidationException('Sign in to leave a match.');
    }
    try {
      await _functions.httpsCallable('leaveMatch').call({'matchId': matchId});
    } on FirebaseFunctionsException catch (error) {
      throw DomainValidationException(
        error.message ?? 'Could not leave this match.',
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
      if (useFirebaseEmulators && _callableUnavailable(error)) {
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
      if (useFirebaseEmulators && _callableUnavailable(error)) {
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

  Stream<Map<String, Map<String, dynamic>>> blockedMatchParticipants() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || FirebaseAuth.instance.currentUser?.isAnonymous == true) {
      return Stream.value(const <String, Map<String, dynamic>>{});
    }
    return _userBlocks
        .where('participantIds', arrayContains: uid)
        .snapshots()
        .map(
          (snapshot) => {
            for (final doc in snapshot.docs)
              if ((doc.data()['participantIds'] as List?)
                      ?.whereType<String>()
                      .any((id) => id != uid) ==
                  true)
                (doc.data()['participantIds'] as List)
                    .whereType<String>()
                    .firstWhere((id) => id != uid): doc
                    .data(),
          },
        );
  }

  Future<void> blockMatchParticipant(String userId) async {
    try {
      await _functions.httpsCallable('blockUser').call({'userId': userId});
    } on FirebaseFunctionsException catch (error) {
      throw DomainValidationException(
        error.message ?? 'This player could not be blocked.',
      );
    }
  }

  Future<void> unblockMatchParticipant(String userId) async {
    try {
      await _functions.httpsCallable('unblockUser').call({'userId': userId});
    } on FirebaseFunctionsException catch (error) {
      throw DomainValidationException(
        error.message ?? 'This player could not be unblocked.',
      );
    }
  }

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
      final data = Map<String, dynamic>.from(result.data as Map);
      final token = data['token']?.toString().trim() ?? '';
      if (token.isEmpty) {
        throw const DomainValidationException(
          'The booking invite did not include a valid link token.',
        );
      }
      return 'https://play-up.fit/join/booking/$token';
    } on FirebaseFunctionsException catch (error) {
      if (useFirebaseEmulators && _callableUnavailable(error)) {
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
        return 'https://play-up.fit/join/booking/$token';
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
      if (!useFirebaseEmulators || !_callableUnavailable(error)) {
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

  Future<void> submitMatchScore({
    required String matchId,
    required int teamAScore,
    required int teamBScore,
    List<String> sets = const [],
  }) async {
    try {
      await _functions.httpsCallable('submitMatchScore').call({
        'matchId': matchId,
        'teamAScore': teamAScore,
        'teamBScore': teamBScore,
        'sets': sets,
      });
    } on FirebaseFunctionsException catch (e) {
      if (useFirebaseEmulators && _callableUnavailable(e)) {
        await _db.collection('matches').doc(matchId).update({
          'score': {
            'teamAScore': teamAScore,
            'teamBScore': teamBScore,
            'sets': sets,
          },
          'scoreSubmittedBy': FirebaseAuth.instance.currentUser?.uid,
          'scoreStatus': 'pendingConfirmation',
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }
      throw DomainValidationException(
        e.message ?? 'Could not submit match score.',
      );
    }
  }

  Future<void> confirmMatchScore({
    required String matchId,
    required bool accept,
  }) async {
    try {
      await _functions.httpsCallable('confirmMatchScore').call({
        'matchId': matchId,
        'accept': accept,
      });
    } on FirebaseFunctionsException catch (e) {
      if (useFirebaseEmulators && _callableUnavailable(e)) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (accept) {
          await _db.collection('matches').doc(matchId).update({
            'scoreStatus': 'confirmed',
            'scoreConfirmedBy': uid,
            'status': 'completed',
            'completedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          await _db.collection('matches').doc(matchId).update({
            'scoreStatus': 'disputed',
            'scoreDisputedBy': uid,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        return;
      }
      throw DomainValidationException(
        e.message ?? 'Could not confirm match score.',
      );
    }
  }

  Future<void> updateCashSplitStatus({
    required String bookingId,
    required String playerId,
    required bool paid,
  }) async {
    try {
      await _functions.httpsCallable('updateCashSplitStatus').call({
        'bookingId': bookingId,
        'playerId': playerId,
        'paid': paid,
      });
    } on FirebaseFunctionsException catch (e) {
      throw DomainValidationException(
        e.message ?? 'Could not update cash status.',
      );
    } catch (_) {
      rethrow;
    }
  }

  Future<void> submitSupportTicket(String category, String message) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw const DomainValidationException(
        'Sign in before contacting support.',
      );
    }
    await _supportTickets.add({
      'userId': user.uid,
      'category': category,
      'message': message.trim(),
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
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
    } catch (error) {
      throw DomainValidationException('Rating could not be submitted: $error');
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
    this.imageUrls = const [],
    this.id = '',
    this.latitude,
    this.longitude,
    this.academyId = '',
    this.sport = 'Sport',
    this.currency = 'JOD',
    this.basePriceMinor = 0,
    this.address = '',
    this.description = '',
    this.phone = '',
    this.email = '',
    this.bookable = true,
    this.active = true,
    this.openingHour = 6,
    this.closingHour = 23,
    this.peakPriceMinor,
    this.peakHourStart,
    this.peakHourEnd,
  });

  final String name;
  final String subtitle;
  final String rating;
  final String distance;
  final String price;
  final List<Color> gradient;
  final IconData icon;
  final String imageUrl;
  final List<String> imageUrls;
  final String id;
  final double? latitude;
  final double? longitude;
  final String academyId;
  final String sport;
  final String currency;
  final int basePriceMinor;
  final String address;
  final String description;
  final String phone;
  final String email;
  final bool bookable;
  final bool active;
  final int openingHour;
  final int closingHour;
  final int? peakPriceMinor;
  final int? peakHourStart;
  final int? peakHourEnd;

  List<String> get galleryImages {
    final images = <String>{};
    if (imageUrl.trim().isNotEmpty) images.add(imageUrl.trim());
    images.addAll(imageUrls.where((url) => url.trim().isNotEmpty));
    return images.toList(growable: false);
  }

  bool get hasPeakPricing =>
      peakPriceMinor != null &&
      peakHourStart != null &&
      peakHourEnd != null &&
      peakPriceMinor! > 0;

  bool isPeakHour(int hour) =>
      hasPeakPricing && hour >= peakHourStart! && hour < peakHourEnd!;

  int effectiveHourlyRateMinor(int hour) =>
      isPeakHour(hour) ? peakPriceMinor! : basePriceMinor;

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

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const _slides = [
    _WelcomeSlide(
      imageUrl: 'asset:assets/images/sports/basketball_court_ball.png',
      badge: 'REAL SPORTS VENUES',
      icon: Icons.sports_tennis_rounded,
      title: 'Find Courts &\nVenues',
      description:
          'Browse real sports venues across Amman. Contact each venue to confirm current rates and availability.',
      tags: ['Real Venues', 'Court Details', 'Contact to Confirm'],
      gradientColors: [Color(0xFF16C784), Color(0xFF087A4A)],
    ),
    _WelcomeSlide(
      imageUrl: 'asset:assets/images/sports/football_court_ball.png',
      badge: 'COMMUNITY & MATCHES',
      icon: CupertinoIcons.person_2_alt,
      title: 'Find Players &\nPlay Together',
      description:
          'Browse games when players and venue organizers publish them. Join live matches and coordinate with teammates.',
      tags: ['Open Match Listings', 'Match Chat', 'Player Community'],
      gradientColors: [Color(0xFF0F766E), Color(0xFF134E4A)],
    ),
    _WelcomeSlide(
      imageUrl: 'asset:assets/images/sports/volleyball_court_ball.png',
      badge: 'SPORTS AROUND AMMAN',
      icon: CupertinoIcons.sportscourt,
      title: 'Discover Local\nSports',
      description:
          'Explore real venue and academy listings. More activities and events appear as local organizers add them.',
      tags: ['Venue Listings', 'Academy Listings', 'Organizer Updates'],
      gradientColors: [Color(0xFFEA580C), Color(0xFF9A3412)],
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onNext() {
    if (_currentPage < _slides.length - 1) {
      _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLastSlide = _currentPage == _slides.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  const PlayUpMark(size: 38),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'PlayUp',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AuthScreen()),
                    ),
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ),

            // 3-Slide PageView Carousel
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        // Photo Card with dark gradient and badge
                        Expanded(
                          flex: 5,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (slide.imageUrl.startsWith('asset:'))
                                  Image.asset(
                                    slide.imageUrl.substring(6),
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            Container(
                                              color: Colors.grey.shade900,
                                              child: const Icon(
                                                Icons.sports_soccer,
                                                color: Colors.white54,
                                                size: 48,
                                              ),
                                            ),
                                  )
                                else
                                  CachedNetworkImage(
                                    imageUrl: slide.imageUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      color: Colors.grey.shade900,
                                      child: const Center(
                                        child: Icon(
                                          Icons.sports_rounded,
                                          color: Colors.white54,
                                          size: 48,
                                        ),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        Container(
                                          color: Colors.grey.shade900,
                                          child: const Icon(
                                            Icons.sports_soccer,
                                            color: Colors.white54,
                                            size: 48,
                                          ),
                                        ),
                                  ),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.black.withValues(alpha: 0.2),
                                        Colors.black.withValues(alpha: 0.75),
                                      ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 16,
                                  left: 16,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: slide.gradientColors.first
                                          .withValues(alpha: 0.9),
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.3,
                                          ),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          slide.icon,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          slide.badge,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 11,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // Title & Description
                        Expanded(
                          flex: 4,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  slide.title,
                                  style: const TextStyle(
                                    fontSize: 26,
                                    height: 1.15,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  slide.description,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.45,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: slide.tags
                                      .map(
                                        (tag) => Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme
                                                .colorScheme
                                                .primaryContainer
                                                .withValues(alpha: 0.6),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Text(
                                            tag,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: theme.colorScheme.primary,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Bottom Actions & Page Indicator
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Dot Indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _slides.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == i ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == i
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Next / Get Started Button
                  PrimaryButton(
                    label: isLastSlide ? 'Get Started' : 'Next',
                    icon: Icons.arrow_forward_rounded,
                    onPressed: _onNext,
                  ),
                  const SizedBox(height: 6),

                  // Guest Entry
                  TextButton(
                    onPressed: () => enterAsGuest(context),
                    child: const Text('Continue as Guest'),
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

class _WelcomeSlide {
  final String imageUrl;
  final String badge;
  final IconData icon;
  final String title;
  final String description;
  final List<String> tags;
  final List<Color> gradientColors;

  const _WelcomeSlide({
    required this.imageUrl,
    required this.badge,
    required this.icon,
    required this.title,
    required this.description,
    required this.tags,
    required this.gradientColors,
  });
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

class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CupertinoIcons.exclamationmark_triangle,
                    size: 48,
                    color: AppColors.danger,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'PlayUp could not start',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Check your connection and try again. Your account data has not been changed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  PrimaryButton(
                    label: 'Try Again',
                    onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const AuthGate()),
                      (route) => false,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => SocialAuth.signOutEverywhere(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
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
    if (_password.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
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
        if (user != null) {
          // Account creation is already committed at this point. A temporary
          // verification-email outage must not make signup look unsuccessful
          // or leave the user on a form they can no longer submit.
          _emailVerificationNotice.value = null;
          try {
            await FirebaseFunctions.instanceFor(
              region: 'me-central1',
            ).httpsCallable('sendPlayUpEmailVerification').call();
            _emailVerificationNotice.value =
                'A verification email was sent to ${user.email ?? 'your email address'}.';
          } catch (_) {
            // EmailVerificationScreen provides a retry action after AuthGate
            // observes this newly authenticated, unverified account.
            _emailVerificationNotice.value =
                'Your account is ready, but we couldn’t send the verification email. Tap Resend below to try again.';
          }
        }
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
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

  Widget _buildAuthField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: obscureText
          ? TextInputAction.done
          : TextInputAction.next,
      autofillHints: obscureText
          ? const [AutofillHints.password]
          : keyboardType == TextInputType.emailAddress
          ? const [AutofillHints.email]
          : const [AutofillHints.name],
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      cursorColor: AppColors.green,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        floatingLabelStyle: const TextStyle(
          color: Color(0xFF6EE7B7),
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: Icon(icon, color: Colors.white70),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.38),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.green, width: 1.8),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.dark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Image(
            image: AssetImage('assets/images/auth_hero.jpg'),
            fit: BoxFit.cover,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.42),
                  AppColors.dark.withValues(alpha: 0.18),
                  AppColors.dark.withValues(alpha: 0.76),
                  AppColors.dark.withValues(alpha: 0.96),
                ],
                stops: const [0, 0.3, 0.62, 1],
              ),
            ),
          ),
          AutofillGroup(
            child: AppScrollPage(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Bar with Back and App Name
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(
                          CupertinoIcons.back,
                          color: Colors.white,
                        ),
                      ),
                      const PlayUpMark(size: 36),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'PlayUp Jordan',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const IconTheme(
                        data: IconThemeData(color: Colors.white),
                        child: _AuthThemeButton(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  const SizedBox(height: 72),
                  Semantics(
                    header: true,
                    child: Text(
                      _isSignUp ? 'Create your account' : 'Welcome back',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _isSignUp
                        ? 'Join Jordan’s sports community and start playing.'
                        : 'Sign in to book courts, join matches, and keep moving.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 15,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Sign In / Create Account Toggle
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.32),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _isSignUp = false;
                              _error = null;
                            }),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: !_isSignUp
                                    ? AppColors.green
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Sign In',
                                style: TextStyle(
                                  fontWeight: !_isSignUp
                                      ? FontWeight.w900
                                      : FontWeight.w600,
                                  color: !_isSignUp
                                      ? Colors.white
                                      : Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _isSignUp = true;
                              _error = null;
                            }),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _isSignUp
                                    ? AppColors.green
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Create Account',
                                style: TextStyle(
                                  fontWeight: _isSignUp
                                      ? FontWeight.w900
                                      : FontWeight.w600,
                                  color: _isSignUp
                                      ? Colors.white
                                      : Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  if (_isSignUp) ...[
                    _buildAuthField(
                      controller: _name,
                      label: 'Full name',
                      icon: CupertinoIcons.person,
                    ),
                    const SizedBox(height: 12),
                  ],
                  _buildAuthField(
                    controller: _email,
                    label: 'Email',
                    icon: CupertinoIcons.mail,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  _buildAuthField(
                    controller: _password,
                    label: 'Password',
                    icon: CupertinoIcons.lock,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword
                          ? 'Show password'
                          : 'Hide password',
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(
                        _obscurePassword
                            ? CupertinoIcons.eye
                            : CupertinoIcons.eye_slash,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  if (!_isSignUp)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ForgotPasswordScreen(
                              initialEmail: _email.text.trim(),
                            ),
                          ),
                        ),
                        child: const Text(
                          'Forgot password?',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
                  if (SocialAuth.appleAvailable ||
                      SocialAuth.googleAvailable) ...[
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        if (SocialAuth.appleAvailable) ...[
                          Expanded(
                            child: ProviderButton(
                              label: 'Continue with Apple',
                              icon: Icons.apple,
                              onTap: _loading
                                  ? () {}
                                  : () => _social(SocialAuth.apple),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        if (SocialAuth.googleAvailable)
                          Expanded(
                            child: ProviderButton(
                              label: 'Continue with Google',
                              icon: CupertinoIcons.globe,
                              leading: Image.asset(
                                'assets/images/google_g.png',
                                width: 20,
                                height: 20,
                              ),
                              onTap: _loading
                                  ? () {}
                                  : () => _social(SocialAuth.google),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
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
        ],
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

final _emailVerificationNotice = ValueNotifier<String?>(null);

class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _checking = false;
  bool _sending = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _emailVerificationNotice.addListener(_syncNotice);
    _message = _emailVerificationNotice.value;
  }

  void _syncNotice() {
    if (mounted) setState(() => _message = _emailVerificationNotice.value);
  }

  @override
  void dispose() {
    _emailVerificationNotice.removeListener(_syncNotice);
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _message = null;
    });
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      final user = FirebaseAuth.instance.currentUser;
      if (user?.emailVerified == true && mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (route) => false,
        );
        return;
      }
      setState(
        () => _message =
            'Your email is not verified yet. Open the link in your inbox, then try again.',
      );
    } on FirebaseAuthException catch (error) {
      setState(() => _message = friendlyAuthError(error));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      await FirebaseFunctions.instanceFor(
        region: 'me-central1',
      ).httpsCallable('sendPlayUpEmailVerification').call();
      _emailVerificationNotice.value = 'A new verification email was sent.';
    } on FirebaseAuthException catch (error) {
      setState(() => _message = friendlyAuthError(error));
    } catch (_) {
      setState(
        () => _message =
            'We couldn’t send the email. Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _sending = false);
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
            'Verify your email',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Text(
            'Verify the account for ${FirebaseAuth.instance.currentUser?.email ?? 'your email address'}. If the message hasn’t arrived, request another below.',
            style: TextStyle(
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_message!),
              ),
            ),
          ],
          const SizedBox(height: 24),
          PrimaryButton(
            label: _checking ? 'Checking...' : 'I verified my email',
            onPressed: _checking ? () {} : _check,
          ),
          const SizedBox(height: 10),
          SecondaryButton(
            label: _sending ? 'Sending...' : 'Resend verification email',
            onPressed: _sending ? () {} : _resend,
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: _checking || _sending
                ? null
                : () => SocialAuth.signOutEverywhere(),
            child: const Text('Use a different account'),
          ),
        ],
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
      title: 'Explore Real Courts',
      accent: 'Real Courts',
      subtitle:
          'Explore real sports venues and contact them to confirm rates and availability.',
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
          const SportImageCard(
            height: 250,
            icon: CupertinoIcons.sportscourt,
            imageUrl: 'asset:assets/images/infinity_sports/court_3x3.jpeg',
          ),
          Positioned(
            left: -4,
            right: -4,
            bottom: -46,
            child: CardBox(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const SportImageThumb(
                    size: 76,
                    imageUrl:
                        'asset:assets/images/infinity_sports/court_3x3.jpeg',
                  ),
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
                          'FIBA 3x3 Basketball Court',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Contact venue for rates',
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
      subtitle:
          'Browse real games when players and venue organizers publish them.',
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
      subtitle: 'Track your activity and see rewards when they are available.',
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
      const MyBookingsScreen(embedded: true),
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
    final guest = user == null || user.isAnonymous;
    final pages = guest ? _guestPages : _pages;
    final index = _index < pages.length ? _index : 0;
    final destinations = guest
        ? const [
            NavigationDestination(
              icon: Icon(Icons.search_rounded),
              label: 'Explore',
            ),
            NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              label: 'Community',
            ),
            NavigationDestination(
              icon: Icon(Icons.login_rounded),
              label: 'Sign in',
            ),
          ]
        : const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.search_rounded),
              label: 'Explore',
            ),
            NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              selectedIcon: Icon(Icons.groups_rounded),
              label: 'Community',
            ),
            NavigationDestination(
              icon: Icon(Icons.event_outlined),
              selectedIcon: Icon(Icons.event_rounded),
              label: 'Bookings',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ];
    // Stable elements preserve search, filters and scroll between tabs.
    final content = IndexedStack(
      index: index,
      children: List.generate(
        pages.length,
        (pageIndex) =>
            TickerMode(enabled: pageIndex == index, child: pages[pageIndex]),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return Scaffold(
          body: Row(
            children: [
              if (wide)
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: _selectTab,
                  labelType: NavigationRailLabelType.all,
                  destinations: destinations
                      .map(
                        (d) => NavigationRailDestination(
                          icon: d.icon,
                          selectedIcon: d.selectedIcon,
                          label: Text(d.label),
                        ),
                      )
                      .toList(),
                ),
              Expanded(child: content),
            ],
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: index,
                  onDestinationSelected: _selectTab,
                  destinations: destinations,
                ),
        );
      },
    );
  }
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
                  title:
                      '${DateTime.now().hour < 12
                          ? 'Good morning'
                          : DateTime.now().hour < 18
                          ? 'Good afternoon'
                          : 'Good evening'},\n$firstName',
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
          const SizedBox(height: 14),
          const HomeSportCarousel(),
          const SizedBox(height: 22),
          SectionHeader(
            title: 'Courts near you',
            onSeeAll: () => onTabChange(1),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: StreamBuilder<List<Court>>(
              stream: CatalogService.instance.courts(),
              initialData: useFirebaseEmulators ? kTestCourts : const <Court>[],
              builder: (context, snapshot) {
                return ValueListenableBuilder<AppLocation?>(
                  valueListenable: LocationService.instance.current,
                  builder: (context, location, _) {
                    final allCourts = snapshot.data ?? const <Court>[];
                    final nearby = CatalogService.instance.nearbyCourts(
                      allCourts,
                      location,
                    );
                    // Keep loaded venues visible when the device location is
                    // outside Jordan; production never substitutes fixtures.
                    final list = nearby.isEmpty ? allCourts : nearby;
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
            title: 'Academies near you',
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
          if (useFirebaseEmulators && kSportActivities.isNotEmpty) ...[
            const SizedBox(height: 22),
            SectionHeader(
              title: 'Outdoor Sport Adventures',
              onSeeAll: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SportActivitiesScreen(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: kSportActivities.length,
                separatorBuilder: (context, index) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final activity = kSportActivities[index];
                  return GestureDetector(
                    onTap: () => showSportActivityDetails(context, activity),
                    child: Container(
                      width: 220,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: 120,
                            width: double.infinity,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                CachedNetworkImage(
                                  imageUrl: activity.imageUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) =>
                                      Container(color: Colors.grey.shade900),
                                  errorWidget: (context, url, error) =>
                                      Container(color: Colors.grey.shade900),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF16C784),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      activity.priceLabel,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  activity.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    const Icon(
                                      CupertinoIcons.location_solid,
                                      size: 12,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        '${activity.location} • ${activity.duration}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      color: Colors.amber,
                                      size: 15,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${activity.rating} Rating',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const Spacer(),
                                    const Icon(
                                      Icons.chat,
                                      color: Color(0xFF25D366),
                                      size: 14,
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
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HomeSportItem {
  const _HomeSportItem({
    required this.sport,
    required this.icon,
    required this.imageUrl,
    required this.badge,
  });

  final String sport;
  final IconData icon;
  final String imageUrl;
  final String badge;
}

class HomeSportCarousel extends StatefulWidget {
  const HomeSportCarousel({super.key});

  @override
  State<HomeSportCarousel> createState() => _HomeSportCarouselState();
}

class _HomeSportCarouselState extends State<HomeSportCarousel> {
  static const _items = <_HomeSportItem>[
    _HomeSportItem(
      sport: 'Football',
      icon: Icons.sports_soccer_rounded,
      imageUrl: 'asset:assets/images/sports/football_court_ball.png',
      badge: 'Team Play',
    ),
    _HomeSportItem(
      sport: 'Basketball',
      icon: Icons.sports_basketball_rounded,
      imageUrl: 'asset:assets/images/sports/basketball_court_ball.png',
      badge: 'Court Sport',
    ),
    _HomeSportItem(
      sport: 'Volleyball',
      icon: Icons.sports_volleyball_rounded,
      imageUrl: 'asset:assets/images/sports/volleyball_court_ball.png',
      badge: 'Team Play',
    ),
    _HomeSportItem(
      sport: 'Sea Sports',
      icon: Icons.scuba_diving_rounded,
      imageUrl:
          'https://images.unsplash.com/photo-1632904074880-b77f02b6d01e?w=900&q=82',
      badge: 'Parasailing • Diving',
    ),
    _HomeSportItem(
      sport: 'Dodgeball',
      icon: Icons.sports_handball_rounded,
      imageUrl:
          'https://images.unsplash.com/photo-1593786930094-d5c8164ac771?w=900&q=82',
      badge: 'Team Play',
    ),
    _HomeSportItem(
      sport: 'Kayaking',
      icon: Icons.kayaking_rounded,
      imageUrl:
          'https://images.unsplash.com/photo-1480480565647-1c4385c7c0bf?w=900&q=82',
      badge: 'Water',
    ),
    _HomeSportItem(
      sport: 'Hiking',
      icon: Icons.hiking_rounded,
      imageUrl:
          'https://images.unsplash.com/photo-1551632811-561732d1e306?w=900&q=82',
      badge: 'Outdoors',
    ),
    _HomeSportItem(
      sport: 'Climbing',
      icon: Icons.landscape_rounded,
      imageUrl:
          'https://images.unsplash.com/photo-1522163182402-834f871fd851?w=900&q=82',
      badge: 'Challenge',
    ),
    _HomeSportItem(
      sport: 'Badminton',
      icon: Icons.sports_tennis_rounded,
      imageUrl:
          'https://images.unsplash.com/photo-1722087642932-9b070e9a066e?w=900&q=82',
      badge: 'Singles • Doubles',
    ),
    _HomeSportItem(
      sport: 'Fitness',
      icon: Icons.fitness_center_rounded,
      imageUrl:
          'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=900&q=82',
      badge: 'CrossFit • HYROX',
    ),
  ];

  late final PageController _controller;
  Timer? _timer;
  bool _motionAllowed = true;
  bool _userDragging = false;

  @override
  void initState() {
    super.initState();
    _controller = PageController(
      viewportFraction: .38,
      initialPage: _items.length * 1000,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motionAllowed = TickerMode.valuesOf(context).enabled;
    if (_motionAllowed == motionAllowed && _timer != null) return;
    _motionAllowed = motionAllowed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restartTimer();
    });
  }

  void _restartTimer() {
    _timer?.cancel();
    if (!_motionAllowed) return;
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || !_controller.hasClients || _userDragging) return;
      final position = _controller.position;
      final nextOffset = position.pixels + 0.55;
      if (nextOffset <= position.maxScrollExtent) {
        _controller.jumpTo(nextOffset);
      }
    });
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userDragging = true;
    } else if (notification is ScrollEndNotification && _userDragging) {
      _userDragging = false;
    }
    return false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Explore Sports & Adventure',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 126,
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScrollNotification,
              child: PageView.builder(
                controller: _controller,
                padEnds: false,
                pageSnapping: false,
                allowImplicitScrolling: true,
                itemBuilder: (context, index) {
                  final item = _items[index % _items.length];
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: _HomeSportHubChip(
                      sport: item.sport,
                      icon: item.icon,
                      imageUrl: item.imageUrl,
                      badge: item.badge,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeSportHubChip extends StatelessWidget {
  final String sport;
  final IconData icon;
  final String imageUrl;
  final String badge;

  const _HomeSportHubChip({
    required this.sport,
    required this.icon,
    required this.imageUrl,
    required this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Explore $sport courts and activities',
      child: Material(
        color: AppColors.dark,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  SportHubScreen(sport: sport, heroImageUrl: imageUrl),
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl.startsWith('asset:'))
                Image.asset(
                  imageUrl.substring(6),
                  fit: BoxFit.cover,
                  cacheWidth: 840,
                  errorBuilder: (context, error, stackTrace) => ColoredBox(
                    color: AppColors.dark2,
                    child: Center(
                      child: Icon(icon, color: Colors.white70, size: 30),
                    ),
                  ),
                )
              else
                CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 420,
                  placeholder: (context, url) => const ColoredBox(
                    color: AppColors.dark2,
                    child: Center(
                      child: Icon(Icons.image_outlined, color: Colors.white54),
                    ),
                  ),
                  errorWidget: (context, url, error) => ColoredBox(
                    color: AppColors.dark2,
                    child: Center(
                      child: Icon(icon, color: Colors.white70, size: 30),
                    ),
                  ),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black12, Colors.black87],
                    stops: [.2, 1],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .42),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Icon(icon, color: Colors.white, size: 19),
                        ),
                        const Spacer(),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .5),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              badge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sport,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            shadows: [Shadow(blurRadius: 8)],
                          ),
                        ),
                        Text(
                          'Courts & activities',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .82),
                            fontSize: 10,
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
  final String? initialSport;
  const BookScreen({super.key, this.initialSport});

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  final _search = TextEditingController();
  late Stream<List<Court>> _courtsStream;
  late String _sport;

  @override
  void initState() {
    super.initState();
    _sport = widget.initialSport ?? 'All';
    _courtsStream = CatalogService.instance.courts();
  }

  void _retryCourts() {
    setState(() => _courtsStream = CatalogService.instance.courts());
  }

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
              title: 'Find your venue',
              subtitle: location?.label ?? 'Choose your location',
              onLocationTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
              ),
              trailing: IconButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MapViewScreen()),
                ),
                tooltip: 'View courts on map',
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
                  'Football',
                  'Tennis',
                  'Basketball',
                  'Padel',
                  'Volleyball',
                  'Dodgeball',
                  'Badminton',
                  'Fitness',
                  'Sea Sports',
                  'Kayaking',
                  'Hiking',
                  'Climbing',
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
            title: 'Available venues',
            onSeeAll: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const MapViewScreen())),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<Court>>(
            stream: _courtsStream,
            initialData: useFirebaseEmulators ? kTestCourts : const <Court>[],
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return ValueListenableBuilder<AppLocation?>(
                valueListenable: LocationService.instance.current,
                builder: (context, location, _) {
                  final allCourts = snapshot.data ?? const <Court>[];
                  final nearby = CatalogService.instance.nearbyCourts(
                    allCourts,
                    location,
                    sport: _sport,
                    query: _search.text,
                  );
                  final list = nearby.isEmpty
                      ? CatalogService.instance.nearbyCourts(
                          allCourts,
                          null,
                          sport: _sport,
                          query: _search.text,
                        )
                      : nearby;
                  if (list.isEmpty) {
                    if (snapshot.hasError) {
                      return CardBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const ErrorBanner(
                              message:
                                  'Venues could not load. Check your connection and try again.',
                            ),
                            const SizedBox(height: 12),
                            SecondaryButton(
                              label: 'Retry',
                              onPressed: _retryCourts,
                            ),
                          ],
                        ),
                      );
                    }
                    return EmptyState(
                      icon: CupertinoIcons.sportscourt,
                      title: 'No venues found',
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
                  final venueList = ListView.separated(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    itemBuilder: (_, index) =>
                        CourtListCard(court: list[index]),
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemCount: list.length,
                  );
                  if (!snapshot.hasError) return venueList;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const CardBox(
                        child: Text(
                          'Showing saved venue details. Confirm current availability directly with the venue.',
                        ),
                      ),
                      const SizedBox(height: 10),
                      SecondaryButton(
                        label: 'Retry connection',
                        onPressed: _retryCourts,
                      ),
                      const SizedBox(height: 12),
                      venueList,
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
                  'Football',
                  'Tennis',
                  'Basketball',
                  'Padel',
                  'Volleyball',
                  'Dodgeball',
                  'Badminton',
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
              return ValueListenableBuilder<AppLocation?>(
                valueListenable: LocationService.instance.current,
                builder: (context, location, _) {
                  list.sort((a, b) {
                    final aDistance = a.distanceKmFrom(location);
                    final bDistance = b.distanceKmFrom(location);
                    if (aDistance == null && bDistance == null) return 0;
                    if (aDistance == null) return 1;
                    if (bDistance == null) return -1;
                    return aDistance.compareTo(bDistance);
                  });
                  return Column(
                    children: [
                      DarkFeatureCard(
                        title: 'Recommended live match',
                        subtitle: list.first.title,
                        meta: list.first.distanceFrom(location).isEmpty
                            ? '${list.first.sport} • ${list.first.skill} • ${list.first.time}'
                            : '${list.first.sport} • ${list.first.skill} • ${list.first.distanceFrom(location)}',
                        cta: 'View',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                MatchDetailsScreen(match: list.first),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      for (final match in list.take(3))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: OpenMatchCard(
                            match: match,
                            location: location,
                          ),
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
                'Football',
                'Tennis',
                'Basketball',
                'Padel',
                'Volleyball',
                'Dodgeball',
                'Badminton',
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
                          const SizedBox(height: 6),
                          Builder(
                            builder: (context) {
                              final reliability =
                                  (data['reliability'] as num?)?.toInt() ?? 100;
                              final isHigh = reliability >= 90;
                              final isGood = reliability >= 70;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isHigh
                                      ? const Color(
                                          0xFF22C55E,
                                        ).withValues(alpha: 0.15)
                                      : isGood
                                      ? AppColors.gold.withValues(alpha: 0.18)
                                      : Colors.red.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isHigh
                                          ? CupertinoIcons.shield_lefthalf_fill
                                          : CupertinoIcons
                                                .exclamationmark_shield_fill,
                                      size: 13,
                                      color: isHigh
                                          ? const Color(0xFF15803D)
                                          : isGood
                                          ? const Color(0xFFB8860B)
                                          : Colors.red.shade700,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      isHigh
                                          ? '$reliability% Reliability • High Trust'
                                          : isGood
                                          ? '$reliability% Reliability • Good Standing'
                                          : '$reliability% Reliability • Needs Improvement',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: isHigh
                                            ? const Color(0xFF15803D)
                                            : isGood
                                            ? const Color(0xFFB8860B)
                                            : Colors.red.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
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
          const SizedBox(height: 24),
          SettingsTile(
            icon: Icons.card_giftcard_outlined,
            title: 'Rewards & offers',
            subtitle: 'Your points, gifts and available discounts',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const Scaffold(body: RewardsScreen()),
              ),
            ),
          ),
          SettingsTile(
            icon: Icons.group_outlined,
            title: 'Friends',
            subtitle: 'Find players and manage your requests',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FriendsScreen()),
            ),
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

  static String _aboutFor(Court court) {
    final description = court.description.trim();
    return description.isEmpty
        ? 'Contact the venue to confirm available facilities and services.'
        : description;
  }

  Future<void> _openDirections(BuildContext context) async {
    final googleMaps = MapLinks.googleDirections(
      name: court.name,
      address: court.address,
      latitude: court.latitude,
      longitude: court.longitude,
    );
    final osmMap = MapLinks.openStreetMap(
      name: court.name,
      address: court.address,
      latitude: court.latitude,
      longitude: court.longitude,
    );
    if (googleMaps == null || osmMap == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venue location is unavailable.')),
      );
      return;
    }

    try {
      final opened = await launchUrl(
        googleMaps,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        final fallbackOpened = await launchUrl(
          osmMap,
          mode: LaunchMode.externalApplication,
        );
        if (!fallbackOpened && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open directions.')),
          );
        }
      }
    } catch (_) {
      try {
        if (!await launchUrl(osmMap, mode: LaunchMode.externalApplication) &&
            context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open directions.')),
          );
        }
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open directions.')),
        );
      }
    }
  }

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
                _CourtPhotoGallery(court: court),
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
            const SizedBox(height: 10),
            const Text(
              'About',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _aboutFor(court),
              style: const TextStyle(
                color: AppColors.muted,
                height: 1.45,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 16),
            SecondaryButton(
              label: 'Open directions',
              onPressed: () => _openDirections(context),
            ),
            const SizedBox(height: 22),
            if (court.bookable) ...[
              const SectionHeader(title: 'Booking hours'),
              const SizedBox(height: 12),
              CardBox(
                child: Text(
                  'Open daily from ${court.openingHour.toString().padLeft(2, '0')}:00 to ${court.closingHour.toString().padLeft(2, '0')}:00. Choose a date to see live availability.',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ] else
              const CardBox(
                child: Text(
                  'Online booking and rates are not configured yet. Contact the venue to confirm pricing and availability.',
                  style: TextStyle(fontWeight: FontWeight.w700),
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
                        'Price',
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
                    label: court.bookable ? 'Book Now' : 'Call venue',
                    onPressed: court.bookable
                        ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SlotSelectionScreen(court: court),
                            ),
                          )
                        : () async {
                            final phone = court.phone.trim();
                            if (phone.isEmpty ||
                                !await launchUrl(
                                  Uri(scheme: 'tel', path: phone),
                                )) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Venue contact details are unavailable.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
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

class _CourtPhotoGallery extends StatefulWidget {
  const _CourtPhotoGallery({required this.court});

  final Court court;

  @override
  State<_CourtPhotoGallery> createState() => _CourtPhotoGalleryState();
}

class _CourtPhotoGalleryState extends State<_CourtPhotoGallery> {
  late final PageController _controller;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.court.galleryImages;
    final gallery = images.isEmpty ? const [''] : images;
    return SizedBox(
      height: 260,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: gallery.length,
            physics: gallery.length > 1
                ? const PageScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            onPageChanged: (page) => setState(() => _currentPage = page),
            itemBuilder: (context, index) => Semantics(
              image: true,
              label:
                  '${widget.court.name} photo ${index + 1} of ${gallery.length}',
              child: SportImageCard(
                height: 260,
                icon: widget.court.icon,
                gradient: widget.court.gradient,
                imageUrl: gallery[index],
              ),
            ),
          ),
          if (gallery.length > 1)
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var index = 0; index < gallery.length; index++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: index == _currentPage ? 22 : 7,
                      height: 7,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: index == _currentPage
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(99),
                        boxShadow: const [
                          BoxShadow(color: Colors.black38, blurRadius: 4),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          if (gallery.length > 1)
            Positioned(
              right: 14,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_currentPage + 1}/${gallery.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
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
  late String _mode;

  bool get _isFitness => widget.court.sport.toLowerCase() == 'fitness';

  bool get _isAdventure => const {
    'sea sports',
    'kayaking',
    'hiking',
    'climbing',
  }.contains(widget.court.sport.toLowerCase());

  List<(String, IconData, String, String)> get _bookingModes {
    if (_isFitness) {
      return const [
        (
          'self',
          Icons.fitness_center_rounded,
          'Single class',
          'Reserve one place in a scheduled class',
        ),
        (
          'private',
          CupertinoIcons.person,
          'Private training',
          'One-to-one session with a coach',
        ),
        (
          'group',
          CupertinoIcons.person_2,
          'Group training',
          'Train together with your own group',
        ),
      ];
    }
    if (_isAdventure) {
      return const [
        (
          'self',
          CupertinoIcons.person,
          'Individual place',
          'Reserve one place on the experience',
        ),
        (
          'private',
          Icons.explore_rounded,
          'Private guide',
          'Book a dedicated guide or instructor',
        ),
        (
          'group',
          CupertinoIcons.person_2,
          'Private group',
          'Reserve the experience for your group',
        ),
      ];
    }
    return const [
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
    ];
  }

  @override
  void initState() {
    super.initState();
    _mode = _isFitness || _isAdventure ? 'self' : 'invite';
    if (_isFitness || _isAdventure) _players = 1;
  }

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
            AnimatedBookingCourt(
              sport: widget.court.sport,
              players: _players,
              courtName: widget.court.name,
            ),
            const SizedBox(height: 20),
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
              'Booking type',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            for (final option in _bookingModes) ...[
              GestureDetector(
                onTap: () => setState(() {
                  _mode = option.$1;
                  if (_mode == 'private') _players = 1;
                }),
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
                          'People included in this booking',
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

/// Mobile counterpart to the animated SportCourt shown on PlayUp web.
/// It previews the selected group and remaining places before booking review.
class AnimatedBookingCourt extends StatelessWidget {
  const AnimatedBookingCourt({
    super.key,
    required this.sport,
    required this.players,
    required this.courtName,
  });

  final String sport;
  final int players;
  final String courtName;

  @override
  Widget build(BuildContext context) {
    final normalized = sport.toLowerCase();
    final capacity =
        normalized.contains('tennis') || normalized.contains('padel')
        ? 4
        : normalized.contains('basketball')
        ? 10
        : 10;
    final selected = players.clamp(1, capacity);
    final remaining = capacity - selected;
    final isCourt =
        normalized.contains('basketball') ||
        normalized.contains('tennis') ||
        normalized.contains('padel');
    return CardBox(
      color: AppColors.dark,
      borderColor: const Color(0xFF214536),
      radius: 22,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                CupertinoIcons.sportscourt,
                color: AppColors.green,
                size: 19,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${sport.toUpperCase()} COURT · ${courtName.toUpperCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .5,
                  ),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  '$remaining open',
                  key: ValueKey(remaining),
                  style: TextStyle(
                    color: remaining == 0 ? AppColors.green : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _CourtLegendDot(color: AppColors.green, label: 'Your group'),
              const SizedBox(width: 14),
              _CourtLegendDot(
                color: Colors.white.withValues(alpha: .75),
                label: 'Open spot',
                hollow: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 190,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isCourt
                            ? const [Color(0xFF176744), Color(0xFF0C3F32)]
                            : const [Color(0xFF20764D), Color(0xFF104934)],
                      ),
                    ),
                  ),
                  CustomPaint(
                    painter: _AnimatedCourtPainter(sport: normalized),
                  ),
                  for (var i = 0; i < capacity; i++)
                    _BookingCourtSpot(
                      index: i,
                      capacity: capacity,
                      occupied: i < selected,
                      team: i < (capacity / 2).ceil(),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 9),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              remaining > 0
                  ? '$selected ${selected == 1 ? 'player' : 'players'} in your group · $remaining spots available'
                  : 'Your group fills this court',
              key: ValueKey('$selected-$remaining'),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourtLegendDot extends StatelessWidget {
  const _CourtLegendDot({
    required this.color,
    required this.label,
    this.hollow = false,
  });
  final Color color;
  final String label;
  final bool hollow;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: hollow ? Colors.transparent : color,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.5),
        ),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _BookingCourtSpot extends StatelessWidget {
  const _BookingCourtSpot({
    required this.index,
    required this.capacity,
    required this.occupied,
    required this.team,
  });
  final int index;
  final int capacity;
  final bool occupied;
  final bool team;

  @override
  Widget build(BuildContext context) {
    final position = _position(index, capacity);
    return Positioned.fill(
      child: Align(
        alignment: Alignment(position.$1 * 2 - 1, position.$2 * 2 - 1),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          width: occupied ? 24 : 19,
          height: occupied ? 24 : 19,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: occupied
                ? (team ? AppColors.green : const Color(0xFFF4F6F5))
                : Colors.white.withValues(alpha: .12),
            border: Border.all(
              color: occupied ? Colors.white : Colors.white70,
              width: 1.4,
            ),
            boxShadow: [
              if (occupied)
                BoxShadow(
                  color: AppColors.green.withValues(alpha: .45),
                  blurRadius: 10,
                ),
            ],
          ),
          child: Icon(
            occupied ? CupertinoIcons.person_fill : CupertinoIcons.add,
            size: occupied ? 12 : 11,
            color: occupied ? AppColors.dark : Colors.white,
          ),
        ),
      ),
    );
  }

  (double, double) _position(int i, int total) {
    // Coordinates are fractions of the court canvas; use opposing halves.
    const xs = [.20, .50, .80, .30, .70];
    final sideCount = (total / 2).ceil();
    final sideIndex = i % sideCount;
    final x = xs[sideIndex % xs.length];
    final y = i < sideCount
        ? .18 + (sideIndex ~/ xs.length) * .12
        : .64 + (sideIndex ~/ xs.length) * .12;
    return (x, y);
  }
}

class _AnimatedCourtPainter extends CustomPainter {
  const _AnimatedCourtPainter({required this.sport});
  final String sport;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = Colors.white.withValues(alpha: .58)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final bounds = Rect.fromLTWH(
      size.width * .055,
      size.height * .06,
      size.width * .89,
      size.height * .88,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(9)),
      line,
    );
    canvas.drawLine(
      Offset(size.width / 2, bounds.top),
      Offset(size.width / 2, bounds.bottom),
      line,
    );
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      size.height * .16,
      line,
    );
    if (sport.contains('basketball')) {
      for (final top in [true, false]) {
        final y = top ? bounds.top : bounds.bottom - size.height * .19;
        final key = Rect.fromLTWH(
          size.width * .35,
          y,
          size.width * .30,
          size.height * .19,
        );
        canvas.drawRect(key, line);
        canvas.drawCircle(
          Offset(size.width / 2, top ? y + size.height * .19 : y),
          size.width * .17,
          line,
        );
      }
    } else if (sport.contains('tennis') || sport.contains('padel')) {
      canvas.drawLine(
        Offset(size.width * .20, size.height / 2),
        Offset(size.width * .80, size.height / 2),
        line..strokeWidth = 3,
      );
      canvas.drawLine(
        Offset(size.width * .32, bounds.top),
        Offset(size.width * .32, bounds.bottom),
        line..strokeWidth = 1.3,
      );
      canvas.drawLine(
        Offset(size.width * .68, bounds.top),
        Offset(size.width * .68, bounds.bottom),
        line,
      );
    } else {
      canvas.drawRect(
        Rect.fromLTWH(
          size.width * .26,
          bounds.top,
          size.width * .48,
          size.height * .16,
        ),
        line,
      );
      canvas.drawRect(
        Rect.fromLTWH(
          size.width * .26,
          bounds.bottom - size.height * .16,
          size.width * .48,
          size.height * .16,
        ),
        line,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AnimatedCourtPainter oldDelegate) =>
      sport != oldDelegate.sport;
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
  bool _quoteLoading = true;
  Map<String, dynamic>? _quote;
  String? _quoteError;
  String? _appliedPromotionCode;
  final _promotion = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadQuote();
  }

  @override
  void dispose() {
    _promotion.dispose();
    super.dispose();
  }

  Future<void> _loadQuote({String? promotionCode}) async {
    final previousQuote = _quote;
    final previousPromotionCode = _appliedPromotionCode;
    setState(() {
      _quoteLoading = true;
      _quoteError = null;
    });
    try {
      final quote = await AppRepository.instance.quoteBooking(
        court: widget.court,
        startUtc: widget.startUtc,
        endUtc: widget.endUtc,
        promotionCode: promotionCode,
      );
      if (!mounted) return;
      setState(() {
        _quote = quote;
        _appliedPromotionCode = quote['promotionCode']?.toString();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _quote = previousQuote;
        _appliedPromotionCode = previousPromotionCode;
        _quoteError = error.toString();
      });
    } finally {
      if (mounted) setState(() => _quoteLoading = false);
    }
  }

  String _money(int minor) {
    final currency = _quote?['currency']?.toString() ?? widget.court.currency;
    return '$currency ${(minor / 100).toStringAsFixed(2)}';
  }

  Future<void> _confirm() async {
    if (_quote == null || _quoteLoading) return;
    setState(() => _loading = true);
    try {
      final bookingId = await AppRepository.instance.createBooking(
        court: widget.court,
        matchmaking: widget.matchmaking,
        startUtc: widget.startUtc,
        endUtc: widget.endUtc,
        playerCapacity: widget.playerCapacity,
        promotionCode: _appliedPromotionCode,
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
    final subtotal = (_quote?['subtotalMinor'] as num?)?.toInt();
    final discount = (_quote?['discountMinor'] as num?)?.toInt() ?? 0;
    final total = (_quote?['totalMinor'] as num?)?.toInt();
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
                        DetailRow(
                          label: 'Subtotal',
                          value: subtotal == null
                              ? 'Verifying...'
                              : _money(subtotal),
                        ),
                        if (discount > 0)
                          DetailRow(
                            label: 'Promotion',
                            value: '-${_money(discount)}',
                          ),
                        DetailRow(
                          label: 'Total',
                          value: total == null ? '—' : _money(total),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            CardBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Promotion code',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _promotion,
                          label: 'Optional code',
                          icon: CupertinoIcons.tag,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [UpperCaseTextFormatter()],
                          onChanged: (_) {
                            if (_appliedPromotionCode != null) {
                              setState(() {
                                _quote = null;
                                _appliedPromotionCode = null;
                                _quoteError =
                                    'Apply the edited code to verify the new total.';
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 56,
                        child: FilledButton.tonal(
                          onPressed: _quoteLoading
                              ? null
                              : () => _loadQuote(
                                  promotionCode: _promotion.text.trim(),
                                ),
                          child: Text(_quoteLoading ? 'Checking' : 'Apply'),
                        ),
                      ),
                    ],
                  ),
                  if (_appliedPromotionCode != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      '$_appliedPromotionCode applied',
                      style: const TextStyle(
                        color: AppColors.green,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (_quoteError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _quoteError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
          label: _quoteLoading
              ? 'Verifying price...'
              : _loading
              ? 'Confirming...'
              : 'Confirm Booking',
          onPressed: _loading || _quoteLoading || _quote == null
              ? null
              : _confirm,
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
              label: 'Share via WhatsApp',
              icon: CupertinoIcons.chat_bubble_fill,
              onPressed: () async {
                try {
                  final url = await AppRepository.instance.createBookingInvite(
                    bookingId,
                  );
                  final timeStr = localStart == null
                      ? ''
                      : '⏰ ${DateFormat('EEE, d MMM • h:mm a').format(localStart)}\n';
                  final message =
                      '🎾 *Game at ${court.name}!*\n'
                      '$timeStr'
                      '📍 ${court.address.isNotEmpty ? court.address : court.name}\n'
                      '💵 Cash at venue: ${court.price}\n'
                      '👉 Join here: $url';
                  final waUri = Uri.parse(
                    'whatsapp://send?text=${Uri.encodeComponent(message)}',
                  );
                  if (await canLaunchUrl(waUri)) {
                    await launchUrl(waUri);
                  } else {
                    await SharePlus.instance.share(
                      ShareParams(
                        text: message,
                        subject: 'PlayUp Match Invite',
                      ),
                    );
                  }
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

class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  BookingView _view = BookingView.upcoming;

  Stream<List<Map<String, dynamic>>> _bookingsStream() async* {
    yield* AppRepository.instance.myBookingParticipation().map(
      (snapshot) => snapshot.docs
          .map((document) => {...document.data(), 'id': document.id})
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'My Bookings',
              onBack: widget.embedded
                  ? null
                  : () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 8),
            Text(
              'Your court time, confirmation and check-in details.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (FirebaseAuth.instance.currentUser?.isAnonymous != false) ...[
              const SizedBox(height: 18),
              CardBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sign in to view your bookings.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    SecondaryButton(
                      label: 'Sign in',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AuthScreen()),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: BookingView.values
                    .map(
                      (view) => ChoiceChip(
                        label: Text(switch (view) {
                          BookingView.upcoming => 'Upcoming',
                          BookingView.past => 'Past',
                          BookingView.cancelled => 'Cancelled',
                        }),
                        selected: _view == view,
                        onSelected: (_) => setState(() => _view = view),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 18),
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: _bookingsStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const ErrorBanner(
                          message:
                              'Bookings could not load. Check your connection and try again.',
                        ),
                        const SizedBox(height: 10),
                        SecondaryButton(
                          label: 'Retry',
                          onPressed: () => setState(() {}),
                        ),
                      ],
                    );
                  }
                  final now = DateTime.now();
                  final source =
                      snapshot.data ?? const <Map<String, dynamic>>[];
                  final docs =
                      source.where((data) {
                        return bookingViewFor(
                              status: data['status']?.toString() ?? '',
                              end: (data['endUtc'] as Timestamp?)?.toDate(),
                              now: now,
                            ) ==
                            _view;
                      }).toList()..sort((a, b) {
                        final first =
                            (a['startUtc'] as Timestamp?)?.toDate() ?? now;
                        final second =
                            (b['startUtc'] as Timestamp?)?.toDate() ?? now;
                        return _view == BookingView.upcoming
                            ? first.compareTo(second)
                            : second.compareTo(first);
                      });
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      source.isEmpty) {
                    return const Center(child: CupertinoActivityIndicator());
                  }
                  if (docs.isEmpty) {
                    return EmptyState(
                      icon: CupertinoIcons.calendar,
                      title: 'No ${_view.name} bookings',
                      message: 'Book a court and it will appear here.',
                      action: 'Book a Court',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const Scaffold(body: BookScreen()),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    itemCount: docs.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final data = docs[index];
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
                            builder: (_) => BookingDetailsScreen(
                              bookingId: (data['id'] ?? '').toString(),
                              booking: data,
                              court: court,
                            ),
                          ),
                        ),
                        child: BookingTile(data: data),
                      );
                    },
                  );
                },
              ),
            ],
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
                  final playerNames = List<String>.from(
                    snapshot.data?.data()?['playerNames'] as List? ?? const [],
                  );
                  if (!players.contains(user.uid)) {
                    return const CardBox(
                      child: Text(
                        'Chat becomes available after you join this match.',
                      ),
                    );
                  }
                  return StreamBuilder<Map<String, Map<String, dynamic>>>(
                    stream: AppRepository.instance.blockedMatchParticipants(),
                    builder: (context, blockSnapshot) {
                      if (blockSnapshot.hasError) {
                        return const CardBox(
                          child: Text(
                            'Safety settings could not be loaded. Chat is unavailable until you reconnect.',
                          ),
                        );
                      }
                      if (!blockSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return _ParticipantChat(
                        matchId: widget.matchId!,
                        controller: _message,
                        sending: _sending,
                        onSend: _send,
                        players: players,
                        playerNames: playerNames,
                        blockedParticipants: blockSnapshot.data!,
                        onToggleBlock: _toggleParticipantBlock,
                        onReport: (userId, name) => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SupportScreen(
                              category: 'Report player',
                              initialMessage:
                                  'Match: ${widget.matchId}\nPlayer: $name\nPlayer ID: $userId\nReason: ',
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Report Player',
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

  Future<void> _toggleParticipantBlock(
    String userId,
    String name,
    bool currentlyBlockedByMe,
  ) async {
    final action = currentlyBlockedByMe ? 'Unblock' : 'Block';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$action $name?'),
        content: Text(
          currentlyBlockedByMe
              ? 'This player will be able to interact with you in match chat again.'
              : 'You will no longer see this player\'s match messages or send messages in a match that includes them. Support can still receive a report.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      if (currentlyBlockedByMe) {
        await AppRepository.instance.unblockMatchParticipant(userId);
      } else {
        await AppRepository.instance.blockMatchParticipant(userId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$name ${currentlyBlockedByMe ? 'unblocked' : 'blocked'}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      await showAdaptiveMessage(
        context,
        title: 'Could not ${action.toLowerCase()} player',
        message: error.toString().replaceFirst(
          'DomainValidationException: ',
          '',
        ),
      );
    }
  }
}

class _ParticipantChat extends StatelessWidget {
  const _ParticipantChat({
    required this.matchId,
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.players,
    required this.playerNames,
    required this.blockedParticipants,
    required this.onToggleBlock,
    required this.onReport,
  });
  final String matchId;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final List<String> players;
  final List<String> playerNames;
  final Map<String, Map<String, dynamic>> blockedParticipants;
  final Future<void> Function(String userId, String name, bool blockedByMe)
  onToggleBlock;
  final void Function(String userId, String name) onReport;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      CardBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Match players',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < players.length; index++)
              if (players[index] != FirebaseAuth.instance.currentUser?.uid)
                _MatchParticipantSafetyRow(
                  userId: players[index],
                  name:
                      index < playerNames.length &&
                          playerNames[index].trim().isNotEmpty
                      ? playerNames[index].trim()
                      : 'Player',
                  block: blockedParticipants[players[index]],
                  onToggleBlock: onToggleBlock,
                  onReport: onReport,
                ),
          ],
        ),
      ),
      if (players.any((id) => blockedParticipants.containsKey(id)))
        const CardBox(
          child: Text(
            'Chat is paused because this match includes a blocked player. You can leave the match or unblock the player to continue.',
          ),
        ),
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
          final messages = (snapshot.data?.docs ?? const [])
              .where(
                (doc) => !blockedParticipants.containsKey(
                  doc.data()['userId']?.toString(),
                ),
              )
              .toList();
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
      if (!players.any((id) => blockedParticipants.containsKey(id))) ...[
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
    ],
  );
}

class _MatchParticipantSafetyRow extends StatelessWidget {
  const _MatchParticipantSafetyRow({
    required this.userId,
    required this.name,
    required this.block,
    required this.onToggleBlock,
    required this.onReport,
  });

  final String userId;
  final String name;
  final Map<String, dynamic>? block;
  final Future<void> Function(String userId, String name, bool blockedByMe)
  onToggleBlock;
  final void Function(String userId, String name) onReport;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final blockedByMe = block?['blockerId'] == uid;
    final blockedByThem = block != null && !blockedByMe;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: blockedByThem
                ? null
                : () => onToggleBlock(userId, name, blockedByMe),
            child: Text(
              blockedByThem
                  ? 'Blocked you'
                  : blockedByMe
                  ? 'Unblock'
                  : 'Block',
            ),
          ),
          TextButton(
            onPressed: () => onReport(userId, name),
            child: const Text('Report'),
          ),
        ],
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
  int _rating = 0;
  final _comment = TextEditingController();
  final _tags = <String>{};
  bool _submitting = false;
  String? _error;

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
              label: _submitting ? 'Submitting...' : 'Submit Rating',
              onPressed: _submitting || _rating == 0
                  ? null
                  : () async {
                      if (_submitting) return;
                      setState(() {
                        _submitting = true;
                        _error = null;
                      });
                      try {
                        await AppRepository.instance.submitRating(
                          _rating,
                          _tags.toList(),
                          _comment.text.trim(),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Thank you for the rating.'),
                          ),
                        );
                        Navigator.of(context).pop();
                      } catch (error) {
                        if (mounted) setState(() => _error = error.toString());
                      } finally {
                        if (mounted) setState(() => _submitting = false);
                      }
                    },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(message: _error!),
            ],
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
              icon: CupertinoIcons.doc_text,
              title: 'Privacy Policy',
              onTap: () => _openLegal(context, privacyPolicyUrl),
            ),
            SettingsTile(
              icon: CupertinoIcons.checkmark_shield,
              title: 'Terms of Service',
              onTap: () => _openLegal(context, termsOfServiceUrl),
            ),
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

  /// Resets the whole navigation stack back to the authenticated app gate.
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

  Future<void> _openLegal(BuildContext context, String value) async {
    final uri = Uri.tryParse(value);
    if (uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This legal page could not be opened.')),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account, profile, preferences, friendships, notifications, and rewards data. Booking records are retained only in anonymized form for operational and financial history.',
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
      await AppRepository.instance.deleteMyAccount();
      await FirebaseAuth.instance.signOut();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is DomainValidationException
                  ? error.message
                  : 'Your account could not be deleted. Please try again.',
            ),
          ),
        );
      }
      return;
    }
    if (context.mounted) _resetToAuth(context);
  }
}

class SupportScreen extends StatefulWidget {
  const SupportScreen({
    super.key,
    required this.category,
    this.initialMessage = '',
  });

  final String category;
  final String initialMessage;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _message = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _message.text = widget.initialMessage;
  }

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
              label: _submitting ? 'Submitting...' : 'Submit Ticket',
              onPressed: () async {
                if (_submitting) return;
                if (_message.text.trim().length < 10) {
                  setState(
                    () => _error =
                        'Please add at least 10 characters so support can understand the issue.',
                  );
                  return;
                }
                setState(() {
                  _submitting = true;
                  _error = null;
                });
                try {
                  await AppRepository.instance.submitSupportTicket(
                    widget.category,
                    _message.text.trim(),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Support ticket submitted.')),
                  );
                  Navigator.of(context).pop();
                } catch (error) {
                  if (mounted) setState(() => _error = error.toString());
                } finally {
                  if (mounted) setState(() => _submitting = false);
                }
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(message: _error!),
            ],
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
  Widget build(BuildContext context) => SafeArea(
    top: topPadding > 0,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final gutter = constraints.maxWidth > 800
            ? (constraints.maxWidth - 760) / 2
            : 20.0;
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(gutter, topPadding, gutter, 32),
          children: [child],
        );
      },
    ),
  );
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
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
      if (onLocationTap != null)
        TextButton.icon(
          onPressed: onLocationTap,
          icon: const Icon(Icons.location_on_outlined, size: 18),
          label: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        )
      else
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            subtitle,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
    ],
  );
}

class PageTopBar extends StatelessWidget {
  const PageTopBar({super.key, required this.title, this.onBack});
  final String title;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (onBack != null) ...[
        IconButton.outlined(
          tooltip: 'Back',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 12),
      ],
      Expanded(
        child: Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
      ),
    ],
  );
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
    this.radius = 16,
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
          return ValueListenableBuilder<AppLocation?>(
            valueListenable: LocationService.instance.current,
            builder: (context, location, _) {
              final sorted = [...matches]
                ..sort((a, b) {
                  final aDistance = a.distanceKmFrom(location);
                  final bDistance = b.distanceKmFrom(location);
                  if (aDistance == null && bDistance == null) return 0;
                  if (aDistance == null) return 1;
                  if (bDistance == null) return -1;
                  return aDistance.compareTo(bDistance);
                });
              final match = sorted.first;
              final distance = match.distanceFrom(location);
              return DarkFeatureCard(
                title: 'Recommended live match',
                subtitle: match.title,
                meta: distance.isEmpty
                    ? '${match.sport} - ${match.skill} - ${match.court}'
                    : '${match.sport} - ${match.skill} - $distance',
                cta: 'View',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MatchDetailsScreen(match: match),
                  ),
                ),
              );
            },
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
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: onPressed == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onPressed!();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 8),
            ],
            Flexible(child: Text(label, textAlign: TextAlign.center)),
          ],
        ),
      ),
    ),
  );
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
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(label, textAlign: TextAlign.center),
      ),
    ),
  );
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
            if (imageUrl.startsWith('asset:'))
              Image.asset(
                imageUrl.substring(6),
                fit: BoxFit.cover,
                cacheWidth: 1600,
                errorBuilder: (context, error, stackTrace) =>
                    CustomPaint(painter: CourtLinesPainter()),
              )
            else if (imageUrl.isNotEmpty)
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
        child: imageUrl.startsWith('asset:')
            ? Image.asset(
                imageUrl.substring(6),
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(CupertinoIcons.sportscourt, color: Colors.white),
              )
            : imageUrl.isEmpty
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
      padding: EdgeInsets.all(compact ? 16 : 22),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.person_3_fill,
            color: AppColors.green,
            size: 34,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Open matches',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Browse real games published by players and venue organizers.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .72),
                    height: 1.35,
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

class LevelCard extends StatelessWidget {
  const LevelCard({super.key});

  @override
  Widget build(BuildContext context) {
    return CardBox(
      color: AppColors.dark,
      borderColor: const Color(0xFF153020),
      radius: 24,
      padding: const EdgeInsets.all(22),
      child: const Row(
        children: [
          Icon(CupertinoIcons.rosette, color: AppColors.gold, size: 36),
          SizedBox(width: 14),
          Expanded(
            child: Text(
              'Your real progress and available rewards appear here as you play.',
              style: TextStyle(
                color: Colors.white,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
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

String _sportPreviewImage(Court court) {
  final sport = '${court.sport} ${court.subtitle}'.toLowerCase();
  if (sport.contains('football') || sport.contains('soccer')) {
    return 'asset:assets/images/sports/football_court_ball.png';
  }
  if (sport.contains('volleyball')) {
    return 'asset:assets/images/sports/volleyball_court_ball.png';
  }
  if (sport.contains('basketball') || sport.contains('3x3')) {
    return 'asset:assets/images/sports/basketball_court_ball.png';
  }
  if (sport.contains('padel') || sport.contains('tennis')) {
    return 'asset:assets/images/sports/tennis_court_ball.png';
  }
  // Generic sports imagery shows equipment and courts without stock people.
  return '';
}

String _courtCardImage(Court court) {
  final venueImages = court.galleryImages;
  return venueImages.isNotEmpty ? venueImages.first : _sportPreviewImage(court);
}

class CourtListCard extends StatelessWidget {
  const CourtListCard({super.key, required this.court});

  final Court court;

  @override
  Widget build(BuildContext context) {
    final location = LocationService.instance.current.value;
    final distanceKm = court.distanceKmFrom(location);
    final locationLabel = distanceKm == null || distanceKm > 100
        ? court.address
        : court.distanceFrom(location);
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
                  imageUrl: _courtCardImage(court),
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
                          locationLabel,
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
    final location = LocationService.instance.current.value;
    final distanceKm = court.distanceKmFrom(location);
    final locationLabel = distanceKm == null || distanceKm > 100
        ? court.address
        : court.distanceFrom(location);
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
                imageUrl: _courtCardImage(court),
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
                      '${court.rating}  •  $locationLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
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
    this.autofillHints,
    this.textCapitalization,
    this.textInputAction,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;
  final Iterable<String>? autofillHints;
  final TextCapitalization? textCapitalization;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;

  // Most call sites don't set these explicitly, so infer sensible OS
  // autofill/keyboard behavior from the field's type and label instead of
  // touching every call site individually.
  Iterable<String>? get _resolvedAutofillHints {
    if (autofillHints != null) return autofillHints;
    if (obscureText) return const [AutofillHints.password];
    if (keyboardType == TextInputType.emailAddress) {
      return const [AutofillHints.email];
    }
    if (keyboardType == TextInputType.phone) {
      return const [AutofillHints.telephoneNumber];
    }
    if (label.toLowerCase().contains('name')) {
      return const [AutofillHints.name];
    }
    return null;
  }

  TextCapitalization get _resolvedCapitalization {
    if (textCapitalization != null) return textCapitalization!;
    if (obscureText || keyboardType == TextInputType.emailAddress) {
      return TextCapitalization.none;
    }
    final lower = label.toLowerCase();
    if (lower.contains('name') ||
        lower.contains('city') ||
        lower.contains('address')) {
      return TextCapitalization.words;
    }
    if (lower.contains('describe') || lower.contains('bio')) {
      return TextCapitalization.sentences;
    }
    return TextCapitalization.none;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onChanged: onChanged,
      autofillHints: _resolvedAutofillHints,
      textCapitalization: _resolvedCapitalization,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
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
          color: Colors.black.withValues(alpha: 0.38),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leading ?? Icon(icon, size: 19, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
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
    final matchId = data['matchId']?.toString() ?? '';
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
                  startsSoon &&
                          ['pending', 'confirmed', 'checkedIn'].contains(status)
                      ? 'Starting soon'
                      : bookingStatusLabel(status),
                  style: TextStyle(
                    color: status == 'cancelled'
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (matchId.isNotEmpty)
            IconButton(
              tooltip: 'Open match chat',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MatchChatScreen(matchId: matchId),
                ),
              ),
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
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: .5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: colors.primary, size: 22),
          ),
          title: Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: subtitle == null
              ? null
              : Text(
                  subtitle!,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: colors.onSurfaceVariant,
          ),
          onTap: onTap,
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
    this.unavailableLabel = 'Booked',
  });

  final String time;
  final String price;
  final bool selected;
  final bool booked;
  final String unavailableLabel;

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
            booked ? unavailableLabel : price,
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
