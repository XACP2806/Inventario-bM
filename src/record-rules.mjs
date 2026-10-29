export function validateLocation(values){
 if(!['bodega','costurera'].includes(values.tipo))throw Error('Selecciona Bodega o Costurera en el campo Tipo.');
 if(values.tipo==='costurera'&&!values.costurera_id)throw Error('Selecciona la costurera a la que pertenece este taller.');
 if(values.tipo==='bodega'&&values.costurera_id)throw Error('Una bodega no debe estar vinculada a una costurera.');
}
