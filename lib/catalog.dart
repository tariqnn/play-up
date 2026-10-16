import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';

import 'main.dart';
import 'location_service.dart';
import 'more_screens.dart';
import 'test_data_seed.dart';

// ---------------------------------------------------------------------------
// Shared visual presets (kept as const so icon tree-shaking still works).
// Firestore stores the *key*; the app resolves it to real colors/icons.
// ---------------------------------------------------------------------------

const kGradientPresets = <String, List<Color>>{
  'teal': [Color(0xFF102A43), Color(0xFF1F7A8C)],
  'purple': [Color(0xFF281B44), Color(0xFF7B3FF2)],
  'green': [Color(0xFF18230F), Color(0xFF62D84E)],
  'navy': [Color(0xFF0B1628), Color(0xFF334155)],
  'sunset': [Color(0xFF3B1D2B), Color(0xFFB5477A)],
};

const kIconPresets = <String, IconData>{
  'court': CupertinoIcons.sportscourt,
  'hex': CupertinoIcons.circle_grid_hex,
  'players': CupertinoIcons.person_3_fill,
  'ball': CupertinoIcons.circle_fill,
  'gift': CupertinoIcons.gift_fill,
  'rosette': CupertinoIcons.rosette,
};

List<Color> gradientFor(String? key) =>
    kGradientPresets[key] ?? kGradientPresets['teal']!;

IconData iconFor(String? key) =>
    kIconPresets[key] ?? CupertinoIcons.sportscourt;

// ---------------------------------------------------------------------------
// Offer model (courts + academies reuse the existing Court / Academy classes)
// ---------------------------------------------------------------------------

class Offer {
  const Offer({
    required this.id,
    required this.title,
    required this.partner,
    required this.points,
    required this.gradientKey,
    required this.category,
    required this.active,
  });

  final String id;
  final String title;
  final String partner;
  final String points;
  final String gradientKey;
  final String category;
  final bool active;

  List<Color> get colors => gradientFor(gradientKey);
}

class EventItem {
  const EventItem({
    this.id = '',
    this.academyId = '',
    required this.title,
    required this.date,
    required this.prize,
  });

  final String id;
  final String academyId;
  final String title;
  final String date;
  final String prize;
}

// ---------------------------------------------------------------------------
// Optional demo data for non-bookable catalog areas. Courts are deliberately
// excluded: every court shown to a player must be a real Firestore document
// created by a platform or academy owner.
// ---------------------------------------------------------------------------

const _academySeed = <Map<String, dynamic>>[
  {
    'name': 'Amman Sports Academy',
    'sports': 'Basketball • Padel • Volleyball',
    'rating': '4.8 (128)',
    'address': 'Sports City, Amman',
    'latitude': 31.9862,
    'longitude': 35.9024,
    'phone': '+962 6 000 0000',
    'email': 'hello@ammansports.example',
    'description': 'Community courts, coaching, and weekly social matches.',
    'trainingPackages': ['Junior basketball', 'Adult padel', 'Team training'],
    'featured': true,
    'gradient': 'teal',
    'icon': 'court',
    'image':
        'https://images.unsplash.com/photo-1608245449230-4ac19066d2d0?w=800&q=70',
    'sort': 1,
  },
  {
    'name': 'Abdoun Padel Academy',
    'sports': 'Basketball • Football',
    'rating': '4.7 (96)',
    'address': 'Abdoun, Amman',
    'latitude': 31.9418,
    'longitude': 35.9296,
    'phone': '+962 6 000 0001',
    'description': 'Padel coaching and open-play packages for every level.',
    'trainingPackages': ['Beginner padel', 'Private coaching'],
    'featured': false,
    'gradient': 'purple',
    'icon': 'hex',
    'image':
        'https://images.unsplash.com/photo-1546519638-68e109498ffc?w=800&q=70',
    'sort': 2,
  },
  {
    'name': 'Jordan Hoops Academy',
    'sports': 'Basketball • 3x3',
    'rating': '4.6 (74)',
    'address': 'Khalda, Amman',
    'latitude': 31.9994,
    'longitude': 35.8434,
    'phone': '+962 6 000 0002',
    'description': 'Skill development, youth programs, and competitive teams.',
    'trainingPackages': ['Youth fundamentals', '3x3 development'],
    'featured': false,
    'gradient': 'green',
    'icon': 'players',
    'image':
        'https://images.unsplash.com/photo-1519861531473-9200262188bf?w=800&q=70',
    'sort': 3,
  },
];

