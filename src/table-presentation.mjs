export const salesCustomerViews=['v_saldo_pedido','v_pedidos_por_entregar','v_pedidos_entregados','v_cumplimiento_detalle_pedido','v_estado_entrega_pedido','v_estado_cuenta_pedido'];
function customerColumns(columns){
 const clean=columns.filter(c=>!['_cliente','cliente_nombre','nombre_cliente'].includes(c.name));
 if(clean.some(c=>c.name==='cliente_id'))return clean.map(c=>c.name==='cliente_id'?{name:'_cliente',label:'Cliente'}:c);
 const at=clean.findIndex(c=>c.name==='pedido_id')+1;clean.splice(at,0,{name:'_cliente',label:'Cliente'});return clean;
}
const salesBalanceColumns=[{name:'pedido_id',label:'Pedido'},{name:'cliente_nombre',label:'Cliente'},{name:'estado',label:'Estado'},{name:'total_neto_pedido',label:'Total neto pedido'},{name:'dinero_recibido',label:'Dinero recibido'},{name:'dinero_reembolsado',label:'Dinero reembolsado'},{name:'saldo_pendiente',label:'Saldo pendiente'}];
const fabricStockColumns=[
 {name:'tela_nombre',label:'Tela'},
 {name:'ubicacion',label:'Ubicación'},
 {name:'lote_tela_id',label:'Lote'},
 {name:'metros_disponibles',label:'Metros disponibles'}
];
const productionColumns=[
 {name:'_prenda',label:'Prenda, color y talla'},
 {name:'_taller',label:'Taller / costurera'},
 {name:'encargo_id',label:'Encargo'},
 {name:'cantidad_solicitada',label:'Encargadas'},
 {name:'_aceptadas',label:'Aceptadas'},
 {name:'_pendientes_recibir',label:'Pendientes de recibir'},
 {name:'_recepcion',label:'Recepción'}
];
const productionDetails=[
 {name:'_recibidas',label:'Recibidas en total'},
 {name:'_rechazadas',label:'Rechazadas'},
 {name:'tarifa_mano_obra_unitaria',label:'Costura por unidad'},
 {name:'_estado_encargo',label:'Estado del encargo'},
 {name:'notas',label:'Notas'},
 {name:'detalle_encargo_id',label:'Código de detalle'},
 {name:'variante_id',label:'Código de variante'},
 {name:'detalle_pedido_id',label:'Código de prenda del pedido'}
];
export function tableColumns(table,columns,expanded=false){
 if(table==='v_saldo_pedido')return expanded?[...salesBalanceColumns,{name:'cliente_id',label:'Código de cliente'}]:salesBalanceColumns;
 if(salesCustomerViews.includes(table)){const named=customerColumns(columns);return expanded?named:named.slice(0,7);}
 if(table==='detalle_encargo_costura')return expanded?[...productionColumns,...productionDetails]:productionColumns;
 if(table!=='v_existencia_tela')return expanded?columns:columns.slice(0,7);
 return expanded?[...fabricStockColumns,{name:'tela_id',label:'Código de tela'},{name:'ubicacion_id',label:'Código de ubicación'}]:fabricStockColumns;
}
export function tableValue(table,column,row){
 if(salesCustomerViews.includes(table)&&column==='_cliente')return row._cliente??row.cliente_nombre??row.nombre_cliente??null;
 if(table==='detalle_encargo_costura'&&column==='encargo_id')return row[column]==null?null:'Encargo '+row[column];
 if(table==='v_existencia_tela'&&column==='lote_tela_id')return row[column]==null?null:'Lote '+row[column];
 return row[column];
}
export function exportTableRows(table,rows){
 if(table==='v_saldo_pedido')return rows.map(row=>Object.fromEntries(salesBalanceColumns.map(c=>[c.label,tableValue(table,c.name,row)])));
 if(salesCustomerViews.includes(table))return rows.map(row=>Object.fromEntries(customerColumns(Object.keys(row).map(name=>({name}))).map(c=>[c.label||c.name,tableValue(table,c.name,row)])));
 if(table==='detalle_encargo_costura')return rows.map(row=>Object.fromEntries([...productionColumns,...productionDetails].map(c=>[c.label,tableValue(table,c.name,row)])));
 if(table!=='v_existencia_tela')return rows;
 return rows.map(row=>Object.fromEntries(fabricStockColumns.map(c=>[c.label,tableValue(table,c.name,row)])));
}
