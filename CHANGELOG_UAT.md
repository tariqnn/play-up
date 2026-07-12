# UAT changelog

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