const _offerSeed = <Map<String, dynamic>>[
  {
    'title': '20% OFF Court Booking',
    'partner': 'Infinity Sports',
    'points': '500',
    'gradient': 'teal',
    'category': 'Academy',
    'active': true,
    'sort': 1,
  },
  {
    'title': 'Free Padel Racket Rental',
    'partner': 'Padel Pro',
    'points': '700',
    'gradient': 'green',
    'category': 'Academy',
    'active': true,
    'sort': 2,
  },
  {
    'title': '1 Free Hour (Weekdays)',
    'partner': 'Skyline Sports',
    'points': '1,200',
    'gradient': 'purple',
    'category': 'Sponsors',
    'active': true,
    'sort': 3,
  },
];

const _matchSeed = <Map<String, dynamic>>[
  {
    'title': 'Court Commanders 5v5',
    'sport': 'Basketball',
    'courtName': 'Infinity Sports Center',
    'time': 'Today, 8:00 PM',
    'skillRange': 'Intermediate',
    'neededPlayers': 3,
    'pricePerPlayer': 'JOD 5.25',
    'ranked': true,
  },
  {
    'title': 'Padel Night Doubles',
    'sport': 'Padel',
    'courtName': 'Padel Pro Club',
    'time': 'Today, 9:30 PM',
    'skillRange': 'Casual',
    'neededPlayers': 2,
    'pricePerPlayer': 'JOD 6.00',
    'ranked': false,
  },
  {
    'title': 'Volleyball Open Court',
    'sport': 'Volleyball',
    'courtName': 'Amman Sports City',
    'time': 'Tomorrow, 6:00 PM',
    'skillRange': 'Advanced',
    'neededPlayers': 4,
    'pricePerPlayer': 'JOD 4.00',
    'ranked': true,
  },
];

const _eventSeed = <Map<String, dynamic>>[
  {
    'title': '3x3 Eid Tournament',
    'date': '28-30 May • Entry JOD 5',
    'prize': 'Prize pool JOD 500',
    'sort': 1,
  },
  {
    'title': 'Padel Night Open',
    'date': 'Every Friday • Entry JOD 3',
    'prize': 'Casual doubles',
    'sort': 2,
  },
];

Court _courtFrom(Map<String, dynamic> d, {String id = ''}) => Court(
  id: id.isEmpty ? (d['id'] ?? '').toString() : id,
  name: (d['name'] ?? 'Court').toString(),
  subtitle: (d['subtitle'] ?? d['address'] ?? d['sport'] ?? 'Sports court')
      .toString(),
  rating: (d['rating'] ?? '4.5').toString(),
  distance: (d['distance'] ?? '1 km').toString(),
  price: _courtPrice(d),
  gradient: gradientFor(d['gradient'] as String?),
  icon: iconFor(d['icon'] as String?),
  imageUrl: (d['imageUrl'] ?? d['image'] ?? '').toString(),
  imageUrls: (d['imageUrls'] as List? ?? const [])
      .map((value) => value.toString())
      .where((value) => value.trim().isNotEmpty)
      .toList(),
  latitude: (d['latitude'] as num?)?.toDouble(),
  longitude: (d['longitude'] as num?)?.toDouble(),
  academyId: (d['academyId'] ?? '').toString(),
  sport: (d['sport'] ?? 'Sport').toString(),
  currency: (d['currency'] ?? 'JOD').toString(),
  basePriceMinor: (d['basePriceMinor'] as num?)?.toInt() ?? 0,
  address: (d['address'] ?? '').toString(),
  active: d['active'] != false,
  openingHour: (d['openingHour'] as num?)?.toInt() ?? 6,
  closingHour: (d['closingHour'] as num?)?.toInt() ?? 23,
  peakPriceMinor: (d['peakPriceMinor'] as num?)?.toInt(),
  peakHourStart: (d['peakHourStart'] as num?)?.toInt(),
  peakHourEnd: (d['peakHourEnd'] as num?)?.toInt(),
);

