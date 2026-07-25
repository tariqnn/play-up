import {
  FormEvent,
  useEffect,
  useMemo,
  useState,
} from "react";
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
  LifeBuoy,
  LayoutDashboard,
  LogOut,
  Menu,
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
  auth,
  db,
  functions,
} from "./firebase";

type Module = {
  label: string;
  collection?: string;
  icon: typeof Activity;
  columns?: string[];
};
const modules: Module[] = [
  {
    label: "Dashboard",
    icon: LayoutDashboard,
  },
  {
    label: "Academies",
    collection: "academies",
    icon: Building2,
    columns: [
      "name",
      "status",
      "currency",
    ],
  },
  {
    label: "Courts",
    collection: "courts",
    icon: Dumbbell,
    columns: [
      "name",
      "sport",
      "academyId",
      "active",
      "basePriceMinor",
    ],
  },
  {
    label: "Bookings",
    collection: "bookings",
    icon: CalendarDays,
    columns: [
      "courtName",
      "userId",
      "academyId",
      "status",
      "paymentStatus",
      "paymentMethod",
      "totalMinor",
    ],
  },
  {
    label: "Users",
    collection: "users",
    icon: Users,
    columns: [
      "displayName",
      "email",
      "role",
      "academyId",
      "suspended",
    ],
  },
  { label: "Owner Accounts", icon: UserPlus },
  {
    label: "Matchmaking",
    collection: "matches",
    icon: Activity,
    columns: [
      "title",
      "sport",
      "hostName",
      "status",
      "capacity",
    ],
  },
  {
    label: "Reviews",
    collection: "reviews",
    icon: Star,
    columns: [
      "userId",
      "rating",
      "comment",
      "hidden",
    ],
  },
  {
    label: "Support",
    collection: "supportTickets",
    icon: LifeBuoy,
    columns: ["category", "userId", "status", "message", "createdAt"],
  },
  {
    label: "Promotions",
    collection: "promotions",
    icon: TicketPercent,
    columns: ["code", "discountType", "discountValue", "academyId", "active"],
  },
  {
    label: "Achievements",
    collection: "achievements",
    icon: Star,
    columns: ["title", "description", "metric", "goal", "rewardPoints", "color", "active"],
  },
  {
    label: "Tournaments",
    collection: "tournaments",
    icon: CalendarDays,
    columns: ["name", "sport", "format", "teamSize", "maxEntries", "status", "academyId"],
  },
  {
    label: "Audit logs",
    collection: "auditLogs",
    icon: ShieldCheck,
    columns: [
      "action",
      "actorId",
      "entity",
      "entityId",
      "academyId",
    ],
  },
  { label: "Settings", icon: Settings },
];

export default function App() {
  const [user, setUser] =
    useState<User | null>(null);
  const [allowed, setAllowed] =
    useState(false);
  const [loading, setLoading] =
    useState(true);
  const [active, setActive] =
    useState(0);
  const [mobile, setMobile] =
    useState(false);
  useEffect(
    () =>
      auth.onAuthStateChanged(
        (next) => {
          setUser(next);
          if (!next) {
            setAllowed(false);
            setLoading(false);
            return;
          }
          return onSnapshot(
            doc(db, "users", next.uid),
            (snap) => {
              const role =
                snap.data()?.role;
              setAllowed(
                role === "superAdmin" ||
                  role ===
                    "platformAdmin",
              );
              setLoading(false);
            },
          );
        },
      ),
    [],
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
          <p>
            This account is not a
            platform administrator.
          </p>
          <button
            onClick={() =>
              signOut(auth)
            }
          >
            Sign out
          </button>
        </div>
      </div>
    );
  const current = modules[active];
  return (
    <div className="shell">
      <aside
        className={mobile ? "open" : ""}
      >
        <div className="brand">
          <img src="/icon.png" />
          <span>PlayUp Admin</span>
          <button
            className="close"
            onClick={() =>
              setMobile(false)
            }
          >
            <X />
          </button>
        </div>
        <nav>
          {modules.map((m, i) => (
            <button
              key={m.label}
              className={
                active === i
                  ? "active"
                  : ""
              }
              onClick={() => {
                setActive(i);
                setMobile(false);
              }}
            >
              <m.icon size={20} />
              <span>{m.label}</span>
            </button>
          ))}
        </nav>
        <div className="account">
          <small>{user.email}</small>
          <button
            onClick={() =>
              signOut(auth)
            }
          >
            <LogOut size={18} /> Sign
            out
          </button>
        </div>
      </aside>
      <main>
        <header>
          <button
            className="hamburger"
            onClick={() =>
              setMobile(true)
            }
          >
            <Menu />
          </button>
          <div>
            <h1>{current.label}</h1>
            <p>
              PlayUp platform
              administration
            </p>
          </div>
          <div className="avatar">
            {user.email?.[0].toUpperCase()}
          </div>
        </header>
        {active === 0 ? (
          <Dashboard />
        ) : current.label === "Academies" ? (
          <AcademyPortfolio />
        ) : current.label === "Owner Accounts" ? (
          <OwnerAccounts />
        ) : current.collection ? (
          <DataModule
            module={current}
          />
        ) : (
          <SettingsPage />
        )}
      </main>
    </div>
  );
}

