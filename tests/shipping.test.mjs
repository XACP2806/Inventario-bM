import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {database} from '../scripts/schema.mjs';
import {saleActions,workflowActions} from '../src/workflows.mjs';
import {shippingCharge} from '../src/shipping.mjs';

test('envío separa cobro, costo y pago sin duplicar gasto, con idempotencia y saldo real',async()=>{
 const db=await database();try{
 await db.exec(fs.readFileSync('tests.sql','utf8').replace(/ROLLBACK;\s*$/,'COMMIT;'));
 await db.exec("SELECT set_config('request.jwt.claim.sub','83d20ad7-300c-4cd0-9ea7-ff82366f77c2',false); SET ROLE authenticated;");
 const rows=async t=>(await db.query('SELECT to_jsonb(x) r FROM bm.'+t+' x')).rows.map(x=>x.r);
 const [variants,arts,rates,clients,lots]=await Promise.all(['variante_articulo','articulo','tarifa_iva_vigencia','cliente','lote_producto'].map(rows));
 const context={variantes:variants,articulos:arts,tarifas:rates};
 const item={variante:variants[0].variante_id,cantidad:1,precio:44,lote:lots[0].lote_producto_id};
 const base={fecha:'2024-03-01',cliente:clients[0].cliente_id,tratamiento:'no_objeto',motivo:'Prueba sintética',modalidad:'entregar',cobro:49,envio_cobrado:5,envio_tratamiento:'no_objeto',envio_motivo:'Prueba sintética',envio_costo:4,envio_pagado:'si',transportadora:'Transportista de prueba',envio_metodo:'efectivo'};
 const save=async(v)=>{const a=saleActions(v,[item],context),id=crypto.randomUUID();const run=()=>db.query('SELECT public.bm_registrar_operacion($1,$2,$3) x',[id,JSON.stringify(a),'Venta con envío de prueba']);const result=(await run()).rows[0].x;await run();return result;};
 const first=await save(base);
 const cash=async day=>(await rows('v_caja_diaria')).find(x=>x.dia===day);
 const result=async day=>(await rows('v_resultado_operativo_diario')).find(x=>x.dia===day);
 assert.equal(Number((await cash(base.fecha)).entradas),49);
 assert.equal(Number((await cash(base.fecha)).salidas),4);
 assert.equal(Number((await result(base.fecha)).resultado_envios),1);
 assert.equal(Number((await result(base.fecha)).gastos_generales_y_mermas),0);
 const pedido=first.find(x=>x.cliente_id&&x.pedido_id);
 assert.equal(Number((await rows('v_saldo_pedido')).find(x=>x.pedido_id===pedido.pedido_id).saldo_pendiente),0);
 await save({...base,fecha:'2024-03-02',envio_costo:6});
 assert.equal(Number((await cash('2024-03-02')).flujo_neto),43);
 assert.equal(Number((await result('2024-03-02')).resultado_envios),-1);
 const unpaid=await save({...base,fecha:'2024-03-03',envio_pagado:'no'});
 assert(unpaid.some(x=>x.cuenta_pagar_id&&Number(x.monto_original)===4));
 assert(!unpaid.some(x=>x.abono_id));
 assert.equal(Number((await cash('2024-03-03')).salidas),0);
 assert.equal(Number((await result('2024-03-03')).resultado_envios),1);
 const iva=rates.find(r=>r.codigo_tarifa==='TEST'&&Number(r.porcentaje)===15);
 const taxed={...base,fecha:'2024-03-04',envio_tratamiento:'gravado',envio_tarifa:iva.tarifa_iva_id,envio_cobrado:5.75,cobro:49.75,envio_costo:4};
 assert.equal(shippingCharge(taxed,rates).base,5);
 await save(taxed);
 assert.equal(Number((await cash('2024-03-04')).entradas),49.75);
 assert.equal(Number((await result('2024-03-04')).resultado_envios),1);
 assert.throws(()=>saleActions({...base,cobro:50},[item],context),/superar/);
 assert.throws(()=>saleActions({...base,envio_tratamiento:''},[item],context),/tratamiento tributario del envío/);
 assert.throws(()=>saleActions({...taxed,envio_tarifa:'no'},[item],context),/tarifa vigente/);
 assert.throws(()=>saleActions({...base,transportadora:''},[item],context),/nombre del transportista/);
 // An order billed now must not pay or dispatch shipping until the later dispatch.
 const pending=await save({...base,fecha:'2024-03-05',modalidad:'pedido'});
 assert.equal(Number((await cash('2024-03-05')).salidas),0);
 const detail=pending.find(x=>x.detalle_pedido_id);
 const dispatch=workflowActions('despacho',{fecha:'2024-03-06',lote:item.lote,cantidad:1,direccion:'Dirección de prueba',modalidad:'transportadora',costo:6,transporte_pagado:'si',transportadora:'Transportista de prueba',transporte_metodo:'transferencia'},{detalle:detail});
 await db.query('SELECT public.bm_registrar_operacion($1,$2,$3)',[crypto.randomUUID(),JSON.stringify(dispatch),'Despacho y pago de prueba']);
 assert.equal(Number((await cash('2024-03-06')).salidas),6);
 assert.equal(Number((await result('2024-03-06')).resultado_envios),-6);
 }finally{await db.close();}
});
