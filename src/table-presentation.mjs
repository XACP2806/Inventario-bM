const fabricStockColumns=[
 {name:'tela_nombre',label:'Tela'},
 {name:'ubicacion',label:'Ubicación'},
 {name:'lote_tela_id',label:'Lote'},
 {name:'metros_disponibles',label:'Metros disponibles'}
];
export function tableColumns(table,columns,expanded=false){
 if(table!=='v_existencia_tela')return expanded?columns:columns.slice(0,7);
 return expanded?[...fabricStockColumns,{name:'tela_id',label:'Código de tela'},{name:'ubicacion_id',label:'Código de ubicación'}]:fabricStockColumns;
}
export function tableValue(table,column,row){
 if(table==='v_existencia_tela'&&column==='lote_tela_id')return row[column]==null?null:'Lote '+row[column];
 return row[column];
}
export function exportTableRows(table,rows){
 if(table!=='v_existencia_tela')return rows;
 return rows.map(row=>Object.fromEntries(fabricStockColumns.map(c=>[c.label,tableValue(table,c.name,row)])));
}