type LiveRow = Record<string, unknown> & { id: string };

function OwnerAccounts() {
  const [academies, setAcademies] = useState<LiveRow[]>([]);
  const [courts, setCourts] = useState<LiveRow[]>([]);
  const [ownerType, setOwnerType] = useState("academy");
  const [academyId, setAcademyId] = useState("");
  const [courtId, setCourtId] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [resetEmail, setResetEmail] = useState("");
  useEffect(() => {
    const a = onSnapshot(collection(db,"academies"), snap => setAcademies(snap.docs.map(d=>({id:d.id,...d.data()}))));
    const c = onSnapshot(collection(db,"courts"), snap => setCourts(snap.docs.map(d=>({id:d.id,...d.data()}))));
    return () => {a();c();};
  },[]);
  const availableCourts = courts.filter(c => c.academyId === academyId);
  async function create(e: FormEvent) {
    e.preventDefault(); setBusy(true); setError(""); setMessage("");
    try {
      await httpsCallable(functions,"createManagedOwnerAccount")({ownerType,academyId,courtId:ownerType==="court"?courtId:null,displayName,email});
      setResetEmail(email);
      try {
        await sendPasswordResetEmail(auth,email);
        setMessage(`Account created. A secure password setup email was sent to ${email}.`);
      } catch {
        setMessage(`Account created for ${email}.`);
        setError("The password email was not sent. Use Resend setup email below.");
      }
      setDisplayName(""); setEmail(""); setCourtId("");
    } catch(err) {
      setError(err instanceof Error ? err.message : "The owner account could not be created.");
    } finally { setBusy(false); }
  }
  return <section className="content owner-workspace">
    <div className="portfolio-head"><div><span className="eyebrow">IDENTITY & ACCESS</span><h2>Create owner account</h2><p>Assign access to an academy or a specific court. The owner receives a secure email to choose their password.</p></div></div>
    <div className="owner-layout">
      <form className="table-card owner-form" onSubmit={create}>
        <div className="owner-type"><button type="button" className={ownerType==="academy"?"selected":""} onClick={()=>{setOwnerType("academy");setCourtId("")}}><Building2/><strong>Academy owner</strong><span>Manage the full academy and all its courts</span></button><button type="button" className={ownerType==="court"?"selected":""} onClick={()=>setOwnerType("court")}><Dumbbell/><strong>Court owner</strong><span>Assigned to one specific court</span></button></div>
        <label>Full name<input value={displayName} onChange={e=>setDisplayName(e.target.value)} required autoComplete="name"/></label>
        <label>Email address<input type="email" value={email} onChange={e=>setEmail(e.target.value)} required autoComplete="email"/></label>
        <label>Academy<select value={academyId} onChange={e=>{setAcademyId(e.target.value);setCourtId("")}} required><option value="">Select an academy</option>{academies.map(a=><option key={a.id} value={a.id}>{String(a.name??a.id)}</option>)}</select></label>
        {ownerType==="court"&&<label>Court<select value={courtId} onChange={e=>setCourtId(e.target.value)} required disabled={!academyId}><option value="">Select a court</option>{availableCourts.map(c=><option key={c.id} value={c.id}>{String(c.name??c.id)}</option>)}</select></label>}
        {error&&<div className="error">{error}{resetEmail&&<button type="button" className="retry-email" onClick={async()=>{setError("");try{await sendPasswordResetEmail(auth,resetEmail);setMessage(`Password setup email sent to ${resetEmail}.`)}catch{setError("Email still could not be sent. Check Firebase email-template configuration.")}}}>Resend setup email</button>}</div>}{message&&<div className="success">{message}</div>}
        <button className="primary-action owner-submit" disabled={busy}>{busy?"Creating account…":"Create account and send email"}</button>
      </form>
      <div className="process-card"><ShieldCheck size={30}/><h3>Secure onboarding</h3><ol><li>PlayUp creates the owner identity.</li><li>The owner receives Firebase's password setup email.</li><li>They choose a private password.</li><li>The app routes them directly to owner operations after sign-in.</li></ol><p>No temporary password is shown or stored by the administrator.</p></div>
    </div>
  </section>;
}

