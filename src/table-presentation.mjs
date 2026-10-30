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
 if(table==='detalle_encargo_costura')return expanded?[...productionColumns,...productionDetails]:productionColumns;
 if(table!=='v_existencia_tela')return expanded?columns:columns.slice(0,7);
 return expanded?[...fabricStockColumns,{name:'tela_id',label:'Código de tela'},{name:'ubicacion_id',label:'Código de ubicación'}]:fabricStockColumns;
}
export function tableValue(table,column,row){
 if(table==='detalle_encargo_costura'&&column==='encargo_id')return row[column]==null?null:'Encargo '+row[column];
 if(table==='v_existencia_tela'&&column==='lote_tela_id')return row[column]==null?null:'Lote '+row[column];
 return row[column];
}
export function exportTableRows(table,rows){
 if(table==='detalle_encargo_costura')return rows.map(row=>Object.fromEntries([...productionColumns,...productionDetails].map(c=>[c.label,tableValue(table,c.name,row)])));
 if(table!=='v_existencia_tela')return rows;
 return rows.map(row=>Object.fromEntries(fabricStockColumns.map(c=>[c.label,tableValue(table,c.name,row)])));
}
