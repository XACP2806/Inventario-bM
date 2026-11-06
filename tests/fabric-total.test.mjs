import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {database} from '../scripts/schema.mjs';
import {tableColumns,exportTableRows} from '../src/table-presentation.mjs';

test('tela total suma lotes y ubicaciones sin duplicar traslados, permite búsqueda y mantiene acceso privado',async()=>{
 const db=await database();try{
  await db.exec(fs.readFileSync('tests.sql','utf8').replace(/ROLLBACK;\s*$/,'COMMIT;'));
  await db.exec("SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','83d20ad7-300c-4cd0-9ea7-ff82366f77c2',false);");
  const fabric=(await db.query("SELECT tela_id FROM bm.tela WHERE nombre='TEST Lino'")).rows[0].tela_id;
  const locations=(await db.query('SELECT ubicacion_id FROM bm.ubicacion_tela ORDER BY ubicacion_id')).rows;
  const [a,b]=locations.map(x=>x.ubicacion_id);
  const ins=(tabla,datos,ref)=>({accion:'insertar',tabla,datos,...(ref?{ref}:{})});
  const ref=x=>({'$ref':x});
  const actions=[
   ins('lote_tela',{tela_id:fabric,metros_comprados:10.5,costo_metro:5,fecha_ingreso:'2024-03-01T17:00:00Z'},'l1'),
   ins('movimiento_tela',{lote_tela_id:ref('l1'),tipo:'compra',destino_ubicacion_id:a,metros:10.5,fecha:'2024-03-01T17:00:00Z'}),
   ins('lote_tela',{tela_id:fabric,metros_comprados:4.25,costo_metro:6,fecha_ingreso:'2024-03-01T17:00:00Z'},'l2'),
   ins('movimiento_tela',{lote_tela_id:ref('l2'),tipo:'compra',destino_ubicacion_id:b,metros:4.25,fecha:'2024-03-01T17:00:00Z'}),
   ins('movimiento_tela',{lote_tela_id:ref('l1'),tipo:'transferencia',origen_ubicacion_id:a,destino_ubicacion_id:b,metros:3,fecha:'2024-03-02T17:00:00Z'}),
   ins('movimiento_tela',{lote_tela_id:ref('l1'),tipo:'merma',origen_ubicacion_id:b,metros:1.25,fecha:'2024-03-03T17:00:00Z'}),
   ins('tela',{nombre:'TEST Agotada'},'t2'),
   ins('lote_tela',{tela_id:ref('t2'),metros_comprados:8,costo_metro:2,fecha_ingreso:'2024-03-01T17:00:00Z'},'l3'),
   ins('movimiento_tela',{lote_tela_id:ref('l3'),tipo:'compra',destino_ubicacion_id:a,metros:8,fecha:'2024-03-01T17:00:00Z'}),
   ins('movimiento_tela',{lote_tela_id:ref('l3'),tipo:'merma',origen_ubicacion_id:a,metros:8,fecha:'2024-03-02T17:00:00Z'})
  ];
  await db.query('SELECT public.bm_registrar_operacion($1,$2,$3)',[crypto.randomUUID(),JSON.stringify(actions),'Prueba de totales de tela']);
  const fetch=async(search='',offset=0,limit=200)=>(await db.query("SELECT public.bm_datos('v_tela_disponible',$1,$2,$3) x",[limit,offset,search])).rows[0].x;
  const data=await fetch();assert.equal(data.total,2);
  const lino=data.rows.find(r=>r.tela_nombre==='TEST Lino');assert.equal(Number(lino.metros_disponibles),13.5);
  assert.equal(Number(data.rows.find(r=>r.tela_nombre==='TEST Agotada').metros_disponibles),0);
  assert.equal((await fetch('Lino',0,1)).total,1);assert.equal((await fetch('Lino',0,1)).rows[0].tela_id,fabric);
  const p1=await fetch('',0,1),p2=await fetch('',1,1);assert.equal(p1.total,2);assert.notEqual(p1.rows[0].tela_id,p2.rows[0].tela_id);
  assert.equal((await fetch('',2,1)).rows.length,0);
  assert.deepEqual(tableColumns('v_tela_disponible',[]).map(c=>c.label),['Tela','Metros disponibles']);
  assert.deepEqual(exportTableRows('v_tela_disponible',[lino]),[{Tela:'TEST Lino','Metros disponibles':lino.metros_disponibles}]);
  const schema=JSON.parse(fs.readFileSync('src/schema.json','utf8'));assert.equal(schema.v_tela_disponible.view,true);
  const before=await db.query('SELECT count(*) n FROM bm.movimiento_tela');await fetch();assert.deepEqual(await db.query('SELECT count(*) n FROM bm.movimiento_tela'),before);
  await db.exec("SELECT set_config('request.jwt.claim.sub','9a70e587-27bc-424b-ae80-c80a9995d249',false);");
  assert.equal((await db.query('SELECT * FROM bm.v_tela_disponible')).rows.length,0);
  await assert.rejects(db.query("SELECT public.bm_datos('v_tela_disponible')"),/no tiene acceso/);
  await db.exec('RESET ROLE; SET ROLE anon;');
  await assert.rejects(db.query('SELECT * FROM bm.v_tela_disponible'),/permission denied/);
 }finally{await db.close();}
});