function money(minor: number, currency: string) {
  return new Intl.NumberFormat(undefined, {style: "currency", currency, maximumFractionDigits: 2}).format(minor / 100);
}

function AcademyPortfolio() {
  const [academies, setAcademies] = useState<LiveRow[]>([]);
  const [courts, setCourts] = useState<LiveRow[]>([]);
  const [bookings, setBookings] = useState<LiveRow[]>([]);
  const [selected, setSelected] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [saving, setSaving] = useState(false);
  useEffect(() => {
    const academyStop = onSnapshot(collection(db, "academies"), snap => setAcademies(snap.docs.map(d => ({id:d.id, ...d.data()}))));
    const courtStop = onSnapshot(collection(db, "courts"), snap => setCourts(snap.docs.map(d => ({id:d.id, ...d.data()}))));
    const bookingStop = onSnapshot(collection(db, "bookings"), snap => setBookings(snap.docs.map(d => ({id:d.id, ...d.data()}))));
    return () => { academyStop(); courtStop(); bookingStop(); };
  }, []);
  const rows = academies.filter(a => String(a.name ?? "").toLowerCase().includes(query.toLowerCase()));
  const current = academies.find(a => a.id === selected);
  const totals = (academyId: string) => {
    const academyBookings = bookings.filter(b => b.academyId === academyId);
    const collected = academyBookings.filter(b => b.paymentStatus === "collected").reduce((sum,b) => sum + Number(b.totalMinor ?? 0), 0);
    const pending = academyBookings.filter(b => b.paymentStatus !== "collected" && b.status !== "cancelled").reduce((sum,b) => sum + Number(b.totalMinor ?? 0), 0);
    const percent = Number(academies.find(a => a.id === academyId)?.platformCommissionPercent ?? 0);
    return {academyBookings, collected, pending, percent, commission: Math.round(collected * percent / 100)};
  };
  if (current) {
    const currency = String(current.currency ?? "JOD");
    const t = totals(current.id);
    const academyCourts = courts.filter(c => c.academyId === current.id);
    async function savePercent(value: string) {
      const percent = Math.min(100, Math.max(0, Number(value) || 0));
      setSaving(true);
      try { await setDoc(doc(db,"academies",current!.id), {platformCommissionPercent: percent, updatedAt: serverTimestamp()}, {merge:true}); }
      finally { setSaving(false); }
    }
    return <section className="content academy-record">
      <button className="back-link" onClick={() => setSelected(null)}><ChevronLeft size={18}/> All academies</button>
      <div className="record-hero">
        <div><span className="eyebrow">ACADEMY ACCOUNT</span><h2>{String(current.name ?? "Academy")}</h2><p>{String(current.address ?? "Location not configured")}</p></div>
        <span className={`status ${current.status === "active" ? "good" : ""}`}>{String(current.status ?? "unknown")}</span>
      </div>
      <div className="record-metrics">
        <article><span>Collected revenue</span><strong>{money(t.collected,currency)}</strong><small>Cash confirmed</small></article>
        <article><span>Pending revenue</span><strong>{money(t.pending,currency)}</strong><small>Awaiting collection</small></article>
        <article className="accent"><span>PlayUp revenue</span><strong>{money(t.commission,currency)}</strong><small>{t.percent}% of collected revenue</small></article>
        <article><span>Bookings</span><strong>{t.academyBookings.length}</strong><small>{academyCourts.length} courts</small></article>
      </div>
      <div className="workspace-grid">
        <div className="table-card">
          <div className="section-title"><div><h3>Courts</h3><p>Performance for every venue</p></div></div>
          <div className="court-records">{academyCourts.map(c => {
            const courtBookings=t.academyBookings.filter(b=>b.courtId===c.id);
            const gross=courtBookings.filter(b=>b.paymentStatus==="collected").reduce((s,b)=>s+Number(b.totalMinor??0),0);
            return <article key={c.id}><div className="court-thumb">{c.imageUrl ? <img src={String(c.imageUrl)} /> : <Dumbbell/>}</div><div><strong>{String(c.name??"Court")}</strong><span>{String(c.sport??"Sport")} · {courtBookings.length} bookings</span></div><b>{money(gross,currency)}</b></article>;
          })}{!academyCourts.length && <div className="empty">No courts have been added.</div>}</div>
        </div>
        <div className="commission-card">
          <CircleDollarSign size={30}/><h3>Commission agreement</h3><p>Set the percentage PlayUp receives from this academy's collected booking revenue.</p>
          <label>Platform percentage<div className="percent-input"><input type="number" min="0" max="100" step="0.1" defaultValue={t.percent} onBlur={e=>savePercent(e.target.value)}/><span>%</span></div></label>
          <small>{saving ? "Saving…" : "Saved automatically"}</small>
          <div className="formula"><span>Collected</span><b>{money(t.collected,currency)}</b><span>PlayUp share</span><b>{money(t.commission,currency)}</b></div>
        </div>
      </div>
    </section>;
  }
  const commissionByCurrency = academies.reduce<Record<string,number>>((result,a) => {
    const currency=String(a.currency??"JOD");
    result[currency]=(result[currency]??0)+totals(a.id).commission;
    return result;
  },{});
  return <section className="content">
    <div className="portfolio-head"><div><span className="eyebrow">PARTNER CRM</span><h2>Academy portfolio</h2><p>Open any academy to inspect its courts, bookings, cash collection, and PlayUp commission.</p></div><div className="portfolio-total"><span>PlayUp collected revenue</span>{Object.entries(commissionByCurrency).map(([currency,value])=><strong key={currency}>{money(value,currency)}</strong>)}{!Object.keys(commissionByCurrency).length&&<strong>—</strong>}</div></div>
    <div className="table-card">
      <div className="table-head"><div><h2>Academy accounts</h2><p>{rows.length} live partners</p></div><label className="search"><Search size={18}/><input placeholder="Search academies" value={query} onChange={e=>setQuery(e.target.value)}/></label></div>
      <div className="academy-list">{rows.map(a=>{const t=totals(a.id);const currency=String(a.currency??"JOD");return <button key={a.id} onClick={()=>setSelected(a.id)}><div className="academy-logo">{String(a.name??"A").charAt(0)}</div><div className="academy-name"><strong>{String(a.name??"Academy")}</strong><span>{courts.filter(c=>c.academyId===a.id).length} courts · {t.academyBookings.length} bookings</span></div><div><span>Collected</span><b>{money(t.collected,currency)}</b></div><div><span>Commission</span><b>{t.percent}% · {money(t.commission,currency)}</b></div><span className={`status ${a.status === "active" ? "good" : ""}`}>{String(a.status??"unknown")}</span><ChevronRight size={20}/></button>})}{!rows.length&&<div className="empty">No academies match this search.</div>}</div>
    </div>
  </section>;
}

