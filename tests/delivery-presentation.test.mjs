import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {database} from '../scripts/schema.mjs';
import {workflowActions} from '../src/workflows.mjs';
import {tableColumns,exportTableRows} from '../src/table-presentation.mjs';

test('recepción muestra cliente y cantidades confirmadas sin alterar despachos',async()=>{
 const db=await database();
 try{
  await db.exec(fs.readFileSync('tests.sql','utf8').replace(/ROLLBACK;\s*$/,'COMMIT;'));
  const before=(await db.query('SELECT to_jsonb(e) data,c.nombre_completo FROM bm.envio e JOIN bm.pedido p USING(pedido_id) JOIN bm.cliente c USING(cliente_id)')).rows;
  assert(before.length>0);
  await db.exec("SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','83d20ad7-300c-4cd0-9ea7-ff82366f77c2',false)");
  for(const {data,nombre_completo} of before){
   const result=(await db.query("SELECT public.bm_datos('envio',200,0,$1,$2) result",[nombre_completo,JSON.stringify({envio_id:String(data.envio_id)})])).rows[0].result;
   assert.equal(result.total,1);
   const row=result.rows[0];
   assert.equal(row._cliente,nombre_completo);
   assert.equal(row._pendientes,Math.max(row._despachadas-row._entregadas,0));
   if(row._despachadas>0&&row._entregadas>=row._despachadas)assert.equal(row._estado_entrega,'entregado');
   for(const [k,v] of Object.entries(data))assert.deepEqual(row[k],v);
   assert.equal(exportTableRows('envio',[row])[0].Cliente,nombre_completo);
  }
  const details=(await db.query("SELECT public.bm_datos('detalle_envio',200,0,'','{}') result")).rows[0].result.rows;
  for(const row of details){
   assert(row._etiqueta.includes(row._cliente+' · Pedido #'+row._pedido));
   assert(row._etiqueta.includes('Pendientes: '+row._pendientes));
   assert.equal(row._pendientes,Math.max(row.cantidad-row._entregadas,0));
  }
  assert(tableColumns('envio',[]).some(c=>c.name==='_cliente'));
  await db.exec("SELECT set_config('request.jwt.claim.sub','9a70e587-27bc-424b-ae80-c80a9995d249',false)");
  await assert.rejects(db.query("SELECT public.bm_datos('envio',20,0,'','{}')"),/no tiene acceso/);
 }finally{await db.close();}
});

test('confirmar recepción rechaza duplicados, excesos y fechas anteriores',()=>{
 const v={fecha:'2026-11-15',cantidad:1};
 const d={envio_id:3,detalle_envio_id:4,_pendientes:0,_fecha_envio:'2026-11-12T17:00:00Z'};
 assert.throws(()=>workflowActions('entrega',v,{detalle:d}),/0 unidades pendientes/);
 assert.throws(()=>workflowActions('entrega',{...v,cantidad:3},{detalle:{...d,_pendientes:2}}),/2 unidades pendientes/);
 assert.throws(()=>workflowActions('entrega',{...v,fecha:'2026-11-11'},{detalle:{...d,_pendientes:2}}),/anterior al despacho/);
 const actions=workflowActions('entrega',v,{detalle:{...d,_pendientes:2}});
 assert.equal(actions[1].datos.cantidad_entregada,1);
 assert(!actions.some(a=>a.tabla==='movimiento_producto'));
});
