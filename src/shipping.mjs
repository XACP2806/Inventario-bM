const round=v=>Math.round((v+Number.EPSILON)*100)/100;
export function shippingCharge(v, rates=[]) {
 const total=Number(v.envio_cobrado||0);
 if(!Number.isFinite(total)||total<0)throw Error('Revisa el importe cobrado por envío.');
 if(!total)return {total:0,base:0,iva:0,fields:{}};
 const type=v.envio_tratamiento;
 if(!['gravado','tarifa_0','exento','no_objeto'].includes(type))throw Error('Selecciona el tratamiento tributario del envío.');
 const taxable=type==='gravado', usesRate=taxable||type==='tarifa_0';
 const rate=rates.find(r=>String(r.tarifa_iva_id)===String(v.envio_tarifa));
 if(usesRate&&(!rate||v.fecha<rate.vigente_desde||(rate.vigente_hasta&&v.fecha>rate.vigente_hasta)||(taxable?Number(rate.porcentaje)<=0:Number(rate.porcentaje)!==0)))throw Error('Selecciona una tarifa vigente para el envío.');
 if(!taxable&&!v.envio_motivo?.trim())throw Error('Indica el motivo tributario del envío.');
 const percent=usesRate?Number(rate.porcentaje):0,base=round(total/(1+percent/100)),iva=round(base*percent/100);
 if(Math.abs(round(base+iva)-total)>.001)throw Error('El importe final del envío no coincide con el redondeo de su IVA. Revisa el valor.');
 return {total:round(total),base,iva,fields:{costo_envio_cobrado:base,envio_aplica_iva:usesRate,envio_porcentaje_iva:percent,envio_tratamiento_iva:type,envio_motivo_tributario:taxable?null:v.envio_motivo.trim(),envio_fecha_tributaria:v.fecha,envio_codigo_tarifa:usesRate?rate.codigo_tarifa:null}};
}
export function shippingPayment({cost,paid,carrier,method,date,envio}) {
 const amount=Number(cost||0);
 if(!Number.isFinite(amount)||amount<0)throw Error('Revisa el costo real del transporte.');
 if(!amount)return [];
 if(!carrier?.trim())throw Error('Escribe el nombre del transportista.');
 const reference=typeof envio==='object'?'Despacho de este registro':'Despacho #'+envio;
 const description='Pago de transporte · '+reference;
 const actions=[{accion:'insertar',tabla:'cuenta_pagar',ref:'pago_transporte_cuenta',datos:{tercero_nombre:carrier.trim(),descripcion:description,monto_original:amount,fecha_origen:date,notas:'Costo ya incluido en el despacho; no registrar también como gasto.'}}];
 if(paid==='si')actions.push({accion:'insertar',tabla:'abono_cuenta_pagar',datos:{cuenta_pagar_id:{$ref:'pago_transporte_cuenta'},monto:amount,fecha_pago:date,metodo:method||'transferencia'}});
 return actions;
}