function Login() {
  const [email, setEmail] = useState(
    import.meta.env.VITE_UAT_EMAIL ||
      "",
  );
  const [password, setPassword] =
    useState(
      import.meta.env
        .VITE_UAT_PASSWORD || "",
    );
  const [error, setError] =
    useState("");
  const [busy, setBusy] =
    useState(false);
  useEffect(() => {
    if (
      import.meta.env
        .VITE_USE_EMULATORS ===
        "true" &&
      email &&
      password
    ) {
      setBusy(true);
      signInWithEmailAndPassword(
        auth,
        email,
        password,
      )
        .catch((err) =>
          setError(
            err instanceof Error
              ? err.message
              : "Sign-in failed",
          ),
        )
        .finally(() => setBusy(false));
    }
  }, []);
  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      await signInWithEmailAndPassword(
        auth,
        email,
        password,
      );
    } catch (err) {
      setError(
        err instanceof Error
          ? err.message
          : "Sign-in failed",
      );
    } finally {
      setBusy(false);
    }
  }
  return (
    <div className="center">
      <form
        className="login"
        onSubmit={submit}
      >
        <img src="/icon.png" />
        <h1>Administration</h1>
        <p>
          Sign in with your platform
          administrator account.
        </p>
        <label>
          Email
          <input
            value={email}
            onChange={(e) =>
              setEmail(e.target.value)
            }
            type="email"
            required
            autoFocus
          />
        </label>
        <label>
          Password
          <input
            value={password}
            onChange={(e) =>
              setPassword(
                e.target.value,
              )
            }
            type="password"
            required
          />
        </label>
        {error && (
          <div className="error">
            {error}
          </div>
        )}
        <button disabled={busy}>
          {busy
            ? "Signing in…"
            : "Sign in"}
        </button>
      </form>
    </div>
  );
}

