/// Returns whether a public profile represents a real player eligible for
/// public leaderboard rankings.
bool isLeaderboardProfileEligible(Map<String, dynamic> profile) {
  final displayName = (profile['displayName'] ?? '').toString().trim();
  final normalizedName = displayName.toLowerCase();
  if (profile['isTest'] == true ||
      profile['isDemo'] == true ||
      profile['isGuest'] == true ||
      displayName.isEmpty ||
      normalizedName == 'player' ||
      normalizedName == 'guest player') {
    return false;
  }
  return !RegExp(r'\b(uat|demo|test|sample|dummy|placeholder)\b')
      .hasMatch(normalizedName);
}
