import { initializeApp } from 'firebase/app';
import { connectAuthEmulator, getAuth } from 'firebase/auth';
import { connectFirestoreEmulator, getFirestore } from 'firebase/firestore';
import { connectFunctionsEmulator, getFunctions } from 'firebase/functions';

const app = initializeApp({
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY || 'emulator-key',
  appId: import.meta.env.VITE_FIREBASE_APP_ID || '1:634238605050:web:c0eaf211bbf88ebc45db43',
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID || 'sports-app-257a0',
  authDomain: 'sports-app-257a0.firebaseapp.com',
});
export const auth = getAuth(app);
export const db = getFirestore(app);
export const functions = getFunctions(app, 'me-central1');
if (import.meta.env.VITE_USE_EMULATORS === 'true') {
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  connectFirestoreEmulator(db, '127.0.0.1', 8080);
  connectFunctionsEmulator(functions, '127.0.0.1', 5001);
}
