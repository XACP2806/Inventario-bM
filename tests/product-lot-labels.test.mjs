import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {database} from '../scripts/schema.mjs';

test('lotes muestran camisa, talla y número sin alterar datos y permiten buscar',async()=>{
 const db=await database();
 try{
  await db.exec(fs.readFileSync('tests.sql','utf8').replace(/ROLLBACK;\s*$/,'COMMIT;'));
  const expected=(await db.query('SELECT to_jsonb(l) data,a.nombre,ta.nombre talla FROM bm.lote_producto l JOIN bm.variante_articulo v USING(variante_id) JOIN bm.articulo a USING(articulo_id) JOIN bm.talla ta USING(talla_id)')).rows;
  assert(expected.length>0);
  await db.exec("SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','83d20ad7-300c-4cd0-9ea7-ff82366f77c2',false);");
  const list=async(search='',offset=0,filters={})=>(await db.query("SELECT public.bm_datos('lote_producto',1,$1,$2,$3) result",[offset,search,JSON.stringify(filters)])).rows[0].result;
  for(const row of expected){
   const filters={lote_producto_id:String(row.data.lote_producto_id)};
   for(const search of [row.nombre,'Talla '+row.talla,'Lote #'+row.data.lote_producto_id]){
    const result=await list(search,0,filters);
    assert.equal(result.total,1);
    const actual=result.rows[0];
    assert.equal(actual._etiqueta,`${row.nombre} · Talla ${row.talla} · Lote #${row.data.lote_producto_id}`);
    for(const [key,value] of Object.entries(row.data))assert.deepEqual(actual[key],value);
   }
  }
  assert.equal((await list('camisa-inexistente-xyz')).total,0);
  assert.equal((await list()).total,expected.length);
  for(let i=0;i<expected.length;i++)assert.equal((await list('',i)).rows.length,1);
  assert.equal((await list('',expected.length)).rows.length,0);
  await assert.rejects(list('',0,{campo_invalido:'1'}),/Filtro inválido/);
  await db.exec("SELECT set_config('request.jwt.claim.sub','9a70e587-27bc-424b-ae80-c80a9995d249',false)");
  await assert.rejects(list(),/no tiene acceso/);
 }finally{await db.close();}
});
