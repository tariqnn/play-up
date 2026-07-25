import 'package:flutter_test/flutter_test.dart';
import 'package:playup/access_control.dart';

void main() {
  test('super administrator has every permission', () {
    const access = AccessContext(uid: 'root', role: AppRole.superAdmin);
    expect(access.can(Permissions.manageUsers), isTrue);
    expect(access.canAccessAcademy('any'), isTrue);
  });

  test('limited platform administrator only receives assigned permissions', () {
    const access = AccessContext(
      uid: 'admin',
      role: AppRole.platformAdmin,
      permissions: {Permissions.manageBookings},
    );
    expect(access.can(Permissions.manageBookings), isTrue);
    expect(access.can(Permissions.manageUsers), isFalse);
  });

  test('academy users are isolated to their tenant', () {
    const access = AccessContext(
      uid: 'owner-a',
      role: AppRole.academyOwner,
      academyId: 'academy-a',
    );
    expect(access.canAccessAcademy('academy-a'), isTrue);
    expect(access.canAccessAcademy('academy-b'), isFalse);
  });

  test('court owners only access their assigned court', () {
    const access = AccessContext(
      uid: 'court-owner',
      role: AppRole.courtOwner,
      academyId: 'academy-a',
      courtIds: {'court-a'},
    );
    expect(access.canAccessCourt('court-a', 'academy-a'), isTrue);
    expect(access.canAccessCourt('court-b', 'academy-a'), isFalse);
    expect(access.canAccessCourt('court-a', 'academy-b'), isFalse);
  });

  test('suspended users have no access', () {
    const access = AccessContext(
      uid: 'staff',
      role: AppRole.academyStaff,
      academyId: 'academy-a',
      permissions: {Permissions.checkIn},
      suspended: true,
    );
    expect(access.can(Permissions.checkIn), isFalse);
  });
}
