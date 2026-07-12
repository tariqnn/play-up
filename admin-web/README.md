# PlayUp Administration Web

Dedicated React + TypeScript + Vite administration website. This is separate from the Flutter player/academy application and uses the same Firebase Auth, Firestore, Functions, roles, permissions, and tenant rules.

```powershell
npm install
Copy-Item .env.example .env.local
npm run dev
npm run build
```

For emulator UAT, set `VITE_USE_EMULATORS=true`. Never commit `.env.local` or passwords.