function Dashboard() {
  const names = [
    "bookings",
    "users",
    "academies",
    "courts",
    "matches",
    "reviews",
  ];
  const [counts, setCounts] = useState<
    Record<string, number>
  >({});
  const [bookings, setBookings] = useState<LiveRow[]>([]);
  const [tickets, setTickets] = useState<LiveRow[]>([]);
  const [error, setError] = useState("");
  useEffect(() => {
    Promise.all(
      names.map(
        async (n) =>
          [
            n,
            (
              await getCountFromServer(
                collection(db, n),
              )
            ).data().count,
          ] as const,
      ),
    )
      .then((rows) => setCounts(Object.fromEntries(rows)))
      .catch(() => setError("Some platform totals could not be loaded."));
    const stopBookings = onSnapshot(
      collection(db, "bookings"),
      (snap) => setBookings(snap.docs.map((d) => ({id: d.id, ...d.data()}))),
      () => setError("Live booking operations are temporarily unavailable."),
    );
    const stopTickets = onSnapshot(
      collection(db, "supportTickets"),
      (snap) => setTickets(snap.docs.map((d) => ({id: d.id, ...d.data()}))),
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
  const collectedMinor = bookings
    .filter((row) => row.paymentStatus === "collected")
    .reduce((total, row) => total + Number(row.totalMinor ?? 0), 0);
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
          <h2>Platform command center</h2>
          <p>Bookings, partners, revenue and service health in one decision-ready view.</p>
        </div>
        <div className="live-indicator"><span /> Live data</div>
      </div>
      {error && <div className="notice warning"><AlertTriangle size={18}/>{error}</div>}
      <div className="executive-metrics">
        <article className="metric-primary">
          <div><CircleDollarSign size={20}/><span>Collected booking value</span></div>
          <strong>{money(collectedMinor, "JOD")}</strong>
          <small><TrendingUp size={14}/> Cash confirmed across the platform</small>
        </article>
        <article>
          <div><CalendarDays size={20}/><span>Active bookings</span></div>
          <strong>{activeBookings.length}</strong>
          <small>{pendingBookings.length} awaiting confirmation</small>
        </article>
        <article>
          <div><Building2 size={20}/><span>Partner network</span></div>
          <strong>{counts.academies ?? "—"}</strong>
          <small>{counts.courts ?? "—"} live court records</small>
        </article>
        <article className={openTickets.length ? "metric-attention" : ""}>
          <div><LifeBuoy size={20}/><span>Support queue</span></div>
          <strong>{openTickets.length}</strong>
          <small>{openTickets.length ? "Needs operator attention" : "All requests handled"}</small>
        </article>
      </div>
      <div className="dashboard-grid">
        <article className="insight-card">
          <div className="section-title"><div><h3>Booking pipeline</h3><p>Current operational distribution</p></div><Activity size={20}/></div>
          <div className="pipeline">
            {bookingStatuses.map((status) => {
              const value = bookings.filter((row) => row.status === status).length;
              return <div className="pipeline-row" key={status}>
                <span>{status}</span>
                <div><i style={{width: `${Math.max(4, value / maximumStatusCount * 100)}%`}} /></div>
                <b>{value}</b>
              </div>;
            })}
          </div>
        </article>
        <article className="insight-card operations-card">
          <div className="section-title"><div><h3>Operations inbox</h3><p>Items requiring a decision</p></div><Clock3 size={20}/></div>
          <div className="operation-list">
            <div><span className="operation-icon amber"><CalendarDays size={18}/></span><div><strong>{pendingBookings.length} booking requests</strong><small>Confirm or cancel pending reservations</small></div><ArrowUpRight size={17}/></div>
            <div><span className="operation-icon purple"><LifeBuoy size={18}/></span><div><strong>{openTickets.length} support requests</strong><small>Review player and partner issues</small></div><ArrowUpRight size={17}/></div>
            <div><span className="operation-icon green"><CheckCircle2 size={18}/></span><div><strong>Access controls active</strong><small>Tenant and role isolation enforced</small></div><ShieldCheck size={17}/></div>
          </div>
        </article>
      </div>
      <div className="section-gap">
        <DataModule module={{label:"Recent bookings",collection:"bookings",icon:CalendarDays,columns:["courtName","academyId","status","paymentStatus","totalMinor"]}} embedded />
      </div>
    </section>
  );
}

function LegacyDataModule({
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
  useEffect(
    () =>
      onSnapshot(
        collection(
          db,
          module.collection!,
        ),
        (snap) =>
          setRows(
            snap.docs.map((d) => ({
              id: d.id,
              ...d.data(),
            })),
          ),
      ),
    [module.collection],
  );
  const filtered = useMemo(
    () =>
      rows.filter((r) =>
        Object.values(r)
          .join(" ")
          .toLowerCase()
          .includes(q.toLowerCase()),
      ),
    [rows, q],
  );
  return (
    <section
      className={
        embedded
          ? "table-card embedded"
          : "content"
      }
    >
      <div className="table-card">
        <div className="table-head">
          <div>
            <h2>{module.label}</h2>
            <p>
              {filtered.length} records
            </p>
          </div>
          <label className="search">
            <Search size={18} />
            <input
              placeholder="Search records"
              value={q}
              onChange={(e) =>
                setQ(e.target.value)
              }
            />
          </label>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>ID</th>
                {module.columns!.map(
                  (c) => (
                    <th key={c}>{c}</th>
                  ),
                )}
              </tr>
            </thead>
            <tbody>
              {filtered.map((row) => (
                <tr key={row.id}>
                  <td>{row.id}</td>
                  {module.columns!.map(
                    (c) => (
                      <td key={c}>
                        {String(
                          row[c] ?? "—",
                        )}
                      </td>
                    ),
                  )}
                </tr>
              ))}
            </tbody>
          </table>
          {!filtered.length && (
            <div className="empty">
              No matching records.
            </div>
          )}
        </div>
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
  const [editing, setEditing] =
    useState<
      | (Record<string, unknown> & {
          id?: string;
        })
      | null
    >(null);
  const [busy, setBusy] =
    useState(false);
  const [error, setError] =
    useState("");
  useEffect(
    () =>
      onSnapshot(
        collection(
          db,
          module.collection!,
        ),
        (snap) =>
          setRows(
            snap.docs.map((d) => ({
              id: d.id,
              ...d.data(),
            })),
          ),
      ),
    [module.collection],
  );
  const filtered = useMemo(
    () =>
      rows.filter((r) =>
        Object.values(r)
          .join(" ")
          .toLowerCase()
          .includes(q.toLowerCase()),
      ),
    [rows, q],
  );
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
      new Blob([csv], {type: "text/csv;charset=utf-8"}),
    );
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `${module.label.toLowerCase().replaceAll(" ", "-")}.csv`;
    anchor.click();
    URL.revokeObjectURL(url);
  }
  const editable =
    !embedded &&
    ![
      "Audit logs",
      "Matchmaking",
    ].includes(module.label);
  async function save(e: FormEvent) {
    e.preventDefault();
    if (!editing) return;
    setBusy(true);
    setError("");
    try {
      const payload: Record<
        string,
        unknown
      > = {
        updatedAt: serverTimestamp(),
      };
      for (const column of module.columns!) {
        let value = editing[column];
        if (
          value === "true" ||
          value === "false"
        )
          value = value === "true";
        else if (
          typeof value === "string" &&
          value.trim() !== "" &&
          !Number.isNaN(Number(value))
        )
          value = Number(value);
        payload[column] = value ?? "";
      }
      if (editing.id)
        await setDoc(
          doc(
            db,
            module.collection!,
            editing.id,
          ),
          payload,
          { merge: true },
        );
      else
        await addDoc(
          collection(
            db,
            module.collection!,
          ),
          {
            ...payload,
            createdAt:
              serverTimestamp(),
          },
        );
      setEditing(null);
    } catch (err) {
      setError(
        err instanceof Error
          ? err.message
          : "Save failed",
      );
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
      await deleteDoc(
        doc(db, module.collection!, id),
      );
    } catch (err) {
      alert(
        err instanceof Error
          ? err.message
          : "Delete failed",
      );
    }
  }
  async function bookingAction(
    id: string,
    status: string,
  ) {
    try {
      await httpsCallable(
        functions,
        "transitionBooking",
      )({ bookingId: id, status });
    } catch (err) {
      alert(
        err instanceof Error
          ? err.message
          : "Update failed",
      );
    }
  }
  async function collectCash(
    id: string,
  ) {
    try {
      await httpsCallable(
        functions,
        "recordCashPayment",
      )({ bookingId: id });
    } catch (err) {
      alert(
        err instanceof Error
          ? err.message
          : "Payment update failed",
      );
    }
  }
  return (
    <section
      className={
        embedded
          ? "table-card embedded"
          : "content"
      }
    >
      <div className="table-card">
        <div className="table-head">
          <div>
            <h2>{module.label}</h2>
            <p>
              {filtered.length} live
              records
            </p>
          </div>
          <label className="search">
            <Search size={18} />
            <input
              placeholder="Search records"
              value={q}
              onChange={(e) =>
                setQ(e.target.value)
              }
            />
          </label>
          <button className="secondary-action" onClick={exportCsv}>
            <Download size={17} /> Export
          </button>
          {editable &&
            module.label !==
              "Bookings" && (
              <button
                className="primary-action"
                onClick={() =>
                  setEditing({})
                }
              >
                <Plus size={18} /> Add
              </button>
            )}
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>ID</th>
                {module.columns!.map(
                  (c) => (
                    <th key={c}>{c}</th>
                  ),
                )}
                {!embedded && (
                  <th>Actions</th>
                )}
              </tr>
            </thead>
            <tbody>
              {filtered.map((row) => (
                <tr key={row.id}>
                  <td>{row.id}</td>
                  {module.columns!.map(
                    (c) => (
                      <td key={c}>
                        {["status", "paymentStatus", "role"].includes(c) ? (
                          <span className={`data-pill ${String(row[c] ?? "").toLowerCase()}`}>
                            {String(row[c] ?? "-")}
                          </span>
                        ) : String(row[c] ?? "-")}
                      </td>
                    ),
                  )}
                  {!embedded && (
                    <td className="row-actions">
                      {editable &&
                        module.label !==
                          "Bookings" && (
                          <>
                            <button
                              title="Edit"
                              onClick={() =>
                                setEditing(
                                  row,
                                )
                              }
                            >
                              <Edit3
                                size={
                                  17
                                }
                              />
                            </button>
                            <button
                              title="Delete"
                              className="danger"
                              onClick={() =>
                                remove(
                                  row.id,
                                )
                              }
                            >
                              <Trash2
                                size={
                                  17
                                }
                              />
                            </button>
                          </>
                        )}
                      {module.label ===
                        "Bookings" && (
                        <>
                          <button
                            onClick={() =>
                              bookingAction(
                                row.id,
                                "confirmed",
                              )
                            }
                          >
                            Confirm
                          </button>
                          <button
                            onClick={() =>
                              bookingAction(
                                row.id,
                                "cancelled",
                              )
                            }
                          >
                            Cancel
                          </button>
                          {row.paymentStatus !==
                            "collected" && (
                            <button
                              onClick={() =>
                                collectCash(
                                  row.id,
                                )
                              }
                            >
                              Cash
                              received
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
          {!filtered.length && (
            <div className="empty">
              No matching records.
            </div>
          )}
        </div>
      </div>
      {editing && (
        <div
          className="modal-backdrop"
          onMouseDown={() =>
            !busy && setEditing(null)
          }
        >
          <form
            className="editor"
            onSubmit={save}
            onMouseDown={(e) =>
              e.stopPropagation()
            }
          >
            <div className="editor-head">
              <div>
                <h2>
                  {editing.id
                    ? "Edit"
                    : "Add"}{" "}
                  {module.label}
                </h2>
                <p>
                  {editing.id ||
                    "New record"}
                </p>
              </div>
              <button
                type="button"
                onClick={() =>
                  setEditing(null)
                }
              >
                <X />
              </button>
            </div>
            {module.columns!.map(
              (column) => (
                <label key={column}>
                  {column}
                  {column === "currency" ? (
                    <select value={String(editing[column] ?? "JOD")} onChange={(e) => setEditing({...editing, [column]: e.target.value})}>
                      {["JOD", "AED", "SAR", "QAR", "KWD", "BHD", "OMR", "USD"].map((v) => <option key={v}>{v}</option>)}
                    </select>
                  ) : ["active", "hidden", "suspended"].includes(column) ? (
                    <select value={String(editing[column] ?? false)} onChange={(e) => setEditing({...editing, [column]: e.target.value === "true"})}>
                      <option value="true">Yes</option><option value="false">No</option>
                    </select>
                  ) : column === "sport" ? (
                    <select value={String(editing[column] ?? "Football")} onChange={(e) => setEditing({...editing, [column]: e.target.value})}>
                      {["Football", "Basketball", "Padel", "Tennis", "Volleyball", "Cricket", "Handball"].map((v) => <option key={v}>{v}</option>)}
                    </select>
                  ) : column === "format" ? (
                    <select value={String(editing[column] ?? "singleElimination")} onChange={(e) => setEditing({...editing, [column]: e.target.value})}>
                      <option value="singleElimination">Single elimination</option><option value="doubleElimination">Double elimination</option><option value="roundRobin">Round robin</option><option value="groupKnockout">Groups + knockout</option>
                    </select>
                  ) : column === "metric" ? (
                    <select value={String(editing[column] ?? "bookings")} onChange={(e) => setEditing({...editing, [column]: e.target.value})}>
                      <option value="bookings">Bookings completed</option><option value="matchesPlayed">Matches played</option><option value="rating5">Five-star rating</option><option value="weekendStreak">Weekend streak</option><option value="noCancellationStreak">No-cancellation streak</option><option value="tournamentWins">Tournament wins</option><option value="matchesHosted">Matches hosted</option><option value="academyLoyalty">Academy loyalty</option>
                    </select>
                  ) : column === "color" ? (
                    <select value={String(editing[column] ?? "purple")} onChange={(e) => setEditing({...editing, [column]: e.target.value})}>
                      {["purple","green","gold","blue","orange","pink"].map((value) => <option key={value}>{value}</option>)}
                    </select>
                  ) : (
                    <input value={String(editing[column] ?? "")} onChange={(e) => setEditing({...editing, [column]: e.target.value})} />
                  )}
                </label>
              ),
            )}
            {error && (
              <div className="error">
                {error}
              </div>
            )}
            <div className="editor-actions">
              <button
                type="button"
                onClick={() =>
                  setEditing(null)
                }
              >
                Cancel
              </button>
              <button
                className="primary-action"
                disabled={busy}
              >
                {busy
                  ? "Saving..."
                  : "Save changes"}
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
  });
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(false);
  useEffect(
    () =>
      onSnapshot(doc(db, "platformConfig", "general"), (snap) => {
        if (snap.exists()) {
          setConfig((current) => ({...current, ...snap.data()}));
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
        {...config, updatedAt: serverTimestamp()},
        {merge: true},
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
          <div><h3>Service configuration</h3><p>Defaults used across PlayUp experiences.</p></div>
          <div className="settings-fields">
            <label>Support email<input type="email" value={config.supportEmail} onChange={(e) => setConfig({...config, supportEmail: e.target.value})} placeholder="support@playup.app" /></label>
            <label>Default currency<select value={config.defaultCurrency} onChange={(e) => setConfig({...config, defaultCurrency: e.target.value})}>{["JOD","AED","SAR","QAR","KWD","BHD","OMR","USD"].map((value) => <option key={value}>{value}</option>)}</select></label>
            <label className="full">Booking notice<textarea value={config.bookingNotice} onChange={(e) => setConfig({...config, bookingNotice: e.target.value})} rows={3} /></label>
          </div>
        </div>
        <div className="settings-section danger-zone">
          <div><h3>Maintenance control</h3><p>Use only when platform access must be paused.</p></div>
          <label className="switch-row">
            <div><strong>Maintenance mode</strong><span>Display a service notice and prevent new operations.</span></div>
            <input type="checkbox" checked={config.maintenanceMode} onChange={(e) => setConfig({...config, maintenanceMode: e.target.checked})} />
          </label>
        </div>
        <div className="settings-save">
          {saved && <span><CheckCircle2 size={17} /> Settings saved</span>}
          <button className="primary-action" disabled={busy}>{busy ? "Saving…" : "Save platform settings"}</button>
        </div>
      </form>
    </section>
  );
}
