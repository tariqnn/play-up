import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'main.dart';
import 'catalog.dart';
import 'test_data_seed.dart';
import 'more_screens.dart';
import 'more_screens2.dart';
import 'sport_activities_screen.dart';

enum _HubDestination { booking, matches, academies, activities }

class _SportHubCopy {
  const _SportHubCopy({
    required this.heroLine,
    required this.firstTitle,
    required this.firstSubtitle,
    required this.firstIcon,
    required this.secondTitle,
    required this.secondSubtitle,
    required this.secondIcon,
    required this.thirdTitle,
    required this.thirdSubtitle,
    required this.thirdIcon,
    required this.firstDestination,
    required this.secondDestination,
    required this.thirdDestination,
    this.adventure = false,
    this.groupsOnly = false,
  });

  final String heroLine;
  final String firstTitle;
  final String firstSubtitle;
  final IconData firstIcon;
  final String secondTitle;
  final String secondSubtitle;
  final IconData secondIcon;
  final String thirdTitle;
  final String thirdSubtitle;
  final IconData thirdIcon;
  final _HubDestination firstDestination;
  final _HubDestination secondDestination;
  final _HubDestination thirdDestination;
  final bool adventure;
  final bool groupsOnly;
}

/// Hub screen dedicated to a single sport (e.g. Padel, Football, Tennis, Basketball, Volleyball).
/// Fulfills the sport-first user flow: Select sport -> Choose Booking, Matchmaking, or Academies -> Cycle proceeds.
class SportHubScreen extends StatelessWidget {
  final String sport;
  final String? heroImageUrl;

  const SportHubScreen({super.key, required this.sport, this.heroImageUrl});

  static String _sportImage(String sport) {
    switch (sport.toLowerCase()) {
      case 'padel':
        return 'asset:assets/images/sports/tennis_court_ball.png';
      case 'football':
        return 'asset:assets/images/sports/football_court_ball.png';
      case 'tennis':
        return 'asset:assets/images/sports/tennis_court_ball.png';
      case 'basketball':
        return 'asset:assets/images/sports/basketball_court_ball.png';
      case 'volleyball':
        return 'asset:assets/images/sports/volleyball_court_ball.png';
      case 'cycling':
        return 'asset:assets/images/sports/cycling_group.jpg';
      case 'running':
        return 'asset:assets/images/sports/running_track.jpg';
      case 'badminton':
        return 'asset:assets/images/sports/tennis_court_ball.png';
      case 'sea sports':
        return 'https://images.unsplash.com/photo-1632904074880-b77f02b6d01e?w=1200&q=80';
      case 'dodgeball':
        return 'https://images.unsplash.com/photo-1593786930094-d5c8164ac771?w=1200&q=80';
      case 'kayaking':
        return 'https://images.unsplash.com/photo-1480480565647-1c4385c7c0bf?w=1200&q=80';
      case 'hiking':
        return 'https://images.unsplash.com/photo-1551632811-561732d1e306?w=1200&q=80';
      case 'climbing':
        return 'https://images.unsplash.com/photo-1522163182402-834f871fd851?w=1200&q=80';
      case 'fitness':
        return 'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?w=1200&q=80';
      default:
        return 'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=1200&q=80';
    }
  }

  static IconData _sportIcon(String sport) {
    switch (sport.toLowerCase()) {
      case 'padel':
      case 'tennis':
        return Icons.sports_tennis_rounded;
      case 'football':
        return Icons.sports_soccer_rounded;
      case 'basketball':
        return Icons.sports_basketball_rounded;
      case 'volleyball':
        return Icons.sports_volleyball_rounded;
      case 'badminton':
        return Icons.sports_tennis_rounded;
      case 'sea sports':
        return Icons.scuba_diving_rounded;
      case 'dodgeball':
        return Icons.sports_handball_rounded;
      case 'kayaking':
        return Icons.kayaking_rounded;
      case 'hiking':
        return Icons.hiking_rounded;
      case 'climbing':
        return Icons.landscape_rounded;
      case 'fitness':
        return Icons.fitness_center_rounded;
      default:
        return Icons.sports_rounded;
    }
  }

