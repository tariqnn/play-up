import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';

import 'catalog.dart';
import 'main.dart';
import 'more_screens.dart';
import 'more_screens2.dart';

// ---------------------------------------------------------------------------
// 1. Curated test courts with peak pricing & realistic Amman venues
// ---------------------------------------------------------------------------

final kTestCourts = <Court>[
  Court(
    id: 'test-court-padel-1',
    academyId: 'uat-academy-a',
    name: 'North Padel Club - Court 1 (Indoor Panoramic)',
    subtitle: 'Panoramic glass • WPT turf • Climate controlled',
    sport: 'Padel',
    rating: '4.9 (142)',
    distance: '1.2 km',
    price: 'JOD 18.00 / hr',
    basePriceMinor: 1800,
    peakPriceMinor: 2800,
    peakHourStart: 18,
    peakHourEnd: 23,
    currency: 'JOD',
    address: 'Sports City, Amman',
    latitude: 31.9862,
    longitude: 35.9024,
    openingHour: 6,
    closingHour: 24,
    imageUrl:
        'https://images.unsplash.com/photo-1626224583764-f87db24ac4ea?w=1200&q=80',
    imageUrls: const [
      'https://images.unsplash.com/photo-1554068865-24cecd4e34b8?w=1200&q=80',
      'https://images.unsplash.com/photo-1599474924187-334a4ae5bd3c?w=1200&q=80',
    ],
    gradient: gradientFor('teal'),
    icon: iconFor('court'),
  ),
  Court(
    id: 'test-court-padel-2',
    academyId: 'uat-academy-a',
    name: 'North Padel Club - Court 2 (Outdoor Pro)',
    subtitle: 'Outdoor doubles • Anti-glare LED spotlights',
    sport: 'Padel',
    rating: '4.8 (89)',
    distance: '1.2 km',
    price: 'JOD 16.00 / hr',
    basePriceMinor: 1600,
    peakPriceMinor: 2400,
    peakHourStart: 18,
    peakHourEnd: 23,
    currency: 'JOD',
    address: 'Sports City, Amman',
    latitude: 31.9862,
    longitude: 35.9024,
    openingHour: 6,
    closingHour: 24,
    imageUrl:
        'https://images.unsplash.com/photo-1554068865-24cecd4e34b8?w=1200&q=80',
    imageUrls: const [
      'https://images.unsplash.com/photo-1626224583764-f87db24ac4ea?w=1200&q=80',
      'https://images.unsplash.com/photo-1599474924187-334a4ae5bd3c?w=1200&q=80',
    ],
    gradient: gradientFor('teal'),
    icon: iconFor('court'),
  ),
  Court(
    id: 'test-court-football-1',
    academyId: 'uat-academy-a',
    name: 'Khalda Football Arena (Pitch A - 7v7 Turf)',
    subtitle: 'FIFA-standard artificial turf • Showers & Lockers',
    sport: 'Football',
    rating: '4.9 (210)',
    distance: '3.5 km',
    price: 'JOD 35.00 / hr',
    basePriceMinor: 3500,
    peakPriceMinor: 5000,
    peakHourStart: 19,
    peakHourEnd: 23,
    currency: 'JOD',
    address: 'Khalda, Amman',
    latitude: 31.9994,
    longitude: 35.8434,
    openingHour: 8,
    closingHour: 24,
    imageUrl:
        'https://images.unsplash.com/photo-1529900748604-07564a03e7a6?w=1200&q=80',
    imageUrls: const [
      'https://images.unsplash.com/photo-1574629810360-7efbbe195018?w=1200&q=80',
      'https://images.unsplash.com/photo-1553778263-73a83bab9b0c?w=1200&q=80',
    ],
    gradient: gradientFor('green'),
    icon: iconFor('court'),
  ),
  Court(
    id: 'test-court-tennis-1',
    academyId: 'uat-academy-b',
    name: 'Abdoun Tennis Academy (Center Court)',
    subtitle: 'Plexicushion hard court • Ball machine available',
    sport: 'Tennis',
    rating: '4.7 (76)',
    distance: '4.1 km',
    price: 'JOD 20.00 / hr',
    basePriceMinor: 2000,
    peakPriceMinor: 3000,
    peakHourStart: 17,
    peakHourEnd: 22,
    currency: 'JOD',
    address: 'Abdoun, Amman',
    latitude: 31.9418,
    longitude: 35.9296,
    openingHour: 7,
    closingHour: 23,
    imageUrl:
        'https://images.unsplash.com/photo-1595435934249-5df7ed86e1c0?w=1200&q=80',
    imageUrls: const [
      'asset:assets/images/tennis_federer.png',
      'https://images.unsplash.com/photo-1554068865-24cecd4e34b8?w=1200&q=80',
    ],
    gradient: gradientFor('purple'),
    icon: iconFor('court'),
  ),
  Court(
    id: 'test-court-basketball-1',
    academyId: 'uat-academy-b',
    name: 'Jordan Hoops Arena (Indoor Court 1)',
    subtitle: 'Maple hardwood • Regulation glass backboards',
    sport: 'Basketball',
    rating: '4.8 (115)',
    distance: '2.8 km',
    price: 'JOD 22.00 / hr',
    basePriceMinor: 2200,
    peakPriceMinor: 3200,
    peakHourStart: 18,
    peakHourEnd: 22,
    currency: 'JOD',
    address: 'Sports City, Amman',
    latitude: 31.9862,
    longitude: 35.9024,
    openingHour: 6,
    closingHour: 23,
    imageUrl:
        'https://images.unsplash.com/photo-1504450758481-7338eba7524a?w=1200&q=80',
    imageUrls: const [
      'https://images.unsplash.com/photo-1546519638-68e109498ffc?w=1200&q=80',
      'https://images.unsplash.com/photo-1519861531473-9200262188bf?w=1200&q=80',
    ],
    gradient: gradientFor('sunset'),
    icon: iconFor('players'),
  ),
  Court(
    id: 'test-court-volleyball-1',
    academyId: 'uat-academy-a',
    name: 'Amman Sports City Volleyball Hub',
    subtitle: 'Olympic sprung floor • Official antennas & referee stand',
    sport: 'Volleyball',
    rating: '4.6 (54)',
    distance: '1.5 km',
    price: 'JOD 14.00 / hr',
    basePriceMinor: 1400,
    currency: 'JOD',
    address: 'Sports City, Amman',
    latitude: 31.9862,
    longitude: 35.9024,
    openingHour: 8,
    closingHour: 22,
    imageUrl:
        'https://images.unsplash.com/photo-1612872087720-bb876e2e67d1?w=1200&q=80',
    imageUrls: const [
      'https://images.unsplash.com/photo-1592656094267-764a45160876?w=1200&q=80',
      'https://images.unsplash.com/photo-1553005746-9245ba190489?w=1200&q=80',
    ],
    gradient: gradientFor('navy'),
    icon: iconFor('court'),
  ),
  Court(
    id: 'test-venue-dodgeball-1',
    academyId: 'uat-academy-a',
    name: 'PlayUp Dodgeball Arena',
    subtitle:
        'Competition court • Foam & cloth ball sessions • Referee included',
    sport: 'Dodgeball',
    rating: '4.7 (38)',
    distance: '2.3 km',
    price: 'JOD 12.00 / hr',
    basePriceMinor: 1200,
    peakPriceMinor: 1800,
    peakHourStart: 18,
    peakHourEnd: 22,
    currency: 'JOD',
    address: 'Al Hussein Youth City, Amman',
    latitude: 31.9868,
    longitude: 35.9061,
    openingHour: 9,
    closingHour: 23,
    imageUrl:
        'https://images.unsplash.com/photo-1593786930094-d5c8164ac771?w=1200&q=80',
    imageUrls: const [
      'https://images.unsplash.com/photo-1518604666860-9ed391f76460?w=1200&q=80',
      'https://images.unsplash.com/photo-1579952363873-27f3bade9f55?w=1200&q=80',
    ],
    gradient: gradientFor('sunset'),
    icon: iconFor('players'),
  ),
  Court(
    id: 'test-experience-sea-sports-1',
    academyId: 'uat-adventure-aqaba',
    name: 'Aqaba Sea Sports Center',
    subtitle: 'Parasailing • Scuba diving • Certified marine crew',
    sport: 'Sea Sports',
    rating: '4.9 (186)',
    distance: 'Aqaba',
    price: 'JOD 45.00 / session',
    basePriceMinor: 4500,
    currency: 'JOD',
    address: 'South Beach, Aqaba',
    latitude: 29.4325,
    longitude: 34.9749,
    openingHour: 7,
    closingHour: 19,
    imageUrl:
        'https://images.unsplash.com/photo-1632904074880-b77f02b6d01e?w=1200&q=80',
    imageUrls: const [
      'https://images.unsplash.com/photo-1583212292454-1fe6229603b7?w=1200&q=80',
      'https://images.unsplash.com/photo-1544551763-77ef2d0cfc6c?w=1200&q=80',
    ],
    gradient: gradientFor('teal'),
    icon: iconFor('players'),
  ),
  Court(
    id: 'test-experience-kayaking-1',
    academyId: 'uat-adventure-aqaba',
    name: 'Aqaba Sunrise Kayak Club',
    subtitle: 'Single & tandem kayaks • Guide • Safety equipment included',
    sport: 'Kayaking',
    rating: '4.8 (92)',
    distance: 'Aqaba',
    price: 'JOD 18.00 / session',
    basePriceMinor: 1800,
    currency: 'JOD',
    address: 'Ayla Marina, Aqaba',
    latitude: 29.5469,
    longitude: 34.9975,
    openingHour: 6,
    closingHour: 19,
    imageUrl:
        'https://images.unsplash.com/photo-1480480565647-1c4385c7c0bf?w=1200&q=80',
    imageUrls: const [
      'https://images.unsplash.com/photo-1544551763-8dd44758c2dd?w=1200&q=80',
      'https://images.unsplash.com/photo-1526481280695-3c687fd643ed?w=1200&q=80',
    ],
    gradient: gradientFor('teal'),
    icon: iconFor('players'),
  ),
  Court(
    id: 'test-experience-hiking-1',
    academyId: 'uat-adventure-jordan',
    name: 'Wadi Mujib Guided Trails',
    subtitle: 'Licensed guide • Trail briefing • Small-group departures',
    sport: 'Hiking',
    rating: '4.9 (247)',
    distance: 'Dead Sea',
    price: 'JOD 28.00 / trip',
    basePriceMinor: 2800,
    currency: 'JOD',
    address: 'Mujib Biosphere Reserve, Jordan',
    latitude: 31.4667,
    longitude: 35.5733,
    openingHour: 7,
    closingHour: 18,
    imageUrl:
        'https://images.unsplash.com/photo-1551632811-561732d1e306?w=1200&q=80',
    imageUrls: const [
      'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=1200&q=80',
      'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=1200&q=80',
    ],
    gradient: gradientFor('green'),
    icon: iconFor('players'),
  ),
  Court(
    id: 'test-experience-climbing-1',
    academyId: 'uat-adventure-jordan',
    name: 'Wadi Rum Climbing Base',
    subtitle:
        'Beginner & advanced routes • Equipment • Certified climbing guide',
    sport: 'Climbing',
    rating: '4.8 (73)',
    distance: 'Wadi Rum',
    price: 'JOD 55.00 / session',
    basePriceMinor: 5500,
    currency: 'JOD',
    address: 'Wadi Rum Village, Jordan',
    latitude: 29.5764,
    longitude: 35.4197,
    openingHour: 6,
    closingHour: 18,
    imageUrl:
        'https://images.unsplash.com/photo-1522163182402-834f871fd851?w=1200&q=80',
    imageUrls: const [
      'https://images.unsplash.com/photo-1522362484457-d7f559aafa1e?w=1200&q=80',
      'https://images.unsplash.com/photo-1564769662533-4f00a87b4056?w=1200&q=80',
    ],
    gradient: gradientFor('sunset'),
    icon: iconFor('players'),
  ),
  Court(
    id: 'test-court-badminton-1',
    academyId: 'uat-academy-b',
    name: 'Sweifieh Badminton Club',
    subtitle: 'BWF-lined courts • Racquet rental • Singles & doubles',
    sport: 'Badminton',
    rating: '4.7 (64)',
    distance: '3.6 km',
    price: 'JOD 10.00 / hr',
    basePriceMinor: 1000,
    peakPriceMinor: 1500,
    peakHourStart: 17,
    peakHourEnd: 22,
    currency: 'JOD',
    address: 'Sweifieh, Amman',
    latitude: 31.9566,
    longitude: 35.8648,
    openingHour: 7,
    closingHour: 23,
    imageUrl:
        'https://images.unsplash.com/photo-1722087642932-9b070e9a066e?w=1200&q=80',
    imageUrls: const [
      'https://images.unsplash.com/photo-1626224583764-f87db24ac4ea?w=1200&q=80',
      'https://images.unsplash.com/photo-1613918431703-aa50889e3be9?w=1200&q=80',
    ],
    gradient: gradientFor('purple'),
    icon: iconFor('court'),
  ),
  Court(
    id: 'test-fitness-studio-1',
    academyId: 'uat-academy-b',
    name: 'Amman Performance Lab',
    subtitle: 'CrossFit • HYROX • Strength & conditioning • Private training',
    sport: 'Fitness',
    rating: '4.9 (131)',
    distance: '2.9 km',
    price: 'JOD 9.00 / class',
    basePriceMinor: 900,
    currency: 'JOD',
    address: 'Abdoun, Amman',
    latitude: 31.9451,
    longitude: 35.8897,
    openingHour: 6,
    closingHour: 23,
    imageUrl:
        'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=1200&q=80',
    imageUrls: const [
      'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=1200&q=80',
      'https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?w=1200&q=80',
    ],
    gradient: gradientFor('navy'),
    icon: iconFor('players'),
  ),
];

