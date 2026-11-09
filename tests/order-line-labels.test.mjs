import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {database} from '../scripts/schema.mjs';

test('prendas del pedido muestran cliente, pedido y SKU y permiten buscar sin cambiar IDs',async()=>{
 const db=await database();
 try{
  await db.exec(fs.readFileSync('tests.sql','utf8').replace(/ROLLBACK;\s*$/,'COMMIT;'));
  const expected=(await db.query('SELECT to_jsonb(d) data,c.nombre_completo FROM bm.detalle_pedido d JOIN bm.pedido p USING(pedido_id) JOIN bm.cliente c USING(cliente_id) ORDER BY d.detalle_pedido_id')).rows.map(r=>({...r.data,nombre_completo:r.nombre_completo}));
  assert(expected.length>0);
  await db.exec("SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','83d20ad7-300c-4cd0-9ea7-ff82366f77c2',false);");
  const list=async(search='',offset=0,filters={})=>(await db.query("SELECT public.bm_datos('detalle_pedido',1,$1,$2,$3) result",[offset,search,JSON.stringify(filters)])).rows[0].result;
  for(const row of expected){
   const result=await list(row.nombre_completo,0,{detalle_pedido_id:String(row.detalle_pedido_id)});
   assert.equal(result.total,1);
   const actual=result.rows[0];
   assert(actual._etiqueta.startsWith(row.nombre_completo+' · Pedido #'+row.pedido_id));
   assert(actual._etiqueta.includes('Prenda #'+row.detalle_pedido_id));
   if(row.sku_vendido)assert(actual._etiqueta.includes(row.sku_vendido));
   for(const [key,value] of Object.entries(row))if(key!=='nombre_completo')assert.deepEqual(actual[key],value);
  }
  assert.equal((await list('cliente-que-no-existe-xyz')).total,0);
  assert.equal((await list('',0)).rows.length,1);
  await assert.rejects(list('',0,{campo_invalido:'1'}),/Filtro inválido/);
  await db.exec("SELECT set_config('request.jwt.claim.sub','9a70e587-27bc-424b-ae80-c80a9995d249',false)");
  await assert.rejects(list(),/no tiene acceso/);
 }finally{await db.close();}
});
