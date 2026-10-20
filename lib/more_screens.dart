import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'catalog.dart';
import 'leaderboard_domain.dart';
import 'location_service.dart';
import 'main.dart';
import 'more_screens2.dart';

// ---------------------------------------------------------------------------
// Shared data
// ---------------------------------------------------------------------------

class SportOption {
  const SportOption(this.label, this.icon);
  final String label;
  final IconData icon;
}

const kSportOptions = <SportOption>[
  SportOption('Basketball', Icons.sports_basketball),
  SportOption('3x3 Basketball', CupertinoIcons.person_3_fill),
  SportOption('Padel', Icons.sports_tennis),
  SportOption('Volleyball', Icons.sports_volleyball),
  SportOption('Football', Icons.sports_soccer),
  SportOption('Tennis', CupertinoIcons.circle_grid_hex),
  SportOption('Cycling', Icons.directions_bike_rounded),
  SportOption('Running', Icons.directions_run_rounded),
  SportOption('Other', CupertinoIcons.sportscourt),
];

const kSkillLevels = <String>[
  'Beginner',
  'Casual',
  'Intermediate',
  'Advanced',
  'Competitive',
];

String _setupErrorMessage(Object error) {
  if (error is FirebaseAuthException) return friendlyAuthError(error);
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' =>
        'We couldn’t access your player profile. Please try again or contact support if this keeps happening.',
      'unavailable' || 'deadline-exceeded' =>
        'We couldn’t reach PlayUp. Check your connection and try again.',
      _ => 'We couldn’t save your setup. Please try again.',
    };
  }
  if (error is StateError) return error.message.toString();
  return 'We couldn’t save your setup. Please try again.';
}

/// A tappable pill used across the setup and filter flows.
class SelectablePill extends StatelessWidget {
  const SelectablePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.purple : scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.purple : scheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 16,
                  color: selected ? Colors.white : scheme.onSurface,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : scheme.onSurface,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Player setup: sports selection -> skill level -> complete
// ---------------------------------------------------------------------------

class SportsSelectionScreen extends StatefulWidget {
  const SportsSelectionScreen({super.key});

  @override
  State<SportsSelectionScreen> createState() => _SportsSelectionScreenState();
}

class _SportsSelectionScreenState extends State<SportsSelectionScreen> {
  final _selected = <String>{};
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadSports();
  }

  Future<void> _loadSports() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        throw StateError('Your session ended. Sign in again to continue.');
      }
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (!mounted) return;
      setState(() {
        _selected
          ..clear()
          ..addAll(
            List<String>.from(snapshot.data()?['sports'] as List? ?? const []),
          );
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = _setupErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Step 1 of 2',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Build your player profile',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Choose the sports you play. We’ll use them to make court and match suggestions more relevant.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${_selected.length} selected',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 52),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_loadError != null) ...[
              ErrorBanner(message: _loadError!),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loadSports,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ] else ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 620 ? 3 : 2;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: kSportOptions.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 116,
                    ),
                    itemBuilder: (context, index) {
                      final sport = kSportOptions[index];
                      return _SportSelectCard(
                        sport: sport,
                        selected: _selected.contains(sport.label),
                        onTap: () => setState(() {
                          if (!_selected.add(sport.label)) {
                            _selected.remove(sport.label);
                          }
                        }),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(
                _selected.isEmpty
                    ? 'Choose at least one sport to continue.'
                    : 'You can change these choices any time in your profile.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'Continue',
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              SkillLevelScreen(sports: _selected.toList()),
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SportSelectCard extends StatelessWidget {
  const _SportSelectCard({
    required this.sport,
    required this.selected,
    required this.onTap,
  });

  final SportOption sport;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(20);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerLow,
        borderRadius: borderRadius,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 1.8 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: borderRadius,
          child: Semantics(
            button: true,
            selected: selected,
            label: sport.label,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: selected
                              ? scheme.primary.withValues(alpha: .14)
                              : scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          sport.icon,
                          color: selected
                              ? scheme.primary
                              : scheme.onSecondaryContainer,
                          size: 23,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        selected
                            ? CupertinoIcons.checkmark_circle_fill
                            : CupertinoIcons.circle,
                        color: selected ? scheme.primary : scheme.outline,
                        size: 22,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    sport.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
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

class SkillLevelScreen extends StatefulWidget {
  const SkillLevelScreen({super.key, required this.sports});

  final List<String> sports;

  @override
  State<SkillLevelScreen> createState() => _SkillLevelScreenState();
}

class _SkillLevelScreenState extends State<SkillLevelScreen> {
  late final Map<String, String> _levels = {
    for (final sport in widget.sports) sport: 'Intermediate',
  };
  String _preferredTime = 'Evening';
  bool _publicProfile = true;
  bool _saving = false;
  String? _error;

  Future<void> _finish() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError('Your session ended. Sign in again to finish setup.');
      }
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'sports': widget.sports,
        'skillLevels': _levels,
        'preferredTime': _preferredTime,
        'publicProfile': _publicProfile,
        'setupComplete': true,
      }, SetOptions(merge: true));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SetupCompleteScreen()),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = _setupErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Step 2 of 2',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            Text(
              'Set your playing style',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'Set your level for each sport so we match you fairly.',
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
            ),
            const SizedBox(height: 20),
            for (final sport in widget.sports) ...[
              Text(
                sport,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
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
                      selected: _levels[sport] == level,
                      onTap: () => setState(() => _levels[sport] = level),
                    ),
                ],
              ),
              const SizedBox(height: 18),
            ],
            Text(
              'When do you usually play?',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final slot in ['Morning', 'Afternoon', 'Evening', 'Night'])
                  SelectablePill(
                    label: slot,
                    selected: _preferredTime == slot,
                    onTap: () => setState(() => _preferredTime = slot),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            CardBox(
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _publicProfile,
                activeThumbColor: AppColors.purple,
                onChanged: (value) => setState(() => _publicProfile = value),
                title: const Text(
                  'Public profile',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  'Let other players discover and invite you.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 24),
            PrimaryButton(
              label: _saving ? 'Saving...' : 'Finish Setup',
              onPressed: _saving ? null : _finish,
            ),
          ],
        ),
      ),
    );
  }
}

