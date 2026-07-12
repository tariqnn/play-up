# UAT test plan

1. Authenticate as every role; verify portal visibility and denied direct writes.
2. With Academy A, attempt reads/updates for Academy B courts, bookings and offers; expect permission denied.
3. Submit two concurrent transactions for the same court/start UTC; expect exactly one booking and lock.
4. Verify cancellation and check-in transitions; completed/cancelled records cannot be reopened.
5. Create/join matchmaking requests; verify duplicate, full, suspended and conflict cases.
6. Reorder, resize, hide and save dashboard widgets; sign out/in and verify restoration.
7. Exercise empty/loading/error states on throttled and offline networks.
8. Run keyboard navigation, screen reader, 200% text scale, phone/tablet portrait/landscape checks.
9. Run the commands in README and verify the release build.
