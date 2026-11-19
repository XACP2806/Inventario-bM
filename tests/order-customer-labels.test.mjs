import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {database} from '../scripts/schema.mjs';
test('pedidos identifican cliente y prendas sin cambiar los datos',async()=>{
 const db=await database();try{
 await db.exec(fs.readFileSync('tests.sql','utf8').replace(/ROLLBACK;\s*$/,'COMMIT;'));
 const before=(await db.query('SELECT to_jsonb(p) data,c.nombre_completo FROM bm.pedido p JOIN bm.cliente c USING(cliente_id)')).rows;
 await db.exec("SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','83d20ad7-300c-4cd0-9ea7-ff82366f77c2',false)");
 for(const {data,nombre_completo} of before){
 const r=(await db.query("SELECT public.bm_datos('pedido',200,0,$1,$2) data",[nombre_completo,JSON.stringify({pedido_id:String(data.pedido_id)})])).rows[0].data;
 assert.equal(r.total,1);assert(r.rows[0]._etiqueta.includes(nombre_completo+' · Pedido #'+data.pedido_id));
 assert(/×|Sin prendas registradas/.test(r.rows[0]._etiqueta));
 for(const [k,v] of Object.entries(data))assert.deepEqual(r.rows[0][k],v);
 }
 }finally{await db.close();}
});
