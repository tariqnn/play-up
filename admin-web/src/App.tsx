import { FormEvent, useEffect, useMemo, useRef, useState } from "react";
import {
  signInWithEmailAndPassword,
  sendPasswordResetEmail,
  signOut,
  User,
} from "firebase/auth";
import {
  addDoc,
  collection,
  deleteDoc,
  doc,
  getCountFromServer,
  onSnapshot,
  serverTimestamp,
  setDoc,
  Timestamp,
} from "firebase/firestore";
import { httpsCallable } from "firebase/functions";
import {
  Activity,
  AlertTriangle,
  ArrowUpRight,
  Building2,
  CalendarDays,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  CircleDollarSign,
  Clock3,
  Download,
  Dumbbell,
  Edit3,
  Eye,
  EyeOff,
  LifeBuoy,
  LayoutDashboard,
  LogOut,
  Menu,
  PanelLeftClose,
  PanelLeftOpen,
  Plus,
  Search,
  Settings,
  ShieldCheck,
  Star,
  TicketPercent,
  Trash2,
  TrendingUp,
  Users,
  UserPlus,
  X,
} from "lucide-react";
import {
  appCheckWarning,
  auth,
  configurationError,
  db,
  functions,
  functionsAvailable,
} from "./firebase";

function PlayUpLogo({ className = "", label }: { className?: string; label?: string }) {
  return (
    <svg
      className={`playup-logo ${className}`.trim()}
      viewBox="0 0 48 48"
      role={label ? "img" : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
    >
      <path d="M8 8h25a8 8 0 0 1 0 16H21L8 37V24h8l8-8H8V8Z" />
      <rect x="23" y="27" width="17" height="12" rx="6" />
    </svg>
  );
}

type Module = {
  label: string;
  collection?: string;
  icon: typeof Activity;
  columns?: string[];
  permission?: string;
  superAdminOnly?: boolean;
  readOnlyColumns?: string[];
  timestampColumns?: string[];
};
const modules: Module[] = [
  {
    label: "Dashboard",
    icon: LayoutDashboard,
    superAdminOnly: true,
  },
  {
    label: "Academies",
    collection: "academies",
    icon: Building2,
    permission: "academies.manage",
    columns: ["name", "status", "currency"],
  },
  {
    label: "Courts",
    collection: "courts",
    icon: Dumbbell,
    permission: "academies.manage",
    columns: [
      "name",
      "sport",
      "academyId",
      "active",
      "basePriceMinor",
      "openingHour",
      "closingHour",
      "timezone",
    ],
  },
  {
    label: "Bookings",
    collection: "bookings",
    icon: CalendarDays,
    permission: "bookings.manage",
    columns: [
      "courtName",
      "userId",
      "academyId",
      "status",
      "paymentStatus",
      "paymentMethod",
      "totalMinor",
      "cashCollectedMinor",
      "platformCommissionMinor",
      "settlementStatus",
    ],
  },
  {
    label: "Users",
    collection: "users",
    icon: Users,
    permission: "users.manage",
    columns: ["displayName", "email", "role", "academyId", "suspended"],
  },
  { label: "Owner Accounts", icon: UserPlus, permission: "users.manage" },
  {
    label: "Matchmaking",
    collection: "matches",
    icon: Activity,
    permission: "matchmaking.manage",
    columns: ["title", "sport", "hostName", "status", "capacity"],
  },
  {
    label: "Reviews",
    collection: "reviews",
    icon: Star,
    permission: "platform.manage",
    columns: ["userId", "rating", "comment", "hidden"],
    readOnlyColumns: ["userId", "rating", "comment"],
  },
  {
    label: "Support",
    collection: "supportTickets",
    icon: LifeBuoy,
    permission: "users.manage",
    columns: ["category", "userId", "status", "message", "createdAt"],
    readOnlyColumns: ["category", "userId", "message", "createdAt"],
  },
  {
    label: "Promotions",
    collection: "promotions",
    icon: TicketPercent,
    permission: "platform.manage",
    columns: [
      "code",
      "discountType",
      "discountValue",
      "academyId",
      "courtId",
      "minimumSpendMinor",
      "usageLimit",
      "perUserLimit",
      "usageCount",
      "startsAt",
      "endsAt",
      "active",
    ],
    readOnlyColumns: ["usageCount"],
    timestampColumns: ["startsAt", "endsAt"],
  },
  {
    label: "Achievements",
    collection: "achievements",
    icon: Star,
    permission: "platform.manage",
    columns: [
      "title",
      "description",
      "metric",
      "goal",
      "rewardPoints",
      "color",
      "active",
    ],
  },
  {
    label: "Tournaments",
    collection: "tournaments",
    icon: CalendarDays,
    permission: "platform.manage",
    columns: [
      "name",
      "sport",
      "format",
      "teamSize",
      "maxEntries",
      "status",
      "academyId",
    ],
  },
  {
    label: "Audit logs",
    collection: "auditLogs",
    icon: ShieldCheck,
    permission: "audit.view",
    columns: ["action", "actorId", "entity", "entityId", "academyId"],
  },
  { label: "Settings", icon: Settings, permission: "platform.manage" },
];

const navigationGroupDefinitions = [
  { label: "Overview", modules: ["Dashboard"] },
  { label: "Operations", modules: ["Academies", "Courts", "Bookings"] },
  {
    label: "People & service",
    modules: ["Users", "Owner Accounts", "Matchmaking", "Reviews", "Support"],
  },
  { label: "Growth", modules: ["Promotions", "Achievements", "Tournaments"] },
  { label: "System", modules: ["Audit logs", "Settings"] },
] as const;

const moduleDescriptions: Record<string, string> = {
  Dashboard: "See what needs attention and keep today's operations moving.",
  Academies: "Manage partner academies, their courts and their operating details.",
  Courts: "Keep sports, opening hours and court prices up to date.",
  Bookings: "Find reservations, confirm arrivals and track cash collected at the venue.",
  Users: "Review player and team accounts and their assigned access.",
  "Owner Accounts": "Give an academy or court owner access to their workspace.",
  Matchmaking: "Review open matches, hosts and available player places.",
  Reviews: "Review player feedback and hide inappropriate comments.",
  Support: "Track requests from players and partners through to resolution.",
  Promotions: "Create discount codes and control when and where they apply.",
  Achievements: "Set clear goals and rewards for player progress.",
  Tournaments: "Review competitions, capacity and registration status.",
  "Audit logs": "Trace who changed a record and when.",
  Settings: "Manage platform contact details, policies and availability.",
};
function sectionSlug(label: string) { return label.toLowerCase().replaceAll(" ", "-"); }
function humanValue(value: unknown): string {
  if (typeof value === "boolean") return value ? "Yes" : "No";
  return String(value ?? "—").replace(/([a-z])([A-Z])/g, "$1 $2").replaceAll("_", " ");
}

type AdminProfile = { role: string; permissions: string[] };

export default function App() {
  const [user, setUser] = useState<User | null>(null);
  const [allowed, setAllowed] = useState(false);
  const [loading, setLoading] = useState(true);
  const [profile, setProfile] = useState<AdminProfile | null>(null);
  const [active, setActive] = useState(0);
  const [route, setRoute] = useState(() => window.location.hash.slice(1));
  useEffect(() => {
    const changed = () => setRoute(window.location.hash.slice(1));
    window.addEventListener("hashchange", changed);
    return () => window.removeEventListener("hashchange", changed);
  }, []);
  const [mobile, setMobile] = useState(false);
  const [navQuery, setNavQuery] = useState("");
  const [sidebarCollapsed, setSidebarCollapsed] = useState(
    () => localStorage.getItem("playup-admin-sidebar-collapsed") === "true",
  );
  const [now, setNow] = useState(() => new Date());
  const mainContent = useRef<HTMLElement>(null);
  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), 30_000);
    return () => clearInterval(timer);
  }, []);
  useEffect(() => {
    let stopProfile: (() => void) | undefined;
    const stopAuth = auth.onAuthStateChanged(
      (next) => {
        stopProfile?.();
        stopProfile = undefined;
        setUser(next);
        if (!next) {
          setAllowed(false);
          setProfile(null);
          setLoading(false);
          return;
        }
        setLoading(true);
        stopProfile = onSnapshot(
          doc(db, "users", next.uid),
          (snap) => {
            const data = snap.data();
            const role = String(data?.role ?? "");
            const permissions = Array.isArray(data?.permissions)
              ? data.permissions.map(String)
              : [];
            setProfile({ role, permissions });
            setAllowed(role === "superAdmin" || role === "platformAdmin");
            setLoading(false);
          },
          () => {
            setAllowed(false);
            setProfile(null);
            setLoading(false);
          },
        );
      },
      () => setLoading(false),
    );
    return () => {
      stopProfile?.();
      stopAuth();
    };
  }, []);
  const visibleModules = useMemo(() => {
    if (!profile) return [];
    if (profile.role === "superAdmin") return modules;
    return modules.filter(
      (module) =>
        !module.superAdminOnly &&
        !!module.permission &&
        profile.permissions.includes(module.permission),
    );
  }, [profile]);
  useEffect(() => {
    const index = visibleModules.findIndex((module) => sectionSlug(module.label) === route);
    setActive(index >= 0 ? index : 0);
  }, [route, visibleModules]);
  function navigateTo(label: string) {
    const index = visibleModules.findIndex((module) => module.label === label);
    if (index < 0) return;
    setActive(index);
    window.location.hash = sectionSlug(label);
    setMobile(false);
  }
  useEffect(() => {
    if (active >= visibleModules.length) setActive(0);
  }, [active, visibleModules.length]);
  useEffect(() => {
    if (!mobile) return;
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") setMobile(false);
    };
    window.addEventListener("keydown", closeOnEscape);
    return () => window.removeEventListener("keydown", closeOnEscape);
  }, [mobile]);
  useEffect(() => {
    localStorage.setItem(
      "playup-admin-sidebar-collapsed",
      String(sidebarCollapsed),
    );
  }, [sidebarCollapsed]);
  useEffect(() => {
    if (!loading && user && allowed) mainContent.current?.focus();
  }, [active]);
  if (configurationError)
    return (
      <div className="center">
        <div className="login" role="alert">
          <AlertTriangle size={36} />
          <h1>Configuration required</h1>
          <p>{configurationError}</p>
        </div>
      </div>
    );
  if (loading)
    return (
      <div className="center">
        <div className="spinner" />
      </div>
    );
  if (!user) return <Login />;
  if (!allowed)
    return (
      <div className="center">
        <div className="login">
          <ShieldCheck size={36} />
          <h1>Access denied</h1>
          <p>This account is not a platform administrator.</p>
          <button onClick={() => signOut(auth)}>Sign out</button>
        </div>
      </div>
    );
  if (!visibleModules.length)
    return (
      <div className="center">
        <div className="login">
          <ShieldCheck size={36} />
          <h1>No assigned permissions</h1>
          <p>
            Ask a super administrator to assign the modules required for this
            role.
          </p>
          <button onClick={() => signOut(auth)}>Sign out</button>
        </div>
      </div>
    );
  const current = visibleModules[active];
  const navigationModules = visibleModules.filter((module) =>
    module.label.toLowerCase().includes(navQuery.trim().toLowerCase()),
  );
  const navigationGroups = navigationGroupDefinitions
    .map((group) => ({
      label: group.label,
      modules: navigationModules.filter((module) =>
        group.modules.some((label) => label === module.label),
      ),
    }))
    .filter((group) => group.modules.length > 0);
  const accountName = user.displayName?.trim() || "PlayUp administrator";
  const accountInitials = accountName
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join("");
  return (
    <div
      className={`shell${sidebarCollapsed ? " sidebar-collapsed" : ""}`}
    >
      <a className="skip-link" href="#main-content">
        Skip to main content
      </a>
      {mobile && (
        <button
          className="nav-scrim"
          aria-label="Close navigation"
          onClick={() => setMobile(false)}
        />
      )}
      <aside className={mobile ? "open" : ""}>
        <div className="brand">
          <div className="brand-mark">
            <PlayUpLogo />
            <span className="brand-copy">
              <strong>PlayUp</strong>
              <small>Admin console</small>
            </span>
          </div>
          <button
            className="collapse-sidebar"
            aria-label={sidebarCollapsed ? "Expand navigation" : "Collapse navigation"}
            aria-expanded={!sidebarCollapsed}
            onClick={() => setSidebarCollapsed((collapsed) => !collapsed)}
          >
            {sidebarCollapsed ? <PanelLeftOpen /> : <PanelLeftClose />}
          </button>
          <button
            className="close"
            aria-label="Close navigation"
            onClick={() => setMobile(false)}
          >
            <X />
          </button>
        </div>
        <label className="nav-search">
          <Search size={17} aria-hidden="true" />
          <span className="sr-only">Find an admin section</span>
          <input
            type="search"
            value={navQuery}
            onChange={(event) => setNavQuery(event.target.value)}
            placeholder="Find a section"
          />
        </label>
        <nav aria-label="Admin sections">
          {navigationGroups.map((group) => (
            <section className="nav-group" key={group.label}>
              <h2>{group.label}</h2>
              <div className="nav-group-items">
                {group.modules.map((m) => {
                  const moduleIndex = visibleModules.indexOf(m);
                  return (
                    <button
                      key={m.label}
                      className={active === moduleIndex ? "active" : ""}
                      aria-current={active === moduleIndex ? "page" : undefined}
                      aria-label={m.label}
                      title={m.label}
                      onClick={() => navigateTo(m.label)}
                    >
                      <span className="nav-icon">
                        <m.icon size={19} aria-hidden="true" />
                      </span>
                      <span className="nav-item-label">{m.label}</span>
                    </button>
                  );
                })}
              </div>
            </section>
          ))}
          {!navigationModules.length && (
            <p className="nav-empty">No sections match “{navQuery}”.</p>
          )}
        </nav>
        <div className="account">
          <div className="account-identity">
            <span className="account-avatar" aria-hidden="true">
              {accountInitials || "PA"}
            </span>
            <span className="account-copy">
              <strong>{accountName}</strong>
              <small>{user.email}</small>
              <span className="account-role">
                {profile?.role === "superAdmin" ? "Super admin" : "Platform admin"}
              </span>
            </span>
          </div>
          <button
            className="account-signout"
            aria-label="Sign out"
            title="Sign out"
            onClick={() => signOut(auth)}
          >
            <LogOut size={18} aria-hidden="true" />
            <span>Sign out</span>
          </button>
        </div>
      </aside>
      <main id="main-content" ref={mainContent} tabIndex={-1}>
        <header>
          <button
            className="hamburger"
            aria-label="Open navigation"
            onClick={() => setMobile(true)}
          >
            <Menu />
          </button>
          <div className="header-crumb">
            <span className="header-crumb-section">{current.label}</span>
            <span className="header-crumb-time">
              {now.toLocaleDateString(undefined, {
                weekday: "long",
                month: "short",
                day: "numeric",
              })}{" "}
              ·{" "}
              {now.toLocaleTimeString(undefined, {
                hour: "numeric",
                minute: "2-digit",
              })}
            </span>
          </div>
          <div className="avatar" title={user.email ?? ""}>
            {user.email?.[0].toUpperCase()}
          </div>
        </header>
        {(appCheckWarning || !functionsAvailable) && (
          <div className="uat-banner" role="status">
            <AlertTriangle size={16} />
            <span>
              {appCheckWarning}
              {appCheckWarning && !functionsAvailable ? " " : ""}
              {!functionsAvailable
                ? "Server actions are unavailable until Firebase billing and Cloud Functions are enabled."
                : ""}
            </span>
          </div>
        )}
        {current.label === "Dashboard" ? (
          <Dashboard onNavigate={navigateTo} />
        ) : current.label === "Academies" ? (
          <AcademyPortfolio />
        ) : current.label === "Owner Accounts" ? (
          <OwnerAccounts />
        ) : current.collection ? (
          <DataModule key={current.label} module={current} />
        ) : (
          <SettingsPage />
        )}
      </main>
    </div>
  );
}

