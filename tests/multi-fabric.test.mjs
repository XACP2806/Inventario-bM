import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {database} from '../scripts/schema.mjs';
import {workflowActions} from '../src/workflows.mjs';

test('una factura admite varias telas sin duplicar compras ni pagos y detecta revisiones desactualizadas',async()=>{
 const db=await database();
 try{
  await db.exec(fs.readFileSync('tests.sql','utf8').replace(/ROLLBACK;\s*$/,'COMMIT;'));
  await db.exec("SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','83d20ad7-300c-4cd0-9ea7-ff82366f77c2',false);");
  const rows=async t=>(await db.query(`SELECT * FROM bm.${t}`)).rows;
  const save=async(actions,id=crypto.randomUUID())=>{
   await db.exec('BEGIN');
   try{const result=(await db.query('SELECT public.bm_registrar_operacion($1,$2,$3) result',[id,JSON.stringify(actions),'Varias telas en una factura'])).rows[0].result;
    await db.exec('COMMIT');return result;
   }catch(e){await db.exec('ROLLBACK');throw e;}
  };
  const [provider,blue,red,green]=await save([
   {accion:'insertar',tabla:'proveedor',datos:{nombre_legal:'Proveedor varias telas'}},
   ...['Azul prueba','Roja prueba','Verde prueba'].map(nombre=>({accion:'insertar',tabla:'tela',datos:{nombre}}))
  ]);
  const location=(await rows('ubicacion_tela')).find(r=>r.tipo==='bodega');
  const values={fecha:'2024-06-02',proveedor:provider.proveedor_id,tela:blue.tela_id,ubicacion:location.ubicacion_id,metros:4,precio:5,iva:3,porcentaje:15,costo:5.75,comprobante:'factura',numero:'VARIAS-001',pagada:'regalo_tercero',pagador:'Persona de prueba'};
  const initial=await save(workflowActions('compra',values));
  const purchase=initial[0];
  const context=async()=>({compra:purchase,cuenta:(await rows('cuenta_pagar')).find(r=>r.compra_id===purchase.compra_id),detalles:(await rows('detalle_compra')).filter(r=>r.compra_id===purchase.compra_id)});
  const more={...values,modo_compra:'existente',compra_existente:purchase.compra_id,tela:red.tela_id,metros:2,iva:1.5};
  const reviewed=await context();
  const actions=workflowActions('compra',more,reviewed);
  assert.equal(actions.some(a=>a.tabla==='compra'),false);
  assert.equal(actions.find(a=>a.tabla==='cuenta_pagar').datos.monto_original,34.5);
  assert.equal(actions.find(a=>a.tabla==='abono_cuenta_pagar').datos.monto,11.5);
  const stale=workflowActions('compra',{...more,tela:green.tela_id,pagada:'si'},reviewed);
  const id=crypto.randomUUID(),result=await save(actions,id);
  assert.deepEqual(await save(actions,id),result);
  assert.equal((await rows('compra')).length,1);
  assert.equal((await context()).detalles.length,2);
  assert.equal((await rows('abono_cuenta_pagar')).length,2);
  assert.equal((await rows('lote_tela')).filter(r=>result.some(x=>x.lote_tela_id===r.lote_tela_id)).length,1);
  const beforeLots=(await rows('lote_tela')).length;
  await assert.rejects(save(stale),/compra cambió/);
  assert.equal((await context()).detalles.length,2);
  assert.equal((await rows('lote_tela')).length,beforeLots);
  // Re-reviewing uses the latest total; paid and pending lines stay distinct.
  await save(workflowActions('compra',{...more,tela:green.tela_id,pagada:'si'},await context()));
  await save(workflowActions('compra',{...more,metros:1,iva:.75,pagada:'no'},await context()));
  assert.equal(Number((await context()).cuenta.monto_original),51.75);
  const balance=(await rows('v_saldo_cuenta_pagar')).find(r=>r.cuenta_pagar_id===reviewed.cuenta.cuenta_pagar_id);
  assert.equal(Number(balance.saldo_pendiente),5.75);
  const panel=(await db.query("SELECT public.bm_panel('2024-06-02','2024-06-02') result")).rows[0].result.serie[0];
  assert.equal(Number(panel.regalos),34.5);
  assert.equal(Number(panel.pagos),11.5);
  // Duplicate new invoices still fail instead of silently merging unrelated data.
  await assert.rejects(save(workflowActions('compra',values)),/uq_compra_factura_proveedor/);
  const current=await context();
  assert.throws(()=>workflowActions('compra',more,{...current,cuenta:{...current.cuenta,estado:'anulada'}}),/vigente/);
  assert.throws(()=>workflowActions('compra',more,{...current,cuenta:{...current.cuenta,monto_original:1000}}),/no coincide/);
  const invalid=workflowActions('compra',more,current);invalid.find(a=>a.esperado).esperado=null;
  await assert.rejects(save(invalid),/esperados invalidos/);
  assert.equal((await context()).detalles.length,4);
  await db.exec("SELECT set_config('request.jwt.claim.sub','9a70e587-27bc-424b-ae80-c80a9995d249',false)");
  await assert.rejects(save(workflowActions('compra',more,current)),/no autorizado/);
 }finally{await db.close();}
});
