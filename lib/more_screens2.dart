import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import 'main.dart';
import 'more_screens.dart';
import 'more_screens3.dart';
import 'more_screens4.dart';
import 'custom_dashboard.dart';
import 'academy_live_screens.dart';
import 'academy_service.dart';

/// Live open matches from Firestore, falling back to bundled samples when
/// none exist yet (e.g. a brand new project with no matches created).
Stream<List<OpenMatch>> openMatchesStream() => FirebaseFirestore.instance
    .collection('matches')
    .where('status', isEqualTo: 'open')
    .snapshots()
    .map(
      (s) => s.docs.map((d) => OpenMatch.fromMap(d.data(), id: d.id)).toList(),
    );

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
  });

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
          ? '${d['currency'] ?? 'AED'} ${(totalMinor / 100 / capacity).toStringAsFixed(2)}'
          : 'Cash at venue',
      ranked: d['ranked'] == true,
    );
  }

  final String title;
  final String? id;
  final String sport;
  final String host;
  final String court;
  final String time;
  final String skill;
  final int joined;
  final int needed;
  final String pricePerPlayer;
  final bool ranked;
}

const kOpenMatches = <OpenMatch>[
  OpenMatch(
    title: 'Court Commanders 5v5',
    sport: 'Basketball',
    host: 'Omar K.',
    court: 'Infinity Sports Center',
    time: 'Today, 8:00 PM',
    skill: 'Intermediate',
    joined: 7,
    needed: 3,
    pricePerPlayer: 'AED 52.5',
    ranked: true,
  ),
  OpenMatch(
    title: 'Padel Night Doubles',
    sport: 'Padel',
    host: 'Sara N.',
    court: 'Padel Pro Club',
    time: 'Today, 9:30 PM',
    skill: 'Casual',
    joined: 2,
    needed: 2,
    pricePerPlayer: 'AED 60',
    ranked: false,
  ),
  OpenMatch(
    title: 'Volleyball Open Court',
    sport: 'Volleyball',
    host: 'Zayd A.',
    court: 'Dubai Sports World',
    time: 'Tomorrow, 6:00 PM',
    skill: 'Advanced',
    joined: 8,
    needed: 4,
    pricePerPlayer: 'AED 40',
    ranked: true,
  ),
  OpenMatch(
    title: 'Friday Football 7s',
    sport: 'Football',
    host: 'Mazen R.',
    court: 'Skyline Sports',
    time: 'Fri, 7:00 PM',
    skill: 'Competitive',
    joined: 10,
    needed: 4,
    pricePerPlayer: 'AED 45',
    ranked: false,
  ),
];

class OpenMatchesScreen extends StatefulWidget {
  const OpenMatchesScreen({super.key});

  @override
  State<OpenMatchesScreen> createState() => _OpenMatchesScreenState();
}

class _OpenMatchesScreenState extends State<OpenMatchesScreen> {
  String _filter = 'All';
  static const _filters = [
    'All',
    'Basketball',
    'Padel',
    'Volleyball',
    'Ranked',
  ];

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
              height: 42,
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
                final source = snapshot.data ?? const <OpenMatch>[];
                final matches = source.where((m) {
                  if (_filter == 'All') return true;
                  if (_filter == 'Ranked') return m.ranked;
                  return m.sport == _filter;
                }).toList();
                if (matches.isEmpty) {
                  return EmptyState(
                    icon: CupertinoIcons.search,
                    title: 'No matches found',
                    message: 'Try a different filter or create your own match.',
                    action: 'Create Match',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CreateMatchScreen(),
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final match in matches)
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
      ),
    );
  }
}

class OpenMatchCard extends StatelessWidget {
  const OpenMatchCard({super.key, required this.match});

