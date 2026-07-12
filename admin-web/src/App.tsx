import { FormEvent, useEffect, useMemo, useState } from 'react';
import { signInWithEmailAndPassword, signOut, User } from 'firebase/auth';
import { collection, doc, getCountFromServer, onSnapshot } from 'firebase/firestore';
import { Activity, Building2, CalendarDays, Dumbbell, LayoutDashboard, LogOut, Menu, Search, Settings, ShieldCheck, Star, Users, X } from 'lucide-react';
import { auth, db } from './firebase';

type Module = { label: string; collection?: string; icon: typeof Activity; columns?: string[] };
const modules: Module[] = [
  {label:'Dashboard',icon:LayoutDashboard},{label:'Academies',collection:'academies',icon:Building2,columns:['name','status','currency']},
  {label:'Courts',collection:'courts',icon:Dumbbell,columns:['name','sport','academyId','active','basePriceMinor']},
  {label:'Bookings',collection:'bookings',icon:CalendarDays,columns:['courtName','userId','academyId','status','totalMinor']},
  {label:'Users',collection:'users',icon:Users,columns:['displayName','email','role','academyId','suspended']},
  {label:'Matchmaking',collection:'matches',icon:Activity,columns:['title','sport','hostName','status','capacity']},
  {label:'Reviews',collection:'reviews',icon:Star,columns:['userId','rating','comment','hidden']},
  {label:'Audit logs',collection:'auditLogs',icon:ShieldCheck,columns:['action','actorId','entity','entityId','academyId']},
  {label:'Settings',icon:Settings},
];

export default function App(){
  const [user,setUser]=useState<User|null>(null); const [allowed,setAllowed]=useState(false); const [loading,setLoading]=useState(true);
  const [active,setActive]=useState(0); const [mobile,setMobile]=useState(false);
  useEffect(()=>auth.onAuthStateChanged(next=>{setUser(next);if(!next){setAllowed(false);setLoading(false);return;}return onSnapshot(doc(db,'users',next.uid),snap=>{const role=snap.data()?.role;setAllowed(role==='superAdmin'||role==='platformAdmin');setLoading(false);});}),[]);
  if(loading)return <div className="center"><div className="spinner"/></div>;
  if(!user)return <Login/>;
  if(!allowed)return <div className="center"><div className="login"><ShieldCheck size={36}/><h1>Access denied</h1><p>This account is not a platform administrator.</p><button onClick={()=>signOut(auth)}>Sign out</button></div></div>;
  const current=modules[active];
  return <div className="shell">
    <aside className={mobile?'open':''}><div className="brand"><img src="/icon.png"/><span>PlayUp Admin</span><button className="close" onClick={()=>setMobile(false)}><X/></button></div><nav>{modules.map((m,i)=><button key={m.label} className={active===i?'active':''} onClick={()=>{setActive(i);setMobile(false)}}><m.icon size={20}/><span>{m.label}</span></button>)}</nav><div className="account"><small>{user.email}</small><button onClick={()=>signOut(auth)}><LogOut size={18}/> Sign out</button></div></aside>
    <main><header><button className="hamburger" onClick={()=>setMobile(true)}><Menu/></button><div><h1>{current.label}</h1><p>PlayUp platform administration</p></div><div className="avatar">{user.email?.[0].toUpperCase()}</div></header>
      {active===0?<Dashboard/>:current.collection?<DataModule module={current}/>:<SettingsPage/>}
    </main>
  </div>;
}

function Login(){const[email,setEmail]=useState(import.meta.env.VITE_UAT_EMAIL||'');const[password,setPassword]=useState(import.meta.env.VITE_UAT_PASSWORD||'');const[error,setError]=useState('');const[busy,setBusy]=useState(false);useEffect(()=>{if(import.meta.env.VITE_USE_EMULATORS==='true'&&email&&password){setBusy(true);signInWithEmailAndPassword(auth,email,password).catch(err=>setError(err instanceof Error?err.message:'Sign-in failed')).finally(()=>setBusy(false))}},[]);async function submit(e:FormEvent){e.preventDefault();setBusy(true);setError('');try{await signInWithEmailAndPassword(auth,email,password)}catch(err){setError(err instanceof Error?err.message:'Sign-in failed')}finally{setBusy(false)}}return <div className="center"><form className="login" onSubmit={submit}><img src="/icon.png"/><h1>Administration</h1><p>Sign in with your platform administrator account.</p><label>Email<input value={email} onChange={e=>setEmail(e.target.value)} type="email" required autoFocus/></label><label>Password<input value={password} onChange={e=>setPassword(e.target.value)} type="password" required/></label>{error&&<div className="error">{error}</div>}<button disabled={busy}>{busy?'Signing in…':'Sign in'}</button></form></div>}

function Dashboard(){const names=['bookings','users','academies','courts','matches','reviews'];const[counts,setCounts]=useState<Record<string,number>>({});useEffect(()=>{Promise.all(names.map(async n=>[n,(await getCountFromServer(collection(db,n))).data().count] as const)).then(rows=>setCounts(Object.fromEntries(rows)))},[]);return <section className="content"><div className="intro"><h2>Platform overview</h2><p>Live operational totals from the current environment.</p></div><div className="metrics">{names.map(name=><article key={name}><span>{name}</span><strong>{counts[name]??'—'}</strong></article>)}</div><DataModule module={{label:'Recent bookings',collection:'bookings',icon:CalendarDays,columns:['courtName','academyId','status','totalMinor']}} embedded/></section>}

function DataModule({module,embedded=false}:{module:Module;embedded?:boolean}){const[rows,setRows]=useState<Array<Record<string,unknown>&{id:string}>>([]);const[q,setQ]=useState('');useEffect(()=>onSnapshot(collection(db,module.collection!),snap=>setRows(snap.docs.map(d=>({id:d.id,...d.data()})))),[module.collection]);const filtered=useMemo(()=>rows.filter(r=>Object.values(r).join(' ').toLowerCase().includes(q.toLowerCase())),[rows,q]);return <section className={embedded?'table-card embedded':'content'}><div className="table-card"><div className="table-head"><div><h2>{module.label}</h2><p>{filtered.length} records</p></div><label className="search"><Search size={18}/><input placeholder="Search records" value={q} onChange={e=>setQ(e.target.value)}/></label></div><div className="table-wrap"><table><thead><tr><th>ID</th>{module.columns!.map(c=><th key={c}>{c}</th>)}</tr></thead><tbody>{filtered.map(row=><tr key={row.id}><td>{row.id}</td>{module.columns!.map(c=><td key={c}>{String(row[c]??'—')}</td>)}</tr>)}</tbody></table>{!filtered.length&&<div className="empty">No matching records.</div>}</div></div></section>}
function SettingsPage(){return <section className="content"><div className="settings-grid"><article><h3>Payment policy</h3><p>Pay at venue. No card data is collected.</p></article><article><h3>Authorization</h3><p>Granular roles and academy tenant isolation are active.</p></article><article><h3>Notifications</h3><p>In-app booking and matchmaking notifications are enabled.</p></article></div></section>}
