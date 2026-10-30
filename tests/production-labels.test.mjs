import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {database} from '../scripts/schema.mjs';
import {workflowActions} from '../src/workflows.mjs';
import {tableColumns,exportTableRows} from '../src/table-presentation.mjs';

test('selectores de producción incluyen nombres buscables y conservan IDs y acceso privado',async()=>{
 const db=await database();
 try{
  await db.exec(fs.readFileSync('tests.sql','utf8').replace(/ROLLBACK;\s*$/,'COMMIT;'));
  await db.exec("SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','83d20ad7-300c-4cd0-9ea7-ff82366f77c2',false);");
  const list=async(table,search='',offset=0,filters={})=>(await db.query('SELECT public.bm_datos($1,1,$2,$3,$4) result',[table,offset,search,JSON.stringify(filters)])).rows[0].result;
  const lot=(await list('lote_tela')).rows[0];
  const fabric=(await db.query('SELECT nombre FROM bm.tela WHERE tela_id=$1',[lot.tela_id])).rows[0];
  assert.equal(lot._etiqueta,`${fabric.nombre} · Lote ${lot.lote_tela_id}`);
  const selected=await list('lote_tela',fabric.nombre,0,{lote_tela_id:String(lot.lote_tela_id)});
  assert.equal(selected.total,1);assert.equal(selected.rows[0].lote_tela_id,lot.lote_tela_id);
  assert.equal((await list('lote_tela',fabric.nombre,1,{lote_tela_id:String(lot.lote_tela_id)})).rows.length,0);
  assert.equal((await list('lote_tela','inexistente-xyz')).total,0);
  const detail=(await list('detalle_encargo_costura')).rows[0];
  const garment=(await db.query('SELECT a.nombre producto,c.nombre color,t.nombre talla FROM bm.variante_articulo v JOIN bm.articulo a USING(articulo_id) JOIN bm.color c USING(color_id) JOIN bm.talla t USING(talla_id) WHERE variante_id=$1',[detail.variante_id])).rows[0];
  for(const part of [garment.producto,garment.color,'Talla '+garment.talla,'Encargo '+detail.encargo_id,'Prenda '+detail.detalle_encargo_id])assert(detail._etiqueta.includes(part));
  const found=await list('detalle_encargo_costura',garment.producto,0,{detalle_encargo_id:String(detail.detalle_encargo_id)});
  assert.equal(found.total,1);assert.equal(found.rows[0].variante_id,detail.variante_id);
  assert.equal((await list('detalle_encargo_costura','Talla '+garment.talla)).total>0,true);
  const save=async actions=>(await db.query('SELECT public.bm_registrar_operacion($1,$2,$3) result',[crypto.randomUUID(),JSON.stringify(actions),'Prueba de avance de recepción'])).rows[0].result;
  const costurera=(await db.query('SELECT costurera_id FROM bm.costurera LIMIT 1')).rows[0];
  const order=await save(workflowActions('encargo',{fecha:'2024-06-02',costurera:costurera.costurera_id,variante:detail.variante_id,cantidad:4,tarifa:5}));
  const progress=async()=>(await list('detalle_encargo_costura','',0,{detalle_encargo_id:String(order[1].detalle_encargo_id)})).rows[0];
  let row=await progress();assert.equal(row._recepcion,'Pendiente');assert.equal(row._pendientes_recibir,4);
  await save(workflowActions('recepcion',{fecha:'2024-06-02',aceptadas:2,rechazadas:0,tela:7,insumos:0},{detalle:order[1]}));
  row=await progress();assert.equal(row._recepcion,'Parcial');assert.equal(row._aceptadas,2);assert.equal(row._pendientes_recibir,2);
  await save(workflowActions('recepcion',{fecha:'2024-06-03',aceptadas:1,rechazadas:1,tela:7,insumos:0},{detalle:order[1]}));
  row=await progress();assert.equal(row._recepcion,'Recibido con rechazos');assert.equal(row._recibidas,4);assert.equal(row._aceptadas,3);assert.equal(row._rechazadas,1);assert.equal(row._pendientes_recibir,0);
  // The progress is derived: it does not silently close the encargo or finalize costs.
  assert.equal(row._estado_encargo,'en_proceso');
  assert.equal(found.rows[0]._recepcion,'Recibido');
  const csv=exportTableRows('detalle_encargo_costura',[row])[0];assert.equal(csv['Prenda, color y talla'],row._prenda);assert.equal(csv['Rechazadas'],1);assert.equal(csv['Encargo'],'Encargo '+row.encargo_id);
  assert(!tableColumns('detalle_encargo_costura',[]).some(c=>c.name==='variante_id'));
  assert.equal((await list('tela')).rows[0]._etiqueta,undefined);
  await assert.rejects(list('usuario_bm'),/Consulta no permitida/);
  await assert.rejects(list('lote_tela','',0,{columna_inexistente:'1'}),/Filtro inválido/);
  await db.exec("SELECT set_config('request.jwt.claim.sub','9a70e587-27bc-424b-ae80-c80a9995d249',false)");
  await assert.rejects(list('lote_tela',fabric.nombre),/no tiene acceso/);
  await assert.rejects(list('detalle_encargo_costura'),/no tiene acceso/);
 }finally{await db.close();}
});
