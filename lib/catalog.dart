import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';

import 'main.dart';
import 'more_screens.dart';

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
  });

  final String id;
  final String title;
  final String partner;
  final String points;
  final String gradientKey;

  List<Color> get colors => gradientFor(gradientKey);
}

class EventItem {
  const EventItem({
    required this.title,
    required this.date,
    required this.prize,
  });

  final String title;
  final String date;
  final String prize;
}

// ---------------------------------------------------------------------------
// Seed data (source of truth for the "Seed sample data" action and the
// offline/empty fallback so screens are never blank).
// ---------------------------------------------------------------------------

const _courtSeed = <Map<String, dynamic>>[
  {
    'name': 'Infinity Sports Center',
    'subtitle': 'Indoor Basketball',
    'rating': '4.8 (128)',
    'distance': '1.2 km',
    'price': 'AED 210 / hr',
    'gradient': 'teal',
    'icon': 'court',
    'image':
        'https://images.unsplash.com/photo-1608245449230-4ac19066d2d0?w=800&q=70',
    'sort': 1,
  },
  {
    'name': 'Dubai Sports World',
    'subtitle': 'Indoor Basketball',
    'rating': '4.7 (96)',
    'distance': '2.1 km',
    'price': 'AED 180 / hr',
    'gradient': 'purple',
    'icon': 'hex',
    'image':
        'https://images.unsplash.com/photo-1544919982-b61976f0ba43?w=800&q=70',
    'sort': 2,
  },
  {
    'name': 'Hoops Basketball Academy',
    'subtitle': 'Indoor Academy',
    'rating': '4.6 (74)',
    'distance': '2.8 km',
    'price': 'AED 200 / hr',
    'gradient': 'green',
    'icon': 'players',
    'image':
        'https://images.unsplash.com/photo-1519861531473-9200262188bf?w=800&q=70',
    'sort': 3,
  },
];

const _academySeed = <Map<String, dynamic>>[
  {
    'name': 'Infinity Sports Center',
    'sports': 'Basketball • Padel • Volleyball',
    'rating': '4.8 (128)',
    'distance': '1.2 km',
    'featured': true,
    'gradient': 'teal',
    'icon': 'court',
    'image':
        'https://images.unsplash.com/photo-1608245449230-4ac19066d2d0?w=800&q=70',
    'sort': 1,
  },
  {
    'name': 'Dubai Sports World',
    'sports': 'Basketball • Football',
    'rating': '4.7 (96)',
    'distance': '2.1 km',
    'featured': false,
    'gradient': 'purple',
    'icon': 'hex',
    'image':
        'https://images.unsplash.com/photo-1546519638-68e109498ffc?w=800&q=70',
    'sort': 2,
  },
  {
    'name': 'Hoops Basketball Academy',
    'sports': 'Basketball • 3x3',
    'rating': '4.6 (74)',
    'distance': '2.8 km',
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
    'sort': 1,
  },
  {
    'title': 'Free Padel Racket Rental',
    'partner': 'Padel Pro',
    'points': '700',
    'gradient': 'green',
    'sort': 2,
  },
  {
    'title': '1 Free Hour (Weekdays)',
    'partner': 'Skyline Sports',
    'points': '1,200',
    'gradient': 'purple',
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
    'pricePerPlayer': 'AED 52.5',
    'ranked': true,
  },
  {
    'title': 'Padel Night Doubles',
    'sport': 'Padel',
    'courtName': 'Padel Pro Club',
    'time': 'Today, 9:30 PM',
    'skillRange': 'Casual',
    'neededPlayers': 2,
    'pricePerPlayer': 'AED 60',
    'ranked': false,
  },
  {
    'title': 'Volleyball Open Court',
    'sport': 'Volleyball',
    'courtName': 'Dubai Sports World',
    'time': 'Tomorrow, 6:00 PM',
    'skillRange': 'Advanced',
    'neededPlayers': 4,
    'pricePerPlayer': 'AED 40',
    'ranked': true,
  },
];

