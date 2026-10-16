import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'main.dart';
import 'booking_domain.dart';

// ---------------------------------------------------------------------------
// Cancel booking
// ---------------------------------------------------------------------------

class CancelBookingScreen extends StatefulWidget {
  const CancelBookingScreen({
    super.key,
    required this.bookingId,
    required this.startUtc,
    required this.totalMinor,
    required this.currency,
  });

  final String bookingId;
  final DateTime? startUtc;
  final int totalMinor;
  final String currency;

  @override
  State<CancelBookingScreen> createState() => _CancelBookingScreenState();
}

class _CancelBookingScreenState extends State<CancelBookingScreen> {
  String? _reason;
  String? _error;
  bool _busy = false;
  static const _reasons = [
    'Schedule conflict',
    'Found another court',
    'Not enough players',
    'Weather',
    'Other',
  ];

  @override
  Widget build(BuildContext context) {
    final hoursUntilStart = widget.startUtc?.difference(DateTime.now()).inHours;
    final late = hoursUntilStart != null && hoursUntilStart < 6;
    final feeMinor = late ? (widget.totalMinor * .5).round() : 0;
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'Cancel Booking',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 18),
            const Text(
              'Why are you cancelling?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              late
                  ? 'This is a late cancellation. A ${widget.currency} ${(feeMinor / 100).toStringAsFixed(2)} fee may be due at the venue.'
                  : 'This booking qualifies for free cancellation.',
              style: TextStyle(
                color: late ? AppColors.danger : AppColors.muted,
                height: 1.4,
                fontWeight: late ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 18),
            for (final reason in _reasons)
              GestureDetector(
                onTap: () => setState(() => _reason = reason),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: CardBox(
                    borderColor: _reason == reason
                        ? AppColors.purple
                        : AppColors.line,
                    child: Row(
                      children: [
                        Icon(
                          _reason == reason
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.circle,
                          color: _reason == reason
                              ? AppColors.purple
                              : AppColors.line,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          reason,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: _busy ? null : () => _confirm(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _busy
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : const Text(
                        'Cancel Booking',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
              ),
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

  Future<void> _confirm(BuildContext context) async {
    if (_reason == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a reason first.')));
      return;
    }
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Cancel this booking?'),
        content: const Text('This cannot be undone.'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Keep'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Cancel Booking'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppRepository.instance.cancelBooking(widget.bookingId, _reason!);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Booking cancelled.')));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is DomainValidationException
            ? error.message
            : 'The booking could not be cancelled. Try again.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Match results
// ---------------------------------------------------------------------------

class MatchResultsScreen extends StatelessWidget {
  const MatchResultsScreen({
    super.key,
    this.teamAName = 'Team A',
    this.teamBName = 'Team B',
    this.teamAScore = 21,
    this.teamBScore = 18,
    this.ratingDelta = 16,
    this.xpGained = 150,
  });

  final String teamAName;
  final String teamBName;
  final int teamAScore;
  final int teamBScore;
  final int ratingDelta;
  final int xpGained;

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
                    'Match Result',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                CardBox(
                      color: Colors.white.withValues(alpha: .05),
                      borderColor: Colors.white.withValues(alpha: .08),
                      child: Row(
                        children: [
                          _TeamScore(
                            name: teamAName,
                            score: teamAScore.toString(),
                            winner: teamAScore >= teamBScore,
                          ),
                          const Text(
                            'VS',
                            style: TextStyle(
                              color: Colors.white54,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          _TeamScore(
                            name: teamBName,
                            score: teamBScore.toString(),
                            winner: teamBScore > teamAScore,
                          ),
                        ],
                      ),
                    )
                    .animate()
                    .fadeIn(duration: 300.ms)
                    .scale(
                      begin: const Offset(.96, .96),
                      end: const Offset(1, 1),
                    ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.gold.withValues(alpha: .25),
                        AppColors.gold.withValues(alpha: .08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.gold.withValues(alpha: .4),
                    ),
                  ),
                  child: Row(
                    children: const [
                      Icon(
                        CupertinoIcons.star_circle_fill,
                        color: AppColors.gold,
                        size: 40,
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MVP of the Match',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              'You • 12 points, 6 assists',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _RewardPill(
                        icon: CupertinoIcons.bolt_fill,
                        label: '+$xpGained XP',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RewardPill(
                        icon: CupertinoIcons.star_fill,
                        label: '${ratingDelta >= 0 ? '+' : ''}$ratingDelta Elo',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: 'Rate Players',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => const PostMatchRatingScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).popUntil((route) => route.isFirst),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: .12),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('Done'),
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

class _TeamScore extends StatelessWidget {
  const _TeamScore({
    required this.name,
    required this.score,
    required this.winner,
  });

  final String name;
  final String score;
  final bool winner;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            name,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .7),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            score,
            style: TextStyle(
              color: winner ? AppColors.green : Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (winner)
            const Text(
              'Winner',
              style: TextStyle(
                color: AppColors.green,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }
}

class _RewardPill extends StatelessWidget {
  const _RewardPill({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.gold, size: 22),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Player reviews
// ---------------------------------------------------------------------------

// ignore: unused_element
class _LegacyPlayerReviewsScreen extends StatelessWidget {
  const _LegacyPlayerReviewsScreen();

  static const _reviews = <(String, int, String, String)>[
    ('Omar K.', 5, 'Great teamwork and always on time.', '2 days ago'),
    ('Sara N.', 5, 'Skilled player, fair play all game.', '1 week ago'),
    ('Zayd A.', 4, 'Good energy, solid defense.', '2 weeks ago'),
    ('Lina H.', 5, 'Friendly and reliable. Would play again!', '3 weeks ago'),
  ];

  @override
  Widget build(BuildContext context) {
    const avg = 4.7;
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'My Reviews',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            CardBox(
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '$avg',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Row(
                        children: List.generate(
                          5,
                          (i) => Icon(
                            i < avg.round()
                                ? CupertinoIcons.star_fill
                                : CupertinoIcons.star,
                            color: AppColors.gold,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      children: [
                        for (final row in const [
                          (5, 0.8),
                          (4, 0.15),
                          (3, 0.03),
                          (2, 0.01),
                          (1, 0.01),
                        ])
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Text(
                                  '${row.$1}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: ProgressBar(
                                    value: row.$2.toDouble(),
                                    dark: false,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Recent reviews',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            for (final review in _reviews)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: CardBox(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Avatar(name: review.$1.characters.first, size: 40),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  review.$1,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Row(
                                  children: List.generate(
                                    5,
                                    (i) => Icon(
                                      i < review.$2
                                          ? CupertinoIcons.star_fill
                                          : CupertinoIcons.star,
                                      color: AppColors.gold,
                                      size: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            review.$4,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        review.$3,
                        style: const TextStyle(
                          color: AppColors.ink,
                          height: 1.4,
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

class PlayerReviewsScreen extends StatelessWidget {
  const PlayerReviewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      body: AppScrollPage(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageTopBar(
              title: 'My Reviews',
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: uid == null
                  ? null
                  : FirebaseFirestore.instance
                        .collection('reviews')
                        .where('userId', isEqualTo: uid)
                        .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final reviews = snapshot.data?.docs ?? const [];
                if (reviews.isEmpty) {
                  return const CardBox(
                    child: Text(
                      'Reviews you submit after completed matches will appear here.',
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${reviews.length} submitted review${reviews.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final review in reviews)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: CardBox(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: List.generate(
                                  5,
                                  (index) => Icon(
                                    index <
                                            ((review.data()['rating'] as num?)
                                                    ?.toInt() ??
                                                0)
                                        ? CupertinoIcons.star_fill
                                        : CupertinoIcons.star,
                                    color: AppColors.gold,
                                    size: 16,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                review
                                            .data()['comment']
                                            ?.toString()
                                            .trim()
                                            .isNotEmpty ==
                                        true
                                    ? review.data()['comment'].toString()
                                    : 'No written comment',
                              ),
                              if (review.data()['tags'] is List) ...[
                                const SizedBox(height: 8),
                                Text(
                                  List<String>.from(
                                    review.data()['tags'] as List,
                                  ).join(' • '),
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
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
