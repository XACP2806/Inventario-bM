import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {database} from '../scripts/schema.mjs';
import {saleActions} from '../src/workflows.mjs';
import {salesCustomerViews,tableColumns,exportTableRows} from '../src/table-presentation.mjs';
const schema=JSON.parse(fs.readFileSync('src/schema.json','utf8'));
test('los seis resúmenes de ventas muestran, buscan y exportan nombres sin alterar filas ni acceso',async()=>{
 const db=await database();try{
 await db.exec(fs.readFileSync('tests.sql','utf8').replace(/ROLLBACK;\s*$/,'COMMIT;'));
 await db.exec("SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','83d20ad7-300c-4cd0-9ea7-ff82366f77c2',false);");
 const rows=async t=>(await db.query('SELECT to_jsonb(x) r FROM bm.'+t+' x')).rows.map(x=>x.r);
 const [variants,arts,clients,lots]=await Promise.all(['variante_articulo','articulo','cliente','lote_producto'].map(rows));
 for(const modalidad of ['pedido','entregar']){
  const a=saleActions({fecha:'2024-03-01',cliente:clients[0].cliente_id,tratamiento:'no_objeto',motivo:'Prueba de nombres',modalidad},[{variante:variants[0].variante_id,precio:44,cantidad:1,lote:lots[0].lote_producto_id}],{variantes:variants,articulos:arts,tarifas:[]});
  await db.query('SELECT public.bm_registrar_operacion($1,$2,$3)',[crypto.randomUUID(),JSON.stringify(a),'Prueba de nombres en resumen']);
 }
 for(const view of salesCustomerViews){
  const original=await rows(view);
  const fetch=async(search='',offset=0,limit=200,filters={})=>(await db.query('SELECT public.bm_datos($1,$2,$3,$4,$5) x',[view,limit,offset,search,JSON.stringify(filters)])).rows[0].x;
  const data=await fetch();assert(data.total>0,view);assert.equal(data.total,original.length,view);
  for(const r of data.rows){
   const expected=(await db.query('SELECT c.nombre_completo FROM bm.pedido p JOIN bm.cliente c USING(cliente_id) WHERE p.pedido_id=$1',[r.pedido_id])).rows[0].nombre_completo;
   assert.equal(r._cliente,expected,view);
   const {_cliente,...unchanged}=r;assert(original.some(o=>JSON.stringify(o)===JSON.stringify(unchanged)),view+' conserva todas las cifras');
   const cols=tableColumns(view,schema[view].columns);const nameCol=cols.find(c=>c.label==='Cliente');assert(nameCol,view);assert.notEqual(nameCol.name,'cliente_id');
   assert.equal(exportTableRows(view,[r])[0].Cliente,expected,view);
  }
  const sample=data.rows[0];const filter={pedido_id:String(sample.pedido_id)};
  const found=await fetch(sample._cliente,0,1,filter);assert(found.total>=1,view);assert.equal(found.rows[0]._cliente,sample._cliente);
  assert.equal((await fetch(sample._cliente,found.total,1,filter)).rows.length,0,view);
  assert.equal((await fetch('cliente-que-no-existe')).total,0,view);
 }
 await db.exec("SELECT set_config('request.jwt.claim.sub','9a70e587-27bc-424b-ae80-c80a9995d249',false);");
 for(const view of salesCustomerViews)await assert.rejects(db.query('SELECT public.bm_datos($1)',[view]),/no tiene acceso/);
 await db.exec('RESET ROLE; SET ROLE anon;');
 await assert.rejects(db.query("SELECT public.bm_datos('v_pedidos_por_entregar')"),/permission denied/);
 }finally{await db.close();}
});
