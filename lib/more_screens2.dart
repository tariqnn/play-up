import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import 'main.dart';
import 'catalog.dart';
import 'location_service.dart';
import 'map_links.dart';
import 'more_screens.dart';
import 'more_screens3.dart';
import 'more_screens4.dart';
import 'custom_dashboard.dart';
import 'academy_live_screens.dart';
import 'academy_service.dart';
import 'booking_domain.dart';
import 'tournament_screens.dart';
import 'multi_court_timeline_screen.dart';

/// Open matches are read from the live Firestore catalogue.
Stream<List<OpenMatch>> openMatchesStream() {
  return FirebaseFirestore.instance
      .collection('matches')
      .where('status', isEqualTo: 'open')
      .limit(100)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(
              (document) => OpenMatch.fromMap(document.data(), id: document.id),
            )
            .where(
              (match) =>
                  (match.bookingId.isNotEmpty || match.groupId.isNotEmpty) &&
                  match.startUtc != null &&
                  match.startUtc!.isAfter(DateTime.now()),
            )
            .toList(),
      );
}

// ---------------------------------------------------------------------------
// Matchmaking: open matches, match details, create match, pre-match check-in
// ---------------------------------------------------------------------------

class OpenMatch {
  const OpenMatch({
    this.id,
    required this.title,
    required this.sport,
    required this.host,
    required this.court,
    required this.time,
    required this.skill,
    required this.joined,
    required this.needed,
    required this.pricePerPlayer,
    required this.ranked,
    this.playerIds = const [],
    this.hostId = '',
    this.bookingId = '',
    this.startUtc,
    this.playerNames = const [],
    this.latitude,
    this.longitude,
    this.scoreStatus = 'none',
    this.scoreSubmittedBy = '',
    this.score,
    this.hostReliability,
    this.status = 'open',
    this.groupId = '',
  });

  final String scoreStatus;
  final String scoreSubmittedBy;
  final Map<String, dynamic>? score;
  final int? hostReliability;
  final String status;
  final String groupId;

  factory OpenMatch.fromMap(Map<String, dynamic> d, {String? id}) {
    final players = (d['players'] as List?)?.length ?? 1;
    final needed = (d['neededPlayers'] as num?)?.toInt() ?? 0;
    final start = (d['startUtc'] as Timestamp?)?.toDate().toLocal();
    final capacity = (d['capacity'] as num?)?.toInt() ?? (players + needed);
    final totalMinor = (d['totalMinor'] as num?)?.toInt() ?? 0;
    return OpenMatch(
      id: id,
      title: (d['title'] ?? 'Match').toString(),
      sport: (d['sport'] ?? 'Basketball').toString(),
      host: (d['hostName'] ?? 'Player').toString(),
      court: (d['courtName'] ?? 'Court').toString(),
      time: start == null
          ? 'Time pending'
          : DateFormat('EEE, d MMM - h:mm a').format(start),
      skill: (d['skillRange'] ?? 'Intermediate').toString(),
      joined: players,
      needed: needed,
      pricePerPlayer: totalMinor > 0
          ? '${d['currency'] ?? 'JOD'} ${(totalMinor / 100 / capacity).toStringAsFixed(2)}'
          : 'Cash at venue',
      ranked: d['ranked'] == true,
      playerIds: List<String>.from(d['players'] as List? ?? const []),
      hostId: (d['hostId'] ?? '').toString(),
      bookingId: (d['bookingId'] ?? '').toString(),
      startUtc: start,
      playerNames: List<String>.from(d['playerNames'] as List? ?? const []),
      latitude: (d['latitude'] as num?)?.toDouble(),
      longitude: (d['longitude'] as num?)?.toDouble(),
      scoreStatus: (d['scoreStatus'] ?? 'none').toString(),
      scoreSubmittedBy: (d['scoreSubmittedBy'] ?? '').toString(),
      score: d['score'] is Map
          ? Map<String, dynamic>.from(d['score'] as Map)
          : null,
      hostReliability: (d['hostReliability'] as num?)?.toInt(),
      status: (d['status'] ?? 'open').toString(),
      groupId: (d['communityGroupId'] ?? '').toString(),
    );
  }

  double? distanceKmFrom(AppLocation? location) {
    if (location == null || latitude == null || longitude == null) {
      return null;
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
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  String distanceFrom(AppLocation? location) {
    final km = distanceKmFrom(location);
    if (km == null) return '';
    final value = km < 1
        ? '${(km * 1000).round()} m'
        : '${km.toStringAsFixed(1)} km';
    return '~$value direct';
  }

  final String title;
  final String? id;
  final String sport;
  final String host;
  final String court;
  final String time;
  final String skill;
  final double? latitude;
  final double? longitude;
  final int joined;
  final int needed;
  final String pricePerPlayer;
  final bool ranked;
  final List<String> playerIds;
  final String hostId;
  final String bookingId;
  final DateTime? startUtc;
  final List<String> playerNames;
}

class _CommunityGroup {
  const _CommunityGroup(
    this.id,
    this.name,
    this.sport,
    this.description,
    this.image,
    this.icon,
  );
  final String id;
  final String name;
  final String sport;
  final String description;
  final String image;
  final IconData icon;
}

const _communityGroups = <_CommunityGroup>[
  _CommunityGroup(
    'into-the-basket',
    'Into The Basket',
    'Basketball',
    'Amman basketball community and organized pickup games.',
    'assets/images/sports/basketball_court_ball.png',
    Icons.sports_basketball_rounded,
  ),
  _CommunityGroup(
    'cycling',
    'Cycling Groups',
    'Cycling',
    'Find local rides and meet other cyclists.',
    'assets/images/sports/cycling_group.jpg',
    Icons.directions_bike_rounded,
  ),
  _CommunityGroup(
    'running',
    'Running Groups',
    'Running',
    'Find local runs and running meetups.',
    'assets/images/sports/running_track.jpg',
    Icons.directions_run_rounded,
  ),
];

class CommunityGroupsSection extends StatelessWidget {
  const CommunityGroupsSection({super.key, this.initialSport});

  final String? initialSport;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SectionHeader(title: 'Community groups'),
      const SizedBox(height: 12),
      for (final group in _communityGroups.where(
        (group) =>
            initialSport == null ||
            group.sport.toLowerCase() == initialSport!.toLowerCase(),
      ))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _CommunityGroupScreen(group: group),
              ),
            ),
            child: CardBox(
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 124,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(group.image, fit: BoxFit.cover),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black87],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: 12,
                        child: Row(
                          children: [
                            Icon(group.icon, color: Colors.white, size: 22),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    group.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    '${group.sport} Â· ${group.description}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              CupertinoIcons.chevron_right,
                              color: Colors.white,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class CommunityGroupsScreen extends StatelessWidget {
  const CommunityGroupsScreen({super.key, this.initialSport});
  final String? initialSport;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AppScrollPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageTopBar(
            title: initialSport == null
                ? 'Community groups'
                : '$initialSport groups',
            onBack: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: 14),
          CommunityGroupsSection(initialSport: initialSport),
        ],
      ),
    ),
  );
}

