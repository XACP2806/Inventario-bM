import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {database} from '../scripts/schema.mjs';
import {workflowActions} from '../src/workflows.mjs';
import {paymentFunds,paymentSummary} from '../src/record-rules.mjs';

test('regalos exigen pagador y no se confunden con pagos pendientes o caja',()=>{
 assert.throws(()=>paymentFunds('regalo_tercero','  '),/quién hizo el regalo/);
 assert.throws(()=>paymentFunds('prestamo','Persona'),/Selecciona quién/);
 assert.deepEqual(paymentFunds('regalo_tercero',' Ana '),{origen_fondos:'regalo_tercero',pagador_nombre:'Ana'});
 assert.deepEqual(paymentFunds('bm','Nombre de una selección anterior'),{origen_fondos:'bm',pagador_nombre:null});
 const purchase={fecha:'2024-06-01',metros:4,precio:5,iva:3,porcentaje:15,costo:5.75,comprobante:'factura',pagada:'no'};
 assert.equal(workflowActions('compra',purchase).some(a=>a.tabla==='abono_cuenta_pagar'),false);
 const gift=workflowActions('compra',{...purchase,pagada:'regalo_tercero',pagador:'Persona'});
 assert.deepEqual(paymentSummary(gift),{pagos:0,regalos:23});
 assert.deepEqual(paymentSummary(workflowActions('compra',{...purchase,pagada:'si'})),{pagos:23,regalos:0});
});

test('regalos liquidan obligaciones, conservan costos y quedan fuera de caja',async()=>{
 const db=await database();
 try{
  await db.exec(fs.readFileSync('tests.sql','utf8').replace(/ROLLBACK;\s*$/,'COMMIT;'));
  await db.exec("SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','83d20ad7-300c-4cd0-9ea7-ff82366f77c2',false);");
  const rows=async(table)=>(await db.query(`SELECT * FROM bm.${table}`)).rows;
  const save=async(actions,id=crypto.randomUUID())=>{
   await db.exec('BEGIN');
   try{
    const r=(await db.query('SELECT public.bm_registrar_operacion($1,$2,$3) result',[id,JSON.stringify(actions),'Prueba de regalos'])).rows[0].result;
    await db.exec('SET CONSTRAINTS bm.z_integridad IMMEDIATE; COMMIT;');return r;
   }catch(e){await db.exec('ROLLBACK');throw e;}
  };
  const [provider]=await save([{tabla:'proveedor',accion:'insertar',datos:{nombre_legal:'Proveedor de prueba de regalos'}}]);
  const tela=(await rows('tela'))[0],ubicacion=(await rows('ubicacion_tela')).find(r=>r.tipo==='bodega');
  const compra={fecha:'2024-06-01',proveedor:provider.proveedor_id,tela:tela.tela_id,ubicacion:ubicacion.ubicacion_id,metros:4,precio:5,iva:3,porcentaje:15,costo:5.75,comprobante:'factura',pagada:'regalo_tercero',pagador:'Persona de prueba',metodo:'transferencia'};
  const actions=workflowActions('compra',compra),id=crypto.randomUUID();
  const purchased=await save(actions,id);await save(actions,id);
  const account=purchased.find(r=>r.cuenta_pagar_id&&r.monto_original);
  assert.equal(Number((await rows('v_saldo_cuenta_pagar')).find(r=>r.cuenta_pagar_id===account.cuenta_pagar_id).saldo_pendiente),0);
  const lot=purchased.find(r=>r.lote_tela_id&&r.metros_comprados);
  assert.equal(Number(lot.costo_metro),5.75);
  assert.equal(Number(lot.metros_comprados),4);
  const variant=(await rows('variante_articulo'))[0],costurera=(await rows('costurera'))[0];
  const enc=await save(workflowActions('encargo',{fecha:'2024-06-01',costurera:costurera.costurera_id,variante:variant.variante_id,cantidad:3,tarifa:5}));
  const rec=await save(workflowActions('recepcion',{fecha:'2024-06-01',aceptadas:3,rechazadas:0,tela:7,insumos:1},{detalle:enc[1]}));
  const shirt=rec.find(r=>r.lote_producto_id&&r.costo_total_unitario);
  assert.equal(Number(shirt.costo_total_unitario),13);
  const common={fecha:'2024-06-01',encargo:enc[0].encargo_id,monto:10,origen_fondos:'regalo_tercero',pagador:'Persona de prueba',metodo:'transferencia'};
  const [gift]=await save(workflowActions('pago_costura',common));
  await save(workflowActions('pago_costura',{...common,monto:5,origen_fondos:'bm'}));
  assert.equal(Number((await rows('v_saldo_costurera_encargo')).find(r=>r.encargo_id===enc[0].encargo_id).saldo_por_pagar),0);
  const panel=async()=>(await db.query("SELECT public.bm_panel('2024-06-01','2024-06-01') result")).rows[0].result.serie[0];
  assert.equal(Number((await panel()).pagos),5);
  assert.equal(Number((await panel()).cobros),0);
  assert.equal(Number((await panel()).regalos),33);
  assert.equal(Number((await panel()).resultado),0);
  assert.equal((await rows('v_pagos_regalados')).length,2);
  assert.equal((await db.query("SELECT public.bm_datos('v_pagos_regalados') result")).rows[0].result.total,2);
  assert.equal(Number((await rows('lote_producto')).find(r=>r.lote_producto_id===shirt.lote_producto_id).costo_total_unitario),13);
  // Standard payments retain their previous effect on cash and do not become gifts.
  await save(workflowActions('compra',{...compra,pagada:'si'}));
  assert.equal(Number((await panel()).pagos),28);
  assert.equal(Number((await panel()).regalos),33);
  // API clients cannot bypass the donor requirement or rewrite confirmed payments.
  const bad=workflowActions('compra',compra);bad.find(a=>a.tabla==='abono_cuenta_pagar').datos.pagador_nombre=' ';
  const before=(await rows('compra')).length;
  await assert.rejects(save(bad),/abono_pagador_coherente/);
  assert.equal((await rows('compra')).length,before);
  const invalid=workflowActions('pago_costura',common);invalid[0].datos.pagador_nombre=null;
  await assert.rejects(save(invalid),/costura_pagador_coherente/);
  await assert.rejects(save([{tabla:'pago_costurera',accion:'actualizar',id:gift.pago_costurera_id,datos:{origen_fondos:'bm',pagador_nombre:null}}]),/solo se permite/);
  // Annulments remove the gift from reports and reopen the payable, without cash movement.
  await save([{tabla:'pago_costurera',accion:'actualizar',id:gift.pago_costurera_id,datos:{estado:'anulado',notas:'Anulación de prueba'}}]);
  assert.equal(Number((await panel()).regalos),23);
  assert.equal(Number((await panel()).pagos),28);
  assert.equal(Number((await rows('v_saldo_costurera_encargo')).find(r=>r.encargo_id===enc[0].encargo_id).saldo_por_pagar),10);
  await db.exec("SELECT set_config('request.jwt.claim.sub','9a70e587-27bc-424b-ae80-c80a9995d249',false)");
  assert.equal((await rows('v_pagos_regalados')).length,0);
  await assert.rejects(db.query("SELECT public.bm_datos('v_pagos_regalados')"),/no tiene acceso/);
 }finally{await db.close();}
});