class SetupCompleteScreen extends StatelessWidget {
  const SetupCompleteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          children: [
            const SizedBox(height: 40),
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primaryContainer,
              ),
              child: Icon(
                CupertinoIcons.checkmark_alt,
                color: scheme.primary,
                size: 64,
              ),
            ).animate().scale(duration: 340.ms, curve: Curves.easeOutBack),
            const SizedBox(height: 26),
            Text(
              'You are all set!',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Text(
              'Your player profile is ready. Book a court, find a match, and start levelling up.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 30),
            PrimaryButton(
              label: 'Start Playing',
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Gamification: leaderboard, achievements, level detail
// ---------------------------------------------------------------------------

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  int _tab = 0;
  static const _tabs = ['All-time', 'My city', 'My sports'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Leaderboard',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _tabs.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) => SelectablePill(
                  label: _tabs[index],
                  selected: _tab == index,
                  onTap: () => setState(() => _tab = index),
                ),
              ),
            ),
            const SizedBox(height: 18),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: CatalogService.instance.topPlayers(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                final uid = FirebaseAuth.instance.currentUser?.uid;
                final mine = docs
                    .where((doc) => doc.id == uid)
                    .map((doc) => doc.data())
                    .firstOrNull;
                final myCity = (mine?['city'] ?? '').toString();
                final mySports = List<String>.from(
                  mine?['sports'] as List? ?? const [],
                );
                final filteredDocs = docs.where((doc) {
                  final profile = doc.data();
                  if (!isLeaderboardProfileEligible(profile)) return false;
                  if (_tab == 0) return true;
                  if (_tab == 1) {
                    return myCity.isNotEmpty &&
                        doc.data()['city']?.toString() == myCity;
                  }
                  final sports = List<String>.from(
                    doc.data()['sports'] as List? ?? const [],
                  );
                  return sports.any(mySports.contains);
                });
                final players = [
                  for (final d in filteredDocs)
                    (
                      (d.data()['displayName'] ?? 'Player').toString(),
                      (d.data()['level'] as num?)?.toInt() ?? 1,
                      (d.data()['rankTitle'] ?? 'Rookie').toString(),
                      _formatXp(d.data()['xp']),
                    ),
                ];
                final myName =
                    FirebaseAuth.instance.currentUser?.displayName ?? 'Player';
                return Column(
                  children: [
                    if (players.isEmpty)
                      EmptyState(
                        icon: CupertinoIcons.chart_bar_alt_fill,
                        title: 'No rankings yet',
                        message:
                            'Complete matches to earn XP and enter the leaderboard.',
                        action: 'Go back',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    _PodiumRow(players: players.take(3).toList()),
                    const SizedBox(height: 18),
                    for (var i = 0; i < players.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _LeaderboardRow(
                          rank: i + 1,
                          player: players[i],
                          isMe: players[i].$1 == myName,
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

  static String _formatXp(dynamic xp) {
    final value = (xp as num?)?.toInt() ?? 0;
    final s = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}

class _PodiumRow extends StatelessWidget {
  const _PodiumRow({required this.players});

  final List<(String, int, String, String)> players;

  @override
  Widget build(BuildContext context) {
    if (players.length < 3) return const SizedBox.shrink();
    Widget podium(int index, double height, Color color) {
      final p = players[index];
      return Expanded(
        child: Column(
          children: [
            Avatar(name: p.$1.characters.first, size: index == 0 ? 58 : 46),
            const SizedBox(height: 6),
            Text(
              p.$1.split(' ').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
            ),
            Text(
              '${p.$4} XP',
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
            const SizedBox(height: 8),
            Container(
              height: height,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color, color.withValues(alpha: .55)],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return CardBox(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          podium(1, 60, const Color(0xFF9AA4B2)),
          const SizedBox(width: 10),
          podium(0, 86, AppColors.gold),
          const SizedBox(width: 10),
          podium(2, 44, const Color(0xFFCD7F32)),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.rank,
    required this.player,
    required this.isMe,
  });

  final int rank;
  final (String, int, String, String) player;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      color: isMe ? AppColors.purple.withValues(alpha: .06) : AppColors.surface,
      borderColor: isMe ? AppColors.purple : AppColors.line,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$rank',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ),
          Avatar(name: player.$1.characters.first, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.$1,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  'Level ${player.$2}  •  ${player.$3}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            '${player.$4}\nXP',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class Achievement {
  const Achievement(
    this.id,
    this.title,
    this.description,
    this.icon,
    this.color,
    this.progress,
    this.goal,
  );
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final int progress;
  final int goal;
}

List<Achievement> buildAchievements({
  required Map<String, dynamic> profile,
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> bookings,
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> matches,
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> definitions,
}) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final bookingRows = bookings.map((doc) => doc.data()).toList();
  final matchRows = matches.map((doc) => doc.data()).toList();
  final validBookings = bookingRows
      .where((row) => row['status']?.toString() != 'cancelled')
      .toList();
  final completedMatches = matchRows
      .where(
        (row) => const {
          'completed',
          'finished',
        }.contains(row['status']?.toString().toLowerCase()),
      )
      .length;
  final rating = (profile['rating'] as num?)?.toDouble() ?? 0;
  final tournamentWins =
      (profile['tournamentWins'] as num?)?.toInt() ??
      (profile['tournamentsWon'] as num?)?.toInt() ??
      0;
  final hostedMatches = matchRows.where((row) => row['hostId'] == uid).length;
  final loyalty = <String, int>{};
  for (final booking in validBookings) {
    final academyId = booking['academyId']?.toString() ?? '';
    if (academyId.isNotEmpty) {
      loyalty[academyId] = (loyalty[academyId] ?? 0) + 1;
    }
  }
  final noCancellationStreak = _noCancellationStreak(bookingRows);
  final weekendStreak = _weekendStreak(validBookings);
  final progressByMetric = <String, int>{
    'bookings': validBookings.length,
    'matchesPlayed': completedMatches,
    'rating5': rating >= 5 ? 1 : 0,
    'weekendStreak': weekendStreak,
    'noCancellationStreak': noCancellationStreak,
    'tournamentWins': tournamentWins,
    'matchesHosted': hostedMatches,
    'academyLoyalty': loyalty.values.fold<int>(0, math.max),
  };
  final fallback = [
    Achievement(
      'first-booking',
      'First Booking',
      'Book your first court',
      CupertinoIcons.calendar,
      AppColors.green,
      validBookings.length,
      1,
    ),
    Achievement(
      'matches-10',
      '10 Matches Played',
      'Play 10 matches',
      CupertinoIcons.sportscourt,
      AppColors.purple,
      completedMatches,
      10,
    ),
    Achievement(
      'five-star',
      '5-Star Player',
      'Earn a 5-star rating',
      CupertinoIcons.star_fill,
      AppColors.gold,
      rating >= 5 ? 1 : 0,
      1,
    ),
    Achievement(
      'weekend-warrior',
      'Weekend Warrior',
      'Play 3 weekends in a row',
      CupertinoIcons.flame_fill,
      Color(0xFFFF7A45),
      weekendStreak,
      3,
    ),
    Achievement(
      'reliable-player',
      'No Cancellation Streak',
      '10 games with no cancels',
      CupertinoIcons.shield_lefthalf_fill,
      Color(0xFF3B82F6),
      noCancellationStreak,
      10,
    ),
    Achievement(
      '3x3-champion',
      '3x3 Champion',
      'Win a 3x3 tournament',
      CupertinoIcons.rosette,
      Color(0xFFEC4899),
      tournamentWins,
      1,
    ),
    Achievement(
      'team-captain',
      'Team Captain',
      'Host 5 matches',
      CupertinoIcons.person_2_fill,
      AppColors.purple,
      hostedMatches,
      5,
    ),
    Achievement(
      'academy-loyal',
      'Academy Loyal',
      'Book same academy 8 times',
      CupertinoIcons.building_2_fill,
      AppColors.green,
      progressByMetric['academyLoyalty']!,
      8,
    ),
  ];
  final activeDefinitions = definitions
      .where((doc) => doc.data()['active'] != false)
      .toList();
  if (activeDefinitions.isEmpty) return fallback;
  return activeDefinitions.map((doc) {
    final data = doc.data();
    final metric = data['metric']?.toString() ?? 'bookings';
    final color = switch (data['color']?.toString()) {
      'gold' => AppColors.gold,
      'green' => AppColors.green,
      'blue' => const Color(0xFF3B82F6),
      'orange' => const Color(0xFFFF7A45),
      'pink' => const Color(0xFFEC4899),
      _ => AppColors.purple,
    };
    final icon = switch (metric) {
      'bookings' => CupertinoIcons.calendar,
      'matchesPlayed' => CupertinoIcons.sportscourt,
      'rating5' => CupertinoIcons.star_fill,
      'weekendStreak' => CupertinoIcons.flame_fill,
      'noCancellationStreak' => CupertinoIcons.shield_lefthalf_fill,
      'tournamentWins' => CupertinoIcons.rosette,
      'matchesHosted' => CupertinoIcons.person_2_fill,
      'academyLoyalty' => CupertinoIcons.building_2_fill,
      _ => CupertinoIcons.checkmark_seal_fill,
    };
    return Achievement(
      doc.id,
      (data['title'] ?? 'Achievement').toString(),
      (data['description'] ?? 'Keep playing to unlock this achievement.')
          .toString(),
      icon,
      color,
      progressByMetric[metric] ?? 0,
      math.max(1, (data['goal'] as num?)?.toInt() ?? 1),
    );
  }).toList();
}

DateTime? _achievementDate(Map<String, dynamic> row) {
  for (final key in const ['startUtc', 'completedAt', 'createdAt']) {
    final value = row[key];
    if (value is Timestamp) return value.toDate().toLocal();
  }
  return null;
}

int _noCancellationStreak(List<Map<String, dynamic>> bookings) {
  final sorted = [...bookings]
    ..sort(
      (a, b) => (_achievementDate(b) ?? DateTime(1970)).compareTo(
        _achievementDate(a) ?? DateTime(1970),
      ),
    );
  var streak = 0;
  for (final booking in sorted) {
    if (booking['status']?.toString() == 'cancelled') break;
    streak++;
  }
  return streak;
}

int _weekendStreak(List<Map<String, dynamic>> bookings) {
  final weekends =
      bookings
          .map(_achievementDate)
          .whereType<DateTime>()
          .where((date) => date.weekday >= DateTime.friday)
          .map((date) {
            final monday = date.subtract(Duration(days: date.weekday - 1));
            return DateTime(monday.year, monday.month, monday.day);
          })
          .toSet()
          .toList()
        ..sort();
  var best = 0;
  var current = 0;
  DateTime? previous;
  for (final week in weekends) {
    current = previous != null && week.difference(previous).inDays == 7
        ? current + 1
        : 1;
    best = math.max(best, current);
    previous = week;
  }
  return best;
}

class UserAchievementsBuilder extends StatelessWidget {
  const UserAchievementsBuilder({super.key, required this.builder});
  final Widget Function(BuildContext, List<Achievement>) builder;

  @override
  Widget build(BuildContext context) => StreamBuilder<Map<String, dynamic>>(
    stream: AppRepository.instance.currentUserDoc(),
    builder: (context, profile) =>
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: AppRepository.instance.myBookings(),
          builder: (context, bookings) =>
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: AppRepository.instance.myMatches(),
                builder: (context, matches) =>
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: CatalogService.instance.raw('achievements'),
                      builder: (context, definitions) {
                        if (!profile.hasData ||
                            !bookings.hasData ||
                            !matches.hasData ||
                            !definitions.hasData) {
                          return const Center(
                            child: CupertinoActivityIndicator(),
                          );
                        }
                        return builder(
                          context,
                          buildAchievements(
                            profile: profile.data!,
                            bookings: bookings.data!.docs,
                            matches: matches.data!.docs,
                            definitions: definitions.data!.docs,
                          ),
                        );
                      },
                    ),
              ),
        ),
  );
}

class LiveAchievementBadges extends StatelessWidget {
  const LiveAchievementBadges({super.key});

  @override
  Widget build(BuildContext context) => UserAchievementsBuilder(
    builder: (context, achievements) {
      final unlocked = achievements
          .where((item) => item.progress >= item.goal)
          .take(4)
          .toList();
      if (unlocked.isEmpty) {
        return const CardBox(
          child: Text('Your first achievement is waiting to be unlocked.'),
        );
      }
      return Wrap(
        spacing: 4,
        runSpacing: 8,
        children: [
          for (final item in unlocked)
            AchievementBadge(icon: item.icon, color: item.color),
        ],
      );
    },
  );
}

class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Achievements',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            UserAchievementsBuilder(
              builder: (context, achievements) {
                final unlocked = achievements
                    .where((a) => a.progress >= a.goal)
                    .length;
                return Column(
                  children: [
                    CardBox(
                      color: AppColors.dark,
                      borderColor: AppColors.dark,
                      child: Row(
                        children: [
                          const Icon(
                            CupertinoIcons.rosette,
                            color: AppColors.gold,
                            size: 34,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$unlocked of ${achievements.length} unlocked',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ProgressBar(
                                  value: achievements.isEmpty
                                      ? 0
                                      : unlocked / achievements.length,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final a in achievements)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _AchievementCard(achievement: a),
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

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.achievement});

  final Achievement achievement;

  @override
  Widget build(BuildContext context) {
    final done = achievement.progress >= achievement.goal;
    return CardBox(
      child: Row(
        children: [
          AchievementBadge(icon: achievement.icon, color: achievement.color),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        achievement.title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (done)
                      const Icon(
                        CupertinoIcons.checkmark_seal_fill,
                        color: AppColors.green,
                        size: 20,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  achievement.description,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                ProgressBar(
                  value: achievement.progress / achievement.goal,
                  dark: false,
                ),
                const SizedBox(height: 4),
                Text(
                  '${achievement.progress}/${achievement.goal}',
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
    );
  }
}

class LevelDetailScreen extends StatelessWidget {
  const LevelDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Level & Rank',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            StreamBuilder<Map<String, dynamic>>(
              stream: AppRepository.instance.currentUserDoc(),
              builder: (context, snapshot) {
                final data = snapshot.data ?? const {};
                final level = (data['level'] as num?)?.toInt() ?? 1;
                final xp = (data['xp'] as num?)?.toInt() ?? 0;
                final nextXp =
                    (data['nextLevelXp'] as num?)?.toInt() ??
                    ((level + 1) * 500);
                final rank = (data['rankTitle'] ?? 'Rookie').toString();
                final sports = List<String>.from(
                  data['sports'] as List? ?? const [],
                );
                final sportRanks = Map<String, dynamic>.from(
                  data['sportRanks'] as Map? ?? const {},
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CardBox(
                      color: AppColors.dark,
                      borderColor: AppColors.dark,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              LevelBadge(text: '$level', size: 62),
                              const SizedBox(width: 14),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    rank,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                    ),
                                  ),
                                  Text(
                                    'Level $level',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          ProgressBar(
                            value: nextXp <= 0 ? 0 : (xp / nextXp).clamp(0, 1),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${formatThousands(xp)} XP • ${formatThousands((nextXp - xp).clamp(0, nextXp))} to next level',
                            style: const TextStyle(
                              color: AppColors.gold,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Your sports',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (sports.isEmpty)
                      const CardBox(
                        child: Text(
                          'Choose sports in your profile to start building sport-specific ranks.',
                        ),
                      )
                    else
                      for (final sport in sports)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: CardBox(
                            child: Row(
                              children: [
                                const Icon(
                                  CupertinoIcons.rosette,
                                  color: AppColors.purple,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    sport,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Text(
                                  sportRanks[sport]?.toString() ?? 'Unranked',
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontWeight: FontWeight.w800,
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
            const SizedBox(height: 22),
            const Text(
              'XP history',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: AppRepository.instance.pointsLedger(),
              builder: (context, snapshot) {
                final rows = snapshot.data?.docs ?? const [];
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (rows.isEmpty) {
                  return const CardBox(
                    child: Text('XP activity will appear after you play.'),
                  );
                }
                return Column(
                  children: [
                    for (final row in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: CardBox(
                          child: Row(
                            children: [
                              const Icon(
                                CupertinoIcons.bolt_fill,
                                color: AppColors.gold,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  row.data()['description']?.toString() ??
                                      'Activity',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Text(
                                '${(row.data()['delta'] as num?)?.toInt() ?? 0} XP',
                                style: const TextStyle(
                                  color: AppColors.green,
                                  fontWeight: FontWeight.w900,
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
}

// ---------------------------------------------------------------------------
// Academies
// ---------------------------------------------------------------------------

class Academy {
  const Academy({
    this.id = '',
    required this.name,
    required this.sports,
    required this.rating,
    required this.distance,
    required this.featured,
    required this.gradient,
    required this.icon,
    this.imageUrl = '',
    this.latitude,
    this.longitude,
    this.address = '',
    this.phone = '',
    this.email = '',
    this.description = '',
    this.trainingPackages = const [],
    this.packages = const [],
  });

  final String id;
  final String name;
  final String sports;
  final String rating;
  final String distance;
  final bool featured;
  final List<Color> gradient;
  final IconData icon;
  final String imageUrl;
  final double? latitude;
  final double? longitude;
  final String address;
  final String phone;
  final String email;
  final String description;
  final List<String> trainingPackages;
  final List<AcademyPackage> packages;

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
    if (km == null) return address.isEmpty ? 'Location unavailable' : address;
    return km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';
  }
}

class AcademiesListScreen extends StatefulWidget {
  final String? initialSport;
  const AcademiesListScreen({super.key, this.initialSport});

  @override
  State<AcademiesListScreen> createState() => _AcademiesListScreenState();
}

class _AcademiesListScreenState extends State<AcademiesListScreen> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.initialSport ?? '');
  }

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
            PageTopBar(
              title: 'Academies',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            SearchBox(controller: _search, onChanged: (_) => setState(() {})),
            const SizedBox(height: 16),
            StreamBuilder<List<Academy>>(
              stream: CatalogService.instance.academies(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final query = _search.text.trim().toLowerCase();
                final list =
                    (snapshot.data ?? const <Academy>[])
                        .where(
                          (academy) =>
                              query.isEmpty ||
                              academy.name.toLowerCase().contains(query) ||
                              academy.sports.toLowerCase().contains(query) ||
                              academy.address.toLowerCase().contains(query),
                        )
                        .toList()
                      ..sort((a, b) => a.name.compareTo(b.name));
                if (list.isEmpty) {
                  return const CardBox(
                    child: Text('No academies match this search.'),
                  );
                }
                return Column(
                  children: [
                    for (final academy in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _AcademyCard(academy: academy),
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

class _AcademyCard extends StatelessWidget {
  const _AcademyCard({required this.academy});

  final Academy academy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AcademyProfileScreen(academy: academy),
        ),
      ),
      child: CardBox(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: academy.gradient),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                    child: academy.imageUrl.isEmpty
                        ? Center(
                            child: Icon(
                              academy.icon,
                              color: Colors.white.withValues(alpha: .5),
                              size: 54,
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: academy.imageUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 120,
                            errorWidget: (context, url, error) => Center(
                              child: Icon(
                                academy.icon,
                                color: Colors.white.withValues(alpha: .5),
                                size: 54,
                              ),
                            ),
                          ),
                  ),
                ),
                if (academy.featured)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'FEATURED',
                        style: TextStyle(
                          color: AppColors.dark,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    academy.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    academy.sports,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        CupertinoIcons.star_fill,
                        color: AppColors.gold,
                        size: 15,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        academy.rating,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 12),
                      const Icon(
                        CupertinoIcons.location_solid,
                        color: AppColors.muted,
                        size: 14,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        academy.distanceFrom(
                          LocationService.instance.current.value,
                        ),
                        style: const TextStyle(color: AppColors.muted),
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

String _cleanAcademyCopy(String value) => value
    .replaceAll('\u00e2\u20ac\u00a2', '\u2022')
    .replaceAll('\u00e2\u20ac\u201c', '\u2013')
    .replaceAll('\u00e2\u20ac\u201d', '\u2014')
    .replaceAll('\u00e2\u20ac\u2122', '\u2019')
    .replaceAll('\u00e2\u20ac\u02dc', '\u2018')
    .replaceAll('\u00e2\u20ac\u0153', '\u201c')
    .replaceAll('\u00e2\u20ac\u009d', '\u201d')
    .replaceAll('\u00c2\u00b7', '\u00b7')
    .replaceAll('\uFFFD', '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

class AcademyProfileScreen extends StatefulWidget {
  const AcademyProfileScreen({super.key, required this.academy});

  final Academy academy;

  @override
  State<AcademyProfileScreen> createState() => _AcademyProfileScreenState();
}

class _AcademyProfileScreenState extends State<AcademyProfileScreen> {
  bool _following = false;

  @override
  Widget build(BuildContext context) {
    final academy = widget.academy;
    return Scaffold(
      body: AppScrollPage(
        topPadding: 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 176,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: academy.gradient,
                    ),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(28),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(28),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (academy.imageUrl.startsWith('asset:'))
                          Image.asset(
                            academy.imageUrl.substring(6),
                            fit: BoxFit.cover,
                            alignment: const Alignment(0, 0.12),
                            errorBuilder: (context, error, stackTrace) =>
                                Center(
                                  child: Icon(
                                    academy.icon,
                                    color: Colors.white54,
                                    size: 72,
                                  ),
                                ),
                          )
                        else if (academy.imageUrl.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: academy.imageUrl,
                            fit: BoxFit.cover,
                            alignment: const Alignment(0, 0.12),
                            errorWidget: (context, url, error) => Center(
                              child: Icon(
                                academy.icon,
                                color: Colors.white.withValues(alpha: .4),
                                size: 72,
                              ),
                            ),
                          )
                        else
                          Center(
                            child: Icon(
                              academy.icon,
                              color: Colors.white.withValues(alpha: .4),
                              size: 72,
                            ),
                          ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0x66000000)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 18,
                  left: 10,
                  child: SafeArea(
                    child: CircleIconButton(
                      icon: CupertinoIcons.arrow_left,
                      dark: true,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              academy.name,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            CupertinoIcons.checkmark_seal_fill,
                            color: AppColors.purple,
                            size: 20,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            CupertinoIcons.star_fill,
                            color: AppColors.gold,
                            size: 15,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_cleanAcademyCopy(academy.rating)}  \u2022  ${_cleanAcademyCopy(academy.distanceFrom(LocationService.instance.current.value))}',
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: FilledButton(
                    onPressed: () => setState(() => _following = !_following),
                    style: FilledButton.styleFrom(
                      backgroundColor: _following
                          ? AppColors.line
                          : AppColors.purple,
                      foregroundColor: _following
                          ? AppColors.ink
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      _following ? 'Following' : 'Follow',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'About',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              academy.description.isEmpty
                  ? 'Contact ${academy.name} to learn about its courts, coaching, and current programs.'
                  : _cleanAcademyCopy(academy.description),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.muted, height: 1.4),
            ),
            if (academy.address.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                academy.address,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    label: 'Contact us',
                    icon: CupertinoIcons.phone_fill,
                    onPressed: () => _contactAcademy(academy),
                  ),
                ),
                const SizedBox(width: 10),
                if (academy.email.isNotEmpty)
                  Expanded(
                    child: SecondaryButton(
                      label: 'Email',
                      onPressed: () => launchUrl(
                        Uri(
                          scheme: 'mailto',
                          path: academy.email,
                          queryParameters: {'subject': 'PlayUp enquiry'},
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (academy.packages.isNotEmpty ||
                academy.trainingPackages.isNotEmpty) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Training packages',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    'Swipe to explore',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 244,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: academy.packages.isNotEmpty
                      ? academy.packages.length
                      : academy.trainingPackages.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    if (academy.packages.isNotEmpty) {
                      return SizedBox(
                        width: 286,
                        child: _AcademyPackageCard(
                          package: academy.packages[index],
                          fallbackImage: _academyPackageImage(academy),
                        ),
                      );
                    }
                    return SizedBox(
                      width: 286,
                      child: _TrainingPackageCard(
                        title: academy.trainingPackages[index],
                        imageUrl: _academyPackageImage(academy),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 14),
            const SizedBox(height: 20),
            StreamBuilder<List<Court>>(
              stream: CatalogService.instance.courts(),
              builder: (context, snapshot) {
                final list = (snapshot.data ?? const <Court>[])
                    .where((court) => court.academyId == academy.id)
                    .toList();
                return CardBox(
                  padding: EdgeInsets.zero,
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    title: const Text(
                      'Courts',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    subtitle: Text(
                      snapshot.connectionState == ConnectionState.waiting
                          ? 'Loading courts'
                          : '${list.length} ${list.length == 1 ? 'court' : 'courts'}',
                    ),
                    children: [
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (list.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('No courts are listed right now.'),
                        )
                      else
                        for (final court in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: CourtListCard(court: court),
                          ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<EventItem>>(
              stream: CatalogService.instance.events(),
              builder: (context, snapshot) {
                final list = (snapshot.data ?? const <EventItem>[])
                    .where((event) => event.academyId == academy.id)
                    .toList();
                return CardBox(
                  padding: EdgeInsets.zero,
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    title: const Text(
                      'Upcoming events',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    subtitle: Text(
                      snapshot.connectionState == ConnectionState.waiting
                          ? 'Loading events'
                          : '${list.length} ${list.length == 1 ? 'event' : 'events'}',
                    ),
                    children: [
                      if (snapshot.connectionState == ConnectionState.waiting)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (list.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('No upcoming events are listed.'),
                        )
                      else
                        for (final event in list)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _EventCard(event: event),
                          ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _contactAcademy(Academy academy) async {
    if (academy.phone.isEmpty) {
      await showAdaptiveMessage(
        context,
        title: 'Contact unavailable',
        message: 'This academy has not published a phone number yet.',
      );
      return;
    }
    final launched = await launchUrl(Uri(scheme: 'tel', path: academy.phone));
    if (!launched && mounted) {
      await showAdaptiveMessage(
        context,
        title: 'Could not open phone',
        message: 'Call ${academy.phone} to contact ${academy.name}.',
      );
    }
  }
}

String _academyPackageImage(Academy academy) {
  final sports = academy.sports.toLowerCase();
  if (sports.contains('basketball') || sports.contains('3x3')) {
    return 'asset:assets/images/sports/basketball_court_ball.png';
  }
  if (sports.contains('football') || sports.contains('soccer')) {
    return 'asset:assets/images/sports/football_court_ball.png';
  }
  if (sports.contains('volleyball')) {
    return 'asset:assets/images/sports/volleyball_court_ball.png';
  }
  if (sports.contains('padel') || sports.contains('tennis')) {
    return 'asset:assets/images/sports/tennis_court_ball.png';
  }
  if (sports.contains('cycling')) {
    return 'asset:assets/images/sports/cycling_group.jpg';
  }
  if (sports.contains('running')) {
    return 'asset:assets/images/sports/running_track.jpg';
  }
  return 'asset:assets/images/sports/basketball_court_ball.png';
}

class _TrainingPackageCard extends StatelessWidget {
  const _TrainingPackageCard({required this.title, required this.imageUrl});

  final String title;
  final String imageUrl;

  @override
  Widget build(BuildContext context) => _PackageCardLayout(
    title: _cleanAcademyCopy(title),
    imageUrl: imageUrl,
    description: '',
  );
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final EventItem event;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (event.imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(22),
              ),
              child: CachedNetworkImage(
                imageUrl: event.imageUrl,
                width: double.infinity,
                height: 150,
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.12),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  CupertinoIcons.rosette,
                  color: AppColors.purple,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      if (event.date.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          event.date,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (event.location.isNotEmpty)
                        Text(
                          event.location,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      if (event.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          event.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (event.prize.isNotEmpty)
                        Text(
                          event.prize,
                          style: const TextStyle(
                            color: AppColors.green,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(
                  CupertinoIcons.chevron_right,
                  color: AppColors.muted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AcademyPackageCard extends StatelessWidget {
  const _AcademyPackageCard({
    required this.package,
    required this.fallbackImage,
  });

  final AcademyPackage package;
  final String fallbackImage;

  @override
  Widget build(BuildContext context) {
    final image = package.imageUrl.isNotEmpty
        ? package.imageUrl
        : fallbackImage;
    return _PackageCardLayout(
      title: _cleanAcademyCopy(package.title),
      imageUrl: image,
      description: _cleanAcademyCopy(package.description),
      price: _cleanAcademyCopy(package.price),
      duration: _cleanAcademyCopy(package.duration),
    );
  }
}

class _PackageCardLayout extends StatelessWidget {
  const _PackageCardLayout({
    required this.title,
    required this.imageUrl,
    required this.description,
    this.price = '',
    this.duration = '',
  });

  final String title;
  final String imageUrl;
  final String description;
  final String price;
  final String duration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CardBox(
      padding: EdgeInsets.zero,
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: SizedBox(
              height: 112,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF0B1628), Color(0xFF1F7A8C)],
                      ),
                    ),
                  ),
                  if (imageUrl.startsWith('asset:'))
                    Image.asset(
                      imageUrl.substring(6),
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, 0.12),
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    )
                  else if (imageUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, 0.12),
                      errorWidget: (_, _, _) => const SizedBox.shrink(),
                    )
                  else
                    const Center(
                      child: Icon(
                        CupertinoIcons.sportscourt,
                        size: 56,
                        color: Colors.white70,
                      ),
                    ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xD9001018)],
                        stops: [0.34, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xE60A1716),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .24),
                        ),
                      ),
                      child: const Text(
                        'TRAINING PACKAGE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .9,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 14,
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 21,
                        height: 1.15,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 10, 13, 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (description.trim().isNotEmpty)
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                if (price.isNotEmpty || duration.isNotEmpty) ...[
                  if (description.trim().isNotEmpty) const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (price.isNotEmpty)
                        _PackageDetailPill(
                          icon: CupertinoIcons.money_dollar_circle,
                          label: price,
                          emphasized: true,
                        ),
                      if (duration.isNotEmpty)
                        _PackageDetailPill(
                          icon: CupertinoIcons.clock,
                          label: duration,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageDetailPill extends StatelessWidget {
  const _PackageDetailPill({
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final foreground = emphasized
        ? const Color(0xFF07241F)
        : Theme.of(context).colorScheme.onSurface;
    return Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: emphasized
            ? const Color(0xFF72E5C2)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rewards: offer details, redeem QR, wallet
// ---------------------------------------------------------------------------

class OfferDetailsScreen extends StatelessWidget {
  const OfferDetailsScreen({
    super.key,
    required this.offerId,
    required this.title,
    required this.partner,
    required this.points,
    required this.colors,
  });

  final String offerId;
  final String title;
  final String partner;
  final String points;
  final List<Color> colors;

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
                Container(
                  height: 176,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: colors),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(28),
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      CupertinoIcons.gift_fill,
                      color: Colors.white.withValues(alpha: .5),
                      size: 64,
                    ),
                  ),
                ),
                Positioned(
                  top: 18,
                  left: 10,
                  child: SafeArea(
                    child: CircleIconButton(
                      icon: CupertinoIcons.arrow_left,
                      dark: true,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              partner,
              style: const TextStyle(color: AppColors.muted, fontSize: 15),
            ),
            const SizedBox(height: 16),
            CardBox(
              child: Row(
                children: [
                  const Icon(CupertinoIcons.circle_fill, color: AppColors.gold),
                  const SizedBox(width: 10),
                  Text(
                    '$points points',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Valid until 30 Jun',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Terms',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            const Text(
              'Redeemable once per player. Show the QR code to academy staff at check-in. Cannot be combined with other offers. Points are deducted on redemption.',
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 24),
            _RedeemOfferButton(
              offerId: offerId,
              title: title,
              partner: partner,
              points: points,
            ),
          ],
        ),
      ),
    );
  }
}

class _RedeemOfferButton extends StatefulWidget {
  const _RedeemOfferButton({
    required this.offerId,
    required this.title,
    required this.partner,
    required this.points,
  });
  final String offerId;
  final String title;
  final String partner;
  final String points;
  @override
  State<_RedeemOfferButton> createState() => _RedeemOfferButtonState();
}

class _RedeemOfferButtonState extends State<_RedeemOfferButton> {
  bool busy = false;
  Future<void> redeem() async {
    if (busy) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      await showAdaptiveMessage(
        context,
        title: 'Account required',
        message: 'Sign in to earn points and redeem gifts.',
      );
      return;
    }
    setState(() => busy = true);
    try {
      final profile = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final balance = (profile.data()?['points'] as num?)?.toInt() ?? 0;
      if (!mounted) return;
      final cost =
          int.tryParse(widget.points.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (cost > 0 && balance < cost) {
        await showAdaptiveMessage(
          context,
          title: 'Not enough points',
          message:
              'You have $balance points. You need ${cost - balance} more points to redeem this gift.',
        );
        return;
      }
      final result = await AppRepository.instance.redeemOffer(widget.offerId);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RedeemQrScreen(
            title: widget.title,
            partner: widget.partner,
            code: result['code'].toString(),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        await showAdaptiveMessage(
          context,
          title: 'Unable to redeem',
          message: error.toString().replaceFirst(
            'DomainValidationException: ',
            '',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PrimaryButton(
    label: busy ? 'Redeeming...' : 'Redeem for ${widget.points} points',
    onPressed: redeem,
  );
}

class RedeemQrScreen extends StatelessWidget {
  const RedeemQrScreen({
    super.key,
    required this.title,
    required this.partner,
    required this.code,
  });

  final String title;
  final String partner;
  final String code;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Redeem',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.green.withValues(alpha: .14),
                    ),
                    child: const Icon(
                      CupertinoIcons.checkmark_alt,
                      color: AppColors.green,
                      size: 48,
                    ),
                  ).animate().scale(
                    duration: 320.ms,
                    curve: Curves.easeOutBack,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Offer Redeemed!',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: CardBox(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    SizedBox(
                      width: 200,
                      height: 200,
                      child: CustomPaint(painter: _QrPainter(code)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      code,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Show this to $partner staff',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'Save to Wallet',
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const WalletScreen())),
            ),
            const SizedBox(height: 10),
            SecondaryButton(
              label: 'Done',
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws a deterministic QR-like matrix from a seed string. Purely decorative.
class _QrPainter extends CustomPainter {
  _QrPainter(this.seed);

  final String seed;

  @override
  void paint(Canvas canvas, Size size) {
    const cells = 21;
    final cell = size.width / cells;
    final paint = Paint()..color = AppColors.ink;
    final rng = math.Random(seed.hashCode);

    void finder(int col, int row) {
      canvas.drawRect(
        Rect.fromLTWH(col * cell, row * cell, cell * 7, cell * 7),
        paint,
      );
      canvas.drawRect(
        Rect.fromLTWH((col + 1) * cell, (row + 1) * cell, cell * 5, cell * 5),
        Paint()..color = Colors.white,
      );
      canvas.drawRect(
        Rect.fromLTWH((col + 2) * cell, (row + 2) * cell, cell * 3, cell * 3),
        paint,
      );
    }

    bool inFinder(int c, int r) =>
        (c < 8 && r < 8) ||
        (c > cells - 9 && r < 8) ||
        (c < 8 && r > cells - 9);

    for (var r = 0; r < cells; r++) {
      for (var c = 0; c < cells; c++) {
        if (inFinder(c, r)) continue;
        if (rng.nextBool()) {
          canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell, cell), paint);
        }
      }
    }
    finder(0, 0);
    finder(cells - 7, 0);
    finder(0, cells - 7);
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) =>
      oldDelegate.seed != seed;
}

class WalletScreen extends StatelessWidget {
  const WalletScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final content = AppScrollPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!embedded)
            PageTopBar(
              title: 'Wallet',
              onBack: () => Navigator.of(context).pop(),
            ),
          const SizedBox(height: 16),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: uid == null
                ? null
                : FirebaseFirestore.instance
                      .collection('users')
                      .doc(uid)
                      .snapshots(),
            builder: (context, snapshot) {
              final points =
                  (snapshot.data?.data()?['points'] as num?)?.toInt() ?? 0;
              return CardBox(
                color: AppColors.dark,
                borderColor: AppColors.dark,
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Points balance',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '$points',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Text(
                          'Available for eligible rewards',
                          style: TextStyle(color: AppColors.gold),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Icon(
                      CupertinoIcons.gift_fill,
                      color: AppColors.gold,
                      size: 44,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          const Text(
            'My coupons',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: uid == null
                ? null
                : FirebaseFirestore.instance
                      .collection('redemptions')
                      .where('userId', isEqualTo: uid)
                      .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final coupons = snapshot.data?.docs ?? const [];
              if (coupons.isEmpty) {
                return const CardBox(
                  child: Text(
                    'Redeemed rewards will appear here as usable coupons.',
                  ),
                );
              }
              return Column(
                children: [
                  for (final coupon in coupons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CouponRow(
                        title:
                            coupon.data()['title']?.toString() ??
                            'Reward coupon',
                        subtitle:
                            '${coupon.data()['partner'] ?? 'PlayUp'} • ${coupon.data()['status'] ?? 'active'} • ${coupon.data()['code'] ?? ''}',
                      ),
                    ),
                ],
              );
            },
          ),
          if (!embedded) const SizedBox(height: 22),
          if (!embedded)
            const Text(
              'Points history',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          const SizedBox(height: 12),
          if (!embedded)
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: AppRepository.instance.pointsLedger(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data?.docs ?? const [];
                if (rows.isEmpty) {
                  return const CardBox(
                    child: Text(
                      'Your earned and redeemed points will appear here.',
                    ),
                  );
                }
                return Column(
                  children: rows.map((doc) {
                    final item = doc.data();
                    final delta = (item['delta'] as num? ?? 0).toInt();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: CardBox(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item['description']?.toString() ??
                                    'Points activity',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              '${delta >= 0 ? '+' : ''}$delta',
                              style: TextStyle(
                                color: delta >= 0
                                    ? AppColors.green
                                    : AppColors.danger,
                                fontWeight: FontWeight.w900,
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
    );
    return embedded ? content : Scaffold(body: content);
  }
}

class _CouponRow extends StatelessWidget {
  const _CouponRow({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              CupertinoIcons.ticket_fill,
              color: AppColors.gold,
            ),
          ),
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
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
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
    );
  }
}

// ---------------------------------------------------------------------------
// Profile: stats, edit profile, friends
// ---------------------------------------------------------------------------

class PlayerStatsScreen extends StatelessWidget {
  const PlayerStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      return Scaffold(
        body: AppScrollPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageTopBar(
                title: 'Stats',
                onBack: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 16),
              const CardBox(child: Text('Sign in to see your player stats.')),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Stats',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const CardBox(
                    child: Text(
                      'Stats could not be loaded. Check your connection and try again.',
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data!.data() ?? const <String, dynamic>{};
                final matches = (data['matches'] as num?)?.toInt() ?? 0;
                final rating = (data['rating'] as num?)?.toDouble() ?? 0;
                final winRate = data['winRate'];
                final level = (data['level'] as num?)?.toInt() ?? 1;
                return GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.1,
                  children: [
                    StatCard(value: '$matches', label: 'Matches played'),
                    StatCard(
                      value: rating > 0
                          ? rating.toStringAsFixed(1)
                          : 'Not rated',
                      label: 'Player rating',
                    ),
                    StatCard(
                      value: winRate is num ? '${winRate.round()}%' : '—',
                      label: 'Win rate',
                    ),
                    StatCard(value: '$level', label: 'Level'),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            const CardBox(
              child: Text(
                'More performance insights will appear as verified match results are recorded.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _bio = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;
  String _photoUrl = '';
  Uint8List? _photoBytes;
  String _photoFileName = 'profile.jpg';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snap.data() ?? {};
      _name.text = (data['displayName'] ?? user.displayName ?? '').toString();
      _city.text = (data['city'] ?? '').toString();
      _bio.text = (data['bio'] ?? '').toString();
      _photoUrl = (data['photoUrl'] ?? user.photoURL ?? '').toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _choosePhoto() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 86,
      maxWidth: 1200,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.lengthInBytes > 5 * 1024 * 1024) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a photo smaller than 5 MB.')),
      );
      return;
    }
    setState(() {
      _photoBytes = bytes;
      _photoFileName = file.name;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final user = FirebaseAuth.instance.currentUser;
    try {
      if (user != null) {
        await user.updateDisplayName(_name.text.trim());
        if (_photoBytes != null) {
          setState(() => _uploadingPhoto = true);
          final extension = _photoFileName.split('.').last.toLowerCase();
          final safeExtension =
              const {'jpg', 'jpeg', 'png', 'webp', 'heic'}.contains(extension)
              ? extension
              : 'jpg';
          final contentType = switch (safeExtension) {
            'png' => 'image/png',
            'webp' => 'image/webp',
            'heic' => 'image/heic',
            _ => 'image/jpeg',
          };
          final ref = FirebaseStorage.instance.ref(
            'profile-images/${user.uid}/avatar.$safeExtension',
          );
          await ref.putData(
            _photoBytes!,
            SettableMetadata(contentType: contentType),
          );
          _photoUrl = await ref.getDownloadURL();
          await user.updatePhotoURL(_photoUrl);
        }
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'displayName': _name.text.trim(),
          'city': _city.text.trim(),
          'bio': _bio.text.trim(),
          if (_photoUrl.isNotEmpty) 'photoUrl': _photoUrl,
        }, SetOptions(merge: true));
      }
      if (mounted) {
        setState(() => _uploadingPhoto = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile updated.')));
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _uploadingPhoto = false;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
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
              title: 'Edit Profile',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CupertinoActivityIndicator(),
                ),
              )
            else ...[
              Center(
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipOval(
                          child: SizedBox(
                            width: 96,
                            height: 96,
                            child: _photoBytes != null
                                ? Image.memory(_photoBytes!, fit: BoxFit.cover)
                                : _photoUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: _photoUrl,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, _, _) => Avatar(
                                      name: _name.text.isEmpty
                                          ? 'A'
                                          : _name.text.characters.first,
                                      size: 96,
                                    ),
                                  )
                                : Avatar(
                                    name: _name.text.isEmpty
                                        ? 'A'
                                        : _name.text.characters.first,
                                    size: 96,
                                  ),
                          ),
                        ),
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: Material(
                            color: AppColors.purple,
                            shape: const CircleBorder(),
                            child: IconButton(
                              tooltip: 'Choose profile photo',
                              onPressed: _uploadingPhoto ? null : _choosePhoto,
                              icon: _uploadingPhoto
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      CupertinoIcons.camera,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _uploadingPhoto ? null : _choosePhoto,
                      icon: const Icon(CupertinoIcons.photo),
                      label: const Text('Add or change photo'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              AppTextField(
                controller: _name,
                label: 'Full name',
                icon: CupertinoIcons.person,
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _city,
                label: 'City',
                icon: CupertinoIcons.location,
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _bio,
                label: 'Bio',
                icon: CupertinoIcons.text_quote,
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                label: _saving ? 'Saving...' : 'Save Changes',
                onPressed: _saving ? () {} : _save,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  int _tab = 0;
  static const _tabs = ['Friends', 'Requests', 'Suggested'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Friends',
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
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: AppRepository.instance.friendships(),
              builder: (context, friendshipSnapshot) {
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: AppRepository.instance.publicPlayers(),
                  builder: (context, playerSnapshot) {
                    if (friendshipSnapshot.connectionState ==
                            ConnectionState.waiting ||
                        playerSnapshot.connectionState ==
                            ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    final friendships =
                        friendshipSnapshot.data?.docs ?? const [];
                    final profiles = {
                      for (final doc in playerSnapshot.data?.docs ?? const [])
                        doc.id: doc.data(),
                    };
                    final connectedIds = <String>{
                      for (final doc in friendships)
                        ...List<String>.from(
                          doc.data()['members'] as List? ?? const [],
                        ),
                    };
                    final rows = <Widget>[];
                    if (_tab == 0) {
                      for (final doc in friendships.where(
                        (doc) => doc.data()['status'] == 'accepted',
                      )) {
                        final members = List<String>.from(
                          doc.data()['members'] as List? ?? const [],
                        );
                        final playerId = members.firstWhere(
                          (id) => id != uid,
                          orElse: () => '',
                        );
                        rows.add(
                          _friendRow(
                            profiles[playerId] ?? const {},
                            label: 'Invite',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const CreateMatchScreen(),
                              ),
                            ),
                          ),
                        );
                      }
                    } else if (_tab == 1) {
                      for (final doc in friendships.where(
                        (doc) =>
                            doc.data()['status'] == 'pending' &&
                            doc.data()['requestedTo'] == uid,
                      )) {
                        final requester =
                            doc.data()['requestedBy']?.toString() ?? '';
                        rows.add(
                          _friendRow(
                            profiles[requester] ??
                                {'displayName': doc.data()['requesterName']},
                            label: 'Accept',
                            onTap: () => _respond(doc.id, true),
                          ),
                        );
                      }
                    } else {
                      for (final entry in profiles.entries.where(
                        (entry) =>
                            entry.key != uid &&
                            !connectedIds.contains(entry.key),
                      )) {
                        rows.add(
                          _friendRow(
                            entry.value,
                            label: 'Add',
                            onTap: () => _send(entry.key),
                          ),
                        );
                      }
                    }
                    if (rows.isEmpty) {
                      return CardBox(
                        child: Text(
                          _tab == 0
                              ? 'Friends you connect with will appear here.'
                              : _tab == 1
                              ? 'You have no pending friend requests.'
                              : 'No new player suggestions are available.',
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final row in rows)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: row,
                          ),
                      ],
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

  Widget _friendRow(
    Map<String, dynamic> profile, {
    required String label,
    required VoidCallback onTap,
  }) {
    final name = (profile['displayName'] ?? 'Player').toString();
    final sports = List<String>.from(profile['sports'] as List? ?? const []);
    return CardBox(
      child: Row(
        children: [
          Avatar(name: name, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
                Text(
                  'Level ${profile['level'] ?? 1} • ${sports.isEmpty ? 'Sports not set' : sports.join(', ')}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
          FilledButton(onPressed: onTap, child: Text(label)),
        ],
      ),
    );
  }

  Future<void> _send(String playerId) async {
    try {
      await AppRepository.instance.sendFriendRequest(playerId);
    } catch (error) {
      if (!mounted) return;
      await showAdaptiveMessage(
        context,
        title: 'Could not add friend',
        message: error.toString().replaceFirst(
          'DomainValidationException: ',
          '',
        ),
      );
    }
  }

  Future<void> _respond(String friendshipId, bool accept) async {
    try {
      await AppRepository.instance.respondFriendRequest(friendshipId, accept);
    } catch (error) {
      if (!mounted) return;
      await showAdaptiveMessage(
        context,
        title: 'Could not update request',
        message: error.toString().replaceFirst(
          'DomainValidationException: ',
          '',
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Help center
// ---------------------------------------------------------------------------

class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const topics = <(String, IconData)>[
      ('Booking problems', CupertinoIcons.calendar),
      ('Payment problems', CupertinoIcons.creditcard),
      ('Matchmaking', CupertinoIcons.person_2),
      ('Points and rewards', CupertinoIcons.gift),
      ('Account', CupertinoIcons.person_crop_circle),
    ];
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Help Center',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            const Text(
              'How can we help?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            for (final topic in topics)
              SettingsTile(
                icon: topic.$2,
                title: topic.$1,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SupportScreen(category: topic.$1),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            PrimaryButton(
              label: 'Contact Support',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const SupportScreen(category: 'Support ticket'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