class _CommunityGroupScreen extends StatelessWidget {
  const _CommunityGroupScreen({required this.group});
  final _CommunityGroup group;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - DateTime.monday));
    final nextMonday = monday.add(const Duration(days: 7));
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('communities')
          .doc(group.id)
          .snapshots(),
      builder: (context, communitySnapshot) {
        final community =
            communitySnapshot.data?.data() ?? const <String, dynamic>{};
        final name = (community['name']?.toString().trim().isNotEmpty ?? false)
            ? community['name'].toString()
            : group.name;
        final sport =
            (community['sport']?.toString().trim().isNotEmpty ?? false)
            ? community['sport'].toString()
            : group.sport;
        final description =
            community['description']?.toString() ?? group.description;
        final cover = community['imageUrl']?.toString() ?? '';
        return Scaffold(
          body: AppScrollPage(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageTopBar(title: name, onBack: () => Navigator.pop(context)),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    height: 185,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (cover.isEmpty)
                          Image.asset(group.image, fit: BoxFit.cover)
                        else
                          Image.network(
                            cover,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                Image.asset(group.image, fit: BoxFit.cover),
                          ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Colors.black87],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 16,
                          bottom: 15,
                          child: Text(
                            '$sport Â· Community',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (description.isNotEmpty)
                  CardBox(
                    child: Text(
                      description,
                      style: const TextStyle(height: 1.5),
                    ),
                  ),
                if ((community['city']?.toString().isNotEmpty ?? false) ||
                    (community['contactPhone']?.toString().isNotEmpty ??
                        false)) ...[
                  const SizedBox(height: 10),
                  CardBox(
                    child: Text(
                      [community['city'], community['contactPhone']]
                          .where(
                            (value) =>
                                value != null && value.toString().isNotEmpty,
                          )
                          .join(' Â· '),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                const SectionHeader(title: 'Community events'),
                const SizedBox(height: 10),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('events')
                      .where('communityId', isEqualTo: group.id)
                      .snapshots(),
                  builder: (context, eventsSnapshot) {
                    if (eventsSnapshot.hasError) {
                      return const CardBox(
                        child: Text(
                          'Community events could not load right now.',
                        ),
                      );
                    }
                    if (eventsSnapshot.connectionState ==
                            ConnectionState.waiting &&
                        !eventsSnapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final events = [...?eventsSnapshot.data?.docs]
                      ..sort(
                        (a, b) => (a.data()['date']?.toString() ?? '')
                            .compareTo(b.data()['date']?.toString() ?? ''),
                      );
                    final today = DateTime.now().toIso8601String().substring(
                      0,
                      10,
                    );
                    final upcoming = events.where(
                      (event) =>
                          event.data()['status'] != 'cancelled' &&
                          (event.data()['date']?.toString() ?? '').compareTo(
                                today,
                              ) >=
                              0,
                    );
                    if (upcoming.isEmpty) {
                      return const CardBox(
                        child: Text('No community events announced yet.'),
                      );
                    }
                    return Column(
                      children: [
                        for (final event in upcoming)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: CardBox(
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.event_available_outlined,
                                ),
                                title: Text(
                                  event.data()['title']?.toString() ??
                                      'Community event',
                                ),
                                subtitle: Text(
                                  [
                                        event.data()['date'],
                                        event.data()['location'],
                                      ]
                                      .where(
                                        (value) =>
                                            value != null &&
                                            value.toString().isNotEmpty,
                                      )
                                      .join(' · '),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 20),
                const SectionHeader(title: 'Matches this week'),
                const SizedBox(height: 10),
                StreamBuilder<List<OpenMatch>>(
                  stream: openMatchesStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const CardBox(
                        child: Text(
                          'This group schedule could not load. Try again shortly.',
                        ),
                      );
                    }
                    final matches =
                        (snapshot.data ?? const <OpenMatch>[]).where((match) {
                            final start = match.startUtc?.toLocal();
                            return match.groupId == group.id &&
                                start != null &&
                                !start.isBefore(monday) &&
                                start.isBefore(nextMonday);
                          }).toList()
                          ..sort((a, b) => a.startUtc!.compareTo(b.startUtc!));
                    if (matches.isEmpty) {
                      return CardBox(
                        child: Text(
                          'No ${sport.toLowerCase()} matches are scheduled for this group this week yet.',
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final match in matches)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: OpenMatchCard(match: match),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class OpenMatchesScreen extends StatefulWidget {
  final String? initialSport;
  const OpenMatchesScreen({super.key, this.initialSport});

  @override
  State<OpenMatchesScreen> createState() => _OpenMatchesScreenState();
}

class _OpenMatchesScreenState extends State<OpenMatchesScreen> {
  late String _filter;
  static const _filters = [
    'All',
    'Padel',
    'Football',
    'Tennis',
    'Basketball',
    'Volleyball',
    'Dodgeball',
    'Badminton',
    'Ranked',
  ];

  @override
  void initState() {
    super.initState();
    _filter = widget.initialSport ?? 'All';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Open Matches',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _filters.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) => SelectablePill(
                  label: _filters[index],
                  selected: _filter == _filters[index],
                  onTap: () => setState(() => _filter = _filters[index]),
                ),
              ),
            ),
            const SizedBox(height: 18),
            StreamBuilder<List<OpenMatch>>(
              stream: openMatchesStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return CardBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ErrorBanner(
                          message:
                              'Open matches could not load. Check your connection and try again.',
                        ),
                        const SizedBox(height: 12),
                        SecondaryButton(
                          label: 'Retry',
                          onPressed: () => setState(() {}),
                        ),
                      ],
                    ),
                  );
                }
                final source = snapshot.data ?? const <OpenMatch>[];
                final matches = source.where((m) {
                  if (_filter == 'All') return true;
                  if (_filter == 'Ranked') return m.ranked;
                  return m.sport == _filter;
                }).toList();
                return ValueListenableBuilder<AppLocation?>(
                  valueListenable: LocationService.instance.current,
                  builder: (context, location, _) {
                    matches.sort((a, b) {
                      final aDistance = a.distanceKmFrom(location);
                      final bDistance = b.distanceKmFrom(location);
                      if (aDistance == null && bDistance == null) return 0;
                      if (aDistance == null) return 1;
                      if (bDistance == null) return -1;
                      return aDistance.compareTo(bDistance);
                    });
                    return _OpenMatchesList(
                      matches: matches,
                      location: location,
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

class _OpenMatchesList extends StatelessWidget {
  const _OpenMatchesList({required this.matches, required this.location});

  final List<OpenMatch> matches;
  final AppLocation? location;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return EmptyState(
        icon: CupertinoIcons.search,
        title: 'No matches found',
        message: 'Try a different filter or create your own match.',
        action: 'Create Match',
        onTap: () async {
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
        },
      );
    }
    return Column(
      children: [
        for (final match in matches)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OpenMatchCard(match: match, location: location),
          ),
      ],
    );
  }
}

class OpenMatchCard extends StatelessWidget {
  const OpenMatchCard({super.key, required this.match, this.location});

  final OpenMatch match;
  final AppLocation? location;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MatchDetailsScreen(match: match)),
      ),
      child: CardBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    match.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: match.ranked
                        ? AppColors.purple.withValues(alpha: .12)
                        : AppColors.green.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    match.ranked ? 'Ranked' : 'Casual',
                    style: TextStyle(
                      color: match.ranked ? AppColors.purple : AppColors.green,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  CupertinoIcons.location_solid,
                  size: 14,
                  color: AppColors.muted,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    match.distanceFrom(location).isEmpty
                        ? '${match.court}  â€¢  ${match.time}'
                        : '${match.court}  â€¢  ${match.time}  â€¢  ${match.distanceFrom(location)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _MatchStat(
                  icon: CupertinoIcons.person_2_fill,
                  label: '${match.joined} joined â€¢ needs ${match.needed}',
                ),
                const Spacer(),
                Text(
                  match.pricePerPlayer,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'View Match',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MatchDetailsScreen(match: match),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchStat extends StatelessWidget {
  const _MatchStat({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.purple),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class MatchDetailsScreen extends StatelessWidget {
  const MatchDetailsScreen({super.key, required this.match});

  final OpenMatch match;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final joined = uid != null && match.playerIds.contains(uid);
    final hosting = uid != null && match.hostId == uid;
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Match Details',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    match.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: match.ranked
                        ? AppColors.purple.withValues(alpha: .12)
                        : AppColors.green.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    match.ranked ? 'Ranked' : 'Casual',
                    style: TextStyle(
                      color: match.ranked ? AppColors.purple : AppColors.green,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            CardBox(
              child: Column(
                children: [
                  DetailRow(label: 'Sport', value: match.sport),
                  DetailRow(label: 'Court', value: match.court),
                  DetailRow(label: 'Time', value: match.time),
                  DetailRow(label: 'Skill range', value: match.skill),
                  DetailRow(
                    label: 'Price per player',
                    value: match.pricePerPlayer,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Text(
                  'Players',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                Text(
                  '${match.joined}/${match.joined + match.needed}',
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < match.joined; i++)
                  Avatar(
                    name:
                        i < match.playerNames.length &&
                            match.playerNames[i].trim().isNotEmpty
                        ? match.playerNames[i]
                        : 'Player ${i + 1}',
                    size: 46,
                  ),
                for (var i = 0; i < match.needed; i++)
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.background,
                      border: Border.all(color: AppColors.line),
                    ),
                    child: const Icon(
                      CupertinoIcons.add,
                      color: AppColors.muted,
                      size: 18,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            CardBox(
              child: Row(
                children: [
                  const Avatar(name: 'H', size: 42),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hosted by ${match.host}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        if (match.hostReliability != null) ...[
                          const SizedBox(height: 4),
                          Builder(
                            builder: (context) {
                              final rel = match.hostReliability!;
                              final isHigh = rel >= 90;
                              final isGood = rel >= 70;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isHigh
                                      ? const Color(
                                          0xFF22C55E,
                                        ).withValues(alpha: 0.15)
                                      : isGood
                                      ? AppColors.gold.withValues(alpha: 0.18)
                                      : Colors.red.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isHigh
                                          ? CupertinoIcons.shield_lefthalf_fill
                                          : CupertinoIcons
                                                .exclamationmark_shield_fill,
                                      size: 11,
                                      color: isHigh
                                          ? const Color(0xFF15803D)
                                          : isGood
                                          ? const Color(0xFFB8860B)
                                          : Colors.red.shade700,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '$rel% Reliable â€¢ ${isHigh
                                          ? 'High Trust'
                                          : isGood
                                          ? 'Good Standing'
                                          : 'Needs Work'}',
                                      style: TextStyle(
                                        fontSize: 10,
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
                        ] else
                          const Text(
                            'Match organizer',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: match.id == null
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  MatchChatScreen(matchId: match.id),
                            ),
                          ),
                    icon: const Icon(
                      CupertinoIcons.chat_bubble_2_fill,
                      color: AppColors.purple,
                    ),
                  ),
                ],
              ),
            ),
            if (match.scoreStatus == 'pendingConfirmation') ...[
              const SizedBox(height: 16),
              CardBox(
                color: AppColors.purple.withValues(alpha: .06),
                borderColor: AppColors.purple.withValues(alpha: .3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(
                          CupertinoIcons.hourglass,
                          color: AppColors.purple,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Score Verification Pending',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            color: AppColors.purple,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        'Team A  ${match.score?['teamAScore'] ?? 0}  -  ${match.score?['teamBScore'] ?? 0}  Team B',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (match.scoreSubmittedBy == uid)
                      const Center(
                        child: Text(
                          'Score submitted. Awaiting confirmation from opponent to update Elo ratings.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      )
                    else if (joined) ...[
                      const Center(
                        child: Text(
                          'Your opponent submitted the final score. Please verify to finalize results & XP.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  _handleScoreConfirmation(context, false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: BorderSide(
                                  color: Colors.red.withValues(alpha: .5),
                                ),
                              ),
                              child: const Text('Dispute'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () =>
                                  _handleScoreConfirmation(context, true),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.green,
                              ),
                              child: const Text('Confirm Score'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ] else if (match.scoreStatus == 'confirmed') ...[
              const SizedBox(height: 16),
              CardBox(
                color: AppColors.green.withValues(alpha: .06),
                borderColor: AppColors.green.withValues(alpha: .3),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          CupertinoIcons.checkmark_seal_fill,
                          color: AppColors.green,
                          size: 20,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Match Result Verified',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.green,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Team A  ${match.score?['teamAScore'] ?? 0}  -  ${match.score?['teamBScore'] ?? 0}  Team B',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      icon: const Icon(
                        CupertinoIcons.chart_bar_alt_fill,
                        size: 16,
                      ),
                      label: const Text('View Results & Ratings'),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MatchResultsScreen(
                              teamAScore:
                                  (match.score?['teamAScore'] as num?)
                                      ?.toInt() ??
                                  21,
                              teamBScore:
                                  (match.score?['teamBScore'] as num?)
                                      ?.toInt() ??
                                  18,
                              ratingDelta: 16,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ] else if (match.scoreStatus == 'disputed') ...[
              const SizedBox(height: 16),
              CardBox(
                color: Colors.red.withValues(alpha: .06),
                borderColor: Colors.red.withValues(alpha: .3),
                child: Row(
                  children: const [
                    Icon(
                      CupertinoIcons.exclamationmark_triangle_fill,
                      color: Colors.red,
                      size: 22,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Score was disputed by a player. Please discuss in match chat.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (joined && match.id != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(CupertinoIcons.sportscourt, size: 18),
                label: const Text(
                  'Submit Match Score',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => _showScoreSubmitSheet(context),
              ),
            ],
            if (match.needed > 0) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(
                    CupertinoIcons.chat_bubble_fill,
                    size: 16,
                    color: Color(0xFF25D366),
                  ),
                  label: const Text(
                    'Invite Players via WhatsApp',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  onPressed: () async {
                    final waText =
                        'ðŸŽ¾ *Join my ${match.sport} match on PlayUp!*\n'
                        'ðŸ“ Court: ${match.court}\n'
                        'â° Time: ${match.time}\n'
                        'ðŸ’° Cash Fee: ${match.pricePerPlayer}\n'
                        'ðŸ‘¥ Need ${match.needed} more player${match.needed == 1 ? '' : 's'}!\n\n'
                        'ðŸ‘‰ Join match: https://play-up.fit/join/match/${match.id ?? ''}';
                    final waUri = Uri.parse(
                      'whatsapp://send?text=${Uri.encodeComponent(waText)}',
                    );
                    if (await canLaunchUrl(waUri)) {
                      await launchUrl(waUri);
                    } else {
                      await SharePlus.instance.share(
                        ShareParams(text: waText, subject: 'Join PlayUp Match'),
                      );
                    }
                  },
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (!joined)
              PrimaryButton(
                label: match.needed == 0 ? 'Match Full' : 'Request to Join',
                onPressed: match.needed == 0 || match.id == null
                    ? null
                    : () async {
                        try {
                          await AppRepository.instance.joinExistingMatch(
                            match.id!,
                          );
                          if (!context.mounted) return;
                          final updated = await FirebaseFirestore.instance
                              .collection('matches')
                              .doc(match.id!)
                              .get();
                          if (!context.mounted) return;
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => MatchDetailsScreen(
                                match: OpenMatch.fromMap(
                                  updated.data() ?? const {},
                                  id: updated.id,
                                ),
                              ),
                            ),
                          );
                        } catch (error) {
                          if (!context.mounted) return;
                          await showAdaptiveMessage(
                            context,
                            title: 'Could not join match',
                            message: error.toString().replaceFirst(
                              'DomainValidationException: ',
                              '',
                            ),
                          );
                        }
                      },
              )
            else
              const CardBox(
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.checkmark_alt_circle_fill,
                      color: AppColors.green,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'You are confirmed for this match.',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            if (joined) ...[
              const SizedBox(height: 10),
              SecondaryButton(
                label: hosting ? 'Cancel Match' : 'Leave Match',
                onPressed: () => _leaveOrCancel(context, hosting),
              ),
            ],
            if (match.id != null && joined) ...[
              const SizedBox(height: 10),
              SecondaryButton(
                label: 'Open Chat',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MatchChatScreen(matchId: match.id),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _leaveOrCancel(BuildContext context, bool hosting) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(hosting ? 'Cancel this match?' : 'Leave this match?'),
        content: Text(
          hosting
              ? 'All players will be notified. The late-cancellation policy may apply.'
              : 'Your place will become available to another player.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep match'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(hosting ? 'Cancel match' : 'Leave match'),
          ),
        ],
      ),
    );
    if (confirmed != true || match.id == null) return;
    try {
      if (hosting) {
        if (match.bookingId.isEmpty) {
          throw const DomainValidationException(
            'The linked booking could not be found. Contact support.',
          );
        }
        await AppRepository.instance.cancelBooking(
          match.bookingId,
          'Match cancelled by host',
        );
      } else {
        await AppRepository.instance.leaveExistingMatch(match.id!);
      }
      if (context.mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!context.mounted) return;
      await showAdaptiveMessage(
        context,
        title: hosting ? 'Match not cancelled' : 'Could not leave match',
        message: error.toString(),
      );
    }
  }

  Future<void> _handleScoreConfirmation(
    BuildContext context,
    bool confirm,
  ) async {
    if (match.id == null) return;
    try {
      await AppRepository.instance.confirmMatchScore(
        matchId: match.id!,
        accept: confirm,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            confirm
                ? 'Score verified! Ratings updated.'
                : 'Score marked as disputed.',
          ),
        ),
      );
      OpenMatch updatedMatch;
      try {
        final updated = await FirebaseFirestore.instance
            .collection('matches')
            .doc(match.id!)
            .get();
        if (updated.exists) {
          updatedMatch = OpenMatch.fromMap(
            updated.data() ?? const {},
            id: updated.id,
          );
        } else {
          updatedMatch = OpenMatch(
            id: match.id,
            title: match.title,
            sport: match.sport,
            host: match.host,
            court: match.court,
            time: match.time,
            skill: match.skill,
            joined: match.joined,
            needed: match.needed,
            pricePerPlayer: match.pricePerPlayer,
            ranked: match.ranked,
            playerIds: match.playerIds,
            hostId: match.hostId,
            bookingId: match.bookingId,
            startUtc: match.startUtc,
            playerNames: match.playerNames,
            latitude: match.latitude,
            longitude: match.longitude,
            scoreStatus: confirm ? 'confirmed' : 'disputed',
            scoreSubmittedBy: match.scoreSubmittedBy,
            score: match.score,
            hostReliability: match.hostReliability,
            status: 'completed',
          );
        }
      } catch (_) {
        updatedMatch = OpenMatch(
          id: match.id,
          title: match.title,
          sport: match.sport,
          host: match.host,
          court: match.court,
          time: match.time,
          skill: match.skill,
          joined: match.joined,
          needed: match.needed,
          pricePerPlayer: match.pricePerPlayer,
          ranked: match.ranked,
          playerIds: match.playerIds,
          hostId: match.hostId,
          bookingId: match.bookingId,
          startUtc: match.startUtc,
          playerNames: match.playerNames,
          latitude: match.latitude,
          longitude: match.longitude,
          scoreStatus: confirm ? 'confirmed' : 'disputed',
          scoreSubmittedBy: match.scoreSubmittedBy,
          score: match.score,
          hostReliability: match.hostReliability,
          status: 'completed',
        );
      }
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MatchDetailsScreen(match: updatedMatch),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        showAdaptiveMessage(
          context,
          title: 'Score confirmation failed',
          message: e.toString(),
        );
      }
    }
  }

  Future<void> _showScoreSubmitSheet(BuildContext context) async {
    final teamACtrl = TextEditingController(text: '0');
    final teamBCtrl = TextEditingController(text: '0');
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: .4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Submit Match Score',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              const Text(
                'Enter final scores. Opponents will confirm before Elo rating updates.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Team A Score',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: teamACtrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'VS',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Team B Score',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: teamBCtrl,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () {
                    final a = int.tryParse(teamACtrl.text.trim()) ?? 0;
                    final b = int.tryParse(teamBCtrl.text.trim()) ?? 0;
                    if (a == b) {
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Matches must have a winner in PlayUp.',
                          ),
                        ),
                      );
                      return;
                    }
                    Navigator.of(sheetContext).pop(true);
                  },
                  child: const Text(
                    'Submit for Confirmation',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (submitted == true && match.id != null && context.mounted) {
      final a = int.tryParse(teamACtrl.text.trim()) ?? 0;
      final b = int.tryParse(teamBCtrl.text.trim()) ?? 0;
      try {
        await AppRepository.instance.submitMatchScore(
          matchId: match.id!,
          teamAScore: a,
          teamBScore: b,
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Score submitted! Opponent notified for confirmation.',
            ),
          ),
        );
        OpenMatch updatedMatch;
        try {
          final updated = await FirebaseFirestore.instance
              .collection('matches')
              .doc(match.id!)
              .get();
          if (updated.exists) {
            updatedMatch = OpenMatch.fromMap(
              updated.data() ?? const {},
              id: updated.id,
            );
          } else {
            updatedMatch = OpenMatch(
              id: match.id,
              title: match.title,
              sport: match.sport,
              host: match.host,
              court: match.court,
              time: match.time,
              skill: match.skill,
              joined: match.joined,
              needed: match.needed,
              pricePerPlayer: match.pricePerPlayer,
              ranked: match.ranked,
              playerIds: match.playerIds,
              hostId: match.hostId,
              bookingId: match.bookingId,
              startUtc: match.startUtc,
              playerNames: match.playerNames,
              latitude: match.latitude,
              longitude: match.longitude,
              scoreStatus: 'pendingConfirmation',
              scoreSubmittedBy: FirebaseAuth.instance.currentUser?.uid ?? '',
              score: {'teamAScore': a, 'teamBScore': b},
              hostReliability: match.hostReliability,
              status: 'completed',
            );
          }
        } catch (_) {
          updatedMatch = OpenMatch(
            id: match.id,
            title: match.title,
            sport: match.sport,
            host: match.host,
            court: match.court,
            time: match.time,
            skill: match.skill,
            joined: match.joined,
            needed: match.needed,
            pricePerPlayer: match.pricePerPlayer,
            ranked: match.ranked,
            playerIds: match.playerIds,
            hostId: match.hostId,
            bookingId: match.bookingId,
            startUtc: match.startUtc,
            playerNames: match.playerNames,
            latitude: match.latitude,
            longitude: match.longitude,
            scoreStatus: 'pendingConfirmation',
            scoreSubmittedBy: FirebaseAuth.instance.currentUser?.uid ?? '',
            score: {'teamAScore': a, 'teamBScore': b},
            hostReliability: match.hostReliability,
            status: 'completed',
          );
        }
        if (!context.mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => MatchDetailsScreen(match: updatedMatch),
          ),
        );
      } catch (e) {
        if (context.mounted) {
          showAdaptiveMessage(
            context,
            title: 'Score Submission Failed',
            message: e.toString(),
          );
        }
      }
    }
  }
}

class CreateMatchScreen extends StatefulWidget {
  const CreateMatchScreen({super.key});

  @override
  State<CreateMatchScreen> createState() => _CreateMatchScreenState();
}

class _CreateMatchScreenState extends State<CreateMatchScreen> {
  int _step = 0;
  String _sport = 'Basketball';
  Court? _court;
  String _type = 'Casual';
  String _skill = 'Intermediate';
  int _players = 6;
  DateTime _start = DateTime.now().add(const Duration(days: 1));
  bool _externalVenue = false;
  String _communityGroupId = '';
  bool _publishing = false;
  late Future<Set<String>> _availableIds;
  late Future<bool> _canUseExternalVenues;
  final _venueNote = TextEditingController();

  static const _steps = ['Sport', 'Venue', 'Type', 'Rules'];

  @override
  void initState() {
    super.initState();
    _canUseExternalVenues = AppRepository.instance.canCreateExternalMatches();
    _refreshAvailability();
  }

  @override
  void dispose() {
    _venueNote.dispose();
    super.dispose();
  }

  void _refreshAvailability() {
    _availableIds = AppRepository.instance.availableCourtIds(
      sport: _sport,
      startUtc: _start,
    );
  }

  Future<void> _publish() async {
    setState(() => _publishing = true);
    try {
      final court = _court;
      if (!_externalVenue && court == null) {
        throw const DomainValidationException(
          'Choose an available court before publishing.',
        );
      }
      final matchId = await AppRepository.instance.createMatch(
        title: '$_sport $_type Match',
        sport: _sport,
        type: _type,
        capacity: _players,
        skill: _skill,
        court: court,
        startUtc: _start,
        externalVenue: _externalVenue,
        venueNote: _venueNote.text.trim(),
        communityGroupId: _communityGroupId,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FindingPlayersScreen(matchId: matchId),
        ),
      );
    } catch (error) {
      if (mounted) {
        await showAdaptiveMessage(
          context,
          title: 'Could not publish match',
          message: error.toString().replaceFirst(
            'DomainValidationException: ',
            '',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  void _next() {
    if (_step == 1 && !_externalVenue && _court == null) {
      showAdaptiveMessage(
        context,
        title: 'Choose a court',
        message:
            'Select one of the courts available for your sport and match time.',
      );
      return;
    }
    if (_step == 1 && _externalVenue && _venueNote.text.trim().length < 3) {
      showAdaptiveMessage(
        context,
        title: 'Add venue',
        message: 'Write the court or venue that will be used.',
      );
      return;
    }
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      _publish();
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
              title: 'Create Match',
              onBack: () => _step == 0
                  ? Navigator.of(context).pop()
                  : setState(() => _step--),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                for (var i = 0; i < _steps.length; i++)
                  Expanded(
                    child: Container(
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i <= _step ? AppColors.purple : AppColors.line,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Step ${_step + 1} of ${_steps.length}  â€¢  ${_steps[_step]}',
              style: const TextStyle(
                color: AppColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            _buildStep(),
            const SizedBox(height: 28),
            PrimaryButton(
              label: _publishing
                  ? 'Publishing...'
                  : (_step == _steps.length - 1 ? 'Publish Match' : 'Continue'),
              onPressed: _publishing ? () {} : _next,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _StepSection(
          title: 'Choose a sport',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final sport in kSportOptions)
                SelectablePill(
                  label: sport.label,
                  icon: sport.icon,
                  selected: _sport == sport.label,
                  onTap: () => setState(() {
                    _sport = sport.label;
                    _court = null;
                    _refreshAvailability();
                  }),
                ),
            ],
          ),
        );
      case 1:
        return _StepSection(
          title: 'Choose the venue',
          child: Column(
            children: [
              FutureBuilder<bool>(
                future: _canUseExternalVenues,
                builder: (context, snapshot) {
                  final canUseExternal = snapshot.data ?? false;
                  if (!canUseExternal) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _externalVenue = false),
                            child: OptionTile(
                              icon: CupertinoIcons.sportscourt,
                              title: 'PlayUp court',
                              subtitle: 'Reserve a listed court',
                              selected: !_externalVenue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _externalVenue = true;
                              _court = null;
                            }),
                            child: OptionTile(
                              icon: CupertinoIcons.text_bubble,
                              title: 'External venue',
                              subtitle: 'Add the court as a note',
                              selected: _externalVenue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              CardBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Match date and time',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      DateFormat('EEE, d MMM yyyy â€¢ h:mm a').format(_start),
                    ),
                    const SizedBox(height: 10),
                    SecondaryButton(
                      label: 'Change date and time',
                      onPressed: _chooseStart,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_externalVenue) ...[
                AppTextField(
                  controller: _venueNote,
                  label: 'Court or venue note',
                  icon: CupertinoIcons.location,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _communityGroupId.isEmpty
                      ? null
                      : _communityGroupId,
                  decoration: const InputDecoration(
                    labelText: 'Community group (optional)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('No group'),
                    ),
                    for (final group in _communityGroups)
                      DropdownMenuItem<String>(
                        value: group.id,
                        child: Text(group.name),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _communityGroupId = value ?? ''),
                ),
                const SizedBox(height: 12),
                const CardBox(
                  child: Text(
                    'This does not reserve a PlayUp court. Players will see your venue note on the match.',
                  ),
                ),
              ] else
                FutureBuilder<Set<String>>(
                  future: _availableIds,
                  builder: (context, availabilitySnapshot) {
                    if (availabilitySnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (availabilitySnapshot.hasError) {
                      return CardBox(
                        child: Column(
                          children: [
                            const Text(
                              'Court availability could not be loaded.',
                            ),
                            const SizedBox(height: 10),
                            SecondaryButton(
                              label: 'Try again',
                              onPressed: () => setState(_refreshAvailability),
                            ),
                          ],
                        ),
                      );
                    }
                    final ids = availabilitySnapshot.data ?? const <String>{};
                    return StreamBuilder<List<Court>>(
                      stream: CatalogService.instance.courts(),
                      builder: (context, courtSnapshot) {
                        final courts = (courtSnapshot.data ?? const <Court>[])
                            .where(
                              (court) =>
                                  ids.contains(court.id) &&
                                  court.isOpenAt(_start),
                            )
                            .toList();
                        if (courts.isEmpty) {
                          return const CardBox(
                            child: Text(
                              'No courts are available for this sport and time. Change the time or choose another sport.',
                            ),
                          );
                        }
                        return Column(
                          children: [
                            for (final court in courts) ...[
                              GestureDetector(
                                onTap: () => setState(() => _court = court),
                                child: OptionTile(
                                  icon: CupertinoIcons.sportscourt,
                                  title: court.name,
                                  subtitle:
                                      '${court.address.isEmpty ? court.subtitle : court.address} â€¢ ${court.price}',
                                  selected: _court?.id == court.id,
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ],
                        );
                      },
                    );
                  },
                ),
            ],
          ),
        );
      case 2:
        return _StepSection(
          title: 'Match type',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final type in const ['Casual', 'Competitive'])
                SelectablePill(
                  label: type,
                  selected: _type == type,
                  onTap: () => setState(() => _type = type),
                ),
            ],
          ),
        );
      default:
        return _StepSection(
          title: 'Player rules',
          child: CardBox(
            child: Column(
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Total players (including you)',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    CounterButton(
                      icon: CupertinoIcons.minus,
                      onTap: () => setState(
                        () => _players = _players > 2 ? _players - 1 : 2,
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
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Choose the full match capacity. One place is reserved for you.',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Skill range',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final level in const [
                      'Open to all',
                      'Beginner',
                      'Intermediate',
                      'Advanced',
                    ])
                      SelectablePill(
                        label: level,
                        selected: _skill == level,
                        onTap: () => setState(() => _skill = level),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
    }
  }

  Future<void> _chooseStart() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      initialDate: _start,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (time == null) return;
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!selected.isAfter(DateTime.now())) {
      if (!mounted) return;
      await showAdaptiveMessage(
        context,
        title: 'Choose a future time',
        message: 'Match time must be later than now.',
      );
      return;
    }
    setState(() {
      _start = selected;
      _court = null;
      _refreshAvailability();
    });
  }
}

class _StepSection extends StatelessWidget {
  const _StepSection({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey(title),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 14),
        child,
      ],
    ).animate().fadeIn(duration: 220.ms).slideX(begin: .05, end: 0);
  }
}

class PreMatchCheckInScreen extends StatelessWidget {
  const PreMatchCheckInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DarkGradient(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleIconButton(
                  icon: CupertinoIcons.arrow_left,
                  dark: true,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: 18),
                const Center(
                  child: Text(
                    'Pre-Match Check-In',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'Starts in 42 min â€¢ Infinity Sports Center',
                    style: TextStyle(color: Colors.white.withValues(alpha: .7)),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: SizedBox(
                      width: 200,
                      height: 200,
                      child: CustomPaint(
                        painter: CheckInQrPainter('PU-CHECKIN'),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Players attending',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .8),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                for (final item in const [
                  ('You', true),
                  ('Omar', true),
                  ('Zayd', true),
                  ('Mazen', false),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        const Avatar(name: 'P', size: 38),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.$1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Icon(
                          item.$2
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.clock,
                          color: item.$2 ? AppColors.green : Colors.white38,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                PrimaryButton(
                  label: "I'm Here",
                  onPressed: () {
                    HapticFeedback.mediumImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Checked in! Enjoy the game.'),
                      ),
                    );
                    Navigator.of(context).pop();
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

/// Decorative check-in QR (dark-on-white). Not a scannable code.
class CheckInQrPainter extends CustomPainter {
  CheckInQrPainter(this.seed);
  final String seed;

  @override
  void paint(Canvas canvas, Size size) {
    const cells = 19;
    final cell = size.width / cells;
    final paint = Paint()..color = AppColors.ink;
    var value = seed.hashCode;
    for (var r = 0; r < cells; r++) {
      for (var c = 0; c < cells; c++) {
        value = value * 1103515245 + 12345;
        if ((value >> 16) & 1 == 1) {
          canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell, cell), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CheckInQrPainter oldDelegate) =>
      oldDelegate.seed != seed;
}

// ---------------------------------------------------------------------------
// Booking depth: slot selection, booking details
// ---------------------------------------------------------------------------

class SlotSelectionScreen extends StatefulWidget {
  const SlotSelectionScreen({super.key, required this.court});

  final Court court;

  @override
  State<SlotSelectionScreen> createState() => _SlotSelectionScreenState();
}

class _SlotSelectionScreenState extends State<SlotSelectionScreen> {
  int _dayIndex = 0;
  int _slotIndex = 0;
  int _duration = 60;
  Set<int>? _unavailableStarts;
  String? _availabilityError;

  @override
  void initState() {
    super.initState();
    _refreshAvailability();
  }

  void _refreshAvailability() {
    final now = DateTime.now();
    final starts = _slotStarts(now);
    if (starts.isEmpty) return;
    setState(() {
      _unavailableStarts = null;
      _availabilityError = null;
    });
    AppRepository.instance
        .unavailableCourtSlotStarts(
          courtId: widget.court.id,
          rangeStartUtc: starts.first.toUtc(),
          rangeEndUtc: DateTime(
            starts.first.year,
            starts.first.month,
            starts.first.day,
            widget.court.closingHour,
          ).toUtc(),
        )
        .then((value) {
          if (!mounted) return;
          setState(() => _unavailableStarts = value);
        })
        .catchError((Object error) {
          if (!mounted) return;
          setState(() {
            _availabilityError = error.toString().replaceFirst(
              'DomainValidationException: ',
              '',
            );
            _unavailableStarts = const {};
          });
        });
  }

  List<DateTime> _slotStarts(DateTime now) {
    final day = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(days: _dayIndex));
    final startHour = widget.court.openingHour;
    final lastStart = widget.court.closingHour - 1;
    return [
      for (var hour = startHour; hour <= lastStart; hour++)
        DateTime(day.year, day.month, day.day, hour),
    ];
  }

  DateTime _selectedStart(DateTime now) {
    final starts = _slotStarts(now);
    return starts[_slotIndex.clamp(0, starts.length - 1)];
  }

  bool _isBooked(DateTime start, Set<int> unavailableStarts) {
    final end = start.add(Duration(minutes: _duration));
    final closing = DateTime(
      start.year,
      start.month,
      start.day,
      widget.court.closingHour,
    );
    if (!start.isAfter(DateTime.now()) || end.isAfter(closing)) return true;
    for (
      var cursor = start.toUtc();
      cursor.isBefore(end.toUtc());
      cursor = cursor.add(const Duration(minutes: 30))
    ) {
      if (unavailableStarts.contains(cursor.millisecondsSinceEpoch)) {
        return true;
      }
    }
    return false;
  }

  String _band(DateTime start) {
    if (start.hour < 12) return 'Morning';
    if (start.hour < 17) return 'Afternoon';
    return 'Evening';
  }

  String _priceLabel([DateTime? start]) {
    final effectiveStart = start ?? _selectedStart(DateTime.now());
    final rate = widget.court.effectiveHourlyRateMinor(effectiveStart.hour);
    final total = ((rate * _duration) / 60).round();
    if (total <= 0) return widget.court.price;
    final isPeak = widget.court.isPeakHour(effectiveStart.hour);
    return '${widget.court.currency} ${(total / 100).toStringAsFixed(2)}${isPeak ? ' â€¢ Peak' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final starts = _slotStarts(now);
    if (_slotIndex >= starts.length) {
      _slotIndex = starts.isEmpty ? 0 : starts.length - 1;
    }
    final selectedStart = _selectedStart(now);
    final selectedEnd = selectedStart.add(Duration(minutes: _duration));
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Choose Time',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            const StepIndicator(active: 0),
            const SizedBox(height: 18),
            CardBox(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  SportImageThumb(
                    size: 58,
                    gradient: widget.court.gradient,
                    imageUrl: widget.court.imageUrl,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.court.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.court.sport} - ${widget.court.price}',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Date',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 78,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 7,
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final day = now.add(Duration(days: index));
                  final selected = index == _dayIndex;
                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {
                      setState(() {
                        _dayIndex = index;
                        _slotIndex = 0;
                      });
                      _refreshAvailability();
                    },
                    child: Container(
                      width: 64,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.purple : scheme.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: selected
                              ? AppColors.purple
                              : scheme.outlineVariant,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            DateFormat('EEE').format(day),
                            style: TextStyle(
                              color: selected
                                  ? Colors.white70
                                  : scheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              color: selected ? Colors.white : scheme.onSurface,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            CardBox(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Duration',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final d in const [60, 90, 120])
                        SelectablePill(
                          label: d % 60 == 0
                              ? '${d ~/ 60} hr'
                              : '${(d / 60).toStringAsFixed(1)} hr',
                          selected: _duration == d,
                          onTap: () => setState(() => _duration = d),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Times',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MultiCourtTimelineScreen(
                          academyId: widget.court.academyId,
                          initialCourtId: widget.court.id,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(CupertinoIcons.square_grid_2x2, size: 16),
                  label: const Text(
                    'All Courts Grid',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final unavailable = _unavailableStarts ?? const <int>{};
                final groups = <String, List<int>>{};
                for (var i = 0; i < starts.length; i++) {
                  groups.putIfAbsent(_band(starts[i]), () => []).add(i);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 10),
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final i in entry.value)
                            Builder(
                              builder: (context) {
                                final booked = _isBooked(
                                  starts[i],
                                  unavailable,
                                );
                                final slotEnd = starts[i].add(
                                  Duration(minutes: _duration),
                                );
                                final closing = DateTime(
                                  starts[i].year,
                                  starts[i].month,
                                  starts[i].day,
                                  widget.court.closingHour,
                                );
                                final unavailableLabel =
                                    !starts[i].isAfter(DateTime.now())
                                    ? 'Past'
                                    : slotEnd.isAfter(closing)
                                    ? 'Unavailable'
                                    : 'Booked';
                                return GestureDetector(
                                  onTap:
                                      booked ||
                                          _unavailableStarts == null ||
                                          _availabilityError != null
                                      ? null
                                      : () => setState(() => _slotIndex = i),
                                  child: SlotChip(
                                    time: DateFormat.jm().format(starts[i]),
                                    price: _priceLabel(starts[i]),
                                    selected: i == _slotIndex && !booked,
                                    booked: booked,
                                    unavailableLabel: unavailableLabel,
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_unavailableStarts == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (_availabilityError != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          _availabilityError!,
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 112),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: CardBox(
          radius: 22,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEE, d MMM').format(selectedStart),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${DateFormat.jm().format(selectedStart)} - ${DateFormat.jm().format(selectedEnd)}',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 142,
                child: PrimaryButton(
                  label: 'Next\n${_priceLabel()}',
                  onPressed:
                      _unavailableStarts == null ||
                          _availabilityError != null ||
                          _isBooked(selectedStart, _unavailableStarts!)
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => BookingSetupScreen(
                                court: widget.court,
                                startUtc: selectedStart.toUtc(),
                                endUtc: selectedEnd.toUtc(),
                              ),
                            ),
                          );
                        },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BookingDetailsScreen extends StatelessWidget {
  const BookingDetailsScreen({
    super.key,
    required this.bookingId,
    required this.booking,
    required this.court,
  });

  final String bookingId;
  final Map<String, dynamic> booking;
  final Court court;

  @override
  Widget build(BuildContext context) {
    final start = (booking['startUtc'] as Timestamp?)?.toDate().toLocal();
    final end = (booking['endUtc'] as Timestamp?)?.toDate().toLocal();
    final status = (booking['status'] ?? 'pending').toString();
    final paymentStatus = (booking['paymentStatus'] ?? 'pending').toString();
    final currency = (booking['currency'] ?? court.currency).toString();
    final totalMinor = (booking['totalMinor'] as num?)?.toInt() ?? 0;
    final matchId = booking['matchId']?.toString() ?? '';
    final isOwner = booking['userId'] == FirebaseAuth.instance.currentUser?.uid;
    final canCancel =
        isOwner && const ['pending', 'confirmed'].contains(status);
    final dateLabel = start == null
        ? 'Time pending'
        : DateFormat('EEEE, d MMMM y').format(start);
    final timeLabel = start == null
        ? 'Time pending'
        : '${DateFormat.jm().format(start)}${end == null ? '' : ' â€“ ${DateFormat.jm().format(end)}'}';
    final paymentLabel = paymentStatus == 'collected'
        ? 'Collected at venue'
        : paymentStatus == 'notRequired'
        ? 'No payment required'
        : 'Pay at venue Â· $currency ${(totalMinor / 100).toStringAsFixed(2)}';
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Booking Details',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            CardBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Booking Summary',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  DetailRow(label: 'Court', value: court.name),
                  DetailRow(label: 'Date', value: dateLabel),
                  DetailRow(label: 'Time', value: timeLabel),
                  DetailRow(label: 'Payment', value: paymentLabel),
                  DetailRow(
                    label: 'Status',
                    value: status.isEmpty
                        ? 'Pending'
                        : '${status[0].toUpperCase()}${status.substring(1)}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Builder(
              builder: (context) {
                final participants = List<String>.from(
                  booking['participants'] as List? ?? [booking['userId'] ?? ''],
                );
                final cashPaidPlayers = Set<String>.from(
                  booking['cashPaidPlayers'] as List? ??
                      [booking['userId'] ?? ''],
                );
                final splitCount = participants.isEmpty
                    ? 1
                    : participants.length;
                final perPlayerMinor = (totalMinor / splitCount).round();
                final perPlayerAmount = (perPlayerMinor / 100).toStringAsFixed(
                  2,
                );

                return CardBox(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Cash Split Tracker',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.green.withValues(alpha: .15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$currency $perPlayerAmount / player',
                              style: const TextStyle(
                                color: AppColors.green,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${cashPaidPlayers.length}/$splitCount players collected cash',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (var i = 0; i < participants.length; i++) ...[
                        Builder(
                          builder: (context) {
                            final pUid = participants[i];
                            final isHost = pUid == booking['userId'];
                            return StatefulBuilder(
                              builder: (context, setPlayerState) {
                                final currentPaid = cashPaidPlayers.contains(
                                  pUid,
                                );
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundColor: currentPaid
                                            ? AppColors.green.withValues(
                                                alpha: .2,
                                              )
                                            : Colors.grey.withValues(alpha: .2),
                                        child: Icon(
                                          currentPaid
                                              ? CupertinoIcons.check_mark
                                              : CupertinoIcons.clock,
                                          size: 14,
                                          color: currentPaid
                                              ? AppColors.green
                                              : Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              isHost
                                                  ? 'Organizer (Host)'
                                                  : 'Player ${i + 1}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 13,
                                              ),
                                            ),
                                            Text(
                                              currentPaid
                                                  ? 'Cash collected'
                                                  : 'Pending cash collection',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: currentPaid
                                                    ? AppColors.green
                                                    : AppColors.muted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isOwner && !isHost)
                                        OutlinedButton(
                                          onPressed: () async {
                                            final nextState = !currentPaid;
                                            setPlayerState(() {
                                              if (nextState) {
                                                cashPaidPlayers.add(pUid);
                                              } else {
                                                cashPaidPlayers.remove(pUid);
                                              }
                                            });
                                            try {
                                              await AppRepository.instance
                                                  .updateCashSplitStatus(
                                                    bookingId: bookingId,
                                                    playerId: pUid,
                                                    paid: nextState,
                                                  );
                                            } catch (e) {
                                              setPlayerState(() {
                                                if (!nextState) {
                                                  cashPaidPlayers.add(pUid);
                                                } else {
                                                  cashPaidPlayers.remove(pUid);
                                                }
                                              });
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Update failed: $e',
                                                    ),
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 4,
                                            ),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
                                          child: Text(
                                            currentPaid
                                                ? 'Mark Pending'
                                                : 'Mark Paid',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        )
                                      else
                                        Text(
                                          currentPaid ? 'PAID' : 'PENDING',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 12,
                                            color: currentPaid
                                                ? AppColors.green
                                                : AppColors.muted,
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                        if (i < participants.length - 1)
                          const Divider(height: 12),
                      ],
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(
                            CupertinoIcons.chat_bubble_fill,
                            size: 16,
                            color: Color(0xFF25D366),
                          ),
                          label: const Text(
                            'Share Cash Breakdown on WhatsApp',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          onPressed: () async {
                            final waText =
                                'ðŸ’µ *PlayUp Cash Split - ${court.name}*\n'
                                'ðŸ“… Date: $dateLabel\n'
                                'â° Time: $timeLabel\n'
                                'ðŸ’° Total Court Fee: $currency ${(totalMinor / 100).toStringAsFixed(2)}\n'
                                'ðŸ‘¥ Share per Player: $currency $perPlayerAmount\n\n'
                                'Please bring exact cash to the court! ðŸ™Œ';
                            final waUri = Uri.parse(
                              'whatsapp://send?text=${Uri.encodeComponent(waText)}',
                            );
                            if (await canLaunchUrl(waUri)) {
                              await launchUrl(waUri);
                            } else {
                              await SharePlus.instance.share(
                                ShareParams(
                                  text: waText,
                                  subject: 'Cash Split Breakdown',
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            const CardBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cancellation policy',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Cancellation is free at least 6 hours before start. A 50% late-cancellation fee may be due at the venue.',
                    style: TextStyle(color: AppColors.muted, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (matchId.isNotEmpty) ...[
              PrimaryButton(
                label: 'Open Match Chat',
                icon: CupertinoIcons.chat_bubble_2,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MatchChatScreen(matchId: matchId),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SecondaryButton(
              label: 'Get Directions',
              onPressed: () => _openDirections(context),
            ),
            if (canCancel) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: () async {
                    final cancelled = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => CancelBookingScreen(
                          bookingId: bookingId,
                          startUtc: (booking['startUtc'] as Timestamp?)
                              ?.toDate(),
                          totalMinor: totalMinor,
                          currency: currency,
                        ),
                      ),
                    );
                    if (cancelled == true && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Cancel Booking',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openDirections(BuildContext context) async {
    try {
      final courtSnapshot = await FirebaseFirestore.instance
          .collection('courts')
          .doc(court.id)
          .get();
      final data = courtSnapshot.data() ?? const <String, dynamic>{};
      final latitude = (data['latitude'] as num?)?.toDouble();
      final longitude = (data['longitude'] as num?)?.toDouble();
      final address = (data['address'] ?? court.address).toString().trim();
      final googleMaps = MapLinks.googleDirections(
        name: court.name,
        address: address,
        latitude: latitude,
        longitude: longitude,
      );
      final osmMap = MapLinks.openStreetMap(
        name: court.name,
        address: address,
        latitude: latitude,
        longitude: longitude,
      );
      if (googleMaps == null || osmMap == null) {
        throw const DomainValidationException(
          'Directions are not configured for this court.',
        );
      }
      var opened = false;
      try {
        opened = await launchUrl(
          googleMaps,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        // Some devices throw when no Google Maps handler is installed.
      }
      if (!opened &&
          !await launchUrl(osmMap, mode: LaunchMode.externalApplication)) {
        throw const DomainValidationException('No maps app is available.');
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is DomainValidationException
                ? error.message
                : 'Directions could not be opened.',
          ),
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Settings pages: notifications & privacy
// ---------------------------------------------------------------------------

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  static const _fieldNames = <String, String>{
    'Booking reminders': 'bookingReminders',
    'Match invites': 'matchInvites',
    'Rewards & offers': 'rewardsAndOffers',
    'Academy announcements': 'academyAnnouncements',
    'System updates': 'systemUpdates',
  };
  final _values = <String, bool>{
    'Booking reminders': true,
    'Match invites': true,
    'Rewards & offers': true,
    'Academy announcements': false,
    'System updates': true,
  };
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final data =
          (await FirebaseFirestore.instance.collection('users').doc(uid).get())
              .data();
      final saved = Map<String, dynamic>.from(
        data?['notificationPreferences'] as Map? ?? const {},
      );
      for (final entry in _fieldNames.entries) {
        if (saved[entry.value] is bool) {
          _values[entry.key] = saved[entry.value] as bool;
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(String label, bool value) async {
    final previous = _values[label] ?? true;
    setState(() => _values[label] = value);
    try {
      await AppRepository.instance.updatePreferences(
        notifications: {
          for (final entry in _fieldNames.entries)
            entry.value: _values[entry.key] ?? true,
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _values[label] = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preference was not saved: $error')),
      );
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
              title: 'Notifications',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              CardBox(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  children: [
                    for (final entry in _values.entries)
                      SwitchListTile.adaptive(
                        value: entry.value,
                        activeThumbColor: AppColors.purple,
                        title: Text(
                          entry.key,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        onChanged: (v) => _save(entry.key, v),
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

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  bool _publicProfile = true;
  bool _showActivity = true;
  bool _allowInvites = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final data =
          (await FirebaseFirestore.instance.collection('users').doc(uid).get())
              .data();
      final saved = Map<String, dynamic>.from(
        data?['privacyPreferences'] as Map? ?? const {},
      );
      _publicProfile = saved['publicProfile'] as bool? ?? true;
      _showActivity = saved['showActivity'] as bool? ?? true;
      _allowInvites = saved['allowInvites'] as bool? ?? true;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save({
    bool? publicProfile,
    bool? showActivity,
    bool? allowInvites,
  }) async {
    final previous = (_publicProfile, _showActivity, _allowInvites);
    setState(() {
      if (publicProfile != null) _publicProfile = publicProfile;
      if (showActivity != null) _showActivity = showActivity;
      if (allowInvites != null) _allowInvites = allowInvites;
    });
    try {
      await AppRepository.instance.updatePreferences(
        privacy: {
          'publicProfile': _publicProfile,
          'showActivity': _showActivity,
          'allowInvites': _allowInvites,
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _publicProfile = previous.$1;
        _showActivity = previous.$2;
        _allowInvites = previous.$3;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Privacy setting was not saved: $error')),
      );
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
              title: 'Privacy',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              CardBox(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      value: _publicProfile,
                      activeThumbColor: AppColors.purple,
                      title: const Text(
                        'Public profile',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: const Text('Discoverable by other players'),
                      onChanged: (v) => _save(publicProfile: v),
                    ),
                    SwitchListTile.adaptive(
                      value: _showActivity,
                      activeThumbColor: AppColors.purple,
                      title: const Text(
                        'Show activity',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: const Text('Display recent matches on profile'),
                      onChanged: (v) => _save(showActivity: v),
                    ),
                    SwitchListTile.adaptive(
                      value: _allowInvites,
                      activeThumbColor: AppColors.purple,
                      title: const Text(
                        'Allow match invites',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: const Text('Let players invite you to matches'),
                      onChanged: (v) => _save(allowInvites: v),
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

// ---------------------------------------------------------------------------
// Academy Owner mode
// ---------------------------------------------------------------------------

class AcademyModeDashboard extends StatefulWidget {
  const AcademyModeDashboard({super.key, this.standalone = false});
  final bool standalone;

  @override
  State<AcademyModeDashboard> createState() => _AcademyModeDashboardState();
}

class _AcademyModeDashboardState extends State<AcademyModeDashboard> {
  late Future<OwnerScope> _scopeFuture;

  @override
  void initState() {
    super.initState();
    _scopeFuture = AcademyService.instance.ownerScope();
  }

  void _retryScope() {
    setState(() => _scopeFuture = AcademyService.instance.ownerScope());
  }

  String _scopeError(Object? error) {
    if (error is StateError) {
      return switch (error.message) {
        'Sign in is required.' => 'Your session ended. Sign in again to open the academy workspace.',
        'No academy is assigned to this account.' => 'This owner account is not linked to an academy yet. Ask the PlayUp administrator to assign the academy, then try again.',
        'This court-owner account needs one assigned court.' => 'This court-owner account needs one assigned court. Ask the academy administrator to assign it, then try again.',
        _ => error.message.toString(),
      };
    }
    return 'We could not load the academy assignment. Check your connection and access, then try again.';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OwnerScope>(
      future: _scopeFuture,
      builder: (context, scopeSnapshot) {
        if (scopeSnapshot.hasError) {
          return Scaffold(
            body: AppScrollPage(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.business_outlined, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'Academy workspace unavailable',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _scopeError(scopeSnapshot.error),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      PrimaryButton(
                        label: 'Try again',
                        icon: Icons.refresh,
                        onPressed: _retryScope,
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
          );
        }
        if (!scopeSnapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final scope = scopeSnapshot.data!;
        final isCourtOwner = scope.isCourtOwner;
        return Scaffold(
          body: AppScrollPage(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PageTopBar(
                  title: isCourtOwner
                      ? 'Court Operations'
                      : 'Academy Operations',
                  onBack: widget.standalone
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
                const SizedBox(height: 16),
                Text(
                  'Manage todayâ€™s activity, then keep your venue ready for the next booking.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                if (scope.canManageBookings) ...[
                  PrimaryButton(
                    label: 'Open bookings & check-in',
                    icon: Icons.event_available_outlined,
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LiveBookingManagementScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const LiveAcademyDashboardSummary(),
                const SizedBox(height: 20),
                const SectionHeader(title: 'Your venue'),
                const SizedBox(height: 12),
                if (scope.canManageAcademy)
                  SettingsTile(
                    icon: CupertinoIcons.building_2_fill,
                    title: 'Academy profile',
                    subtitle:
                        'Photos, contact details, sports and training packages',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AcademyProfileManagementScreen(),
                      ),
                    ),
                  ),
                if (scope.canManageStaff)
                  SettingsTile(
                    icon: CupertinoIcons.person_2_fill,
                    title: 'Your team',
                    subtitle: 'Staff accounts and permissions',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AcademyStaffManagementScreen(),
                      ),
                    ),
                  ),
                if (scope.canManageCourts)
                  SettingsTile(
                    icon: CupertinoIcons.sportscourt,
                    title: 'Courts & availability',
                    subtitle: 'Prices, opening hours and maintenance',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LiveCourtManagementScreen(),
                      ),
                    ),
                  ),
                if (scope.canManageBookings)
                  SettingsTile(
                    icon: CupertinoIcons.calendar,
                    title: 'Bookings & check-in',
                    subtitle: 'Confirm, check in and collect payment',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LiveBookingManagementScreen(),
                      ),
                    ),
                  ),
                if (scope.canManageCatalog)
                  SettingsTile(
                    icon: CupertinoIcons.gift,
                    title: 'Offers',
                    subtitle: 'Rewards and incentives for your players',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const OffersManagementScreen(),
                      ),
                    ),
                  ),
                if (scope.canManageCatalog)
                  SettingsTile(
                    icon: CupertinoIcons.rosette,
                    title: 'Events',
                    subtitle: 'Activities at your academy',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const EventManagementScreen(),
                      ),
                    ),
                  ),
                if (scope.canManageTournaments)
                  SettingsTile(
                    icon: CupertinoIcons.flag_fill,
                    title: 'Create Tournament',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CreateTournamentScreen(),
                      ),
                    ),
                  ),
                if (scope.canViewAnalytics)
                  SettingsTile(
                    icon: CupertinoIcons.chart_bar_alt_fill,
                    title: 'Reports',
                    subtitle: 'Bookings, completed sessions and revenue',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LiveAcademyAnalyticsScreen(),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                const SectionHeader(title: 'Workspace preferences'),
                const SizedBox(height: 12),
                const ThemeModeTile(),
                if (scope.isAcademyOwner)
                  SettingsTile(
                    icon: CupertinoIcons.square_grid_2x2,
                    title: 'Customize Dashboard',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CustomDashboard(
                          scope: 'academy',
                          available: academyWidgets,
                        ),
                      ),
                    ),
                  ),
                if (widget.standalone) ...[
                  const SizedBox(height: 18),
                  SecondaryButton(
                    label: 'Sign out',
                    onPressed: () async => SocialAuth.signOutEverywhere(),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class LiveAcademyDashboardSummary extends StatelessWidget {
  const LiveAcademyDashboardSummary({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: AcademyService.instance.academyId(),
    builder: (context, id) {
      if (!id.hasData) return const Center(child: CircularProgressIndicator());
      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: AcademyService.instance.academy(id.data!),
        builder: (context, academy) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: AcademyService.instance.bookings(id.data!),
            builder: (context, bookings) {
              final rows =
                  bookings.data?.docs.map((d) => d.data()).toList() ?? [];
              final now = DateTime.now();
              final today = rows.where((b) {
                final date = (b['startUtc'] as Timestamp?)?.toDate().toLocal();
                return date != null &&
                    date.year == now.year &&
                    date.month == now.month &&
                    date.day == now.day;
              }).toList();
              final revenue = rows
                  .where((b) => b['paymentStatus'] == 'collected')
                  .fold<int>(
                    0,
                    (total, b) =>
                        total +
                        (b['cashCollectedMinor'] as num? ??
                                b['totalMinor'] as num? ??
                                0)
                            .toInt(),
                  );
              final pending = rows
                  .where((b) => ['pending', 'confirmed'].contains(b['status']))
                  .length;
              return Column(
                children: [
                  CardBox(
                    color: AppColors.dark,
                    borderColor: AppColors.dark,
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          academy.data?.data()?['name']?.toString() ??
                              'Your academy',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Live owner dashboard',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent:
                        170 *
                        MediaQuery.textScalerOf(
                          context,
                        ).scale(1).clamp(1.0, 2.0),
                    children: [
                      _OwnerMetric(
                        label: "Today's bookings",
                        value: '${today.length}',
                        icon: CupertinoIcons.calendar_today,
                      ),
                      _OwnerMetric(
                        label: 'Cash collected',
                        value:
                            '${academy.data?.data()?['currency'] ?? 'JOD'} ${(revenue / 100).toStringAsFixed(2)}',
                        icon: CupertinoIcons.money_dollar_circle,
                      ),
                      _OwnerMetric(
                        label: 'All bookings',
                        value: '${rows.length}',
                        icon: CupertinoIcons.chart_pie,
                      ),
                      _OwnerMetric(
                        label: 'Pending actions',
                        value: '$pending',
                        icon: CupertinoIcons.person_badge_plus,
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );
}

class _OwnerMetric extends StatelessWidget {
  const _OwnerMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.purple, size: 24),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
          ),
          Text(
            label,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class CourtManagementScreen extends StatelessWidget {
  const CourtManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.purple,
        onPressed: () => _showAddCourt(context),
        icon: const Icon(CupertinoIcons.add, color: Colors.white),
        label: const Text(
          'Add Court',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
      ),
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Court Management',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<Court>>(
              stream: CatalogService.instance.courts(),
              builder: (context, snapshot) {
                final courts = snapshot.data ?? const <Court>[];
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (courts.isEmpty) {
                  return const CardBox(
                    child: Text('No courts have been configured.'),
                  );
                }
                return Column(
                  children: [
                    for (final court in courts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: CardBox(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      court.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    Text(
                                      '${court.subtitle} â€¢ ${court.price}',
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    _showAddCourt(context, name: court.name),
                                icon: const Icon(
                                  CupertinoIcons.pencil,
                                  color: AppColors.purple,
                                ),
                              ),
                            ],
                          ),
                        ),
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

  void _showAddCourt(BuildContext context, {String? name}) {
    final controller = TextEditingController(text: name);
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
              name == null ? 'Add Court' : 'Edit Court',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: controller,
              label: 'Court name',
              icon: CupertinoIcons.sportscourt,
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Save Court',
              onPressed: () {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Saved ${controller.text}.')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class BookingManagementScreen extends StatefulWidget {
  const BookingManagementScreen({super.key});

  @override
  State<BookingManagementScreen> createState() =>
      _BookingManagementScreenState();
}

class _BookingManagementScreenState extends State<BookingManagementScreen> {
  int _tab = 0;
  static const _tabs = ['Today', 'Upcoming', 'Completed'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Bookings',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (var i = 0; i < _tabs.length; i++) ...[
                  SelectablePill(
                    label: _tabs[i],
                    selected: _tab == i,
                    onTap: () => setState(() => _tab = i),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 18),
            for (final booking in const [
              ('Ahmad S.', 'Basketball â€¢ 6:00 PM', 'Court 1'),
              ('Lina H.', 'Padel â€¢ 7:30 PM', 'Court 3'),
              ('Omar K.', 'Volleyball â€¢ 9:00 PM', 'Court 2'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: CardBox(
                  child: Row(
                    children: [
                      const Avatar(name: 'A', size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              booking.$1,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              '${booking.$2} â€¢ ${booking.$3}',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_tab == 0)
                        FilledButton(
                          onPressed: () =>
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Player checked in.'),
                                ),
                              ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.purple,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          child: const Text(
                            'Check in',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        )
                      else
                        Text(
                          _tab == 1 ? 'Confirmed' : 'Done',
                          style: const TextStyle(
                            color: AppColors.green,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