  final OpenMatch match;

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
                    '${match.court}  •  ${match.time}',
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
                  label: '${match.joined} joined • needs ${match.needed}',
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
                  const Avatar(name: 'P', size: 46),
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
                        const Text(
                          'Level 11 • 98% reliability',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MatchChatScreen(matchId: match.id),
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
            const SizedBox(height: 24),
            PrimaryButton(
              label: match.needed == 0 ? 'Match Full' : 'Request to Join',
              onPressed: match.needed == 0 || match.id == null
                  ? null
                  : () async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await AppRepository.instance.joinExistingMatch(
                          match.id!,
                        );
                        if (!context.mounted) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MatchFoundScreen(),
                          ),
                        );
                      } catch (error) {
                        messenger.showSnackBar(
                          SnackBar(content: Text(error.toString())),
                        );
                      }
                    },
            ),
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
        ),
      ),
    );
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
  String _courtChoice = 'Book a new court';
  String _type = 'Casual';
  String _skill = 'Intermediate';
  int _players = 6;
  bool _publishing = false;

  static const _steps = ['Sport', 'Court', 'Type', 'Rules'];

  Future<void> _publish() async {
    setState(() => _publishing = true);
    try {
      final matchId = await AppRepository.instance.joinMatch(
        '$_sport $_type Match',
        sport: _sport,
        type: _type,
        neededPlayers: _players,
        skill: _skill,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => FindingPlayersScreen(matchId: matchId),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  void _next() {
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
              'Step ${_step + 1} of ${_steps.length}  •  ${_steps[_step]}',
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
                  onTap: () => setState(() => _sport = sport.label),
                ),
            ],
          ),
        );
      case 1:
        return _StepSection(
          title: 'Choose a court',
          child: Column(
            children: [
              for (final choice in const [
                'Book a new court',
                'Use an existing booking',
                'Let players vote on the court',
              ]) ...[
                GestureDetector(
                  onTap: () => setState(() => _courtChoice = choice),
                  child: OptionTile(
                    icon: CupertinoIcons.sportscourt,
                    title: choice,
                    subtitle: 'Tap to select',
                    selected: _courtChoice == choice,
                  ),
                ),
                const SizedBox(height: 10),
              ],
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
              for (final type in const [
                'Casual',
                'Ranked',
                'Training',
                'Tournament',
              ])
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
                        'Players needed',
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
                    'Skill range',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final level in kSkillLevels)
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
                    'Starts in 42 min • Infinity Sports Center',
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
  int _slotIndex = 2;
  int _duration = 60;

  static const _slots = [
    '6:00 PM',
    '7:00 PM',
    '8:00 PM',
    '9:00 PM',
    '10:00 PM',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Select Slot',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            const Text(
              'Choose a date',
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
                  const weekday = [
                    'Mon',
                    'Tue',
                    'Wed',
                    'Thu',
                    'Fri',
                    'Sat',
                    'Sun',
                  ];
                  final selected = index == _dayIndex;
                  return GestureDetector(
                    onTap: () => setState(() => _dayIndex = index),
                    child: Container(
                      width: 58,
                      decoration: BoxDecoration(
                        color: selected ? AppColors.purple : AppColors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: selected ? AppColors.purple : AppColors.line,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            weekday[day.weekday - 1],
                            style: TextStyle(
                              color: selected
                                  ? Colors.white70
                                  : AppColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              color: selected ? Colors.white : AppColors.ink,
                              fontSize: 18,
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
            const SizedBox(height: 22),
            const Text(
              'Available times',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < _slots.length; i++)
                  GestureDetector(
                    onTap: () => setState(() => _slotIndex = i),
                    child: SlotChip(
                      time: _slots[i],
                      price: widget.court.price.split(' ').take(2).join(' '),
                      selected: i == _slotIndex,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              'Duration',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final d in const [30, 60, 90, 120])
                  SelectablePill(
                    label: '$d min',
                    selected: _duration == d,
                    onTap: () => setState(() => _duration = d),
                  ),
              ],
            ),
            const SizedBox(height: 26),
            CardBox(
              child: Column(
                children: [
                  DetailRow(label: 'Court', value: widget.court.name),
                  DetailRow(
                    label: 'Time',
                    value: '${_slots[_slotIndex]} • $_duration min',
                  ),
                  DetailRow(label: 'Price', value: widget.court.price),
                ],
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Continue',
              onPressed: () {
                final day = DateTime(
                  now.year,
                  now.month,
                  now.day,
                ).add(Duration(days: _dayIndex));
                final start = DateTime(
                  day.year,
                  day.month,
                  day.day,
                  18 + _slotIndex,
                );
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => BookingSetupScreen(
                      court: widget.court,
                      startUtc: start.toUtc(),
                      endUtc: start.add(Duration(minutes: _duration)).toUtc(),
                    ),
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

class BookingDetailsScreen extends StatelessWidget {
  const BookingDetailsScreen({super.key, required this.court});

  final Court court;

  @override
  Widget build(BuildContext context) {
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
                  const DetailRow(label: 'Date', value: 'Today, 20 May'),
                  const DetailRow(label: 'Time', value: '8:00 PM - 9:00 PM'),
                  const DetailRow(label: 'Payment', value: 'Paid • Visa 4242'),
                  const DetailRow(label: 'Status', value: 'Confirmed'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Players',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: const [
                Avatar(name: 'A', size: 44),
                Avatar(name: 'O', size: 44),
                Avatar(name: 'Z', size: 44),
                Avatar(name: 'M', size: 44),
              ],
            ),
            const SizedBox(height: 20),
            CardBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Cancellation policy',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Free cancellation up to 6 hours before start. After that, 50% of the court fee applies.',
                    style: TextStyle(color: AppColors.muted, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'QR Check-In',
              icon: CupertinoIcons.qrcode,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PreMatchCheckInScreen(),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SecondaryButton(
              label: 'View Match Result',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MatchResultsScreen()),
              ),
            ),
            const SizedBox(height: 10),
            SecondaryButton(
              label: 'Get Directions',
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Opening maps directions...')),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CancelBookingScreen(),
                  ),
                ),
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
        ),
      ),
    );
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
  final _values = <String, bool>{
    'Booking reminders': true,
    'Match invites': true,
    'Rewards & offers': true,
    'Academy announcements': false,
    'System updates': true,
  };

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
                      onChanged: (v) => setState(() => _values[entry.key] = v),
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
                    onChanged: (v) => setState(() => _publicProfile = v),
                  ),
                  SwitchListTile.adaptive(
                    value: _showActivity,
                    activeThumbColor: AppColors.purple,
                    title: const Text(
                      'Show activity',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text('Display recent matches on profile'),
                    onChanged: (v) => setState(() => _showActivity = v),
                  ),
                  SwitchListTile.adaptive(
                    value: _allowInvites,
                    activeThumbColor: AppColors.purple,
                    title: const Text(
                      'Allow match invites',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: const Text('Let players invite you to matches'),
                    onChanged: (v) => setState(() => _allowInvites = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SecondaryButton(
              label: 'Blocked Players',
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No blocked players.')),
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

class AcademyModeDashboard extends StatelessWidget {
  const AcademyModeDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Academy Mode',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            const LiveAcademyDashboardSummary(),
            const SizedBox(height: 20),
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
            SettingsTile(
              icon: CupertinoIcons.building_2_fill,
              title: 'Academy Profile & Contact',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AcademyProfileManagementScreen(),
                ),
              ),
            ),
            SettingsTile(
              icon: CupertinoIcons.person_2_fill,
              title: 'Staff & Permissions',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AcademyStaffManagementScreen(),
                ),
              ),
            ),
            SettingsTile(
              icon: CupertinoIcons.sportscourt,
              title: 'Court Management',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LiveCourtManagementScreen(),
                ),
              ),
            ),
            SettingsTile(
              icon: CupertinoIcons.calendar,
              title: 'Booking Management',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LiveBookingManagementScreen(),
                ),
              ),
            ),
            SettingsTile(
              icon: CupertinoIcons.gift,
              title: 'Offers Management',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const OffersManagementScreen(),
                ),
              ),
            ),
            SettingsTile(
              icon: CupertinoIcons.rosette,
              title: 'Event Management',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const EventManagementScreen(),
                ),
              ),
            ),
            SettingsTile(
              icon: CupertinoIcons.chart_bar_alt_fill,
              title: 'Analytics',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LiveAcademyAnalyticsScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
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
                        total + (b['totalMinor'] as num? ?? 0).toInt(),
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
                    childAspectRatio: 1.5,
                    children: [
                      _OwnerMetric(
                        label: "Today's bookings",
                        value: '${today.length}',
                        icon: CupertinoIcons.calendar_today,
                      ),
                      _OwnerMetric(
                        label: 'Cash collected',
                        value: 'AED ${(revenue / 100).toStringAsFixed(0)}',
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
                              '${court.subtitle} • ${court.price}',
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
              ('Ahmad S.', 'Basketball • 6:00 PM', 'Court 1'),
              ('Lina H.', 'Padel • 7:30 PM', 'Court 3'),
              ('Omar K.', 'Volleyball • 9:00 PM', 'Court 2'),
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
                              '${booking.$2} • ${booking.$3}',
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
