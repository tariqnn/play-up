# Role and permission matrix

| Capability | Super Admin | Platform Admin | Academy Owner | Academy Staff | Player |
|---|---|---|---|---|---|
| Platform settings, roles, delete | Full | Assigned only | No | No | No |
| Users, bookings, matchmaking | Full | Assigned only | Own academy bookings | Assigned academy actions | Own records |
| Academies and courts | Full | Assigned only | Own academy CRUD | Assigned own-academy CRUD | View public |
| Approve/export/reports | Full | Assigned only | Own academy reports | Assigned own-academy reports | No |
| Check-in | Full | Assigned only | Own academy | If assigned | No |
| Dashboard configuration | Own layout | Own layout | Own layout | Own layout | No admin dashboard |
| Audit logs | Full | If assigned | No platform log | No | No |

Platform administrators and academy staff use the `permissions` array. Academy isolation is enforced in Firestore rules using the authenticated user's immutable `academyId`.