const _eventSeed = <Map<String, dynamic>>[
  {
    'title': '3x3 Eid Tournament',
    'date': '28-30 May • Entry AED 50',
    'prize': 'Prize pool AED 5,000',
    'sort': 1,
  },
  {
    'title': 'Padel Night Open',
    'date': 'Every Friday • Entry AED 30',
    'prize': 'Casual doubles',
    'sort': 2,
  },
];

Court _courtFrom(Map<String, dynamic> d, {String id = ''}) => Court(
  id: id.isEmpty ? (d['id'] ?? '').toString() : id,
  name: (d['name'] ?? 'Court').toString(),
  subtitle: (d['subtitle'] ?? 'Sports court').toString(),
  rating: (d['rating'] ?? '4.5').toString(),
  distance: (d['distance'] ?? '1 km').toString(),
  price: (d['price'] ?? 'AED 150 / hr').toString(),
  gradient: gradientFor(d['gradient'] as String?),
  icon: iconFor(d['icon'] as String?),
  imageUrl: (d['image'] ?? '').toString(),
);

Academy _academyFrom(Map<String, dynamic> d) => Academy(
  name: (d['name'] ?? 'Academy').toString(),
  sports: (d['sports'] ?? 'Multi-sport').toString(),
  rating: (d['rating'] ?? '4.5').toString(),
  distance: (d['distance'] ?? '1 km').toString(),
  featured: d['featured'] == true,
  gradient: gradientFor(d['gradient'] as String?),
  icon: iconFor(d['icon'] as String?),
  imageUrl: (d['image'] ?? '').toString(),
);

Offer _offerFrom(String id, Map<String, dynamic> d) => Offer(
  id: id,
  title: (d['title'] ?? 'Offer').toString(),
  partner: (d['partner'] ?? 'PlayUp').toString(),
  points: (d['points'] ?? '500').toString(),
  gradientKey: (d['gradient'] ?? 'teal').toString(),
);

EventItem _eventFrom(Map<String, dynamic> d) => EventItem(
  title: (d['title'] ?? 'Event').toString(),
  date: (d['date'] ?? '').toString(),
  prize: (d['prize'] ?? '').toString(),
);

/// Fallback lists (used when Firestore is empty, offline, or unreadable).
final List<Court> kFallbackCourts = _courtSeed.map(_courtFrom).toList();
final List<Academy> kFallbackAcademies = _academySeed
    .map(_academyFrom)
    .toList();
final List<Offer> kFallbackOffers = [
  for (var i = 0; i < _offerSeed.length; i++)
    _offerFrom('seed$i', _offerSeed[i]),
];
final List<EventItem> kFallbackEvents = _eventSeed.map(_eventFrom).toList();

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
  Stream<List<Court>> courts() => col('courts').snapshots().map(
    (s) => s.docs.map((d) => _courtFrom(d.data(), id: d.id)).toList(),
  );

  Stream<List<Academy>> academies() => col(
    'academies',
  ).snapshots().map((s) => s.docs.map((d) => _academyFrom(d.data())).toList());

  Stream<List<Offer>> offers() => col('offers').snapshots().map(
    (s) => s.docs.map((d) => _offerFrom(d.id, d.data())).toList(),
  );

  Stream<List<EventItem>> events() => col(
    'events',
  ).snapshots().map((s) => s.docs.map((d) => _eventFrom(d.data())).toList());

  // --- Admin raw streams ---
  Stream<QuerySnapshot<Map<String, dynamic>>> raw(String collection) =>
      col(collection).snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> topPlayers() =>
      col('users').orderBy('xp', descending: true).limit(50).snapshots();

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
    final batch = _db.batch();
    void seed(String collection, List<Map<String, dynamic>> rows) {
      for (final row in rows) {
        batch.set(col(collection).doc(), {
          ...row,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }

    seed('courts', _courtSeed);
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

  /// Seeds only if the courts collection is currently empty.
  Future<void> seedIfEmpty() async {
    try {
      final snap = await col('courts').limit(1).get();
      if (snap.docs.isEmpty) await seedAll();
    } catch (_) {
      // Ignore: rules/offline. Fallback lists keep the UI populated.
    }
  }
}
