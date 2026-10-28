import fs from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
export async function database(){const db=new PGlite();await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role; CREATE SCHEMA auth; CREATE TABLE auth.users(id uuid PRIMARY KEY,email text); CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$; GRANT USAGE ON SCHEMA auth TO authenticated; GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated;`);for(const file of fs.readdirSync('supabase/migrations').filter(n=>n.endsWith('.sql')).sort())await db.exec(fs.readFileSync('supabase/migrations/'+file,'utf8'));return db;}
if(process.argv[1]?.endsWith('schema.mjs')){
const db=await database();try{
const tables=(await db.query(`SELECT tabla,clave FROM bm.recurso ORDER BY tabla`)).rows;
const schema={};
for(const {tabla,clave} of tables){
 const columns=(await db.query(`SELECT column_name name,data_type type,is_nullable='YES' nullable,column_default AS "default",is_generated<>'NEVER' OR is_identity='YES' AS readonly,character_maximum_length AS max FROM information_schema.columns WHERE table_schema='bm' AND table_name=$1 ORDER BY ordinal_position`,[tabla])).rows;
 const checks=(await db.query(`SELECT pg_get_constraintdef(oid) def FROM pg_constraint WHERE conrelid=$1::regclass AND contype='c'`,['bm.'+tabla])).rows.map(c=>c.def);
 const fks=(await db.query(`SELECT a.attname col,cl.relname target,at.attname key FROM pg_constraint c JOIN LATERAL unnest(c.conkey,c.confkey) k(local,remote) ON true JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=k.local JOIN pg_class cl ON cl.oid=c.confrelid JOIN pg_attribute at ON at.attrelid=c.confrelid AND at.attnum=k.remote JOIN bm.recurso r ON r.tabla=cl.relname AND r.clave=at.attname WHERE c.contype='f' AND c.conrelid=$1::regclass ORDER BY cardinality(c.conkey),c.conname`,['bm.'+tabla])).rows;
 for(const col of columns){col.readonly ||= ['registrado_en','registrado_por','actualizado_en'].includes(col.name);col.fk=fks.find(f=>f.col===col.name);const check=checks.find(c=>c.includes(col.name)&&c.includes('ANY (ARRAY[')&&!c.includes(' OR '));if(check){const segment=check.match(/ARRAY\[([^\]]+)\]/)?.[1];col.options=segment?[...segment.matchAll(/'([^']+)'/g)].map(m=>m[1]):undefined;}}
 schema[tabla]={key:clave,columns};
}
const views=(await db.query(`SELECT c.table_name,c.column_name FROM information_schema.columns c JOIN information_schema.views v USING(table_schema,table_name) WHERE c.table_schema='bm' ORDER BY c.table_name,c.ordinal_position`)).rows;
for(const v of views){schema[v.table_name]??={view:true,columns:[]};schema[v.table_name].columns.push({name:v.column_name,readonly:true});}
fs.mkdirSync('src',{recursive:true});fs.writeFileSync('src/schema.json',JSON.stringify(schema,null,2));console.log('Schema generated:',Object.keys(schema).length,'resources');
}finally{await db.close();}}
