import {PGlite} from '@electric-sql/pglite';
import fs from 'node:fs';
const db=new PGlite();
try {
 await db.exec(`CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role;
 CREATE SCHEMA auth; CREATE TABLE auth.users(id uuid PRIMARY KEY);
 CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 GRANT USAGE ON SCHEMA auth TO authenticated; GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated;`);
 for (const file of fs.readdirSync('supabase/migrations').filter(name=>name.endsWith('.sql')).sort()) {
   await db.exec(fs.readFileSync(`supabase/migrations/${file}`,'utf8'));
 }
 console.log('PASS: schema creates successfully');
 await db.query('SELECT bm.validar_integridad()');
 console.log('PASS: empty integrity');
 console.log((await db.query("SELECT count(*) n FROM pg_tables WHERE schemaname='bm'")).rows);
 if(fs.existsSync('tests.sql'))await db.exec(fs.readFileSync('tests.sql','utf8').replace(/ROLLBACK;\s*$/,'COMMIT;'));
 console.log('PASS: all regression SQL');
 const backup=await db.dumpDataDir();
 const restored=new PGlite({loadDataDir:backup});
 try{
   await restored.query('SELECT bm.validar_integridad()');
   const {rows}=await restored.query("SELECT count(*)::int n FROM pg_tables WHERE schemaname='bm'");
   if(rows[0].n!==55)throw Error('Restored schema table count mismatch');
   const original=(await db.query('SELECT sum(stock_fisico)::int stock FROM bm.v_stock_variante')).rows;
   const recovered=(await restored.query('SELECT sum(stock_fisico)::int stock FROM bm.v_stock_variante')).rows;
   if(JSON.stringify(original)!==JSON.stringify(recovered)||original[0].stock!==9)throw Error('Restored data mismatch');
   console.log('PASS: local backup restores schema, test data, stock and integrity functions');
 }finally{await restored.close();}
} catch(e){console.error({message:e.message,detail:e.detail,where:e.where,position:e.position,query:e.position?e.query?.slice(Math.max(0,Number(e.position)-150),Number(e.position)+150):e.query?.slice(0,500)});process.exitCode=1;}finally{await db.close();}
