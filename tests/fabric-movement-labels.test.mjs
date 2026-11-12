import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {database} from '../scripts/schema.mjs';
import {tableColumns,exportTableRows} from '../src/table-presentation.mjs';

test('movimientos muestran y buscan tela conservando movimientos y permisos',async()=>{
 const db=await database();
 try{
  await db.exec(fs.readFileSync('tests.sql','utf8').replace(/ROLLBACK;\s*$/,'COMMIT;'));
  const expected=(await db.query('SELECT to_jsonb(m) data,t.nombre FROM bm.movimiento_tela m JOIN bm.lote_tela l USING(lote_tela_id) JOIN bm.tela t USING(tela_id)')).rows;
  assert(expected.length>0);
  await db.exec("SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','83d20ad7-300c-4cd0-9ea7-ff82366f77c2',false);");
  const list=async(search='',filters={})=>(await db.query("SELECT public.bm_datos('movimiento_tela',200,0,$1,$2) result",[search,JSON.stringify(filters)])).rows[0].result;
  for(const row of expected){
   const result=await list(row.nombre,{movimiento_tela_id:String(row.data.movimiento_tela_id)});
   assert.equal(result.total,1);
   assert.equal(result.rows[0]._tela,row.nombre);
   for(const [key,value] of Object.entries(row.data))assert.deepEqual(result.rows[0][key],value);
   assert.equal(exportTableRows('movimiento_tela',result.rows)[0].Tela,row.nombre);
  }
  const cols=['movimiento_tela_id','lote_tela_id','origen_ubicacion_id','destino_ubicacion_id','detalle_encargo_id','tipo','metros','notas'].map(name=>({name}));
  assert(tableColumns('movimiento_tela',cols).some(c=>c.name==='_tela'&&c.label==='Tela'));
  assert(tableColumns('movimiento_tela',cols).some(c=>c.name==='metros'));
  assert.equal((await list()).total,expected.length);
  assert.equal((await list('tela-inexistente-xyz')).total,0);
  await assert.rejects(list('',{campo_invalido:'1'}),/Filtro inválido/);
  await db.exec("SELECT set_config('request.jwt.claim.sub','9a70e587-27bc-424b-ae80-c80a9995d249',false)");
  await assert.rejects(list(),/no tiene acceso/);
 }finally{await db.close();}
});