// ---------------------------------------------------------------------------
// 2. Curated test academies
// ---------------------------------------------------------------------------

final kTestAcademies = <Academy>[
  Academy(
    id: 'uat-academy-a',
    name: 'Amman North Sports Academy',
    sports: 'Padel • Football • Volleyball',
    rating: '4.9 (164)',
    distance: '1.2 km',
    featured: true,
    address: 'Sports City, Amman',
    latitude: 31.9862,
    longitude: 35.9024,
    phone: '+962 6 568 0000',
    email: 'contact@northsports.jo',
    description:
        'Premier multi-sport complex in Amman featuring indoor panoramic padel courts, 7v7 turf pitches, and certified coaches.',
    trainingPackages: const [
      'Adult Padel Masterclass',
      'Junior Football Camp',
      'Open Social Leagues',
    ],
    gradient: gradientFor('teal'),
    icon: iconFor('court'),
    imageUrl:
        'https://images.unsplash.com/photo-1626224583764-f87db24ac4ea?w=1200&q=80',
  ),
  Academy(
    id: 'uat-academy-b',
    name: 'Abdoun Elite Sports Club',
    sports: 'Tennis • Basketball',
    rating: '4.8 (112)',
    distance: '3.8 km',
    featured: true,
    address: 'Abdoun, Amman',
    latitude: 31.9418,
    longitude: 35.9296,
    phone: '+962 6 592 1111',
    email: 'info@abdounelite.jo',
    description:
        'Luxury athletic club in Abdoun offering professional hard tennis courts, indoor hardwood basketball arena, and fitness suites.',
    trainingPackages: const [
      'Private Tennis Coaching',
      '3x3 Basketball Academy',
    ],
    gradient: gradientFor('purple'),
    icon: iconFor('hex'),
    imageUrl:
        'https://images.unsplash.com/photo-1595435934249-5df7ed86e1c0?w=1200&q=80',
  ),
  Academy(
    id: 'uat-academy-racket-team',
    name: 'Amman Racket & Team Sports Center',
    sports: 'Badminton • Dodgeball',
    rating: '4.7 (86)',
    distance: '2.3 km',
    featured: true,
    address: 'Al Hussein Youth City, Amman',
    latitude: 31.9868,
    longitude: 35.9061,
    phone: '+962 7 9100 2200',
    email: 'training@playup-demo.test',
    description:
        'Demo training center for badminton technique, social doubles, youth dodgeball, and team development programs.',
    trainingPackages: const [
      'Private Badminton Coaching',
      'Junior Dodgeball Skills',
      'Adult Social Training',
    ],
    gradient: gradientFor('sunset'),
    icon: iconFor('players'),
    imageUrl:
        'https://images.unsplash.com/photo-1722087642932-9b070e9a066e?w=1200&q=80',
  ),
  Academy(
    id: 'uat-academy-sea',
    name: 'Aqaba Water Adventure Academy',
    sports: 'Sea Sports • Parasailing • Diving • Kayaking',
    rating: '4.9 (203)',
    distance: 'Aqaba',
    featured: true,
    address: 'South Beach, Aqaba',
    latitude: 29.4325,
    longitude: 34.9749,
    phone: '+962 7 9200 3300',
    email: 'academy@playup-demo.test',
    description:
        'Demo marine academy offering discovery diving, parasailing safety sessions, kayak instruction, and private water-sports coaching.',
    trainingPackages: const [
      'PADI Discovery Dive',
      'Kayak Skills & Rescue',
      'Private Sea Sports Session',
    ],
    gradient: gradientFor('teal'),
    icon: iconFor('players'),
    imageUrl:
        'https://images.unsplash.com/photo-1632904074880-b77f02b6d01e?w=1200&q=80',
  ),
  Academy(
    id: 'uat-academy-outdoor',
    name: 'Jordan Outdoor Skills School',
    sports: 'Hiking • Climbing',
    rating: '4.8 (119)',
    distance: '4.8 km',
    featured: false,
    address: 'Jabal Amman, Amman',
    latitude: 31.9504,
    longitude: 35.9235,
    phone: '+962 7 9300 4400',
    email: 'guides@playup-demo.test',
    description:
        'Demo outdoor school for hiking preparation, navigation, climbing technique, equipment use, and guided Jordan expeditions.',
    trainingPackages: const [
      'Hiking Essentials Workshop',
      'Beginner Climbing Course',
      'Private Outdoor Guide',
    ],
    gradient: gradientFor('green'),
    icon: iconFor('players'),
    imageUrl:
        'https://images.unsplash.com/photo-1522163182402-834f871fd851?w=1200&q=80',
  ),
  Academy(
    id: 'uat-academy-fitness',
    name: 'Amman Performance Lab',
    sports: 'Fitness • CrossFit • HYROX • Strength',
    rating: '4.9 (154)',
    distance: '2.9 km',
    featured: true,
    address: 'Abdoun, Amman',
    latitude: 31.9451,
    longitude: 35.8897,
    phone: '+962 7 9400 5500',
    email: 'coach@playup-demo.test',
    description:
        'Demo performance studio with CrossFit classes, HYROX preparation, strength programming, mobility, and private coaching.',
    trainingPackages: const [
      'CrossFit Foundations',
      'HYROX 8-Week Program',
      'Private Strength Coaching',
    ],
    gradient: gradientFor('navy'),
    icon: iconFor('players'),
    imageUrl:
        'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=1200&q=80',
  ),
];

