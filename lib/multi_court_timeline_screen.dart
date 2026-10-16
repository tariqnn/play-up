import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'catalog.dart';
import 'main.dart';

class MultiCourtTimelineScreen extends StatefulWidget {
  const MultiCourtTimelineScreen({
    super.key,
    required this.academyId,
    this.initialCourtId,
  });

  final String academyId;
  final String? initialCourtId;

  @override
  State<MultiCourtTimelineScreen> createState() =>
      _MultiCourtTimelineScreenState();
}

class _MultiCourtTimelineScreenState extends State<MultiCourtTimelineScreen> {
  int _dayIndex = 0;
  final Map<String, Set<int>> _courtUnavailableStarts = {};
  bool _loadingAvailability = false;

  @override
  void initState() {
    super.initState();
    _fetchAvailability();
  }

  Future<void> _fetchAvailability() async {
    setState(() => _loadingAvailability = true);
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day).add(
      Duration(days: _dayIndex),
    );
    final rangeStart = DateTime(day.year, day.month, day.day, 6).toUtc();
    final rangeEnd = DateTime(day.year, day.month, day.day, 24).toUtc();

    try {
      final allCourts = await CatalogService.instance.courts().first;
      final academyCourts = allCourts.where((c) {
        if (widget.academyId.isNotEmpty) {
          return c.academyId == widget.academyId;
        }
        return true;
      }).toList();

      for (final c in academyCourts) {
        try {
          final unavailable = await AppRepository.instance
              .unavailableCourtSlotStarts(
                courtId: c.id,
                rangeStartUtc: rangeStart,
                rangeEndUtc: rangeEnd,
              );
          _courtUnavailableStarts[c.id] = unavailable;
        } catch (_) {
          _courtUnavailableStarts[c.id] = const {};
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingAvailability = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final selectedDay = DateTime(now.year, now.month, now.day).add(
      Duration(days: _dayIndex),
    );

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  CircleIconButton(
                    icon: CupertinoIcons.arrow_left,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Multi-Court Timeline',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (_loadingAvailability)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            // Date selector
            SizedBox(
              height: 64,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 7,
                itemBuilder: (context, index) {
                  final day = DateTime(
                    now.year,
                    now.month,
                    now.day,
                  ).add(Duration(days: index));
                  final selected = index == _dayIndex;
                  return GestureDetector(
                    onTap: () {
                      if (_dayIndex != index) {
                        setState(() => _dayIndex = index);
                        _fetchAvailability();
                      }
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.primary
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            index == 0
                                ? 'Today'
                                : index == 1
                                ? 'Tmrw'
                                : DateFormat('EEE').format(day),
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : scheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            DateFormat('d MMM').format(day),
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : scheme.onSurface,
                              fontSize: 14,
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
            const SizedBox(height: 10),
            // Legend
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _legendDot(const Color(0xFF22C55E), 'Available'),
                  const SizedBox(width: 14),
                  _legendDot(AppColors.gold, 'Peak Rate'),
                  const SizedBox(width: 14),
                  _legendDot(Colors.grey.shade600, 'Booked / Closed'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            // Timeline Matrix
            Expanded(
              child: StreamBuilder<List<Court>>(
                stream: CatalogService.instance.courts(),
                builder: (context, snapshot) {
                  final allCourts = snapshot.data ?? const <Court>[];
                  final courts = allCourts.where((c) {
                    if (widget.academyId.isNotEmpty) {
                      return c.academyId == widget.academyId;
                    }
                    return true;
                  }).toList();

                  if (courts.isEmpty) {
                    return const Center(
                      child: Text('No courts found for this venue.'),
                    );
                  }

                  // Operating hours bounds across courts
                  final minHour = courts
                      .map((c) => c.openingHour)
                      .reduce((a, b) => a < b ? a : b);
                  final maxHour = courts
                      .map((c) => c.closingHour)
                      .reduce((a, b) => a > b ? a : b);

                  return SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Court headers
                          Row(
                            children: [
                              const SizedBox(width: 64),
                              for (final court in courts)
                                Container(
                                  width: 140,
                                  margin: const EdgeInsets.only(right: 10),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: court.id == widget.initialCourtId
                                          ? scheme.primary
                                          : scheme.outlineVariant,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        court.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        court.sport,
                                        style: TextStyle(
                                          color: scheme.onSurfaceVariant,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Hour rows
                          for (var hour = minHour; hour < maxHour; hour++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 64,
                                    child: Text(
                                      DateFormat.jm().format(
                                        DateTime(2026, 1, 1, hour),
                                      ),
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  for (final court in courts)
                                    _buildCell(
                                      context,
                                      court,
                                      hour,
                                      selectedDay,
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
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildCell(
    BuildContext context,
    Court court,
    int hour,
    DateTime selectedDay,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final start = DateTime(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day,
      hour,
    );
    final end = start.add(const Duration(hours: 1));
    final now = DateTime.now();

    // Check if court is open at this hour
    final isOpen = hour >= court.openingHour && hour < court.closingHour;
    final isPast = !start.isAfter(now);

    // Check availability against downloaded locks
    final unavailable = _courtUnavailableStarts[court.id] ?? const <int>{};
    final isBooked =
        unavailable.contains(start.toUtc().millisecondsSinceEpoch) ||
        unavailable.contains(
          start.add(const Duration(minutes: 30)).toUtc().millisecondsSinceEpoch,
        );

    final canBook = isOpen && !isPast && !isBooked;
    final isPeak = court.isPeakHour(hour);
    final rateMinor = court.effectiveHourlyRateMinor(hour);

    Color cellColor;
    Color borderColor;
    String label;

    if (!isOpen || isPast) {
      cellColor = scheme.surfaceContainerLowest.withValues(alpha: 0.5);
      borderColor = Colors.transparent;
      label = isPast ? 'Past' : 'Closed';
    } else if (isBooked) {
      cellColor = scheme.surfaceContainerHighest.withValues(alpha: 0.6);
      borderColor = scheme.outlineVariant;
      label = 'Booked';
    } else {
      cellColor = isPeak
          ? AppColors.gold.withValues(alpha: 0.14)
          : const Color(0xFF22C55E).withValues(alpha: 0.12);
      borderColor = isPeak
          ? AppColors.gold.withValues(alpha: 0.6)
          : const Color(0xFF22C55E).withValues(alpha: 0.5);
      label = isPeak ? 'Peak' : 'Available';
    }

    return GestureDetector(
      onTap: canBook
          ? () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BookingSetupScreen(
                    court: court,
                    startUtc: start.toUtc(),
                    endUtc: end.toUtc(),
                  ),
                ),
              );
            }
          : null,
      child: Container(
        width: 140,
        height: 52,
        margin: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          color: cellColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              canBook
                  ? '${court.currency} ${(rateMinor / 100).toStringAsFixed(0)}'
                  : label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: canBook
                    ? (isPeak ? const Color(0xFFB8860B) : const Color(0xFF15803D))
                    : scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            if (canBook && isPeak)
              const Text(
                '★ Peak',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFB8860B),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
