-- Run only in a transaction that is rolled back; no business records persist.
BEGIN;
SELECT set_config('request.jwt.claim.sub',(SELECT usuario_id::text FROM bm.usuario_bm WHERE activo AND rol='administrador' LIMIT 1),true);
SET LOCAL ROLE authenticated;
DO $test$
DECLARE anterior jsonb; posterior jsonb; r jsonb; cuenta bigint; saldo numeric;
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
END $test$;
SET CONSTRAINTS bm.z_integridad IMMEDIATE;
SELECT true AS regalo_liquidado_sin_mover_caja, current_user AS rol;
ROLLBACK;