  static _SportHubCopy _copyFor(String sport) {
    switch (sport.toLowerCase()) {
      case 'sea sports':
        return const _SportHubCopy(
          heroLine: 'Parasailing, diving & unforgettable water adventures',
          firstTitle: 'Explore',
          firstSubtitle: 'Find sea experiences',
          firstIcon: Icons.scuba_diving_rounded,
          secondTitle: 'Book',
          secondSubtitle: 'Reserve an adventure',
          secondIcon: Icons.calendar_month_rounded,
          thirdTitle: 'Learn',
          thirdSubtitle: 'Guides & certifications',
          thirdIcon: Icons.workspace_premium_rounded,
          firstDestination: _HubDestination.activities,
          secondDestination: _HubDestination.activities,
          thirdDestination: _HubDestination.academies,
          adventure: true,
        );
      case 'cycling':
      case 'running':
        final cycling = sport.toLowerCase() == 'cycling';
        return _SportHubCopy(
          heroLine: cycling
              ? 'Find local cycling groups and rides'
              : 'Find local running groups and meetups',
          firstTitle: 'Find a group',
          firstSubtitle: cycling
              ? 'Join a cycling ride'
              : 'Join a running meetup',
          firstIcon: cycling
              ? Icons.directions_bike_rounded
              : Icons.directions_run_rounded,
          secondTitle: '',
          secondSubtitle: '',
          secondIcon: Icons.groups_rounded,
          thirdTitle: '',
          thirdSubtitle: '',
          thirdIcon: Icons.groups_rounded,
          firstDestination: _HubDestination.matches,
          secondDestination: _HubDestination.matches,
          thirdDestination: _HubDestination.matches,
          groupsOnly: true,
        );
      case 'kayaking':
        return const _SportHubCopy(
          heroLine: 'Kayak rentals, guided paddles & water skills',
          firstTitle: 'Paddle',
          firstSubtitle: 'Explore kayak trips',
          firstIcon: Icons.kayaking_rounded,
          secondTitle: 'Book',
          secondSubtitle: 'Reserve kayak & guide',
          secondIcon: Icons.calendar_month_rounded,
          thirdTitle: 'Learn',
          thirdSubtitle: 'Lessons & safety',
          thirdIcon: Icons.school_rounded,
          firstDestination: _HubDestination.activities,
          secondDestination: _HubDestination.activities,
          thirdDestination: _HubDestination.academies,
          adventure: true,
        );
      case 'hiking':
        return const _SportHubCopy(
          heroLine: 'Jordan trails, guided hikes & outdoor skills',
          firstTitle: 'Trails',
          firstSubtitle: 'Discover hiking routes',
          firstIcon: Icons.route_rounded,
          secondTitle: 'Guided',
          secondSubtitle: 'Book a guided hike',
          secondIcon: Icons.hiking_rounded,
          thirdTitle: 'Prepare',
          thirdSubtitle: 'Guides & trail skills',
          thirdIcon: Icons.backpack_rounded,
          firstDestination: _HubDestination.activities,
          secondDestination: _HubDestination.activities,
          thirdDestination: _HubDestination.academies,
          adventure: true,
        );
      case 'climbing':
        return const _SportHubCopy(
          heroLine: 'Indoor walls, outdoor climbs & expert instruction',
          firstTitle: 'Climb',
          firstSubtitle: 'Explore climbing spots',
          firstIcon: Icons.landscape_rounded,
          secondTitle: 'Sessions',
          secondSubtitle: 'Book a climb',
          secondIcon: Icons.calendar_month_rounded,
          thirdTitle: 'Coaching',
          thirdSubtitle: 'Technique & safety',
          thirdIcon: Icons.school_rounded,
          firstDestination: _HubDestination.activities,
          secondDestination: _HubDestination.activities,
          thirdDestination: _HubDestination.academies,
          adventure: true,
        );
      case 'fitness':
        return const _SportHubCopy(
          heroLine: 'CrossFit, HYROX, strength & functional training',
          firstTitle: 'Classes',
          firstSubtitle: 'Book your workout',
          firstIcon: Icons.calendar_month_rounded,
          secondTitle: 'Private',
          secondSubtitle: 'One-to-one training',
          secondIcon: Icons.person_rounded,
          thirdTitle: 'Programs',
          thirdSubtitle: 'CrossFit & HYROX plans',
          thirdIcon: Icons.fitness_center_rounded,
          firstDestination: _HubDestination.booking,
          secondDestination: _HubDestination.academies,
          thirdDestination: _HubDestination.academies,
        );
      default:
        return _SportHubCopy(
          heroLine: '$sport venues, matches & coaching across Amman',
          firstTitle: 'Book',
          firstSubtitle: 'Reserve a venue',
          firstIcon: CupertinoIcons.calendar_badge_plus,
          secondTitle: 'Play',
          secondSubtitle: 'Join open matches',
          secondIcon: CupertinoIcons.person_2_alt,
          thirdTitle: 'Train',
          thirdSubtitle: 'Academies & coaches',
          thirdIcon: Icons.school_rounded,
          firstDestination: _HubDestination.booking,
          secondDestination: _HubDestination.matches,
          thirdDestination: _HubDestination.academies,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = heroImageUrl ?? _sportImage(sport);
    final icon = _sportIcon(sport);
    final copy = _copyFor(sport);

    void openDestination(_HubDestination destination) {
      switch (destination) {
        case _HubDestination.activities:
          final activityCategory = switch (sport.toLowerCase()) {
            'sea sports' || 'kayaking' => 'Water',
            _ => 'All',
          };
          final activityQuery = switch (sport.toLowerCase()) {
            'sea sports' => '',
            'kayaking' => 'kayak',
            'hiking' => 'hiking',
            'climbing' => 'climbing',
            _ => sport,
          };
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SportActivitiesScreen(
                initialCategory: activityCategory,
                initialQuery: activityQuery,
              ),
            ),
          );
          return;
        case _HubDestination.booking:
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => Scaffold(
                appBar: AppBar(title: Text('$sport Booking')),
                body: BookScreen(initialSport: sport),
              ),
            ),
          );
          return;
        case _HubDestination.matches:
          if (copy.groupsOnly) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CommunityGroupsScreen(initialSport: sport),
              ),
            );
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OpenMatchesScreen(initialSport: sport),
            ),
          );
          return;
        case _HubDestination.academies:
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AcademiesListScreen(initialSport: sport),
            ),
          );
          return;
      }
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Hero Header with sporty photography and dark gradient
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            leading: IconButton(
              icon: const Icon(CupertinoIcons.back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(
                left: 20,
                bottom: 16,
                right: 20,
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Icon(icon, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$sport Hub',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl.startsWith('asset:'))
                    Image.asset(
                      imageUrl.substring(6),
                      fit: BoxFit.cover,
                      cacheWidth: 1600,
                      errorBuilder: (context, error, stackTrace) =>
                          Container(color: Colors.black),
                    )
                  else
                    CachedNetworkImage(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          Container(color: Colors.grey.shade900),
                      errorWidget: (context, url, error) =>
                          Container(color: Colors.black),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.black.withValues(alpha: 0.85),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 80,
                    left: 20,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'PLAYUP ACTIVITY HUB',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          copy.heroLine,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 3 Core Pathways as prominent, vibrant cards
                  Text(
                    'What would you like to do?',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (copy.groupsOnly)
                    _HubActionCard(
                      icon: copy.firstIcon,
                      title: copy.firstTitle,
                      subtitle: copy.firstSubtitle,
                      onTap: () => openDestination(copy.firstDestination),
                    )
                  else
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _HubActionCard(
                              icon: copy.firstIcon,
                              title: copy.firstTitle,
                              subtitle: copy.firstSubtitle,
                              onTap: () =>
                                  openDestination(copy.firstDestination),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _HubActionCard(
                              icon: copy.secondIcon,
                              title: copy.secondTitle,
                              subtitle: copy.secondSubtitle,
                              onTap: () =>
                                  openDestination(copy.secondDestination),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _HubActionCard(
                              icon: copy.thirdIcon,
                              title: copy.thirdTitle,
                              subtitle: copy.thirdSubtitle,
                              onTap: () =>
                                  openDestination(copy.thirdDestination),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (!copy.groupsOnly) const SizedBox(height: 28),

                  // Available Courts Preview Section
                  if (!copy.groupsOnly)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          copy.adventure
                              ? 'Available $sport Experiences'
                              : sport.toLowerCase() == 'fitness'
                              ? 'Fitness Studios & Classes'
                              : 'Available $sport Courts',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            if (copy.adventure) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const SportActivitiesScreen(),
                                ),
                              );
                              return;
                            }
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(
                                    leading: IconButton(
                                      icon: const Icon(CupertinoIcons.back),
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                    ),
                                    title: Text('$sport Courts'),
                                  ),
                                  body: BookScreen(initialSport: sport),
                                ),
                              ),
                            );
                          },
                          child: const Text('See All'),
                        ),
                      ],
                    ),
                  if (!copy.groupsOnly) const SizedBox(height: 8),

                  if (!copy.groupsOnly)
                    StreamBuilder<List<Court>>(
                      stream: CatalogService.instance.courts(),
                      initialData: useFirebaseEmulators
                          ? kTestCourts
                          : const <Court>[],
                      builder: (context, snapshot) {
                        final allCourts = snapshot.data ?? const <Court>[];
                        final matchingCourts = allCourts.where((c) {
                          return c.sport.toLowerCase() == sport.toLowerCase();
                        }).toList();

                        if (matchingCourts.isEmpty) {
                          return CardBox(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text(
                                  copy.adventure
                                      ? 'New $sport experiences are being added. Tap Explore above to browse current adventures.'
                                      : 'No $sport venues found at this moment.',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        return Column(
                          children: matchingCourts.take(3).map((court) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: CourtListCard(court: court),
                            );
                          }).toList(),
                        );
                      },
                    ),

                  if (copy.secondDestination == _HubDestination.matches) ...[
                    const SizedBox(height: 24),

                    // Active Open Matches Preview
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Active $sport Matches',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    OpenMatchesScreen(initialSport: sport),
                              ),
                            );
                          },
                          child: const Text('See All'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    StreamBuilder<List<OpenMatch>>(
                      stream: openMatchesStream(),
                      builder: (context, snapshot) {
                        final allMatches = snapshot.data ?? const <OpenMatch>[];
                        final matchingMatches = allMatches.where((m) {
                          return m.sport.toLowerCase() == sport.toLowerCase();
                        }).toList();

                        if (matchingMatches.isEmpty) {
                          return CardBox(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text(
                                  'No open $sport matches right now. Create the first one!',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        return Column(
                          children: matchingMatches.take(2).map((match) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: OpenMatchCard(match: match),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HubActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HubActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: Material(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 148),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.18),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: Colors.white, size: 23),
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                Icon(
                  CupertinoIcons.arrow_right,
                  color: theme.colorScheme.primary,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