String _courtPrice(Map<String, dynamic> d) {
  final explicit = d['price']?.toString().trim() ?? '';
  if (explicit.isNotEmpty) return explicit;
  final currency = (d['currency'] ?? 'JOD').toString();
  final minor = (d['basePriceMinor'] as num?)?.toInt() ?? 0;
  return '$currency ${(minor / 100).toStringAsFixed(2)} / hr';
}

Academy _academyFrom(String id, Map<String, dynamic> d) => Academy(
  id: id,
  name: (d['name'] ?? 'Academy').toString(),
  sports: (d['sports'] ?? 'Multi-sport').toString(),
  rating: (d['rating'] ?? '4.5').toString(),
  distance: (d['distance'] ?? '1 km').toString(),
  featured: d['featured'] == true,
  gradient: gradientFor(d['gradient'] as String?),
  icon: iconFor(d['icon'] as String?),
  imageUrl: (d['imageUrl'] ?? d['image'] ?? '').toString(),
  latitude: (d['latitude'] as num?)?.toDouble(),
  longitude: (d['longitude'] as num?)?.toDouble(),
  address: (d['address'] ?? '').toString(),
  phone: (d['phone'] ?? '').toString(),
  email: (d['email'] ?? '').toString(),
  description: (d['description'] ?? '').toString(),
  trainingPackages: List<String>.from(
    d['trainingPackages'] as List? ?? const [],
  ),
);

Offer _offerFrom(String id, Map<String, dynamic> d) => Offer(
  id: id,
  title: (d['title'] ?? 'Offer').toString(),
  partner: (d['partner'] ?? 'PlayUp').toString(),
  points: (d['points'] ?? '500').toString(),
  gradientKey: (d['gradient'] ?? 'teal').toString(),
  category: (d['category'] ?? 'Academy').toString(),
  active: d['active'] != false,
);

EventItem _eventFrom(Map<String, dynamic> d, {String id = ''}) => EventItem(
  id: id,
  academyId: (d['academyId'] ?? '').toString(),
  title: (d['title'] ?? 'Event').toString(),
  date: (d['date'] ?? '').toString(),
  prize: (d['prize'] ?? '').toString(),
);

// ---------------------------------------------------------------------------
// Catalog service: live Firestore streams + admin CRUD + seeding.
// ---------------------------------------------------------------------------

class CatalogService {
  CatalogService._();
  static final instance = CatalogService._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> col(String name) =>
      _db.collection(name);

  // --- UI streams (mapped to view models) ---
  Stream<List<Court>> courts() async* {
    // Sample records belong to isolated emulator sessions only. Never mix
    // fictional inventory into a signed production build or its cached data.
    if (useFirebaseEmulators) yield kTestCourts;
    yield* col('courts')
        .snapshots()
        .map((s) {
          final result = s.docs
              .map((d) => _courtFrom(d.data(), id: d.id))
              .where((court) => court.active)
              .toList();
          result.sort((a, b) => a.name.compareTo(b.name));
          return result;
        })
        .handleError((e) {
          debugPrint('Firestore courts stream error: $e');
          return useFirebaseEmulators ? kTestCourts : <Court>[];
        });
  }

  Stream<List<Academy>> academies() async* {
    if (useFirebaseEmulators) yield kTestAcademies;
    yield* col('academies')
        .snapshots()
        .map((s) {
          final result = s.docs
              .where((d) => (d.data()['status'] ?? 'active') == 'active')
              .map((d) => _academyFrom(d.id, d.data()))
              .toList();
          result.sort((a, b) => a.name.compareTo(b.name));
          return result;
        })
        .handleError((e) {
          debugPrint('Firestore academies stream error: $e');
          return useFirebaseEmulators ? kTestAcademies : <Academy>[];
        });
  }

