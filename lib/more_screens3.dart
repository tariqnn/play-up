import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'main.dart';
import 'more_screens.dart';
import 'location_service.dart';
import 'catalog.dart';
import 'academy_service.dart';

// ---------------------------------------------------------------------------
// Location picker & map view
// ---------------------------------------------------------------------------

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _search = TextEditingController();
  AppLocation? _selected;
  List<AppLocation> _results = const [];
  bool _loading = false;
  Timer? _debounce;

  Future<void> _searchLocations(String query) async {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      if (query.trim().length < 3) {
        if (mounted) setState(() => _results = const []);
        return;
      }
      setState(() => _loading = true);
      try {
        final rows = await LocationService.instance.search(query);
        if (mounted) setState(() => _results = rows);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.toString())));
        }
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    });
  }

  Future<void> _currentLocation() async {
    try {
      final value = await LocationService.instance.useCurrentLocation();
      if (value != null && mounted) {
        setState(() => _selected = value);
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
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
              title: 'Location',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            AppTextField(
              controller: _search,
              label: 'Search city or area',
              icon: CupertinoIcons.search,
              onChanged: _searchLocations,
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _currentLocation,
              child: CardBox(
                borderColor: AppColors.purple,
                child: Row(
                  children: const [
                    Icon(
                      CupertinoIcons.location_circle_fill,
                      color: AppColors.purple,
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Use current location',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (_loading) const LinearProgressIndicator(),
            const SizedBox(height: 18),
            const Text(
              'Search results',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            if (_results.isEmpty &&
                _search.text.trim().length >= 3 &&
                !_loading)
              const CardBox(
                child: Text(
                  'No matching location found. Try a city, district, or address.',
                ),
              ),
            for (final area in _results)
              GestureDetector(
                onTap: () => setState(() => _selected = area),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: CardBox(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    borderColor: _selected == area
                        ? AppColors.purple
                        : AppColors.line,
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.location,
                          color: AppColors.muted,
                          size: 18,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            area.label,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (_selected == area)
                          const Icon(
                            CupertinoIcons.checkmark_circle_fill,
                            color: AppColors.purple,
                            size: 20,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Save Location',
              onPressed: _selected == null
                  ? null
                  : () async {
                      await LocationService.instance.setManual(_selected!);
                      if (context.mounted) Navigator.of(context).pop();
                    },
            ),
          ],
        ),
      ),
    );
  }
}

/// Decorative stylized map with a grid and a center pin.
class MapPreview extends StatelessWidget {
  const MapPreview({super.key, this.height = 200, this.pins = 1});

  final double height;
  final int pins;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: height,
        color: const Color(0xFFE9EEF4),
        child: CustomPaint(
          painter: _MapPainter(),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  CupertinoIcons.placemark_fill,
                  color: AppColors.purple,
                  size: 38,
                ),
                SizedBox(height: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()
      ..color = Colors.white
      ..strokeWidth = 6;
    final thinRoad = Paint()
      ..color = Colors.white
      ..strokeWidth = 3;
    final block = Paint()..color = const Color(0xFFDCE3EC);

    // Blocks
    final rng = math.Random(7);
    for (var i = 0; i < 12; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, 34, 26),
          const Radius.circular(4),
        ),
        block,
      );
    }
    // Roads
    canvas.drawLine(
      Offset(0, size.height * .4),
      Offset(size.width, size.height * .55),
      road,
    );
    canvas.drawLine(
      Offset(size.width * .3, 0),
      Offset(size.width * .45, size.height),
      road,
    );
    canvas.drawLine(
      Offset(size.width * .7, 0),
      Offset(size.width * .6, size.height),
      thinRoad,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MapViewScreen extends StatelessWidget {
  const MapViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Court>>(
      stream: CatalogService.instance.courts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final courts = (snapshot.data ?? const <Court>[])
            .where((court) => court.latitude != null && court.longitude != null)
            .toList();
        return ValueListenableBuilder<AppLocation?>(
          valueListenable: LocationService.instance.current,
          builder: (context, location, _) {
            final center = location != null
                ? LatLng(location.latitude, location.longitude)
                : courts.isNotEmpty
                ? LatLng(courts.first.latitude!, courts.first.longitude!)
                : const LatLng(20, 0);
            return Scaffold(
              body: Stack(
                children: [
                  Positioned.fill(
                    child: FlutterMap(
                      options: MapOptions(
                        initialCenter: center,
                        initialZoom: location == null && courts.isEmpty
                            ? 2
                            : 12,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.playup.playup',
                        ),
                        MarkerLayer(
                          markers: [
                            if (location != null)
                              Marker(
                                point: center,
                                width: 44,
                                height: 44,
                                child: const Icon(
                                  Icons.my_location,
                                  color: Colors.blue,
                                  size: 32,
                                ),
                              ),
                            ...courts.map(
                              (court) => Marker(
                                point: LatLng(
                                  court.latitude!,
                                  court.longitude!,
                                ),
                                width: 48,
                                height: 48,
                                child: GestureDetector(
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          CourtDetailsScreen(court: court),
                                    ),
                                  ),
                                  child: const Icon(
                                    CupertinoIcons.placemark_fill,
                                    color: AppColors.purple,
                                    size: 42,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        RichAttributionWidget(
                          attributions: const [
                            TextSourceAttribution('OpenStreetMap contributors'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: CircleIconButton(
                        icon: CupertinoIcons.arrow_left,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                  DraggableScrollableSheet(
                    initialChildSize: 0.35,
                    minChildSize: 0.2,
                    maxChildSize: 0.85,
                    builder: (context, controller) => Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      child: ListView(
                        controller: controller,
                        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
                        children: [
                          Center(
                            child: Container(
                              width: 44,
                              height: 5,
                              decoration: BoxDecoration(
                                color: AppColors.line,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Courts near you',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (courts.isEmpty)
                            const CardBox(
                              child: Text(
                                'No courts with map coordinates are available near this location.',
                              ),
                            ),
                          for (final court in courts)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: CourtListCard(court: court),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Search results
// ---------------------------------------------------------------------------

class SearchResultsScreen extends StatefulWidget {
  const SearchResultsScreen({super.key});

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  final _search = TextEditingController();
  String _sort = 'Recommended';
  static const _sorts = [
    'Recommended',
    'Nearest',
    'Cheapest',
    'Top rated',
    'Available now',
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
                CircleIconButton(
                  icon: CupertinoIcons.arrow_left,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AppTextField(
                    controller: _search,
                    label: 'Search courts or academies',
                    icon: CupertinoIcons.search,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _sorts.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) => SelectablePill(
                  label: _sorts[index],
                  selected: _sort == _sorts[index],
                  onTap: () => setState(() => _sort = _sorts[index]),
                ),
              ),
            ),
            const SizedBox(height: 18),
            StreamBuilder<List<Court>>(
              stream: CatalogService.instance.courts(),
              builder: (context, snapshot) {
                final results = CatalogService.instance.nearbyCourts(
                  snapshot.data ?? const <Court>[],
                  LocationService.instance.current.value,
                  query: _search.text,
                );
                if (_sort == 'Cheapest') {
                  results.sort(
                    (a, b) => a.basePriceMinor.compareTo(b.basePriceMinor),
                  );
                } else if (_sort == 'Top rated') {
                  results.sort((a, b) => b.rating.compareTo(a.rating));
                } else if (_sort == 'Available now') {
                  results.removeWhere(
                    (court) => !court.isOpenAt(DateTime.now()),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (results.isEmpty) {
                  return const CardBox(
                    child: Text('No courts match this search.'),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${results.length} courts • sorted by $_sort',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final court in results)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: CourtListCard(court: court),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Firebase password reset
// ---------------------------------------------------------------------------

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_email.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter your email first.')));
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _email.text.trim(),
      );
      if (!mounted) return;
      await showAdaptiveMessage(
        context,
        title: 'Check your email',
        message:
            'If an account exists for this address, Firebase has sent a secure password-reset link. Open that link to choose a new password.',
      );
      if (mounted) Navigator.of(context).pop();
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _error = friendlyAuthError(error));
    } catch (error) {
      if (mounted) setState(() => _error = friendlyAuthError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
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
              title: 'Reset Password',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            const AuthHeroBanner(caption: 'Reset password'),
            const SizedBox(height: 20),
            const Text(
              'Forgot your password?',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Enter the email linked to your account and we will send a secure reset link.',
              style: TextStyle(color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 22),
            AppTextField(
              controller: _email,
              label: 'Email',
              icon: CupertinoIcons.mail,
              keyboardType: TextInputType.emailAddress,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 22),
            PrimaryButton(
              label: _sending ? 'Sending...' : 'Send Reset Link',
              onPressed: _sending ? () {} : _send,
            ),
          ],
        ),
      ),
    );
  }
}

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({super.key, required this.email});

  final String email;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final List<TextEditingController> _controllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _nodes = List.generate(4, (_) => FocusNode());

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  bool get _complete => _controllers.every((c) => c.text.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Verify',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            const AuthHeroBanner(caption: 'Verify it\'s you'),
            const SizedBox(height: 20),
            const Text(
              'Enter the code',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'We sent a 4-digit code to ${widget.email}.',
              style: const TextStyle(color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 26),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < 4; i++)
                  SizedBox(
                    width: 64,
                    height: 68,
                    child: TextField(
                      controller: _controllers[i],
                      focusNode: _nodes[i],
                      autofocus: i == 0,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                      ),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: AppColors.surface,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(color: AppColors.line),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(
                            color: AppColors.purple,
                            width: 2,
                          ),
                        ),
                      ),
                      onChanged: (value) {
                        if (value.isNotEmpty && i < 3) {
                          _nodes[i + 1].requestFocus();
                        } else if (value.isEmpty && i > 0) {
                          _nodes[i - 1].requestFocus();
                        }
                        setState(() {});
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Center(
              child: TextButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('A new code was sent.')),
                ),
                child: const Text('Resend code'),
              ),
            ),
            const SizedBox(height: 10),
            PrimaryButton(
              label: 'Verify',
              onPressed: _complete
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ResetPasswordScreen(),
                      ),
                    )
                  : () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Enter the full 4-digit code.'),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Password updated. Please sign in.')),
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'New Password',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            const AuthHeroBanner(caption: 'Almost there'),
            const SizedBox(height: 20),
            const Text(
              'Create a new password',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your new password must be different from previous passwords.',
              style: TextStyle(color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 22),
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
            const SizedBox(height: 22),
            PrimaryButton(label: 'Update Password', onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Owner: offers & events editors
// ---------------------------------------------------------------------------

class OffersManagementScreen extends StatefulWidget {
  const OffersManagementScreen({super.key});

  @override
  State<OffersManagementScreen> createState() => _OffersManagementScreenState();
}

class _OffersManagementScreenState extends State<OffersManagementScreen> {
  late final Future<String> _academyId = AcademyService.instance.academyId();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.purple,
        onPressed: () => _editor(),
        icon: const Icon(CupertinoIcons.add, color: Colors.white),
        label: const Text(
          'New Offer',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
      ),
      body: AppScrollPage(
        child: FutureBuilder<String>(
          future: _academyId,
          builder: (context, academy) {
            if (academy.hasError) {
              return const ErrorBanner(
                message: 'Your academy scope could not be loaded.',
              );
            }
            if (!academy.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return StreamBuilder(
              stream: CatalogService.instance.raw('offers'),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const ErrorBanner(
                    message: 'Offers could not be loaded.',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final offers = snapshot.data!.docs
                    .where((doc) => doc.data()['academyId'] == academy.data)
                    .toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PageTopBar(
                      title: 'Offers',
                      onBack: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(height: 16),
                    if (offers.isEmpty)
                      EmptyState(
                        icon: CupertinoIcons.gift,
                        title: 'No offers yet',
                        message: 'Create a reward offer for your players.',
                        action: 'Create Offer',
                        onTap: _editor,
                      ),
                    for (final offer in offers)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: CardBox(
                          child: Row(
                            children: [
                              const Icon(
                                CupertinoIcons.gift_fill,
                                color: AppColors.gold,
                                size: 34,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (offer.data()['title'] ?? 'Offer')
                                          .toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      '${offer.data()['pointsCost'] ?? offer.data()['points'] ?? 0} pts · ${offer.data()['active'] == false ? 'Inactive' : 'Active'}',
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Edit offer',
                                onPressed: () =>
                                    _editor(id: offer.id, data: offer.data()),
                                icon: const Icon(CupertinoIcons.pencil),
                              ),
                              IconButton(
                                tooltip: 'Delete offer',
                                onPressed: () => _delete('offers', offer.id),
                                icon: const Icon(
                                  CupertinoIcons.trash,
                                  color: AppColors.danger,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _delete(String collection, String id) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialog) => CupertinoAlertDialog(
        title: const Text('Delete this offer?'),
        content: const Text('Players will no longer be able to redeem it.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await CatalogService.instance.delete(collection, id);
  }

  void _editor({String? id, Map<String, dynamic>? data}) {
    final title = TextEditingController(text: data?['title']?.toString() ?? '');
    final points = TextEditingController(
      text: (data?['pointsCost'] ?? data?['points'] ?? '').toString(),
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              id == null ? 'New Offer' : 'Edit Offer',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: title,
              label: 'Offer title',
              icon: CupertinoIcons.tag,
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: points,
              label: 'Points required',
              icon: CupertinoIcons.circle_fill,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Save Offer',
              onPressed: () async {
                final pointsValue = int.tryParse(points.text.trim());
                if (title.text.trim().isEmpty ||
                    pointsValue == null ||
                    pointsValue <= 0) {
                  return;
                }
                final academyId = await _academyId;
                await CatalogService.instance.upsert('offers', id, {
                  'academyId': academyId,
                  'title': title.text.trim(),
                  'partner': 'Academy reward',
                  'points': pointsValue,
                  'pointsCost': pointsValue,
                  'category': 'Academy',
                  'active': data?['active'] != false,
                });
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class EventManagementScreen extends StatefulWidget {
  const EventManagementScreen({super.key});

  @override
  State<EventManagementScreen> createState() => _EventManagementScreenState();
}

class _EventManagementScreenState extends State<EventManagementScreen> {
  late final Future<String> _academyId = AcademyService.instance.academyId();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.purple,
        onPressed: () => _editor(),
        icon: const Icon(CupertinoIcons.add, color: Colors.white),
        label: const Text(
          'New Event',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
      ),
      body: AppScrollPage(
        child: FutureBuilder<String>(
          future: _academyId,
          builder: (context, academy) {
            if (academy.hasError) {
              return const ErrorBanner(
                message: 'Your academy scope could not be loaded.',
              );
            }
            if (!academy.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return StreamBuilder(
              stream: CatalogService.instance.raw('events'),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const ErrorBanner(
                    message: 'Events could not be loaded.',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final events = snapshot.data!.docs
                    .where((doc) => doc.data()['academyId'] == academy.data)
                    .toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PageTopBar(
                      title: 'Events',
                      onBack: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(height: 16),
                    if (events.isEmpty)
                      EmptyState(
                        icon: CupertinoIcons.rosette,
                        title: 'No events yet',
                        message: 'Create an event for your academy.',
                        action: 'Create Event',
                        onTap: _editor,
                      ),
                    for (final event in events)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: CardBox(
                          child: Row(
                            children: [
                              const Icon(
                                CupertinoIcons.rosette,
                                color: AppColors.purple,
                                size: 34,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (event.data()['title'] ?? 'Event')
                                          .toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      (event.data()['date'] ?? 'Date not set')
                                          .toString(),
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Edit event',
                                onPressed: () =>
                                    _editor(id: event.id, data: event.data()),
                                icon: const Icon(CupertinoIcons.pencil),
                              ),
                              IconButton(
                                tooltip: 'Delete event',
                                onPressed: () => _deleteEvent(event.id),
                                icon: const Icon(
                                  CupertinoIcons.trash,
                                  color: AppColors.danger,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _deleteEvent(String id) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialog) => CupertinoAlertDialog(
        title: const Text('Delete this event?'),
        content: const Text('This removes it from the player app.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await CatalogService.instance.delete('events', id);
    }
  }

  void _editor({String? id, Map<String, dynamic>? data}) {
    final title = TextEditingController(text: data?['title']?.toString() ?? '');
    final existingDateText = data?['date']?.toString() ?? '';
    DateTime? selectedDate;
    try {
      selectedDate = DateFormat('MMM d, yyyy').parse(existingDateText);
    } catch (_) {
      selectedDate = null;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                id == null ? 'New Event' : 'Edit Event',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: title,
                label: 'Event title',
                icon: CupertinoIcons.rosette,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate ?? DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (picked != null) {
                    setSheetState(() => selectedDate = picked);
                  }
                },
                icon: const Icon(CupertinoIcons.calendar),
                label: Text(
                  selectedDate != null
                      ? DateFormat('MMM d, yyyy').format(selectedDate!)
                      : (existingDateText.isNotEmpty
                            ? existingDateText
                            : 'Choose event date'),
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Save Event',
                onPressed: () async {
                  if (title.text.trim().isEmpty || selectedDate == null) {
                    return;
                  }
                  final academyId = await _academyId;
                  await CatalogService.instance.upsert('events', id, {
                    'academyId': academyId,
                    'title': title.text.trim(),
                    'date': DateFormat('MMM d, yyyy').format(selectedDate!),
                    'prize': data?['prize']?.toString() ?? '',
                  });
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Academy analytics
// ---------------------------------------------------------------------------

class AcademyAnalyticsScreen extends StatelessWidget {
  const AcademyAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const revenue = [1200.0, 1800.0, 1500.0, 2200.0, 2600.0, 3100.0, 2800.0];
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    const peak = [0.3, 0.5, 0.4, 0.7, 0.9, 1.0, 0.6];
    const hours = ['4p', '5p', '6p', '7p', '8p', '9p', '10p'];

    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Analytics',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.1,
              children: const [
                StatCard(value: 'JOD 15.2k', label: 'Revenue (7d)'),
                StatCard(value: '128', label: 'Total bookings'),
                StatCard(value: '76%', label: 'Occupancy'),
                StatCard(value: '42', label: 'Returning players'),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              'Revenue this week',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            CardBox(
              child: SizedBox(
                height: 170,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _LineChartPainter(revenue),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final d in days)
                            Text(
                              d,
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Peak hours',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            CardBox(
              child: SizedBox(
                height: 150,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < peak.length; i++)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              height: peak[i] * 100,
                              margin: const EdgeInsets.symmetric(horizontal: 5),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [AppColors.purple, Color(0xFF75E0AF)],
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              hours[i],
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Most active sports',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            for (final item in const [
              ('Basketball', 0.9),
              ('Padel', 0.65),
              ('Volleyball', 0.4),
              ('Football', 0.3),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.$1,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          '${(item.$2 * 100).round()}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.purple,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ProgressBar(value: item.$2, dark: false),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter(this.values);
  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.reduce(math.max);
    final minV = values.reduce(math.min);
    final range = (maxV - minV) == 0 ? 1 : (maxV - minV);
    final chartHeight = size.height - 24;

    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = size.width * (i / (values.length - 1));
      final y = chartHeight - ((values[i] - minV) / range) * (chartHeight - 10);
      points.add(Offset(x, y));
    }

    final line = Paint()
      ..color = AppColors.purple
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = ui.Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final midX = (prev.dx + curr.dx) / 2;
      path.cubicTo(midX, prev.dy, midX, curr.dy, curr.dx, curr.dy);
    }

    // Fill under the curve
    final fillPath = ui.Path.from(path)
      ..lineTo(points.last.dx, chartHeight)
      ..lineTo(points.first.dx, chartHeight)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.purple.withValues(alpha: .25),
            AppColors.purple.withValues(alpha: .02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, chartHeight)),
    );

    canvas.drawPath(path, line);

    final dot = Paint()..color = AppColors.purple;
    final dotRing = Paint()..color = Colors.white;
    for (final p in points) {
      canvas.drawCircle(p, 5, dotRing);
      canvas.drawCircle(p, 3.5, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) => false;
}
