import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {database} from '../scripts/schema.mjs';
import {tableColumns,exportTableRows} from '../src/table-presentation.mjs';
test('saldos muestran y buscan clientes por nombre conservando importes, filtros y acceso privado',async()=>{
 const db=await database();try{
 await db.exec(fs.readFileSync('tests.sql','utf8').replace(/ROLLBACK;\s*$/,'COMMIT;'));
 await db.exec("SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','83d20ad7-300c-4cd0-9ea7-ff82366f77c2',false);");
 const original=(await db.query('SELECT pedido_id,cliente_id,total_neto_pedido,dinero_recibido,dinero_reembolsado FROM bm.v_estado_cuenta_pedido ORDER BY pedido_id')).rows;
 const result=(await db.query('SELECT * FROM bm.v_saldo_pedido ORDER BY pedido_id')).rows;
 assert.equal(result.length,original.length);
 for(let i=0;i<result.length;i++){
  const r=result[i];for(const key of Object.keys(original[i]))assert.equal(r[key],original[i][key]);
  const client=(await db.query('SELECT nombre_completo FROM bm.cliente WHERE cliente_id=$1',[r.cliente_id])).rows[0];assert.equal(r.cliente_nombre,client.nombre_completo);
 }
 const sample=result[0];
 const search=async offset=>(await db.query('SELECT public.bm_datos($1,1,$2,$3,$4) x',['v_saldo_pedido',offset,sample.cliente_nombre,JSON.stringify({pedido_id:String(sample.pedido_id)})])).rows[0].x;
 assert.equal((await search(0)).total,1);assert.equal((await search(0)).rows[0].pedido_id,sample.pedido_id);assert.equal((await search(1)).rows.length,0);
 assert.equal(tableColumns('v_saldo_pedido',[])[1].name,'cliente_nombre');
 assert.equal(exportTableRows('v_saldo_pedido',[sample])[0].Cliente,sample.cliente_nombre);
 await db.exec("SELECT set_config('request.jwt.claim.sub','9a70e587-27bc-424b-ae80-c80a9995d249',false);");
 await assert.rejects(db.query("SELECT public.bm_datos('v_saldo_pedido')"),/no tiene acceso/);
 assert.equal((await db.query('SELECT * FROM bm.v_saldo_pedido')).rows.length,0);
 }finally{await db.close();}
});
