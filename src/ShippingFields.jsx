import React from 'react';
export default function ShippingFields({v,change,rates}) {
 const methods=[['efectivo','Efectivo'],['transferencia','Transferencia'],['tarjeta','Tarjeta'],['otro','Otro']];
 return <section className="more"><h3>Envío</h3><p className="muted">Separa la tarifa que cobras al cliente del costo que pagas por transportar la camisa.</p><div className="fields">
 <label className="field"><span>Envío cobrado al cliente · importe final</span><input type="number" required min="0" step="0.01" value={v.envio_cobrado} onChange={e=>change('envio_cobrado',e.target.value)}/><small>Se suma al precio de las prendas. Incluye IVA cuando corresponda; deja 0 si no cobras envío.</small></label>
 {Number(v.envio_cobrado)>0&&<>
 <label className="field"><span>Tratamiento tributario del envío *</span><select required value={v.envio_tratamiento} onChange={e=>{change('envio_tratamiento',e.target.value);change('envio_tarifa','');}}><option value="">Seleccionar…</option><option value="gravado">Gravado con IVA</option><option value="tarifa_0">Tarifa 0%</option><option value="exento">Exento</option><option value="no_objeto">No objeto</option></select></label>
 {['gravado','tarifa_0'].includes(v.envio_tratamiento)&&<label className="field"><span>Tarifa de IVA del envío *</span><select required value={v.envio_tarifa} onChange={e=>change('envio_tarifa',e.target.value)}><option value="">Seleccionar…</option>{rates.filter(t=>t.vigente_desde<=v.fecha&&(!t.vigente_hasta||t.vigente_hasta>=v.fecha)&&(v.envio_tratamiento==='gravado'?Number(t.porcentaje)>0:Number(t.porcentaje)===0)).map(t=><option key={t.tarifa_iva_id} value={t.tarifa_iva_id}>{t.codigo_tarifa} · {t.porcentaje}%</option>)}</select></label>}
 {v.envio_tratamiento&&v.envio_tratamiento!=='gravado'&&<label className="field"><span>Motivo tributario del envío *</span><input required value={v.envio_motivo} onChange={e=>change('envio_motivo',e.target.value)}/></label>}
 </>}
 {v.modalidad==='entregar'&&<>
 <label className="field"><span>Forma de entrega</span><select value={v.envio_modalidad} onChange={e=>change('envio_modalidad',e.target.value)}><option value="entrega_personal">Entrega personal</option><option value="transportadora">Transportadora</option><option value="mensajeria">Mensajería</option><option value="retiro">Retiro</option></select></label>
 <label className="field"><span>Dirección o lugar de entrega</span><input value={v.direccion} onChange={e=>change('direccion',e.target.value)}/></label>
 <label className="field"><span>Costo real del transporte</span><input type="number" required min="0" step="0.01" value={v.envio_costo} onChange={e=>change('envio_costo',e.target.value)}/><small>Lo que cuesta el transporte a bM; puede diferir de lo cobrado al cliente. No lo repitas como gasto.</small></label>
 {Number(v.envio_costo)>0&&<>
 <label className="field"><span>¿bM ya pagó este transporte?</span><select value={v.envio_pagado} onChange={e=>change('envio_pagado',e.target.value)}><option value="no">No; registraré el pago después</option><option value="si">Sí; registrar el pago ahora</option></select></label>
 <label className="field"><span>Transportista o mensajero *</span><input required maxLength="100" value={v.transportadora} onChange={e=>change('transportadora',e.target.value)}/></label>
 {v.envio_pagado==='si'&&<label className="field"><span>Forma de pago del transporte</span><select value={v.envio_metodo} onChange={e=>change('envio_metodo',e.target.value)}>{methods.map(([k,t])=><option key={k} value={k}>{t}</option>)}</select></label>}
 </>}
 </>}
 </div>{v.modalidad!=='entregar'&&<p className="muted">El costo real y su pago se registran al despachar las prendas. Aquí puedes cobrar por adelantado el envío al cliente.</p>}</section>;
}
