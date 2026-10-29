export function validateLocation(values){
 if(!['bodega','costurera'].includes(values.tipo))throw Error('Selecciona Bodega o Costurera en el campo Tipo.');
 if(values.tipo==='costurera'&&!values.costurera_id)throw Error('Selecciona la costurera a la que pertenece este taller.');
 if(values.tipo==='bodega'&&values.costurera_id)throw Error('Una bodega no debe estar vinculada a una costurera.');
}

export const fundingOptions=[['bm','Dinero de bM'],['regalo_tercero','Pagado por un tercero — regalo, sin devolución']];
export function paymentFunds(origen='bm',nombre=''){
 if(!['bm','regalo_tercero'].includes(origen))throw Error('Selecciona quién pagó: bM o un tercero como regalo.');
 const pagador=String(nombre||'').trim();
 if(origen==='regalo_tercero'&&(!pagador||pagador.length>180))throw Error('Escribe quién hizo el regalo (hasta 180 caracteres).');
 return {origen_fondos:origen,pagador_nombre:origen==='regalo_tercero'?pagador:null};
}
export function paymentSummary(actions){
 return actions.filter(a=>['abono_cuenta_pagar','pago_costurera'].includes(a.tabla)&&a.accion==='insertar').reduce((s,a)=>{
  s[a.datos.origen_fondos==='regalo_tercero'?'regalos':'pagos']+=Number(a.datos.monto);
  return s;
 },{pagos:0,regalos:0});
}