type LiveRow = Record<string, unknown> & { id: string };

async function createManagedAccount(input: {
  ownerType: "academy" | "court" | "community";
  academyId?: string;
  courtId?: string;
  communityId?: string;
  communityName?: string;
  sport?: string;
  description?: string;
  displayName: string;
  email: string;
}) {
  const callable = httpsCallable<typeof input, { uid: string }>(
    functions,
    "createManagedOwnerAccount",
  );
  const response = await callable({
    ...input,
    email: input.email.trim().toLowerCase(),
    displayName: input.displayName.trim(),
  });
  return response.data.uid;
}

function OwnerAccounts() {
  const [academies, setAcademies] = useState<LiveRow[]>([]);
  const [courts, setCourts] = useState<LiveRow[]>([]);
  const [ownerType, setOwnerType] = useState<"academy" | "court" | "community">("academy");
  const [academyId, setAcademyId] = useState("");
  const [courtId, setCourtId] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [email, setEmail] = useState("");
  const [communityName, setCommunityName] = useState("");
  const [communitySport, setCommunitySport] = useState("Basketball");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [resetEmail, setResetEmail] = useState("");
  useEffect(() => {
    const a = onSnapshot(collection(db, "academies"), (snap) =>
      setAcademies(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
    );
    const c = onSnapshot(collection(db, "courts"), (snap) =>
      setCourts(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
    );
    return () => {
      a();
      c();
    };
  }, []);
  const availableCourts = courts.filter((c) => c.academyId === academyId);
  async function create(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    setMessage("");
    let accountCreated = false;
    try {
      await createManagedAccount({
        ownerType,
        ...(ownerType !== "community" ? { academyId } : {
          communityName: communityName.trim(),
          communityId: communityName.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "").slice(0, 48),
          sport: communitySport.trim(),
          description: `${communitySport.trim()} community activities and weekly meetups.`,
        }),
        courtId: ownerType === "court" ? courtId : undefined,
        displayName,
        email,
      });
      accountCreated = true;
      setResetEmail(email);
      await sendPasswordResetEmail(auth, email.trim());
      setMessage(
        `Account created. A secure setup email was sent to ${email.trim()}.`,
      );
      setDisplayName("");
      setEmail("");
      setCourtId("");
    } catch (err) {
      const code =
        typeof err === "object" && err !== null && "code" in err
          ? String((err as { code?: unknown }).code)
          : "";
      setError(
        accountCreated
          ? "The account was created, but the setup email could not be sent. Check the Firebase email template and resend it below."
          : code === "functions/unauthenticated"
            ? "Firebase rejected this request because the browser App Check token was missing. Verify that admin.play-up.fit is allowed for this App Check web key, then reload and retry."
            : err instanceof Error
            ? err.message
            : "The owner account could not be created.",
      );
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="content owner-workspace">
      <div className="portfolio-head">
        <div>
          <span className="eyebrow">ACCESS</span>
          <h2>New owner</h2>
        </div>
      </div>
      <div className="owner-layout">
        <form className="table-card owner-form" onSubmit={create}>
          <div className="owner-type">
            <button
              type="button"
              className={ownerType === "academy" ? "selected" : ""}
              onClick={() => {
                setOwnerType("academy");
                setCourtId("");
              }}
            >
              <Building2 />
              <strong>Academy owner</strong>
              <span>Manage the full academy and all its courts</span>
            </button>
            <button
              type="button"
              className={ownerType === "court" ? "selected" : ""}
              onClick={() => setOwnerType("court")}
            >
              <Dumbbell />
              <strong>Court owner</strong>
              <span>Assigned to one specific court</span>
            </button>
            <button
              type="button"
              className={ownerType === "community" ? "selected" : ""}
              onClick={() => setOwnerType("community")}
            >
              <Users />
              <strong>Community owner</strong>
              <span>Manage a group page, photos, contact details and events</span>
            </button>
          </div>
          <label>
            Full name
            <input
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              required
              autoComplete="name"
            />
          </label>
          <label>
            Email address
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              autoComplete="email"
            />
          </label>
          {ownerType === "community" ? (
            <>
              <label>
                Community name
                <input value={communityName} onChange={(e) => setCommunityName(e.target.value)} required autoComplete="organization" placeholder="Into The Basket" />
              </label>
              <label>
                Sport
                <input value={communitySport} onChange={(e) => setCommunitySport(e.target.value)} required placeholder="Basketball" />
              </label>
              <div className="helper-note">A community page will be created with a unique URL ID. Its owner can add photos and public contact details in the PlayUp app.</div>
            </>
          ) : <>
          <label>
            Academy
            <select
              value={academyId}
              onChange={(e) => {
                setAcademyId(e.target.value);
                setCourtId("");
              }}
              required
            >
              <option value="">Select an academy</option>
              {academies.map((a) => (
                <option key={a.id} value={a.id}>
                  {String(a.name ?? a.id)}
                </option>
              ))}
            </select>
          </label>
          {ownerType === "court" && (
            <label>
              Court
              <select
                value={courtId}
                onChange={(e) => setCourtId(e.target.value)}
                required
                disabled={!academyId}
              >
                <option value="">Select a court</option>
                {availableCourts.map((c) => (
                  <option key={c.id} value={c.id}>
                    {String(c.name ?? c.id)}
                  </option>
                ))}
              </select>
            </label>
          )}
          </>}
          {error && (
            <div className="error">
              {error}
              {resetEmail && (
                <button
                  type="button"
                  className="retry-email"
                  onClick={async () => {
                    setError("");
                    try {
                      await sendPasswordResetEmail(auth, resetEmail);
                      setMessage(`Password setup email sent to ${resetEmail}.`);
                    } catch {
                      setError(
                        "Email still could not be sent. Check Firebase email-template configuration.",
                      );
                    }
                  }}
                >
                  Resend setup email
                </button>
              )}
            </div>
          )}
          {message && <div className="success">{message}</div>}
          <button
            className="primary-action owner-submit"
            disabled={busy}
          >
            {busy ? "Creating…" : "Create owner"}
          </button>
        </form>
        <div className="process-card">
          <ShieldCheck size={30} />
          <h3>Secure setup</h3>
          <p>
            PlayUp generates an unknown random credential, then Firebase emails
            the owner a one-time password setup link.
          </p>
        </div>
      </div>
    </section>
  );
}

function money(minor: number, currency: string) {
  return new Intl.NumberFormat(undefined, {
    style: "currency",
    currency,
    maximumFractionDigits: 2,
  }).format(minor / 100);
}

function formatFieldLabel(column: string): string {
  const words = column
    .replace(/Minor$/, "")
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .toLowerCase();
  const label = words.charAt(0).toUpperCase() + words.slice(1);
  return column.endsWith("Minor") ? `${label} amount` : label;
}

function authErrorMessage(error: unknown): string {
  const code =
    typeof error === "object" && error && "code" in error
      ? String(error.code)
      : "";
  if (["auth/invalid-credential", "auth/wrong-password", "auth/user-not-found"].includes(code))
    return "The email or password is incorrect. Check the test account details and try again.";
  if (code === "auth/invalid-email") return "Enter a valid email address.";
  if (code === "auth/too-many-requests")
    return "Too many sign-in attempts. Wait a moment, then try again or reset the password.";
  if (code === "auth/network-request-failed")
    return "The admin page could not reach Firebase. Check your connection and try again.";
  return error instanceof Error ? error.message : "Sign-in failed. Please try again.";
}

function AcademyPortfolio() {
  const [academies, setAcademies] = useState<LiveRow[]>([]);
  const [courts, setCourts] = useState<LiveRow[]>([]);
  const [bookings, setBookings] = useState<LiveRow[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [saving, setSaving] = useState(false);
  const [creating, setCreating] = useState(false);
  const [createError, setCreateError] = useState("");
  const [academyName, setAcademyName] = useState("");
  const [academyAddress, setAcademyAddress] = useState("");
  const [academyCurrency, setAcademyCurrency] = useState("JOD");
  const [academyCommissionPercent, setAcademyCommissionPercent] =
    useState("10");
  const [ownerName, setOwnerName] = useState("");
  const [ownerEmail, setOwnerEmail] = useState("");
  useEffect(() => {
    const academyStop = onSnapshot(collection(db, "academies"), (snap) =>
      setAcademies(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
    );
    const courtStop = onSnapshot(collection(db, "courts"), (snap) =>
      setCourts(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
    );
    const bookingStop = onSnapshot(collection(db, "bookings"), (snap) =>
      setBookings(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
    );
    return () => {
      academyStop();
      courtStop();
      bookingStop();
    };
  }, []);
  const rows = academies.filter((a) =>
    String(a.name ?? "")
      .toLowerCase()
      .includes(query.toLowerCase()),
  );
  const current = academies.find((a) => a.id === selected);
  async function createAcademy(e: FormEvent) {
    e.preventDefault();
    setSaving(true);
    setCreateError("");
    let academyId = "";
    let ownerCreated = false;
    try {
      const commissionPercent = Number(academyCommissionPercent);
      if (
        !Number.isFinite(commissionPercent) ||
        commissionPercent < 0 ||
        commissionPercent > 100
      ) {
        throw new Error("Commission must be between 0 and 100 percent.");
      }
      const academy = await addDoc(collection(db, "academies"), {
        name: academyName.trim(),
        address: academyAddress.trim(),
        currency: academyCurrency,
        status: "active",
        platformCommissionPercent: commissionPercent,
        createdAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      });
      academyId = academy.id;
      await createManagedAccount({
        ownerType: "academy",
        academyId: academy.id,
        displayName: ownerName,
        email: ownerEmail,
      });
      ownerCreated = true;
      let setupEmailSent = true;
      try {
        await sendPasswordResetEmail(auth, ownerEmail.trim());
      } catch {
        setupEmailSent = false;
      }
      setCreating(false);
      setAcademyName("");
      setAcademyAddress("");
      setAcademyCommissionPercent("10");
      setOwnerName("");
      setOwnerEmail("");
      setSelected(academy.id);
      if (!setupEmailSent) {
        window.alert(
          "The academy and owner account were created, but the setup email was not sent. Use Owner Accounts to resend it after checking the Firebase email template.",
        );
      }
    } catch (error) {
      if (academyId && !ownerCreated) {
        await deleteDoc(doc(db, "academies", academyId)).catch(() => undefined);
      }
      setCreateError(
        error instanceof Error
          ? error.message
          : "Academy could not be created.",
      );
    } finally {
      setSaving(false);
    }
  }
  const totals = (academyId: string) => {
    const academyBookings = bookings.filter((b) => b.academyId === academyId);
    const collectedBookings = academyBookings.filter(
      (b) => b.paymentStatus === "collected",
    );
    const collected = collectedBookings.reduce(
      (sum, b) => sum + Number(b.cashCollectedMinor ?? b.totalMinor ?? 0),
      0,
    );
    const pending = academyBookings
      .filter(
        (b) => b.paymentStatus !== "collected" && b.status !== "cancelled",
      )
      .reduce((sum, b) => sum + Number(b.totalMinor ?? 0), 0);
    const percent = Number(
      academies.find((a) => a.id === academyId)?.platformCommissionPercent ?? 0,
    );
    const commission = collectedBookings.reduce(
      (sum, b) => sum + Number(b.platformCommissionMinor ?? 0),
      0,
    );
    const outstandingCommission = collectedBookings
      .filter((b) => b.settlementStatus === "academyOwesPlatform")
      .reduce((sum, b) => sum + Number(b.platformCommissionMinor ?? 0), 0);
    return {
      academyBookings,
      collected,
      pending,
      percent,
      commission,
      outstandingCommission,
    };
  };
  if (current) {
    const currency = String(current.currency ?? "JOD");
    const t = totals(current.id);
    const academyCourts = courts.filter((c) => c.academyId === current.id);
    async function savePercent(value: string) {
      const percent = Math.min(100, Math.max(0, Number(value) || 0));
      setSaving(true);
      try {
        await setDoc(
          doc(db, "academies", current!.id),
          { platformCommissionPercent: percent, updatedAt: serverTimestamp() },
          { merge: true },
        );
      } finally {
        setSaving(false);
      }
    }
    return (
      <section className="content academy-record">
        <button className="back-link" onClick={() => setSelected(null)}>
          <ChevronLeft size={18} /> All academies
        </button>
        <div className="record-hero">
          <div>
            <span className="eyebrow">ACADEMY ACCOUNT</span>
            <h2>{String(current.name ?? "Academy")}</h2>
            <p>{String(current.address ?? "Location not configured")}</p>
          </div>
          <span
            className={`status ${current.status === "active" ? "good" : ""}`}
          >
            {String(current.status ?? "unknown")}
          </span>
        </div>
        <div className="record-metrics">
          <article>
            <span>Collected revenue</span>
            <strong>{money(t.collected, currency)}</strong>
            <small>Cash confirmed</small>
          </article>
          <article>
            <span>Pending revenue</span>
            <strong>{money(t.pending, currency)}</strong>
            <small>Awaiting collection</small>
          </article>
          <article className="accent">
            <span>PlayUp revenue</span>
            <strong>{money(t.commission, currency)}</strong>
            <small>
              {money(t.outstandingCommission, currency)} awaiting settlement
            </small>
          </article>
          <article>
            <span>Bookings</span>
            <strong>{t.academyBookings.length}</strong>
            <small>{academyCourts.length} courts</small>
          </article>
        </div>
        <div className="workspace-grid">
          <div className="table-card">
            <div className="section-title">
              <div>
                <h3>Courts</h3>
                <p>Performance for every venue</p>
              </div>
            </div>
            <div className="court-records">
              {academyCourts.map((c) => {
                const courtBookings = t.academyBookings.filter(
                  (b) => b.courtId === c.id,
                );
                const gross = courtBookings
                  .filter((b) => b.paymentStatus === "collected")
                  .reduce(
                    (s, b) =>
                      s + Number(b.cashCollectedMinor ?? b.totalMinor ?? 0),
                    0,
                  );
                return (
                  <article key={c.id}>
                    <div className="court-thumb">
                      {c.imageUrl ? (
                        <img src={String(c.imageUrl)} alt="" />
                      ) : (
                        <Dumbbell />
                      )}
                    </div>
                    <div>
                      <strong>{String(c.name ?? "Court")}</strong>
                      <span>
                        {String(c.sport ?? "Sport")} · {courtBookings.length}{" "}
                        bookings
                      </span>
                    </div>
                    <b>{money(gross, currency)}</b>
                  </article>
                );
              })}
              {!academyCourts.length && (
                <div className="empty">No courts have been added.</div>
              )}
            </div>
          </div>
          <div className="commission-card">
            <CircleDollarSign size={30} />
            <h3>Commission agreement</h3>
            <p>
              Set the percentage PlayUp receives from this academy's collected
              booking revenue.
            </p>
            <label>
              Platform percentage
              <div className="percent-input">
                <input
                  type="number"
                  min="0"
                  max="100"
                  step="0.1"
                  defaultValue={t.percent}
                  onBlur={(e) => savePercent(e.target.value)}
                />
                <span>%</span>
              </div>
            </label>
            <small>{saving ? "Saving…" : "Saved automatically"}</small>
            <div className="formula">
              <span>Collected</span>
              <b>{money(t.collected, currency)}</b>
              <span>PlayUp share</span>
              <b>{money(t.commission, currency)}</b>
            </div>
          </div>
        </div>
      </section>
    );
  }
  return (
    <section className="content">
      <div className="portfolio-head">
        <div>
          <span className="eyebrow">PARTNERS</span>
          <h2>Academies</h2>
        </div>
        <div>
          <button
            className="primary-action"
            onClick={() => setCreating(true)}
            disabled={!functionsAvailable}
            title={
              functionsAvailable
                ? undefined
                : "Requires deployed Firebase Cloud Functions"
            }
          >
            <Plus size={18} /> Add academy
          </button>
        </div>
      </div>
      <div className="table-card">
        <div className="table-head">
          <div>
            <h2>Academy accounts</h2>
            <p>{rows.length} live partners</p>
          </div>
          <label className="search">
            <Search size={18} />
            <input
              placeholder="Search academies"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
          </label>
        </div>
        <div className="academy-list">
          {rows.map((a) => {
            const t = totals(a.id);
            const currency = String(a.currency ?? "JOD");
            return (
              <button key={a.id} onClick={() => setSelected(a.id)}>
                <div className="academy-logo">
                  {String(a.name ?? "A").charAt(0)}
                </div>
                <div className="academy-name">
                  <strong>{String(a.name ?? "Academy")}</strong>
                  <span>
                    {courts.filter((c) => c.academyId === a.id).length} courts ·{" "}
                    {t.academyBookings.length} bookings
                  </span>
                </div>
                <div>
                  <span>Collected</span>
                  <b>{money(t.collected, currency)}</b>
                </div>
                <div>
                  <span>Commission</span>
                  <b>
                    {t.percent}% · {money(t.commission, currency)}
                  </b>
                </div>
                <span
                  className={`status ${a.status === "active" ? "good" : ""}`}
                >
                  {String(a.status ?? "unknown")}
                </span>
                <ChevronRight size={20} />
              </button>
            );
          })}
          {!rows.length && (
            <div className="empty">No academies match this search.</div>
          )}
        </div>
      </div>
      {creating && (
        <div
          className="modal-backdrop"
          onMouseDown={() => !saving && setCreating(false)}
        >
          <form
            className="editor"
            role="dialog"
            aria-modal="true"
            aria-labelledby="new-academy-title"
            onSubmit={createAcademy}
            onMouseDown={(e) => e.stopPropagation()}
          >
            <div className="editor-head">
              <div>
                <h2 id="new-academy-title">New academy</h2>
              </div>
              <button
                type="button"
                aria-label="Close academy form"
                onClick={() => setCreating(false)}
              >
                <X />
              </button>
            </div>
            <label>
              Academy name
              <input
                value={academyName}
                onChange={(e) => setAcademyName(e.target.value)}
                required
              />
            </label>
            <label>
              Address
              <input
                value={academyAddress}
                onChange={(e) => setAcademyAddress(e.target.value)}
                required
              />
            </label>
            <label>
              Currency
              <select
                value={academyCurrency}
                onChange={(e) => setAcademyCurrency(e.target.value)}
              >
                {["JOD", "AED", "SAR", "QAR", "KWD", "BHD", "OMR", "USD"].map(
                  (v) => (
                    <option key={v}>{v}</option>
                  ),
                )}
              </select>
            </label>
            <label>
              PlayUp commission %
              <input
                type="number"
                min="0"
                max="100"
                step="0.1"
                value={academyCommissionPercent}
                onChange={(e) => setAcademyCommissionPercent(e.target.value)}
                required
              />
            </label>
            <h3>Owner account</h3>
            <label>
              Owner name
              <input
                value={ownerName}
                onChange={(e) => setOwnerName(e.target.value)}
                required
              />
            </label>
            <label>
              Owner email
              <input
                type="email"
                value={ownerEmail}
                onChange={(e) => setOwnerEmail(e.target.value)}
                required
              />
            </label>
            <p className="form-note">
              The owner receives a secure Firebase password setup email. No
              temporary password is displayed or stored here.
            </p>
            {createError && <div className="error">{createError}</div>}
            <button
              className="primary-action"
              disabled={saving || !functionsAvailable}
            >
              {saving ? "Creating…" : "Create academy"}
            </button>
          </form>
        </div>
      )}
    </section>
  );
}

function Login() {
  const [email, setEmail] = useState(import.meta.env.VITE_UAT_EMAIL || "");
  const [password, setPassword] = useState(
    import.meta.env.VITE_UAT_PASSWORD || "",
  );
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);
  const [resetSent, setResetSent] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  useEffect(() => {
    if (import.meta.env.VITE_USE_EMULATORS === "true" && email && password) {
      setBusy(true);
      signInWithEmailAndPassword(auth, email, password)
        .catch((err) => setError(authErrorMessage(err)))
        .finally(() => setBusy(false));
    }
  }, []);
  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    setResetSent(false);
    try {
      await signInWithEmailAndPassword(auth, email, password);
    } catch (err) {
      setError(authErrorMessage(err));
    } finally {
      setBusy(false);
    }
  }
  async function resetPassword() {
    if (!email) {
      setError("Enter your email address above first.");
      return;
    }
    setError("");
    try {
      await sendPasswordResetEmail(auth, email);
      setResetSent(true);
    } catch (err) {
      setError(authErrorMessage(err));
    }
  }
  return (
    <div className="center">
      <div className="login-backdrop" aria-hidden="true">
        <span className="login-blob login-blob-1" />
        <span className="login-blob login-blob-2" />
        <span className="login-blob login-blob-3" />
        <span className="login-court" />
      </div>
      <form className="login login-in" onSubmit={submit}>
        <PlayUpLogo className="login-logo" label="PlayUp" />
        <h1>Administration</h1>
        <p>Sign in with your platform administrator account.</p>
        <label>
          Email
          <input
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            type="email"
            autoComplete="username"
            required
            autoFocus
          />
        </label>
        <label>
          Password
          <span className="password-field">
            <input
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              type={showPassword ? "text" : "password"}
              autoComplete="current-password"
              required
            />
            <button
              type="button"
              aria-label={showPassword ? "Hide password" : "Show password"}
              aria-pressed={showPassword}
              onClick={() => setShowPassword((visible) => !visible)}
            >
              {showPassword ? <EyeOff size={19} /> : <Eye size={19} />}
            </button>
          </span>
        </label>
        {error && <div className="error" role="alert">{error}</div>}
        {resetSent && (
          <div className="success">
            Password reset email sent to {email}.
          </div>
        )}
        <button disabled={busy}>{busy ? "Signing in…" : "Sign in"}</button>
        <button
          type="button"
          className="retry-email"
          onClick={resetPassword}
          disabled={busy}
        >
          Forgot password?
        </button>
      </form>
    </div>
  );
}

function Dashboard({ onNavigate }: { onNavigate: (label: string) => void }) {
  const names = [
    "bookings",
    "users",
    "academies",
    "courts",
    "matches",
    "reviews",
  ];
  const [counts, setCounts] = useState<Record<string, number>>({});
  const [bookings, setBookings] = useState<LiveRow[]>([]);
  const [tickets, setTickets] = useState<LiveRow[]>([]);
  const [error, setError] = useState("");
  useEffect(() => {
    Promise.all(
      names.map(
        async (n) =>
          [
            n,
            (await getCountFromServer(collection(db, n))).data().count,
          ] as const,
      ),
    )
      .then((rows) => setCounts(Object.fromEntries(rows)))
      .catch(() => setError("Some platform totals could not be loaded."));
    const stopBookings = onSnapshot(
      collection(db, "bookings"),
      (snap) => setBookings(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      () => setError("Live booking operations are temporarily unavailable."),
    );
    const stopTickets = onSnapshot(
      collection(db, "supportTickets"),
      (snap) => setTickets(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
      () => setError("Support queue could not be loaded."),
    );
    return () => {
      stopBookings();
      stopTickets();
    };
  }, []);
  const activeBookings = bookings.filter((row) =>
    ["pending", "confirmed", "checkedIn"].includes(String(row.status)),
  );
  const pendingBookings = bookings.filter((row) => row.status === "pending");
  const collectedBookings = bookings.filter(
    (row) => row.paymentStatus === "collected",
  );
  const groupedAmount = (field: "cash" | "commission") => {
    const totals = new Map<string, number>();
    for (const row of collectedBookings) {
      const currency = String(row.currency ?? "JOD");
      const amount =
        field === "cash"
          ? Number(row.cashCollectedMinor ?? row.totalMinor ?? 0)
          : Number(row.platformCommissionMinor ?? 0);
      totals.set(currency, (totals.get(currency) ?? 0) + amount);
    }
    if (!totals.size) return money(0, "JOD");
    return [...totals.entries()]
      .map(([currency, amount]) => money(amount, currency))
      .join(" · ");
  };
  const openTickets = tickets.filter((row) =>
    ["open", "pending"].includes(String(row.status ?? "open")),
  );
  const bookingStatuses = ["pending", "confirmed", "checkedIn", "completed"];
  const maximumStatusCount = Math.max(
    1,
    ...bookingStatuses.map(
      (status) => bookings.filter((row) => row.status === status).length,
    ),
  );
  return (
    <section className="content">
      <div className="dashboard-hero">
        <div>
          <span className="eyebrow">LIVE OPERATIONS</span>
          <h2>Your operations, at a glance</h2>
          <p>
            Start with outstanding requests, then review bookings and partner activity.
          </p>
        </div>
        <div className="live-indicator">
          <span /> Live data
        </div>
      </div>
      {error && (
        <div className="notice warning">
          <AlertTriangle size={18} />
          {error}
        </div>
      )}
      <div className="workspace-shortcuts">
        <button onClick={() => onNavigate("Bookings")}><CalendarDays size={22}/><span><strong>Manage bookings</strong><small>Reservations and arrivals</small></span><ChevronRight size={18}/></button>
        <button onClick={() => onNavigate("Academies")}><Building2 size={22}/><span><strong>Manage academies</strong><small>Partners, courts and pricing</small></span><ChevronRight size={18}/></button>
        <button onClick={() => onNavigate("Support")}><LifeBuoy size={22}/><span><strong>Help your customers</strong><small>Open support requests</small></span><ChevronRight size={18}/></button>
      </div>
      <div className="executive-metrics">
        <article className="metric-primary">
          <div>
            <CircleDollarSign size={20} />
            <span>Collected booking value</span>
          </div>
          <strong>{groupedAmount("cash")}</strong>
          <small>
            <TrendingUp size={14} /> PlayUp share: {groupedAmount("commission")}
          </small>
        </article>
        <article>
          <div>
            <CalendarDays size={20} />
            <span>Active bookings</span>
          </div>
          <strong>{activeBookings.length}</strong>
          <small>{pendingBookings.length} awaiting confirmation</small>
        </article>
        <article>
          <div>
            <Building2 size={20} />
            <span>Partner network</span>
          </div>
          <strong>{counts.academies ?? "—"}</strong>
          <small>{counts.courts ?? "—"} live court records</small>
        </article>
        <article className={openTickets.length ? "metric-attention" : ""}>
          <div>
            <LifeBuoy size={20} />
            <span>Support queue</span>
          </div>
          <strong>{openTickets.length}</strong>
          <small>
            {openTickets.length
              ? "Needs operator attention"
              : "All requests handled"}
          </small>
        </article>
      </div>
      <div className="dashboard-grid">
        <article className="insight-card">
          <div className="section-title">
            <div>
              <h3>Booking pipeline</h3>
              <p>Current operational distribution</p>
            </div>
            <Activity size={20} />
          </div>
          <div className="pipeline">
            {bookingStatuses.map((status) => {
              const value = bookings.filter(
                (row) => row.status === status,
              ).length;
              return (
                <div className="pipeline-row" key={status}>
                  <span>{humanValue(status)}</span>
                  <div>
                    <i
                      style={{
                        width: `${(value / maximumStatusCount) * 100}%`,
                      }}
                    />
                  </div>
                  <b>{value}</b>
                </div>
              );
            })}
          </div>
        </article>
        <article className="insight-card operations-card">
          <div className="section-title">
            <div>
              <h3>Operations inbox</h3>
              <p>Items requiring a decision</p>
            </div>
            <Clock3 size={20} />
          </div>
          <div className="operation-list">
            <button type="button" onClick={() => onNavigate("Bookings")}>
              <span className="operation-icon amber">
                <CalendarDays size={18} />
              </span>
              <div>
                <strong>{pendingBookings.length} booking requests</strong>
                <small>Confirm or cancel pending reservations</small>
              </div>
              <ArrowUpRight size={17} />
            </button>
            <button type="button" onClick={() => onNavigate("Support")}>
              <span className="operation-icon purple">
                <LifeBuoy size={18} />
              </span>
              <div>
                <strong>{openTickets.length} support requests</strong>
                <small>Review player and partner issues</small>
              </div>
              <ArrowUpRight size={17} />
            </button>
            <div>
              <span className="operation-icon green">
                <CheckCircle2 size={18} />
              </span>
              <div>
                <strong>Access controls active</strong>
                <small>Tenant and role isolation enforced</small>
              </div>
              <ShieldCheck size={17} />
            </div>
          </div>
        </article>
      </div>
      <div className="section-gap">
        <DataModule
          module={{
            label: "Recent bookings",
            collection: "bookings",
            icon: CalendarDays,
            columns: [
              "courtName",
              "academyId",
              "status",
              "paymentStatus",
              "totalMinor",
            ],
          }}
          embedded
        />
      </div>
    </section>
  );
}

function DataModule({
  module,
  embedded = false,
}: {
  module: Module;
  embedded?: boolean;
}) {
  const [rows, setRows] = useState<
    Array<
      Record<string, unknown> & {
        id: string;
      }
    >
  >([]);
  const [q, setQ] = useState("");
  const [statusFilter, setStatusFilter] = useState("");
  const [page, setPage] = useState(0);
  const [sortNewest, setSortNewest] = useState(true);
  const [selectedRecord, setSelectedRecord] = useState<Record<string, unknown> | null>(null);
  const [rowsLoading, setRowsLoading] = useState(true);
  const [loadError, setLoadError] = useState("");
  const [editing, setEditing] = useState<
    | (Record<string, unknown> & {
        id?: string;
      })
    | null
  >(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [academies, setAcademies] = useState<
    Array<{ id: string; name?: unknown }>
  >([]);
  const [courts, setCourts] = useState<
    Array<{ id: string; name?: unknown; academyId?: unknown }>
  >([]);
  const [lastAcademyId, setLastAcademyId] = useState("");
  useEffect(() => {
    setRowsLoading(true);
    setLoadError("");
    return onSnapshot(
      collection(db, module.collection!),
      (snap) => {
        setRows(
          snap.docs.map((d) => ({
            id: d.id,
            ...d.data(),
          })),
        );
        setRowsLoading(false);
      },
      () => {
        setLoadError(
          `Could not load ${module.label.toLowerCase()}. Check your connection and permissions.`,
        );
        setRowsLoading(false);
      },
    );
  }, [module.collection, module.label]);
  useEffect(() => {
    if (!module.columns?.includes("academyId")) return;
    return onSnapshot(collection(db, "academies"), (snap) =>
      setAcademies(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
    );
  }, [module.columns]);
  useEffect(() => {
    if (!module.columns?.includes("courtId")) return;
    return onSnapshot(collection(db, "courts"), (snap) =>
      setCourts(snap.docs.map((d) => ({ id: d.id, ...d.data() }))),
    );
  }, [module.columns]);
  const statusField = module.columns?.includes("status") ? "status"
    : module.columns?.includes("role") ? "role" : module.columns?.includes("active") ? "active" : "";
  const statuses = [...new Set(rows.map(row => String(row[statusField] ?? "")).filter(Boolean))].sort();
  useEffect(() => setPage(0), [q, statusFilter, sortNewest]);
  const filtered = useMemo(() => {
    const matching = rows.filter(row =>
      Object.values(row).join(" ").toLowerCase().includes(q.trim().toLowerCase())
      && (!statusFilter || String(row[statusField]) === statusFilter));
    const dateValue = (row: Record<string, unknown>) => {
      const value = (row.createdAt ?? row.startUtc) as { toMillis?: () => number } | undefined;
      return value?.toMillis?.() ?? 0;
    };
    return matching.sort((a, b) => sortNewest ? dateValue(b) - dateValue(a)
      : String(a.name ?? a.displayName ?? a.courtName ?? a.id).localeCompare(String(b.name ?? b.displayName ?? b.courtName ?? b.id)));
  }, [rows, q, statusFilter, statusField, sortNewest]);
  const pageCount = Math.max(1, Math.ceil(filtered.length / 25));
  const currentPage = Math.min(page, pageCount - 1);
  const displayed = filtered.slice(currentPage * 25, currentPage * 25 + 25);
  useEffect(() => {
    if (!selectedRecord) return;
    const close = (event: KeyboardEvent) => { if (event.key === "Escape") setSelectedRecord(null); };
    window.addEventListener("keydown", close);
    return () => window.removeEventListener("keydown", close);
  }, [selectedRecord]);
  function exportCsv() {
    const columns = ["id", ...(module.columns ?? [])];
    const escape = (value: unknown) =>
      `"${String(value ?? "").replaceAll('"', '""')}"`;
    const csv = [
      columns.map(escape).join(","),
      ...filtered.map((row) =>
        columns.map((column) => escape(row[column])).join(","),
      ),
    ].join("\n");
    const url = URL.createObjectURL(
      new Blob([csv], { type: "text/csv;charset=utf-8" }),
    );
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `${module.label.toLowerCase().replaceAll(" ", "-")}.csv`;
    anchor.click();
    URL.revokeObjectURL(url);
  }
  const editable =
    !embedded &&
    !["Audit logs", "Matchmaking", "Users", "Tournaments"].includes(
      module.label,
    );
  const canAdd =
    editable && !["Bookings", "Reviews", "Support"].includes(module.label);
  const canDelete = editable && !["Reviews", "Support"].includes(module.label);
  const hasActions = !embedded && editable;
  function newRecord(): Record<string, unknown> {
    if (module.label === "Courts") {
      return {
        sport: "Football",
        active: true,
        currency: "JOD",
        openingHour: 6,
        closingHour: 23,
        timezone: "Asia/Amman",
        academyId: lastAcademyId,
      };
    }
    if (module.label === "Promotions") {
      return {
        discountType: "percentage",
        discountValue: 10,
        minimumSpendMinor: 0,
        usageLimit: 100,
        perUserLimit: 1,
        usageCount: 0,
        active: true,
      };
    }
    if (module.label === "Achievements") {
      return {
        metric: "bookings",
        goal: 1,
        rewardPoints: 0,
        color: "purple",
        active: true,
      };
    }
    return {};
  }
  async function save(e: FormEvent) {
    e.preventDefault();
    if (!editing) return;
    setBusy(true);
    setError("");
    try {
      const payload: Record<string, unknown> = {
        updatedAt: serverTimestamp(),
      };
      for (const column of module.columns!) {
        if (module.readOnlyColumns?.includes(column)) continue;
        let value = editing[column];
        if (module.timestampColumns?.includes(column)) {
          const parsed = value ? new Date(String(value)) : null;
          if (parsed && Number.isNaN(parsed.valueOf())) {
            throw new Error(`${column} must be a valid date and time.`);
          }
          value = parsed ? Timestamp.fromDate(parsed) : null;
        } else if (value === "true" || value === "false")
          value = value === "true";
        else if (
          typeof value === "string" &&
          value.trim() !== "" &&
          !Number.isNaN(Number(value))
        )
          value = Number(value);
        payload[column] = value ?? "";
      }
      if (module.label === "Promotions") {
        const original = editing.id
          ? rows.find((row) => row.id === editing.id)
          : undefined;
        const code = String(original?.code ?? payload.code ?? "")
          .trim()
          .toUpperCase();
        if (!/^[A-Z0-9_-]{3,32}$/.test(code)) {
          throw new Error(
            "Promotion code must be 3-32 letters, numbers, dashes or underscores.",
          );
        }
        payload.code = code;
        if (editing.id) {
          await setDoc(doc(db, module.collection!, editing.id), payload, {
            merge: true,
          });
        } else {
          await setDoc(doc(db, module.collection!, code), {
            ...payload,
            usageCount: 0,
            createdAt: serverTimestamp(),
          });
        }
      } else if (editing.id)
        await setDoc(doc(db, module.collection!, editing.id), payload, {
          merge: true,
        });
      else
        await addDoc(collection(db, module.collection!), {
          ...payload,
          createdAt: serverTimestamp(),
        });
      setEditing(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Save failed");
    } finally {
      setBusy(false);
    }
  }
  async function remove(id: string) {
    if (
      !confirm(
        `Delete ${module.label.toLowerCase()} record ${id}? This cannot be undone.`,
      )
    )
      return;
    try {
      await deleteDoc(doc(db, module.collection!, id));
    } catch (err) {
      alert(err instanceof Error ? err.message : "Delete failed");
    }
  }
  async function bookingAction(id: string, status: string) {
    try {
      await httpsCallable(
        functions,
        "transitionBooking",
      )({ bookingId: id, status });
    } catch (err) {
      alert(err instanceof Error ? err.message : "Update failed");
    }
  }
  async function collectCash(id: string) {
    try {
      await httpsCallable(functions, "recordCashPayment")({ bookingId: id });
    } catch (err) {
      alert(err instanceof Error ? err.message : "Payment update failed");
    }
  }
  async function settleCommission(id: string) {
    const reference = window.prompt(
      "Optional payout or reconciliation reference:",
      "",
    );
    if (reference === null) return;
    try {
      await httpsCallable(
        functions,
        "settleBookingCommission",
      )({
        bookingId: id,
        reference: reference.trim(),
      });
    } catch (err) {
      alert(err instanceof Error ? err.message : "Settlement update failed");
    }
  }
  function cellValue(row: Record<string, unknown>, column: string) {
    if (column.endsWith("Minor") && row[column] != null) {
      return money(Number(row[column]), String(row.currency ?? "JOD"));
    }
    if (module.timestampColumns?.includes(column)) {
      const value = row[column] as { toDate?: () => Date } | undefined;
      return value?.toDate?.().toLocaleString() ?? "-";
    }
    return humanValue(row[column]);
  }
  function timestampEditorValue(value: unknown) {
    const date = (value as { toDate?: () => Date } | undefined)?.toDate?.();
    if (!date) return typeof value === "string" ? value : "";
    const local = new Date(date.valueOf() - date.getTimezoneOffset() * 60_000);
    return local.toISOString().slice(0, 16);
  }
  return (
    <section className={embedded ? "table-card embedded" : "content"}>
      {!embedded && <div className="module-intro"><span className="eyebrow">WORKSPACE</span><h2>{module.label}</h2><p>{moduleDescriptions[module.label]}</p></div>}
      {loadError && (
        <div className="notice warning" role="alert">
          <AlertTriangle size={18} />
          {loadError}
        </div>
      )}
      {module.label === "Bookings" && !functionsAvailable && (
        <div className="notice warning" role="status">
          <AlertTriangle size={18} />
          Booking transitions, cash collection, and commission settlement are
          read-only until Firebase Cloud Functions are deployed.
        </div>
      )}
      <div className="table-card">
        <div className="table-head">
          <div>
            <h2>{module.label}</h2>
            <p aria-live="polite">
              {rowsLoading
                ? "Loading live records…"
                : q
                  ? `${filtered.length} of ${rows.length} records`
                  : `${rows.length} live records`}
            </p>
          </div>
          <label className="search">
            <Search size={18} />
            <span className="sr-only">Search {module.label.toLowerCase()}</span>
            <input
              type="search"
              placeholder={`Search ${module.label.toLowerCase()}`}
              value={q}
              onChange={(e) => setQ(e.target.value)}
            />
            {q && (
              <button
                type="button"
                aria-label="Clear search"
                onClick={() => setQ("")}
              >
                <X size={16} />
              </button>
            )}
          </label>
          <button
            className="secondary-action"
            onClick={exportCsv}
            disabled={!filtered.length}
          >
            <Download size={17} /> Export
          </button>
          {canAdd && (
            <button
              className="primary-action"
              onClick={() => setEditing(newRecord())}
            >
              <Plus size={18} /> Add
            </button>
          )}
        </div>
        {!embedded && <div className="record-filters">
          {statusField && <label>{formatFieldLabel(statusField)}<select value={statusFilter} onChange={e => setStatusFilter(e.target.value)}>
            <option value="">All {statusField === "role" ? "roles" : "statuses"}</option>
            {statuses.map(status => <option key={status} value={status}>{status === "true" ? "Active" : status === "false" ? "Inactive" : humanValue(status)}</option>)}
          </select></label>}
          <label>Sort by<select value={sortNewest ? "newest" : "name"} onChange={e => setSortNewest(e.target.value === "newest")}>
            <option value="newest">Newest first</option><option value="name">Name, A–Z</option>
          </select></label>
          {(q || statusFilter) && <button className="secondary-action" onClick={() => {setQ(""); setStatusFilter("");}}>Clear filters</button>}
          <span className="filter-count">{filtered.length} results</span>
        </div>}
        <div className="table-wrap" aria-busy={rowsLoading}>
          <table>
            <thead>
              <tr>
                <th>Record ID</th>
                {module.columns!.map((c) => (
                  <th key={c}>{formatFieldLabel(c)}</th>
                ))}
                {hasActions && <th>Actions</th>}
              </tr>
            </thead>
            <tbody>
              {displayed.map((row, index) => (
                <tr
                  key={row.id}
                  className="row-in"
                  style={{ animationDelay: `${Math.min(index, 12) * 25}ms` }}
                >
                  <td data-label="Record ID" title={row.id}>
                    <button className="record-link" onClick={() => setSelectedRecord(row)} aria-label={`View record ${row.id}`}>{row.id}</button>
                  </td>
                  {module.columns!.map((c) => (
                    <td
                      key={c}
                      data-label={formatFieldLabel(c)}
                      title={String(row[c] ?? "")}
                    >
                      {["status", "paymentStatus", "role"].includes(c) ? (
                        <span
                          className={`data-pill ${String(row[c] ?? "").toLowerCase()}`}
                        >
                          {humanValue(row[c])}
                        </span>
                      ) : (
                        cellValue(row, c)
                      )}
                    </td>
                  ))}
                  {hasActions && (
                    <td className="row-actions" data-label="Actions">
                      {editable && module.label !== "Bookings" && (
                        <>
                          <button
                            title="Edit"
                            aria-label={`Edit ${module.label.toLowerCase()} record`}
                            onClick={() => setEditing(row)}
                          >
                            <Edit3 size={17} />
                          </button>
                          {canDelete && (
                            <button
                              title="Delete"
                              aria-label={`Delete ${module.label.toLowerCase()} record`}
                              className="danger"
                              onClick={() => remove(row.id)}
                            >
                              <Trash2 size={17} />
                            </button>
                          )}
                        </>
                      )}
                      {module.label === "Bookings" && (
                        <>
                          {row.status === "pending" && (
                            <button
                              disabled={!functionsAvailable}
                              onClick={() => bookingAction(row.id, "confirmed")}
                            >
                              Confirm
                            </button>
                          )}
                          {["pending", "confirmed"].includes(
                            String(row.status),
                          ) && (
                            <button
                              disabled={!functionsAvailable}
                              onClick={() => bookingAction(row.id, "cancelled")}
                            >
                              Cancel
                            </button>
                          )}
                          {row.status === "confirmed" && (
                            <button
                              disabled={!functionsAvailable}
                              onClick={() => bookingAction(row.id, "checkedIn")}
                            >
                              Check in
                            </button>
                          )}
                          {row.status === "checkedIn" &&
                            row.paymentStatus === "collected" && (
                              <button
                                disabled={!functionsAvailable}
                                onClick={() =>
                                  bookingAction(row.id, "completed")
                                }
                              >
                                Complete
                              </button>
                            )}
                          {row.paymentStatus !== "collected" &&
                            (row.status === "confirmed" ||
                              row.status === "checkedIn" ||
                              (row.status === "cancelled" &&
                                Number(row.cancellationFeeMinor ?? 0) > 0)) && (
                              <button
                                disabled={!functionsAvailable}
                                onClick={() => collectCash(row.id)}
                              >
                                Cash received
                              </button>
                            )}
                          {row.settlementStatus === "academyOwesPlatform" && (
                            <button
                              disabled={!functionsAvailable}
                              onClick={() => settleCommission(row.id)}
                            >
                              Mark settled
                            </button>
                          )}
                        </>
                      )}
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
          {rowsLoading ? (
            <div className="empty loading-state">
              <span className="inline-spinner" aria-hidden="true" />
              Loading {module.label.toLowerCase()}…
            </div>
          ) : !filtered.length ? (
            <div className="empty">
              <strong>{q ? "No matching records" : `No ${module.label.toLowerCase()} yet`}</strong>
              <span>
                {q
                  ? "Try a different name, status, email, or record ID."
                  : canAdd
                    ? "Use Add to create the first record."
                    : "New records will appear here automatically."}
              </span>
            </div>
          ) : null}
        </div>
      </div>
      {filtered.length > 25 && <div className="pagination">
        <span>Showing {currentPage * 25 + 1}–{Math.min((currentPage + 1) * 25, filtered.length)} of {filtered.length}</span>
        <button className="secondary-action" disabled={currentPage === 0} onClick={() => setPage(currentPage - 1)}><ChevronLeft size={16}/> Previous</button>
        <button className="secondary-action" disabled={currentPage >= pageCount - 1} onClick={() => setPage(currentPage + 1)}>Next <ChevronRight size={16}/></button>
      </div>}
      {selectedRecord && <div className="modal-backdrop" onClick={() => setSelectedRecord(null)}>
        <section className="editor record-details" role="dialog" aria-modal="true" aria-labelledby="record-detail-title" onClick={event => event.stopPropagation()}>
          <div className="editor-head"><div><h2 id="record-detail-title">Record details</h2><p>{module.label}</p></div><button autoFocus aria-label="Close record details" onClick={() => setSelectedRecord(null)}><X/></button></div>
          <dl>{["id", ...(module.columns ?? [])].map(column => <div key={column}><dt>{formatFieldLabel(column)}</dt><dd>{cellValue(selectedRecord, column)}</dd></div>)}</dl>
          <button className="secondary-action" onClick={() => setSelectedRecord(null)}>Done</button>
        </section>
      </div>}
      {editing && (
        <div
          className="modal-backdrop"
          onMouseDown={() => !busy && setEditing(null)}
        >
          <form
            className="editor"
            role="dialog"
            aria-modal="true"
            aria-labelledby="record-editor-title"
            onSubmit={save}
            onMouseDown={(e) => e.stopPropagation()}
          >
            <div className="editor-head">
              <div>
                <h2 id="record-editor-title">
                  {editing.id ? "Edit" : "Add"} {module.label}
                </h2>
                <p>{editing.id || "New record"}</p>
              </div>
              <button
                type="button"
                aria-label="Close editor"
                onClick={() => setEditing(null)}
              >
                <X />
              </button>
            </div>
            {module.columns!.map((column) => (
              <label key={column}>
                {formatFieldLabel(column)}
                {column.endsWith("Minor") ? (
                  <input
                    type="number"
                    step="0.01"
                    min="0"
                    placeholder={`0.00 ${String(editing.currency ?? "")}`.trim()}
                    value={
                      Number.isFinite(Number(editing[column]))
                        ? (Number(editing[column]) / 100).toFixed(2)
                        : ""
                    }
                    onChange={(e) => {
                      const major = parseFloat(e.target.value);
                      setEditing({
                        ...editing,
                        [column]: Number.isFinite(major)
                          ? Math.round(major * 100)
                          : 0,
                      });
                    }}
                  />
                ) : column === "currency" ? (
                  <select
                    value={String(editing[column] ?? "JOD")}
                    onChange={(e) =>
                      setEditing({ ...editing, [column]: e.target.value })
                    }
                  >
                    {[
                      "JOD",
                      "AED",
                      "SAR",
                      "QAR",
                      "KWD",
                      "BHD",
                      "OMR",
                      "USD",
                    ].map((v) => (
                      <option key={v}>{v}</option>
                    ))}
                  </select>
                ) : ["active", "hidden", "suspended"].includes(column) ? (
                  <select
                    value={String(editing[column] ?? false)}
                    onChange={(e) =>
                      setEditing({
                        ...editing,
                        [column]: e.target.value === "true",
                      })
                    }
                  >
                    <option value="true">Yes</option>
                    <option value="false">No</option>
                  </select>
                ) : column === "sport" ? (
                  <select
                    value={String(editing[column] ?? "Football")}
                    onChange={(e) =>
                      setEditing({ ...editing, [column]: e.target.value })
                    }
                  >
                    {[
                      "Football",
                      "Basketball",
                      "Padel",
                      "Tennis",
                      "Volleyball",
                      "Cricket",
                      "Handball",
                    ].map((v) => (
                      <option key={v}>{v}</option>
                    ))}
                  </select>
                ) : column === "format" ? (
                  <select
                    value={String(editing[column] ?? "singleElimination")}
                    onChange={(e) =>
                      setEditing({ ...editing, [column]: e.target.value })
                    }
                  >
                    <option value="singleElimination">
                      Single elimination
                    </option>
                    <option value="doubleElimination">
                      Double elimination
                    </option>
                    <option value="roundRobin">Round robin</option>
                    <option value="groupKnockout">Groups + knockout</option>
                  </select>
                ) : column === "metric" ? (
                  <select
                    value={String(editing[column] ?? "bookings")}
                    onChange={(e) =>
                      setEditing({ ...editing, [column]: e.target.value })
                    }
                  >
                    <option value="bookings">Bookings completed</option>
                    <option value="matchesPlayed">Matches played</option>
                    <option value="rating5">Five-star rating</option>
                    <option value="weekendStreak">Weekend streak</option>
                    <option value="noCancellationStreak">
                      No-cancellation streak
                    </option>
                    <option value="tournamentWins">Tournament wins</option>
                    <option value="matchesHosted">Matches hosted</option>
                    <option value="academyLoyalty">Academy loyalty</option>
                  </select>
                ) : column === "color" ? (
                  <select
                    value={String(editing[column] ?? "purple")}
                    onChange={(e) =>
                      setEditing({ ...editing, [column]: e.target.value })
                    }
                  >
                    {["purple", "green", "gold", "blue", "orange", "pink"].map(
                      (value) => (
                        <option key={value}>{value}</option>
                      ),
                    )}
                  </select>
                ) : column === "discountType" ? (
                  <select
                    value={String(editing[column] ?? "percentage")}
                    onChange={(e) =>
                      setEditing({ ...editing, [column]: e.target.value })
                    }
                  >
                    <option value="percentage">Percentage</option>
                    <option value="fixed">Fixed amount (minor units)</option>
                  </select>
                ) : column === "status" && module.label === "Support" ? (
                  <select
                    value={String(editing[column] ?? "open")}
                    onChange={(e) =>
                      setEditing({ ...editing, [column]: e.target.value })
                    }
                  >
                    <option value="open">Open</option>
                    <option value="pending">Pending</option>
                    <option value="resolved">Resolved</option>
                    <option value="closed">Closed</option>
                  </select>
                ) : column === "academyId" ? (
                  <select
                    value={String(editing[column] ?? "")}
                    onChange={(e) => {
                      const value = e.target.value;
                      setEditing({ ...editing, [column]: value, courtId: "" });
                      if (value) setLastAcademyId(value);
                    }}
                  >
                    <option value="">
                      {module.label === "Courts"
                        ? "Select an academy"
                        : "All academies"}
                    </option>
                    {academies.map((a) => (
                      <option key={a.id} value={a.id}>
                        {String(a.name ?? a.id)}
                      </option>
                    ))}
                  </select>
                ) : column === "courtId" ? (
                  <select
                    value={String(editing[column] ?? "")}
                    onChange={(e) =>
                      setEditing({ ...editing, [column]: e.target.value })
                    }
                  >
                    <option value="">Any court</option>
                    {courts
                      .filter(
                        (c) =>
                          !editing.academyId ||
                          c.academyId === editing.academyId,
                      )
                      .map((c) => (
                        <option key={c.id} value={c.id}>
                          {String(c.name ?? c.id)}
                        </option>
                      ))}
                  </select>
                ) : module.timestampColumns?.includes(column) ? (
                  <input
                    type="datetime-local"
                    value={timestampEditorValue(editing[column])}
                    onChange={(e) =>
                      setEditing({ ...editing, [column]: e.target.value })
                    }
                  />
                ) : (
                  <input
                    type={
                      /(Minor|Value|Limit|Count|Hour|goal|rewardPoints|maxEntries|teamSize|capacity)$/i.test(
                        column,
                      )
                        ? "number"
                        : "text"
                    }
                    min={
                      /(Minor|Value|Limit|Count|goal|rewardPoints|maxEntries|teamSize|capacity)$/i.test(
                        column,
                      )
                        ? 0
                        : column === "openingHour" || column === "closingHour"
                          ? 0
                          : undefined
                    }
                    max={
                      column === "openingHour" || column === "closingHour"
                        ? 24
                        : undefined
                    }
                    value={String(editing[column] ?? "")}
                    disabled={
                      module.readOnlyColumns?.includes(column) ||
                      (module.label === "Promotions" &&
                        column === "code" &&
                        !!editing.id)
                    }
                    onChange={(e) =>
                      setEditing({
                        ...editing,
                        [column]:
                          column === "code"
                            ? e.target.value.toUpperCase()
                            : e.target.value,
                      })
                    }
                  />
                )}
              </label>
            ))}
            {error && <div className="error">{error}</div>}
            <div className="editor-actions">
              <button type="button" onClick={() => setEditing(null)}>
                Cancel
              </button>
              <button className="primary-action" disabled={busy}>
                {busy ? "Saving..." : "Save changes"}
              </button>
            </div>
          </form>
        </div>
      )}
    </section>
  );
}
function SettingsPage() {
  const [config, setConfig] = useState({
    supportEmail: "",
    maintenanceMode: false,
    bookingNotice: "Pay at venue. No card data is collected.",
    defaultCurrency: "JOD",
    platformCommissionPercent: 10,
  });
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);
  useEffect(
    () =>
      onSnapshot(doc(db, "platformConfig", "general"), (snap) => {
        if (snap.exists()) {
          setConfig((current) => ({ ...current, ...snap.data() }));
        }
      }),
    [],
  );
  async function save(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setSaved(false);
    try {
      await setDoc(
        doc(db, "platformConfig", "general"),
        { ...config, updatedAt: serverTimestamp() },
        { merge: true },
      );
      setSaved(true);
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="content settings-workspace">
      <div className="portfolio-head">
        <div>
          <span className="eyebrow">PLATFORM CONTROL</span>
          <h2>Operational settings</h2>
          <p>Manage player-facing service policy and emergency controls.</p>
        </div>
      </div>
      <form className="settings-form table-card" onSubmit={save}>
        <div className="settings-section">
          <div>
            <h3>Service configuration</h3>
            <p>Defaults used across PlayUp experiences.</p>
          </div>
          <div className="settings-fields">
            <label>
              Support email
              <input
                type="email"
                value={config.supportEmail}
                onChange={(e) =>
                  setConfig({ ...config, supportEmail: e.target.value })
                }
                placeholder="support@playup.app"
              />
            </label>
            <label>
              Default currency
              <select
                value={config.defaultCurrency}
                onChange={(e) =>
                  setConfig({ ...config, defaultCurrency: e.target.value })
                }
              >
                {["JOD", "AED", "SAR", "QAR", "KWD", "BHD", "OMR", "USD"].map(
                  (value) => (
                    <option key={value}>{value}</option>
                  ),
                )}
              </select>
            </label>
            <label>
              Default PlayUp commission %
              <input
                type="number"
                min="0"
                max="100"
                step="0.1"
                value={config.platformCommissionPercent}
                onChange={(e) =>
                  setConfig({
                    ...config,
                    platformCommissionPercent: Math.min(
                      100,
                      Math.max(0, Number(e.target.value) || 0),
                    ),
                  })
                }
              />
            </label>
            <label className="full">
              Booking notice
              <textarea
                value={config.bookingNotice}
                onChange={(e) =>
                  setConfig({ ...config, bookingNotice: e.target.value })
                }
                rows={3}
              />
            </label>
          </div>
        </div>
        <div className="settings-section danger-zone">
          <div>
            <h3>Maintenance control</h3>
            <p>Use only when platform access must be paused.</p>
          </div>
          <label className="switch-row">
            <div>
              <strong>Maintenance mode</strong>
              <span>Display a service notice and prevent new operations.</span>
            </div>
            <input
              type="checkbox"
              checked={config.maintenanceMode}
              onChange={(e) =>
                setConfig({ ...config, maintenanceMode: e.target.checked })
              }
            />
          </label>
        </div>
        <div className="settings-save">
          {saved && (
            <span>
              <CheckCircle2 size={17} /> Settings saved
            </span>
          )}
          <button className="primary-action" disabled={busy}>
            {busy ? "Saving…" : "Save platform settings"}
          </button>
        </div>
      </form>
    </section>
  );
}
