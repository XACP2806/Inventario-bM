import test from 'node:test';
import assert from 'node:assert/strict';
import {database} from '../scripts/schema.mjs';
import fs from 'node:fs';
import {validateLocation} from '../src/record-rules.mjs';

test('ubicaciones ofrecen tipos válidos y exigen la relación correspondiente',()=>{
 const schema=JSON.parse(fs.readFileSync('src/schema.json','utf8'));
 assert.deepEqual(schema.ubicacion_tela.columns.find(c=>c.name==='tipo').options,['bodega','costurera']);
 assert.equal(schema.envio.columns.find(c=>c.name==='transportadora').options,undefined);
 assert.ok(schema.envio.columns.find(c=>c.name==='modalidad_entrega').options.includes('transportadora'));
 assert.doesNotThrow(()=>validateLocation({tipo:'bodega'}));
 assert.doesNotThrow(()=>validateLocation({tipo:'costurera',costurera_id:'@paso1'}));
 assert.throws(()=>validateLocation({tipo:'Costurera',costurera_id:'3'}),/Selecciona Bodega/);
 assert.throws(()=>validateLocation({tipo:'costurera'}),/Selecciona la costurera/);
 assert.throws(()=>validateLocation({tipo:'bodega',costurera_id:'3'}),/no debe estar vinculada/);
});

test('guardado autenticado confirma la transacción sin permisos internos',async()=>{
 const db=await database();
 const uid='83d20ad7-300c-4cd0-9ea7-ff82366f77c2';
 try{
  await db.exec(`INSERT INTO auth.users(id) VALUES('${uid}');
   INSERT INTO bm.usuario_bm(usuario_id,nombre,rol,activo) VALUES('${uid}','Prueba','administrador',true);
   SET ROLE authenticated;
   SELECT set_config('request.jwt.claim.sub','${uid}',false);`);
  const permissions=(await db.query(`SELECT has_function_privilege(current_user,'bm.validar_integridad()','EXECUTE') AS validator,
   has_table_privilege(current_user,'bm.proveedor','INSERT') AS direct_write`)).rows[0];
  assert.equal(permissions.validator,false);
  assert.equal(permissions.direct_write,false);
  assert.equal((await db.query('SELECT current_user AS role')).rows[0].role,'authenticated');
  const id=crypto.randomUUID();
  const actions=JSON.stringify([{tabla:'proveedor',accion:'insertar',datos:{nombre_legal:'Proveedor de prueba'}}]);
  await db.exec('BEGIN');
  await db.query('SELECT public.bm_registrar_operacion($1,$2,$3)',[id,actions,'Prueba de proveedor']);
  // Simulate PostgREST completing the transaction after the RPC has returned.
  await db.exec('SET CONSTRAINTS bm.z_integridad IMMEDIATE; COMMIT;');
  assert.equal((await db.query('SELECT count(*)::int n FROM bm.proveedor')).rows[0].n,1);
  const locations=[
   {tabla:'costurera',accion:'insertar',ref:'taller',datos:{nombre_completo:'Costurera de prueba'}},
   {tabla:'ubicacion_tela',accion:'insertar',datos:{nombre:'Taller de prueba',tipo:'costurera',costurera_id:{$ref:'taller'}}},
   {tabla:'ubicacion_tela',accion:'insertar',datos:{nombre:'Bodega de prueba',tipo:'bodega'}}
  ];
  await db.exec('BEGIN');
  await db.query('SELECT public.bm_registrar_operacion($1,$2,$3)',[crypto.randomUUID(),JSON.stringify(locations),'Registrar ubicaciones']);
  await db.exec('SET CONSTRAINTS bm.z_integridad IMMEDIATE; COMMIT;');
  const stored=(await db.query('SELECT tipo,costurera_id FROM bm.ubicacion_tela ORDER BY tipo')).rows;
  assert.equal(stored.length,2);
  assert.equal(stored[0].costurera_id,null);
  assert.ok(stored[1].costurera_id);
  await db.exec('BEGIN');
  await db.query('SELECT public.bm_registrar_operacion($1,$2,$3)',[id,actions,'Prueba de proveedor']);
  await db.exec('COMMIT');
  assert.equal((await db.query('SELECT count(*)::int n FROM bm.proveedor')).rows[0].n,1);
 }finally{await db.close();}
});