// ---------------------------------------------------------------------------
// 3. Reactive in-memory test state (matches, bookings, cash split tracker)
// ---------------------------------------------------------------------------

class TestState {
  TestState._() {
    if (useFirebaseEmulators) _initDefaults();
  }
  static final instance = TestState._();

  final _bookingsCtrl =
      StreamController<List<Map<String, dynamic>>>.broadcast();
  final _matchesCtrl = StreamController<List<OpenMatch>>.broadcast();

  final List<Map<String, dynamic>> _bookings = [];
  final List<OpenMatch> _matches = [];

  void _initDefaults() {
    final now = DateTime.now();

    // 1. Pre-seeded Cash Split Booking for the current user
    _bookings.add({
      'id': 'test-booking-cash-split',
      'userId':
          FirebaseAuth.instance.currentUser?.uid ??
          'UUAlUWcLirhRwN90S44xWEtsh3B3',
      'courtId': 'test-court-padel-1',
      'courtName': 'North Padel Club - Court 1 (Indoor Panoramic)',
      'sport': 'Padel',
      'startUtc': Timestamp.fromDate(now.add(const Duration(hours: 3))),
      'endUtc': Timestamp.fromDate(
        now.add(const Duration(hours: 4, minutes: 30)),
      ),
      'durationMinutes': 90,
      'status': 'confirmed',
      'paymentStatus': 'pending',
      'paymentMethod': 'cash',
      'currency': 'JOD',
      'totalMinor': 2800,
      'subtotalMinor': 2800,
      'discountMinor': 0,
      'playerCapacity': 4,
      'participants': [
        FirebaseAuth.instance.currentUser?.uid ??
            'UUAlUWcLirhRwN90S44xWEtsh3B3',
        'test-user-omar',
        'test-user-rami',
        'test-user-zaid',
      ],
      'playerNames': ['Tariq (You)', 'Omar Haddad', 'Rami K.', 'Zaid M.'],
      'cashPaidPlayers': [
        FirebaseAuth.instance.currentUser?.uid ??
            'UUAlUWcLirhRwN90S44xWEtsh3B3',
        'test-user-omar',
      ],
      'createdAt': Timestamp.fromDate(now.subtract(const Duration(hours: 1))),
      'updatedAt': Timestamp.fromDate(now.subtract(const Duration(hours: 1))),
    });

    // 2. Open Matches with Reliability Badges & WhatsApp Invites
    _matches.addAll([
      OpenMatch(
        id: 'test-match-padel-open',
        title: 'Friday Padel Doubles (Ranked Elo)',
        sport: 'Padel',
        host: 'Omar Haddad',
        court: 'North Padel Club - Court 1',
        time: 'Today, 7:00 PM',
        skill: 'Intermediate',
        joined: 3,
        needed: 1,
        pricePerPlayer: 'JOD 6.00',
        ranked: true,
        hostId: 'test-user-omar',
        hostReliability: 98,
        playerIds: const ['test-user-omar', 'test-user-rami', 'test-user-zaid'],
        playerNames: const ['Omar Haddad', 'Rami K.', 'Zaid M.'],
        startUtc: now.add(const Duration(hours: 4)),
        status: 'open',
        scoreStatus: 'none',
      ),
      OpenMatch(
        id: 'test-match-football-open',
        title: '7v7 Turf Football Night',
        sport: 'Football',
        host: 'Ahmad Saleh',
        court: 'Khalda Football Arena',
        time: 'Today, 8:30 PM',
        skill: 'Casual',
        joined: 11,
        needed: 3,
        pricePerPlayer: 'JOD 3.50',
        ranked: false,
        hostId: 'test-user-ahmad',
        hostReliability: 92,
        playerIds: const [
          'test-user-ahmad',
          'p2',
          'p3',
          'p4',
          'p5',
          'p6',
          'p7',
          'p8',
          'p9',
          'p10',
          'p11',
        ],
        playerNames: const [
          'Ahmad Saleh',
          'Hamza',
          'Kareem',
          'Fadi',
          'Nasser',
          'Yousef',
          'Bilal',
          'Sami',
          'Laith',
          'Hani',
          'Mustafa',
        ],
        startUtc: now.add(const Duration(hours: 6)),
        status: 'open',
        scoreStatus: 'none',
      ),
      OpenMatch(
        id: 'test-match-tennis-open',
        title: 'Abdoun Evening Singles',
        sport: 'Tennis',
        host: 'Lina Haddad',
        court: 'Abdoun Tennis Academy',
        time: 'Tomorrow, 6:00 PM',
        skill: 'Intermediate',
        joined: 1,
        needed: 1,
        pricePerPlayer: 'JOD 10.00',
        ranked: true,
        hostId: 'test-user-lina',
        hostReliability: 96,
        playerIds: const ['test-user-lina'],
        playerNames: const ['Lina Haddad'],
        startUtc: now.add(const Duration(days: 1, hours: 2)),
        status: 'open',
        scoreStatus: 'none',
      ),
      OpenMatch(
        id: 'test-match-basketball-open',
        title: 'Jordan Hoops 3x3 Run',
        sport: 'Basketball',
        host: 'Zaid M.',
        court: 'Jordan Hoops Arena',
        time: 'Tonight, 9:00 PM',
        skill: 'All levels',
        joined: 4,
        needed: 2,
        pricePerPlayer: 'JOD 4.00',
        ranked: false,
        hostId: 'test-user-zaid',
        hostReliability: 91,
        playerIds: const ['test-user-zaid', 'b2', 'b3', 'b4'],
        playerNames: const ['Zaid M.', 'Samer', 'Ali', 'Fares'],
        startUtc: now.add(const Duration(hours: 7)),
        status: 'open',
        scoreStatus: 'none',
      ),
      OpenMatch(
        id: 'test-match-volleyball-open',
        title: 'Mixed Volleyball Social',
        sport: 'Volleyball',
        host: 'Dana N.',
        court: 'Amman Sports City Volleyball Hub',
        time: 'Saturday, 5:30 PM',
        skill: 'Social',
        joined: 8,
        needed: 4,
        pricePerPlayer: 'JOD 2.50',
        ranked: false,
        hostId: 'test-user-dana',
        hostReliability: 94,
        playerIds: const ['test-user-dana', 'v2', 'v3', 'v4'],
        playerNames: const ['Dana N.', 'Maya', 'Rana', 'Noor'],
        startUtc: now.add(const Duration(days: 2)),
        status: 'open',
        scoreStatus: 'none',
      ),
      OpenMatch(
        id: 'test-match-dodgeball-open',
        title: 'Friday Dodgeball Challenge',
        sport: 'Dodgeball',
        host: 'Kareem A.',
        court: 'PlayUp Dodgeball Arena',
        time: 'Friday, 7:30 PM',
        skill: 'Casual',
        joined: 9,
        needed: 3,
        pricePerPlayer: 'JOD 2.00',
        ranked: false,
        hostId: 'test-user-kareem',
        hostReliability: 93,
        playerIds: const ['test-user-kareem', 'd2', 'd3', 'd4'],
        playerNames: const ['Kareem A.', 'Omar', 'Rami', 'Laith'],
        startUtc: now.add(const Duration(days: 3)),
        status: 'open',
        scoreStatus: 'none',
      ),
      OpenMatch(
        id: 'test-match-badminton-open',
        title: 'Badminton Doubles Mixer',
        sport: 'Badminton',
        host: 'Sara K.',
        court: 'Sweifieh Badminton Club',
        time: 'Tomorrow, 8:00 PM',
        skill: 'Intermediate',
        joined: 3,
        needed: 1,
        pricePerPlayer: 'JOD 3.50',
        ranked: true,
        hostId: 'test-user-sara',
        hostReliability: 97,
        playerIds: const ['test-user-sara', 'bd2', 'bd3'],
        playerNames: const ['Sara K.', 'Hala', 'Yazan'],
        startUtc: now.add(const Duration(days: 1, hours: 4)),
        status: 'open',
        scoreStatus: 'none',
      ),
      // 3. Match Ready for Mutual Score Verification & Dynamic Elo
      OpenMatch(
        id: 'test-match-score-verification',
        title: 'Padel Semi-Final Showdown',
        sport: 'Padel',
        host: 'Rami K.',
        court: 'North Padel Club - Court 1',
        time: 'Today, 4:00 PM',
        skill: 'Advanced',
        joined: 4,
        needed: 0,
        pricePerPlayer: 'JOD 7.00',
        ranked: true,
        hostId: 'test-user-rami',
        hostReliability: 95,
        playerIds: [
          'test-user-rami',
          FirebaseAuth.instance.currentUser?.uid ??
              'UUAlUWcLirhRwN90S44xWEtsh3B3',
        ],
        playerNames: const ['Rami K.', 'You'],
        startUtc: now.subtract(const Duration(hours: 2)),
        status: 'completed',
        scoreStatus: 'pendingConfirmation',
        scoreSubmittedBy: 'test-user-rami',
        score: const {
          'teamAScore': 21,
          'teamBScore': 18,
          'sets': ['6-4', '4-6', '7-5'],
        },
      ),
    ]);
  }

