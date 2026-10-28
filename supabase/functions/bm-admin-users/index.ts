import { createClient } from 'npm:@supabase/supabase-js@2.118.0';

const site = 'https://inventariobm.mariabonitaec.com';
const allowed = new Set([site, 'https://inventariobm.pages.dev', 'http://127.0.0.1:5173']);
Deno.serve(async (req: Request) => {
  const origin = req.headers.get('origin') || '';
  const headers = {'Content-Type':'application/json','Cache-Control':'no-store','Vary':'Origin',
    'Access-Control-Allow-Origin':allowed.has(origin)?origin:site,
    'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info',
    'Access-Control-Allow-Methods':'POST, OPTIONS'};
  const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), {status, headers});
  if (req.method === 'OPTIONS') return new Response(null,{status:204,headers});
  if (req.method !== 'POST') return reply({error:'Método no permitido'},405);
  const bearer = req.headers.get('authorization');
  if (!bearer?.startsWith('Bearer ')) return reply({error:'Inicia sesión'},401);
  const url = Deno.env.get('SUPABASE_URL')!;
  const caller = createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{
    global:{headers:{Authorization:bearer}},auth:{persistSession:false,autoRefreshToken:false}});
  const {data:identity,error:identityError} = await caller.auth.getUser(bearer.slice(7));
  if(identityError || !identity.user) return reply({error:'Sesión inválida'},401);
  const {data:profile,error:profileError} = await caller.rpc('bm_perfil');
  if(profileError || profile?.rol !== 'administrador') return reply({error:'Requiere administrador activo'},403);
  try {
    const body = await req.json();
    const {data:members,error:membersError} = await caller.rpc('bm_usuarios');
    if(membersError) throw membersError;
    const admin = createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
    if(body.accion === 'recuperar') {
      const member = members.find((u:{id:string;activo:boolean})=>u.id===body.usuario && u.activo);
      if(!member) return reply({error:'Selecciona una persona activa del equipo'},400);
      const {data,error} = await admin.auth.admin.generateLink({type:'recovery',email:member.email});
      if(error) throw error;
      return reply({nombre:member.nombre,link:site+'/#token_hash='+encodeURIComponent(data.properties.hashed_token)+'&type=recovery'});
    }
    const email = String(body.email||'').trim().toLowerCase();
    const nombre = String(body.nombre||'').trim();
    const rol = body.rol;
    if(!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)||email.length>254||!nombre||nombre.length>100||!['administrador','operador','consulta'].includes(rol)) return reply({error:'Revisa nombre, correo y permisos'},400);
    if(members.some((u:{email:string})=>u.email.toLowerCase()===email)) return reply({error:'La persona ya pertenece al equipo. Usa «Nuevo enlace» en su cuenta.'},409);
    const {data,error} = await admin.auth.admin.generateLink({type:'invite',email});
    if(error) throw error;
    const access = await caller.rpc('bm_gestionar_usuario',{p_usuario:data.user.id,p_nombre:nombre,p_rol:rol,p_activo:true});
    if(access.error) {await admin.auth.admin.deleteUser(data.user.id);throw access.error;}
    return reply({nombre,link:site+'/#token_hash='+encodeURIComponent(data.properties.hashed_token)+'&type=invite'});
  } catch(e) {
    // Do not log request bodies, bearer tokens or activation links.
    return reply({error:e instanceof Error?e.message:'No pudimos completar la operación. Revisa las cuentas antes de repetirla.'},400);
  }
});
