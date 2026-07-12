enum AppRole {
  superAdmin,
  platformAdmin,
  academyOwner,
  academyStaff,
  player;

  static AppRole parse(Object? value) => switch (value) {
    'superAdmin' => superAdmin,
    'platformAdmin' => platformAdmin,
    'academyOwner' => academyOwner,
    'academyStaff' => academyStaff,
    _ => player,
  };
}

abstract final class Permissions {
  static const managePlatform = 'platform.manage';
  static const manageUsers = 'users.manage';
  static const manageAcademies = 'academies.manage';
  static const manageBookings = 'bookings.manage';
  static const manageMatchmaking = 'matchmaking.manage';
  static const manageAcademyProfile = 'academy.profile.manage';
  static const manageAcademyCourts = 'academy.courts.manage';
  static const manageAcademyBookings = 'academy.bookings.manage';
  static const checkIn = 'academy.bookings.checkin';
  static const viewAcademyReports = 'academy.reports.view';
  static const configureDashboard = 'dashboard.configure';
  static const viewAuditLogs = 'audit.view';
}

class AccessContext {
  const AccessContext({
    required this.uid,
    required this.role,
    this.academyId,
    this.permissions = const {},
    this.suspended = false,
  });

  factory AccessContext.fromMap(String uid, Map<String, dynamic> data) =>
      AccessContext(
        uid: uid,
        role: AppRole.parse(data['role']),
        academyId: data['academyId'] as String?,
        permissions: (data['permissions'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toSet(),
        suspended: data['suspended'] == true,
      );

  final String uid;
  final AppRole role;
  final String? academyId;
  final Set<String> permissions;
  final bool suspended;

  bool get isPlatformAdmin =>
      role == AppRole.superAdmin || role == AppRole.platformAdmin;
  bool get isAcademyUser =>
      role == AppRole.academyOwner || role == AppRole.academyStaff;

  bool can(String permission) {
    if (suspended) return false;
    if (role == AppRole.superAdmin) return true;
    if (role == AppRole.academyOwner && permission.startsWith('academy.')) {
      return true;
    }
    return permissions.contains(permission);
  }

  bool canAccessAcademy(String requestedAcademyId) =>
      !suspended &&
      ((isPlatformAdmin && can(Permissions.manageAcademies)) ||
          (isAcademyUser && academyId == requestedAcademyId));
}