  Stream<List<Map<String, dynamic>>> myBookingsStream() async* {
    yield List<Map<String, dynamic>>.from(_bookings);
    yield* _bookingsCtrl.stream;
  }

  Stream<List<OpenMatch>> openMatchesStream() async* {
    yield List<OpenMatch>.from(_matches.where((m) => m.status == 'open'));
    yield* _matchesCtrl.stream.map(
      (list) => list.where((m) => m.status == 'open').toList(),
    );
  }

  Stream<List<OpenMatch>> myMatchesStream() async* {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    yield List<OpenMatch>.from(
      _matches.where((m) => uid == null || m.playerIds.contains(uid)),
    );
    yield* _matchesCtrl.stream.map(
      (list) =>
          list.where((m) => uid == null || m.playerIds.contains(uid)).toList(),
    );
  }

  void addBooking(Map<String, dynamic> booking) {
    _bookings.insert(0, booking);
    _bookingsCtrl.add(List.from(_bookings));
  }

  void toggleCashPaid(String bookingId, String playerId, bool paid) {
    final index = _bookings.indexWhere((b) => b['id'] == bookingId);
    if (index != -1) {
      final paidList = List<String>.from(
        _bookings[index]['cashPaidPlayers'] as List? ?? [],
      );
      if (paid && !paidList.contains(playerId)) {
        paidList.add(playerId);
      } else if (!paid) {
        paidList.remove(playerId);
      }
      _bookings[index] = {
        ..._bookings[index],
        'cashPaidPlayers': paidList,
        'updatedAt': Timestamp.now(),
      };
      _bookingsCtrl.add(List.from(_bookings));
    }
  }

