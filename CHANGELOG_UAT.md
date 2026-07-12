# UAT changelog

## 2026-07-13 functional cycle

- Replaced static rewards with transactional points, ledgers, redemption codes and duplicate protection.
- Added cash-pending bookings, cash collection, booking invite links, owner notifications and audited transitions.
- Replaced simulated matchmaking and in-memory chat with live, membership-protected Firestore workflows.
- Added live academy dashboards, academy profile editing, staff provisioning and operational booking controls.
- Added biometric session unlock, mobile deep links, adaptive platform configuration and admin website CRUD.

- Added explicit super admin, platform admin, academy owner, academy staff and player access model.
- Enforced academy tenant ownership and blocked client privilege escalation.
- Added transaction-backed booking slot locks and domain transition validation.
- Added matchmaking duplicate/capacity/suspension/conflict validation.
- Added persistent per-user platform and academy dashboard layouts.
- Added security, role, booking and matchmaking tests and UAT documentation.
- Added Firebase Cloud Functions for authoritative quotes, booking creation/status, matchmaking, notifications and protected user/UAT provisioning.
- Replaced academy court, booking and analytics sample workflows with tenant-scoped live data.
- Added behavioral Firestore rules tests and zero-vulnerability Node dependency audits.
- Generated exact Android adaptive/legacy and iOS launcher icon sets from the supplied root artwork.
