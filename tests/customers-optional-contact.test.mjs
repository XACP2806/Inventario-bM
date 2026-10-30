import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {database} from '../scripts/schema.mjs';

test('nueve clientes sin contacto se guardan juntos sin duplicarse al reintentar',async()=>{
 const db=await database();
 try{
  await db.exec(fs.readFileSync('tests.sql','utf8').replace(/ROLLBACK;\s*$/,'COMMIT;'));
  await db.exec("SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','83d20ad7-300c-4cd0-9ea7-ff82366f77c2',false);");
  const save=async(actions,id=crypto.randomUUID())=>(await db.query('SELECT public.bm_registrar_operacion($1,$2,$3) result',[id,JSON.stringify(actions),'Clientes sin datos de contacto'])).rows[0].result;
  const count=async()=>Number((await db.query('SELECT count(*) n FROM bm.cliente')).rows[0].n);
  const before=await count(),actions=Array.from({length:9},(_,i)=>({accion:'insertar',tabla:'cliente',ref:'paso'+(i+1),datos:{nombre_completo:'Cliente temporal '+(i+1),...(i%2?{email:null,telefono:null}:{})}}));
  const id=crypto.randomUUID(),result=await save(actions,id);
  assert.equal(result.length,9);assert(result.every(r=>r.email===null&&r.telefono===null));
  assert.equal(await count(),before+9);
  assert.deepEqual(await save(actions,id),result);assert.equal(await count(),before+9);
  // Optional contact can be supplied later, and provided emails remain unique.
  await save([{accion:'actualizar',tabla:'cliente',id:result[0].cliente_id,datos:{email:'cliente-prueba@example.invalid',telefono:'0990000000'}}]);
  await assert.rejects(save([{accion:'insertar',tabla:'cliente',datos:{nombre_completo:'Otro cliente',email:'cliente-prueba@example.invalid'}}]),/cliente_email_key/);
  // A failure still rolls the whole batch back; the required name is not relaxed.
  await assert.rejects(save([actions[0],{accion:'insertar',tabla:'cliente',datos:{nombre_completo:null}}]),/not-null constraint/);
  assert.equal(await count(),before+9);
  await db.exec("SELECT set_config('request.jwt.claim.sub','9a70e587-27bc-424b-ae80-c80a9995d249',false)");
  await assert.rejects(save(actions),/no autorizado/);
 }finally{await db.close();}
});