  List<OpenMatch> get currentMatches => List.unmodifiable(_matches);
  List<Map<String, dynamic>> get currentBookings =>
      List.unmodifiable(_bookings);

  void submitScore({
    required String matchId,
    required int teamAScore,
    required int teamBScore,
    List<String> sets = const [],
  }) {
    final index = _matches.indexWhere((m) => m.id == matchId);
    if (index != -1) {
      final current = _matches[index];
      _matches[index] = OpenMatch(
        id: current.id,
        title: current.title,
        sport: current.sport,
        host: current.host,
        court: current.court,
        time: current.time,
        skill: current.skill,
        joined: current.joined,
        needed: current.needed,
        pricePerPlayer: current.pricePerPlayer,
        ranked: current.ranked,
        playerIds: current.playerIds,
        hostId: current.hostId,
        bookingId: current.bookingId,
        startUtc: current.startUtc,
        playerNames: current.playerNames,
        latitude: current.latitude,
        longitude: current.longitude,
        scoreStatus: 'pendingConfirmation',
        scoreSubmittedBy: FirebaseAuth.instance.currentUser?.uid ?? '',
        score: {
          'teamAScore': teamAScore,
          'teamBScore': teamBScore,
          'sets': sets,
        },
        hostReliability: current.hostReliability,
        status: 'completed',
      );
      _matchesCtrl.add(List.from(_matches));
    }
  }

