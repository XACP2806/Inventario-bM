-- Run only in a transaction that is rolled back; no business records persist.
BEGIN;
SELECT set_config('request.jwt.claim.sub',(SELECT usuario_id::text FROM bm.usuario_bm WHERE activo AND rol='administrador' LIMIT 1),true);
SET LOCAL ROLE authenticated;
DO $test$
DECLARE anterior jsonb; posterior jsonb; r jsonb; cuenta bigint; saldo numeric; compra bigint; tela bigint; ubicacion bigint; lote bigint; nuevo jsonb; acciones jsonb; operacion uuid:=gen_random_uuid(); bloqueado boolean:=false;
BEGIN
 anterior:=public.bm_panel('2024-06-01','2024-06-01')->'serie'->0;
 r:=public.bm_registrar_operacion(gen_random_uuid(),'[{"tabla":"proveedor","accion":"insertar","ref":"proveedor_test","datos":{"nombre_legal":"Verificación temporal de regalo"}},{"tabla":"tela","accion":"insertar","ref":"tela_test","datos":{"nombre":"Verificación temporal de regalo"}},{"tabla":"ubicacion_tela","accion":"insertar","ref":"ubicacion_test","datos":{"nombre":"Verificación temporal de regalo","tipo":"bodega"}},{"accion":"insertar","tabla":"compra","datos":{"proveedor_id":{"$ref":"proveedor_test"},"fecha_compra":"2024-06-01","tipo_comprobante":"factura","numero_factura":null},"ref":"compra"},{"accion":"insertar","tabla":"detalle_compra","datos":{"compra_id":{"$ref":"compra"},"tipo":"tela","tela_id":{"$ref":"tela_test"},"descripcion":"Compra de tela","cantidad":4,"precio_unitario_sin_iva":5,"iva_facturado":3,"iva_porcentaje":15},"ref":"detalle"},{"accion":"insertar","tabla":"lote_tela","datos":{"tela_id":{"$ref":"tela_test"},"detalle_compra_id":{"$ref":"detalle"},"metros_comprados":4,"costo_metro":5.75,"fecha_compra":"2024-06-01","fecha_ingreso":"2024-06-01T12:00:00-05:00","referencia_compra":null},"ref":"lote"},{"accion":"insertar","tabla":"movimiento_tela","datos":{"lote_tela_id":{"$ref":"lote"},"destino_ubicacion_id":{"$ref":"ubicacion_test"},"tipo":"compra","metros":4,"fecha":"2024-06-01T12:00:00-05:00"}},{"accion":"insertar","tabla":"cuenta_pagar","datos":{"compra_id":{"$ref":"compra"},"proveedor_id":{"$ref":"proveedor_test"},"descripcion":"Compra de tela ","monto_original":23,"fecha_origen":"2024-06-01"},"ref":"cuenta"},{"accion":"insertar","tabla":"abono_cuenta_pagar","datos":{"origen_fondos":"regalo_tercero","pagador_nombre":"Persona ficticia de prueba","cuenta_pagar_id":{"$ref":"cuenta"},"monto":23,"metodo":"transferencia","fecha_pago":"2024-06-01"}}]'::jsonb,'Verificación transitoria de regalo');
 SELECT (value->>'cuenta_pagar_id')::bigint INTO cuenta FROM jsonb_array_elements(r) WHERE value ? 'monto_original';
 SELECT saldo_pendiente INTO saldo FROM bm.v_saldo_cuenta_pagar WHERE cuenta_pagar_id=cuenta;
 posterior:=public.bm_panel('2024-06-01','2024-06-01')->'serie'->0;
 IF saldo<>0 OR (posterior->>'regalos')::numeric-(anterior->>'regalos')::numeric<>23
 OR posterior->>'pagos' IS DISTINCT FROM anterior->>'pagos'
 OR posterior->>'cobros' IS DISTINCT FROM anterior->>'cobros'
 THEN RAISE EXCEPTION 'Regalo no conciliado'; END IF;

 SELECT (value->>'compra_id')::bigint INTO compra FROM jsonb_array_elements(r) WHERE value ? 'numero_factura';
 SELECT (value->>'tela_id')::bigint INTO tela FROM jsonb_array_elements(r) WHERE value ? 'metros_comprados';
 SELECT (value->>'destino_ubicacion_id')::bigint INTO ubicacion FROM jsonb_array_elements(r) WHERE value ? 'movimiento_tela_id';
 acciones:=jsonb_build_array(
 jsonb_build_object('accion','insertar','tabla','detalle_compra','ref','detalle','datos',jsonb_build_object('compra_id',compra,'tipo','tela','tela_id',tela,'descripcion','Segunda línea temporal','cantidad',2,'precio_unitario_sin_iva',5,'iva_facturado',1.5,'iva_porcentaje',15)),
 jsonb_build_object('accion','insertar','tabla','lote_tela','ref','lote','datos',jsonb_build_object('tela_id',tela,'detalle_compra_id',jsonb_build_object('$ref','detalle'),'metros_comprados',2,'costo_metro',5.75,'fecha_compra','2024-06-01','fecha_ingreso','2024-06-01T12:00:00-05:00')),
 jsonb_build_object('accion','insertar','tabla','movimiento_tela','datos',jsonb_build_object('lote_tela_id',jsonb_build_object('$ref','lote'),'destino_ubicacion_id',ubicacion,'tipo','compra','metros',2,'fecha','2024-06-01T12:00:00-05:00')),
 jsonb_build_object('accion','actualizar','tabla','cuenta_pagar','id',cuenta,'datos',jsonb_build_object('monto_original',34.5),'esperado',jsonb_build_object('monto_original',23,'estado','vigente','compra_id',compra)),
 jsonb_build_object('accion','insertar','tabla','abono_cuenta_pagar','datos',jsonb_build_object('cuenta_pagar_id',cuenta,'monto',11.5,'fecha_pago','2024-06-01','metodo','transferencia','origen_fondos','regalo_tercero','pagador_nombre','Persona ficticia de prueba'))
 );
 nuevo:=public.bm_registrar_operacion(operacion,acciones,'Añadir tela temporal a factura');
 IF public.bm_registrar_operacion(operacion,acciones,'Añadir tela temporal a factura') IS DISTINCT FROM nuevo THEN RAISE EXCEPTION 'Reintento no idempotente'; END IF;
 BEGIN
  PERFORM public.bm_registrar_operacion(gen_random_uuid(),acciones,'Revisión desactualizada temporal');
 EXCEPTION WHEN serialization_failure THEN bloqueado:=true;
 END;
 IF NOT bloqueado THEN RAISE EXCEPTION 'No se protegió la revisión desactualizada'; END IF;
 IF (SELECT count(*) FROM bm.detalle_compra d WHERE d.compra_id=compra)<>2 THEN RAISE EXCEPTION 'Detalle duplicado'; END IF;
 IF (SELECT monto_original FROM bm.cuenta_pagar c WHERE c.cuenta_pagar_id=cuenta)<>34.5 THEN RAISE EXCEPTION 'Total incorrecto'; END IF;
 SELECT saldo_pendiente INTO saldo FROM bm.v_saldo_cuenta_pagar c WHERE c.cuenta_pagar_id=cuenta;
 posterior:=public.bm_panel('2024-06-01','2024-06-01')->'serie'->0;
 IF saldo<>0 OR (posterior->>'regalos')::numeric-(anterior->>'regalos')::numeric<>34.5
 OR posterior->>'pagos' IS DISTINCT FROM anterior->>'pagos' THEN RAISE EXCEPTION 'Segunda tela no conciliada'; END IF;
END $test$;
SET CONSTRAINTS bm.z_integridad IMMEDIATE;
SELECT true AS varias_telas_conciliadas_sin_duplicados, current_user AS rol;
ROLLBACK;
