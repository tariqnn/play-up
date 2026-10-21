import { initializeApp } from 'firebase/app';
import { initializeAppCheck, ReCaptchaEnterpriseProvider } from 'firebase/app-check';
import { connectAuthEmulator, getAuth } from 'firebase/auth';
import { connectFirestoreEmulator, getFirestore } from 'firebase/firestore';
import { connectFunctionsEmulator, getFunctions } from 'firebase/functions';

const useEmulators = import.meta.env.VITE_USE_EMULATORS === 'true';
const suppliedConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY as string | undefined,
  appId: import.meta.env.VITE_FIREBASE_APP_ID as string | undefined,
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID as string | undefined,
};
const missing = Object.entries(suppliedConfig)
  .filter(([, value]) => !value || value.startsWith('your-'))
  .map(([key]) => key);
const appCheckKey = import.meta.env.VITE_FIREBASE_APP_CHECK_KEY as string | undefined;
const requireAppCheck = import.meta.env.VITE_REQUIRE_APP_CHECK !== 'false';
const appCheckMissing = !appCheckKey || appCheckKey.startsWith('your-');
if (!useEmulators && requireAppCheck && appCheckMissing) {
  missing.push('appCheckKey');
}
export const appCheckWarning = !useEmulators && !requireAppCheck && appCheckMissing
  ? 'UAT preview: App Check is not enabled on this temporary build.'
  : '';
export const functionsAvailable = import.meta.env.VITE_FUNCTIONS_AVAILABLE !== 'false';
export const configurationError = !useEmulators && missing.length > 0
  ? `Set the production Firebase ${missing.join(', ')} environment value${missing.length === 1 ? '' : 's'} before deploying this admin build.`
  : '';
export const firebaseConfig = {
  apiKey: suppliedConfig.apiKey || 'emulator-key',
  appId: suppliedConfig.appId || 'emulator-app',
  projectId: suppliedConfig.projectId || 'playup-emulator',
  authDomain: `${suppliedConfig.projectId || 'playup-emulator'}.firebaseapp.com`,
};
const app = initializeApp(firebaseConfig);
if (!useEmulators && !configurationError && !appCheckMissing && appCheckKey) {
  initializeAppCheck(app, {
    provider: new ReCaptchaEnterpriseProvider(appCheckKey),
    isTokenAutoRefreshEnabled: true,
  });
}
export const auth = getAuth(app);
export const db = getFirestore(app);
export const functions = getFunctions(app, import.meta.env.VITE_FIREBASE_REGION || 'me-central1');
if (useEmulators) {
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  connectFirestoreEmulator(db, '127.0.0.1', 8080);
  connectFunctionsEmulator(functions, '127.0.0.1', 5001);
}