  void confirmScore({required String matchId, required bool accept}) {
    final index = _matches.indexWhere((m) => m.id == matchId);
    if (index != -1) {
      final current = _matches[index];
      _matches[index] = OpenMatch(
        id: current.id,
        title: current.title,
        sport: current.sport,
        host: current.host,
        court: current.court,
        time: current.time,
        skill: current.skill,
        joined: current.joined,
        needed: current.needed,
        pricePerPlayer: current.pricePerPlayer,
        ranked: current.ranked,
        playerIds: current.playerIds,
        hostId: current.hostId,
        bookingId: current.bookingId,
        startUtc: current.startUtc,
        playerNames: current.playerNames,
        latitude: current.latitude,
        longitude: current.longitude,
        scoreStatus: accept ? 'confirmed' : 'disputed',
        scoreSubmittedBy: current.scoreSubmittedBy,
        score: current.score,
        hostReliability: current.hostReliability,
        status: 'completed',
      );
      _matchesCtrl.add(List.from(_matches));
    }
  }
}

// ---------------------------------------------------------------------------
// 4. Sport Activities & Outdoor Adventures (Parasailing, Skydiving, Canyoning)
// ---------------------------------------------------------------------------

class SportActivity {
  const SportActivity({
    required this.id,
    required this.title,
    required this.category,
    required this.categoryIcon,
    required this.location,
    required this.priceLabel,
    required this.priceMinor,
    required this.duration,
    required this.imageUrl,
    required this.description,
    required this.whatsIncluded,
    required this.operatorName,
    required this.operatorPhone,
    this.badge = '',
    this.rating = '4.9',
  });