  Stream<List<Offer>> offers() => col('offers').snapshots().map(
    (s) => s.docs
        .map((d) => _offerFrom(d.id, d.data()))
        .where((offer) => offer.active)
        .toList(),
  );

  List<Court> nearbyCourts(
    Iterable<Court> source,
    AppLocation? location, {
    String sport = 'All',
    String query = '',
    double radiusKm = 100,
  }) {
    final needle = query.trim().toLowerCase();
    final result = source.where((court) {
      final sportMatches =
          sport == 'All' ||
          court.sport.toLowerCase() == sport.toLowerCase() ||
          court.subtitle.toLowerCase().contains(sport.toLowerCase());
      final queryMatches =
          needle.isEmpty ||
          court.name.toLowerCase().contains(needle) ||
          court.address.toLowerCase().contains(needle) ||
          court.sport.toLowerCase().contains(needle);
      final distance = court.distanceKmFrom(location);
      return sportMatches &&
          queryMatches &&
          (distance == null || distance <= radiusKm);
    }).toList();
    result.sort((a, b) {
      final aDistance = a.distanceKmFrom(location);
      final bDistance = b.distanceKmFrom(location);
      if (aDistance == null && bDistance == null) {
        return a.name.compareTo(b.name);
      }
      if (aDistance == null) return 1;
      if (bDistance == null) return -1;
      return aDistance.compareTo(bDistance);
    });
    return result;
  }

  List<Academy> nearbyAcademies(
    Iterable<Academy> source,
    AppLocation? location, {
    double radiusKm = 100,
  }) {
    final result = source.where((academy) {
      final distance = academy.distanceKmFrom(location);
      return distance == null || distance <= radiusKm;
    }).toList();
    result.sort((a, b) {
      final aDistance = a.distanceKmFrom(location);
      final bDistance = b.distanceKmFrom(location);
      if (aDistance == null && bDistance == null) {
        return a.name.compareTo(b.name);
      }
      if (aDistance == null) return 1;
      if (bDistance == null) return -1;
      return aDistance.compareTo(bDistance);
    });
    return result;
  }

  Stream<List<EventItem>> events() => col('events').snapshots().map(
    (s) => s.docs.map((d) => _eventFrom(d.data(), id: d.id)).toList(),
  );

  // --- Admin raw streams ---
  Stream<QuerySnapshot<Map<String, dynamic>>> raw(String collection) =>
      col(collection).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> topPlayers() => col(
    'publicProfiles',
  ).orderBy('xp', descending: true).limit(50).snapshots();

  Future<void> upsert(
    String collection,
    String? id,
    Map<String, dynamic> data,
  ) async {
    final payload = {...data, 'updatedAt': FieldValue.serverTimestamp()};
    if (id == null) {
      await col(
        collection,
      ).add({...payload, 'createdAt': FieldValue.serverTimestamp()});
    } else {
      await col(collection).doc(id).set(payload, SetOptions(merge: true));
    }
  }

  Future<void> delete(String collection, String id) =>
      col(collection).doc(id).delete();

  /// Writes all seed data. Used by the admin "Seed sample data" action.
  Future<void> seedAll() async {
    if (!useFirebaseEmulators) {
      throw StateError(
        'Sample data can only be written to Firebase emulators.',
      );
    }
    final batch = _db.batch();
    void seed(String collection, List<Map<String, dynamic>> rows) {
      for (final row in rows) {
        batch.set(col(collection).doc(), {
          ...row,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }

    seed('academies', _academySeed);
    seed('offers', _offerSeed);
    seed('events', _eventSeed);

    // Open matches must be hosted by the signed-in user to satisfy security
    // rules. Seed a few so the Play tab shows live data immediately.
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      for (final row in _matchSeed) {
        batch.set(col('matches').doc(), {
          ...row,
          'hostId': user.uid,
          'hostName': user.displayName ?? 'Player',
          'players': [user.uid],
          'status': 'open',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
  }
}
