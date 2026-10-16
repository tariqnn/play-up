import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AppLocation {
  const AppLocation({
    required this.latitude,
    required this.longitude,
    required this.label,
    this.fromDevice = false,
  });
  final double latitude;
  final double longitude;
  final String label;
  final bool fromDevice;
}

class LocationService {
  LocationService._();
  static final instance = LocationService._();
  final current = ValueNotifier<AppLocation?>(null);
  final loading = ValueNotifier<bool>(false);

  Future<AppLocation?> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final lat = prefs.getDouble('location_latitude');
    final lng = prefs.getDouble('location_longitude');
    final label = prefs.getString('location_label');
    if (lat != null && lng != null && label != null) {
      current.value = AppLocation(latitude: lat, longitude: lng, label: label);
    }
    try {
      return await useCurrentLocation(silent: true);
    } catch (error) {
      debugPrint('Location initialization skipped: $error');
      return current.value;
    }
  }

  Future<AppLocation?> useCurrentLocation({bool silent = false}) async {
    loading.value = true;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (silent) return current.value;
        throw StateError('Turn on location services to show nearby courts.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (silent) return current.value;
        throw StateError(
          'Location permission is required. You can also choose a location manually.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final label = await _reverseGeocode(
        position.latitude,
        position.longitude,
      );
      final value = AppLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        label: label,
        fromDevice: true,
      );
      await setManual(value);
      return value;
    } catch (error) {
      if (silent) {
        debugPrint('Current location unavailable: $error');
        return current.value;
      }
      throw StateError(
        'Your current location could not be read. Choose a location manually.',
      );
    } finally {
      loading.value = false;
    }
  }

  Future<void> setManual(AppLocation value) async {
    current.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('location_latitude', value.latitude);
    await prefs.setDouble('location_longitude', value.longitude);
    await prefs.setString('location_label', value.label);
  }

  Future<List<AppLocation>> search(String query) async {
    if (query.trim().length < 3) return const [];
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'format': 'jsonv2',
      'q': query.trim(),
      'limit': '6',
      'addressdetails': '1',
    });
    final response = await http
        .get(
          uri,
          headers: const {
            'User-Agent': 'PlayUp/1.0 (+https://play-up.fit/contact)',
          },
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw StateError('Location search is temporarily unavailable.');
    }
    final rows = jsonDecode(response.body) as List<dynamic>;
    return rows.map((raw) {
      final row = raw as Map<String, dynamic>;
      return AppLocation(
        latitude: double.parse(row['lat'].toString()),
        longitude: double.parse(row['lon'].toString()),
        label: row['display_name']?.toString() ?? query.trim(),
      );
    }).toList();
  }

  Future<String> _reverseGeocode(double latitude, double longitude) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': '$latitude',
        'lon': '$longitude',
        'zoom': '12',
      });
      final response = await http
          .get(
            uri,
            headers: const {
              'User-Agent': 'PlayUp/1.0 (+https://play-up.fit/contact)',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>? ?? const {};
        final city =
            address['city'] ??
            address['town'] ??
            address['village'] ??
            address['county'];
        final country = address['country'];
        if (city != null && country != null) return '$city, $country';
        if (country != null) return country.toString();
      }
    } catch (_) {}
    return '${latitude.toStringAsFixed(3)}, ${longitude.toStringAsFixed(3)}';
  }
}