  final String id;
  final String title;
  final String category;
  final IconData categoryIcon;
  final String location;
  final String priceLabel;
  final int priceMinor;
  final String duration;
  final String imageUrl;
  final String description;
  final List<String> whatsIncluded;
  final String operatorName;
  final String operatorPhone;
  final String badge;
  final String rating;
}

final kSportActivities = <SportActivity>[
  const SportActivity(
    id: 'activity-parasailing-aqaba',
    title: 'Red Sea Parasailing Flight',
    category: 'Water',
    categoryIcon: CupertinoIcons.wind,
    location: 'Aqaba Marine Coast',
    priceLabel: 'JOD 35.00 / person',
    priceMinor: 3500,
    duration: '15 min flight + 45 min boat ride',
    badge: 'POPULAR',
    rating: '4.9 (188)',
    imageUrl:
        'https://images.unsplash.com/photo-1544551763-46a013bb70d5?w=1200&q=80',
    description:
        'Soar 150 meters above the turquoise waters of the Gulf of Aqaba. Enjoy breathtaking panoramic views of Jordan, Egypt, and Saudi Arabia from the sky. Available in Single or Tandem flights with internationally certified captains and complete safety gear.',
    whatsIncluded: [
      'High-speed offshore speedboat ride',
      'Safety briefing & certified life vest',
      'Single or Tandem flight option',
      'Optional HD Go-Pro photo & video package',
      'Check in with the activity team at the marina dock',
    ],
    operatorName: 'Aqaba Sky & Sea Adventures',
    operatorPhone: '+962 7 9000 1234',
  ),
  const SportActivity(
    id: 'activity-skydiving-jordan',
    title: 'Tandem Skydiving Jump (12,000 ft)',
    category: 'Air',
    categoryIcon: CupertinoIcons.airplane,
    location: 'Wadi Rum Desert / Dead Sea Dropzone',
    priceLabel: 'JOD 185.00 / jump',
    priceMinor: 18500,
    duration: '3 hours total (45s freefall)',
    badge: 'EXTREME THRILL',
    rating: '5.0 (94)',
    imageUrl:
        'https://images.unsplash.com/photo-1521673845837-12c82f93998b?w=1200&q=80',
    description:
        'The ultimate bucket-list adrenaline rush! Leap from 12,000 feet securely harnessed to an internationally certified USPA tandem master. Experience 45 seconds of exhilarating 200 km/h freefall before a serene 5-minute canopy glide over Mars-like desert sandstone.',
    whatsIncluded: [
      'Full tandem harness, jumpsuit & goggles',
      '20-minute scenic ascent flight',
      '45-second 200 km/h freefall',
      '5-minute parachute canopy glide & soft landing',
      'Official skydiving achievement certificate',
      'Check in with the flight team at the airport manifest desk',
    ],
    operatorName: 'Royal Aero Sports Club of Jordan',
    operatorPhone: '+962 7 9555 4321',
  ),
  const SportActivity(
    id: 'activity-canyoning-mujib',
    title: 'Wadi Mujib Siq Trail Canyoning',
    category: 'Canyon',
    categoryIcon: CupertinoIcons.flame_fill,
    location: 'Wadi Mujib Biosphere Reserve',
    priceLabel: 'JOD 25.00 / person',
    priceMinor: 2500,
    duration: '2.5 to 3 hours',
    badge: 'MUST VISIT',
    rating: '4.9 (320)',
    imageUrl:
        'https://images.unsplash.com/photo-1469854523086-cc02fe5d8800?w=1200&q=80',
    description:
        'Hike, wade, and swim through a dramatic river canyon between towering sandstone cliffs at the lowest nature reserve on Earth. Slide down natural rock water-slides and finish beneath an awe-inspiring 20-meter waterfall.',
    whatsIncluded: [
      'Reserve entry permit & environmental pass',
      'RSCN-certified high-buoyancy life vest',
      'Rope-assisted river gorge obstacles',
      'On-site rescue team & locker facilities',
      'Cash payment at Mujib Adventure Center',
    ],
    operatorName: 'Wild Jordan & Mujib Adventures',
    operatorPhone: '+962 6 461 6523',
  ),
  const SportActivity(
    id: 'activity-scuba-aqaba',
    title: 'Aqaba Coral Reef Scuba Diving',
    category: 'Water',
    categoryIcon: CupertinoIcons.drop_fill,
    location: 'South Beach Marine Park, Aqaba',
    priceLabel: 'JOD 45.00 / dive',
    priceMinor: 4500,
    duration: '2 hours (45 min underwater)',
    badge: 'BEGINNER FRIENDLY',
    rating: '4.8 (145)',
    imageUrl:
        'https://images.unsplash.com/photo-1544551763-77ef2d0cfc6c?w=1200&q=80',
    description:
        'Dive into world-famous Red Sea coral reefs including the Japanese Garden and Seven Sisters tank shipwreck. Suitable for both beginners (discovery dive) and certified PADI divers with personalized guide attention.',
    whatsIncluded: [
      'Full scuba gear, wetsuit & air tank rental',
      'PADI-certified Divemaster instructor',
      'High-resolution underwater marine photo pack',
      'Beach club access, sunbed & hot mint tea',
      'Pay cash on-site at dive center desk',
    ],
    operatorName: 'Deep Blue Dive Center Aqaba',
    operatorPhone: '+962 7 9888 7766',
  ),
  const SportActivity(
    id: 'activity-sandboarding-rum',
    title: 'Wadi Rum Buggy & Sandboarding Safari',
    category: 'Desert',
    categoryIcon: CupertinoIcons.sun_max_fill,
    location: 'Wadi Rum Protected Area',
    priceLabel: 'JOD 30.00 / 2 hours',
    priceMinor: 3000,
    duration: '2 hours',
    badge: 'TOP RATED',
    rating: '4.9 (215)',
    imageUrl:
        'https://images.unsplash.com/photo-1509316975850-ff9c5deb0cd9?w=1200&q=80',
    description:
        'Drive high-powered off-road buggies across sweeping red dunes, then strap on custom sandboards to carve down the tallest desert slopes. Conclude with traditional Bedouin sweet tea at a panoramic sunset camp.',
    whatsIncluded: [
      'High-power 4x4 Dune Buggy rental',
      'Custom wax sandboard equipment',
      'Bedouin guide escort across protected dunes',
      'Safety helmet & anti-dust desert goggles',
      'Sunset tea hospitality at camp',
    ],
    operatorName: 'Bedouin Moon Desert Adventures',
    operatorPhone: '+962 7 7777 8899',
  ),
  const SportActivity(
    id: 'activity-kayak-dam',
    title: 'King Talal Lake Kayaking',
    category: 'Water',
    categoryIcon: CupertinoIcons.compass,
    location: 'Jerash / King Talal Dam',
    priceLabel: 'JOD 15.00 / hour',
    priceMinor: 1500,
    duration: '1 to 2 hours',
    badge: 'SCENIC & RELAXING',
    rating: '4.7 (78)',
    imageUrl:
        'https://images.unsplash.com/photo-1544551763-8dd44758c2dd?w=1200&q=80',
    description:
        'Paddle across the calm, emerald waters of King Talal lake surrounded by pine-covered hills. Ideal for recreational solo or tandem kayaking away from city noise.',
    whatsIncluded: [
      'Single or double sit-on-top kayak',
      'Ergonomic carbon paddle & life jacket',
      'Waterproof phone case',
      'Dockside safety orientation',
    ],
    operatorName: 'Jordan Kayak Club',
    operatorPhone: '+962 7 9111 2233',
  ),
  const SportActivity(
    id: 'activity-hiking-dana',
    title: 'Dana Reserve Guided Hiking Trail',
    category: 'Desert',
    categoryIcon: CupertinoIcons.map_fill,
    location: 'Dana Biosphere Reserve, Tafileh',
    priceLabel: 'JOD 28.00 / person',
    priceMinor: 2800,
    duration: '4 hours',
    badge: 'GUIDED HIKE',
    rating: '4.9 (167)',
    imageUrl:
        'https://images.unsplash.com/photo-1551632811-561732d1e306?w=1200&q=80',
    description:
        'Explore Dana village and the reserve trails with a licensed local guide. The demo experience includes scenic viewpoints, wildlife interpretation, and a paced route suitable for active beginners.',
    whatsIncluded: [
      'Licensed local hiking guide',
      'Trail briefing and route map',
      'Trekking poles and first-aid support',
      'Water and a light trail snack',
    ],
    operatorName: 'Jordan Outdoor Skills School',
    operatorPhone: '+962 7 9300 4400',
  ),
  const SportActivity(
    id: 'activity-climbing-wadi-rum',
    title: 'Wadi Rum Beginner Rock Climbing',
    category: 'Desert',
    categoryIcon: CupertinoIcons.arrow_up_right_circle_fill,
    location: 'Wadi Rum Protected Area',
    priceLabel: 'JOD 55.00 / person',
    priceMinor: 5500,
    duration: '3 hours',
    badge: 'BEGINNER READY',
    rating: '4.8 (96)',
    imageUrl:
        'https://images.unsplash.com/photo-1522163182402-834f871fd851?w=1200&q=80',
    description:
        'Learn core climbing movement and rope safety on a carefully selected sandstone route with a certified guide. This demo session includes progressive instruction and supervised climbing.',
    whatsIncluded: [
      'Certified climbing guide',
      'Helmet, harness, shoes and ropes',
      'Safety and belay instruction',
      'Transport from Wadi Rum Village',
    ],
    operatorName: 'Wadi Rum Climbing Base',
    operatorPhone: '+962 7 9550 6600',
  ),
];
