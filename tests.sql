-- Synthetic records only. Everything is rolled back, including auth user.
BEGIN;
INSERT INTO auth.users(id) VALUES('83d20ad7-300c-4cd0-9ea7-ff82366f77c2');
INSERT INTO bm.usuario_bm(usuario_id,rol) VALUES('83d20ad7-300c-4cd0-9ea7-ff82366f77c2','administrador');
SELECT set_config('request.jwt.claim.sub','83d20ad7-300c-4cd0-9ea7-ff82366f77c2',true);
DO $test$
DECLARE result jsonb; again jsonb; acciones jsonb; n numeric; x bigint; y bigint; pedido bigint; lote bigint; linea bigint; envio bigint; de bigint; id_aj bigint;
BEGIN
 acciones:='[
 {"accion":"insertar","tabla":"categoria","ref":"cat","datos":{"nombre":"TEST Camisas"}},
 {"accion":"insertar","tabla":"talla","ref":"s","datos":{"nombre":"TEST S"}},
 {"accion":"insertar","tabla":"talla","ref":"m","datos":{"nombre":"TEST M"}},
 {"accion":"insertar","tabla":"color","ref":"color","datos":{"nombre":"TEST Azul"}},
 {"accion":"insertar","tabla":"articulo","ref":"art","datos":{"categoria_id":{"$ref":"cat"},"nombre":"TEST LA AZUL","precio_final_catalogo":44}},
 {"accion":"insertar","tabla":"variante_articulo","ref":"var","datos":{"articulo_id":{"$ref":"art"},"color_id":{"$ref":"color"},"talla_id":{"$ref":"s"},"sku":"TEST-A-S"}},
 {"accion":"insertar","tabla":"variante_articulo","ref":"var2","datos":{"articulo_id":{"$ref":"art"},"color_id":{"$ref":"color"},"talla_id":{"$ref":"m"},"sku":"TEST-A-M"}},
 {"accion":"insertar","tabla":"cliente","ref":"cliente","datos":{"nombre_completo":"TEST Cliente","telefono":"TEST"}},
 {"accion":"insertar","tabla":"costurera","ref":"cost","datos":{"nombre_completo":"TEST Costurera"}},
 {"accion":"insertar","tabla":"ubicacion_tela","ref":"bodega","datos":{"nombre":"TEST Bodega","tipo":"bodega"}},
 {"accion":"insertar","tabla":"ubicacion_tela","ref":"taller","datos":{"nombre":"TEST Taller","tipo":"costurera","costurera_id":{"$ref":"cost"}}},
 {"accion":"insertar","tabla":"tela","ref":"tela","datos":{"nombre":"TEST Lino"}},
 {"accion":"insertar","tabla":"lote_tela","ref":"tela_lote","datos":{"tela_id":{"$ref":"tela"},"metros_comprados":20,"costo_metro":5,"fecha_ingreso":"2024-01-01T12:00:00-05:00"}},
 {"accion":"insertar","tabla":"movimiento_tela","datos":{"lote_tela_id":{"$ref":"tela_lote"},"tipo":"compra","destino_ubicacion_id":{"$ref":"bodega"},"metros":20,"fecha":"2024-01-01T12:00:00-05:00"}},
 {"accion":"insertar","tabla":"encargo_costura","ref":"enc","datos":{"costurera_id":{"$ref":"cost"},"fecha_encargo":"2024-01-02T12:00:00-05:00"}},
 {"accion":"insertar","tabla":"detalle_encargo_costura","ref":"dec","datos":{"encargo_id":{"$ref":"enc"},"variante_id":{"$ref":"var"},"cantidad_solicitada":10,"tarifa_mano_obra_unitaria":5}},
 {"accion":"insertar","tabla":"movimiento_tela","datos":{"lote_tela_id":{"$ref":"tela_lote"},"tipo":"transferencia","origen_ubicacion_id":{"$ref":"bodega"},"destino_ubicacion_id":{"$ref":"taller"},"metros":20,"fecha":"2024-01-03T12:00:00-05:00"}},
 {"accion":"insertar","tabla":"movimiento_tela","datos":{"lote_tela_id":{"$ref":"tela_lote"},"tipo":"consumo","origen_ubicacion_id":{"$ref":"taller"},"detalle_encargo_id":{"$ref":"dec"},"metros":20,"fecha":"2024-01-04T12:00:00-05:00"}},
 {"accion":"insertar","tabla":"recepcion_costura","ref":"rec","datos":{"encargo_id":{"$ref":"enc"},"fecha_recepcion":"2024-01-05T12:00:00-05:00"}},
 {"accion":"insertar","tabla":"detalle_recepcion_costura","ref":"drec","datos":{"recepcion_id":{"$ref":"rec"},"encargo_id":{"$ref":"enc"},"detalle_encargo_id":{"$ref":"dec"},"cantidad_recibida":10,"cantidad_aceptada":10,"cantidad_rechazada":0}},
 {"accion":"insertar","tabla":"lote_producto","ref":"lp","datos":{"detalle_recepcion_id":{"$ref":"drec"},"variante_id":{"$ref":"var"},"costo_tela_unitario":10,"costo_mano_obra_unitario":5,"fecha_alta":"2024-01-05T12:00:00-05:00"}},
 {"accion":"insertar","tabla":"movimiento_producto","datos":{"lote_producto_id":{"$ref":"lp"},"tipo":"produccion","cantidad_delta":10,"fecha":"2024-01-05T12:00:00-05:00"}},
 {"accion":"insertar","tabla":"tarifa_iva_vigencia","datos":{"codigo_tarifa":"TEST","porcentaje":12,"vigente_desde":"2020-01-01","vigente_hasta":"2023-12-31","sustento_normativo":"Tarifa ficticia de prueba"}},
 {"accion":"insertar","tabla":"tarifa_iva_vigencia","datos":{"codigo_tarifa":"TEST","porcentaje":15,"vigente_desde":"2024-01-01","sustento_normativo":"Tarifa ficticia de prueba"}},
 {"accion":"insertar","tabla":"pedido","ref":"p","datos":{"cliente_id":{"$ref":"cliente"},"fecha_pedido":"2024-01-06T12:00:00-05:00"}},
 {"accion":"insertar","tabla":"detalle_pedido","ref":"dp","datos":{"pedido_id":{"$ref":"p"},"variante_id":{"$ref":"var"},"descripcion_vendida":"TEST AZUL S","sku_vendido":"TEST-A-S","cantidad":3,"precio_lista_unitario":44,"precio_unitario_final":44,"aplica_iva":true,"porcentaje_iva":15,"tratamiento_iva":"gravado","codigo_tarifa":"TEST","fecha_tributaria":"2024-01-06"}},
 {"accion":"actualizar","tabla":"pedido","id":{"$ref":"p"},"datos":{"estado":"confirmado","fecha_confirmacion":"2024-01-06T12:00:00-05:00"}},
 {"accion":"insertar","tabla":"pago_pedido","datos":{"pedido_id":{"$ref":"p"},"monto":132,"metodo":"TEST efectivo","fecha_pago":"2024-01-06T12:00:00-05:00"}},
 {"accion":"insertar","tabla":"envio","ref":"e","datos":{"pedido_id":{"$ref":"p"},"direccion_entrega":"TEST retiro","modalidad_entrega":"retiro","fecha_envio":"2024-01-07T12:00:00-05:00","estado":"despachado"}},
 {"accion":"insertar","tabla":"detalle_envio","ref":"de","datos":{"envio_id":{"$ref":"e"},"detalle_pedido_id":{"$ref":"dp"},"lote_producto_id":{"$ref":"lp"},"cantidad":2}},
 {"accion":"insertar","tabla":"movimiento_producto","datos":{"lote_producto_id":{"$ref":"lp"},"tipo":"venta","detalle_envio_id":{"$ref":"de"},"cantidad_delta":-2,"fecha":"2024-01-07T12:00:00-05:00"}},
 {"accion":"insertar","tabla":"entrega_pedido","ref":"ent","datos":{"envio_id":{"$ref":"e"},"estado":"confirmada","fecha_entrega":"2024-01-08T12:00:00-05:00"}},
 {"accion":"insertar","tabla":"detalle_entrega","datos":{"entrega_id":{"$ref":"ent"},"envio_id":{"$ref":"e"},"detalle_envio_id":{"$ref":"de"},"cantidad_entregada":1}}
 ]'::jsonb;
 result:=bm.registrar_operacion('29da8422-d6df-4a98-9941-0819a8bbc034',acciones,'TEST reconstrucción histórica');
 again:=bm.registrar_operacion('29da8422-d6df-4a98-9941-0819a8bbc034',acciones,'TEST reconstrucción histórica');
 IF result<>again THEN RAISE EXCEPTION 'FAIL idempotencia'; END IF;
 SELECT pedido_id,detalle_pedido_id INTO pedido,linea FROM bm.detalle_pedido WHERE sku_vendido='TEST-A-S';
 SELECT lote_producto_id,envio_id,detalle_envio_id INTO lote,envio,de FROM bm.detalle_envio WHERE detalle_pedido_id=linea;
 SELECT total_neto_pedido INTO n FROM bm.v_saldo_pedido WHERE pedido_id=pedido;
 IF n<>132 THEN RAISE EXCEPTION 'FAIL total final %',n; END IF;
 SELECT subtotal_linea INTO n FROM bm.detalle_pedido WHERE detalle_pedido_id=linea;
 IF n<>114.78 THEN RAISE EXCEPTION 'FAIL base IVA %',n; END IF;
 SELECT stock_fisico INTO n FROM bm.v_stock_lote_producto WHERE lote_producto_id=lote;
 IF n<>8 THEN RAISE EXCEPTION 'FAIL stock %',n; END IF;
 SELECT unidades_pendientes_entrega INTO n FROM bm.v_estado_entrega_pedido WHERE pedido_id=pedido;
 IF n<>2 THEN RAISE EXCEPTION 'FAIL entrega parcial %',n; END IF;
 -- Entire batch rolls back if lot variant or total delivered is incompatible.
 BEGIN
  INSERT INTO bm.reserva_producto(detalle_pedido_id,lote_producto_id,cantidad) VALUES(linea,lote,2);
  PERFORM bm.validar_integridad(); RAISE EXCEPTION 'FAIL reserva superior a compromiso';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
  INSERT INTO bm.entrega_pedido(envio_id,fecha_entrega,estado) VALUES(envio,'2024-01-08T13:00:00-05:00','confirmada') RETURNING entrega_id INTO x;
  INSERT INTO bm.detalle_entrega(entrega_id,envio_id,detalle_envio_id,cantidad_entregada) VALUES(x,envio,de,2);
  PERFORM bm.validar_integridad(); RAISE EXCEPTION 'FAIL sobreentrega';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
  INSERT INTO bm.envio(pedido_id,direccion_entrega) VALUES(pedido,'TEST') RETURNING envio_id INTO x;
  INSERT INTO bm.detalle_pedido(pedido_id,variante_id,descripcion_vendida,sku_vendido,cantidad,precio_lista_unitario,precio_unitario_final,fecha_tributaria,tratamiento_iva,aplica_iva,porcentaje_iva,motivo_tributario)
  SELECT pedido,variante_id,'TEST talla distinta',sku,1,44,44,'2024-01-06','exento',false,0,'Prueba' FROM bm.variante_articulo WHERE sku='TEST-A-M' RETURNING detalle_pedido_id INTO y;
  INSERT INTO bm.detalle_envio(envio_id,detalle_pedido_id,lote_producto_id,cantidad) VALUES(x,y,lote,1);
  PERFORM bm.validar_integridad(); RAISE EXCEPTION 'FAIL lote de otra talla';
 EXCEPTION WHEN check_violation THEN NULL; END;
 IF NOT EXISTS(SELECT 1 FROM bm.pago_pedido WHERE pedido_id=pedido AND registrado_en>fecha_pago+interval '1 day') THEN RAISE EXCEPTION 'FAIL fecha real de registro'; END IF;
 -- Negative scenarios must fail through the same gateway as the app.
 BEGIN
   PERFORM bm.registrar_operacion(gen_random_uuid(),jsonb_build_array(jsonb_build_object('accion','insertar','tabla','movimiento_producto','datos',jsonb_build_object('lote_producto_id',lote,'tipo','ajuste_negativo','cantidad_delta',-99,'fecha','2024-01-09T12:00:00-05:00'))),'TEST sobreventa');
   RAISE EXCEPTION 'FAIL aceptó sobreventa';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
   PERFORM bm.registrar_operacion(gen_random_uuid(),jsonb_build_array(jsonb_build_object('accion','insertar','tabla','movimiento_producto','datos',jsonb_build_object('lote_producto_id',lote,'tipo','ajuste_negativo','cantidad_delta',-1,'fecha','2023-01-01T12:00:00-05:00'))),'TEST stock histórico');
   RAISE EXCEPTION 'FAIL aceptó stock histórico negativo';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
   PERFORM bm.registrar_operacion(gen_random_uuid(),'[{"accion":"insertar","tabla":"tarifa_iva_vigencia","datos":{"codigo_tarifa":"TEST","porcentaje":16,"vigente_desde":"2024-02-01"}}]'::jsonb,'TEST solapamiento');
   RAISE EXCEPTION 'FAIL aceptó tarifa superpuesta';
 EXCEPTION WHEN check_violation THEN NULL; END;
 BEGIN
   UPDATE bm.detalle_pedido SET precio_unitario_final=1 WHERE detalle_pedido_id=linea;
   RAISE EXCEPTION 'FAIL editó venta confirmada';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
 -- A final cost is reconciled against actual material consumed, units, and tariff.
 UPDATE bm.encargo_costura SET estado='cerrado' WHERE encargo_id=(SELECT encargo_id FROM bm.encargo_costura LIMIT 1);
 UPDATE bm.lote_producto SET costo_finalizado=true WHERE lote_producto_id=lote;
 PERFORM bm.validar_integridad();
 BEGIN
   UPDATE bm.lote_producto SET costo_tela_unitario=11 WHERE lote_producto_id=lote;
   RAISE EXCEPTION 'FAIL editó costo cerrado';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
 -- Authorized return requires the matching reentry in the same transaction.
 INSERT INTO bm.devolucion_pedido(pedido_id,tipo,estado,fecha_solicitud,fecha_resolucion)
 VALUES(pedido,'devolucion','aprobada','2024-02-01T12:00:00-05:00','2024-02-01T12:00:00-05:00') RETURNING devolucion_id INTO x;
 INSERT INTO bm.detalle_devolucion(devolucion_id,detalle_envio_id,cantidad,condicion,reingresa_inventario,credito_subtotal,credito_iva)
 VALUES(x,de,1,'nuevo',true,38.26,5.74) RETURNING detalle_devolucion_id INTO y;
 BEGIN PERFORM bm.validar_integridad(); RAISE EXCEPTION 'FAIL devolución sin reingreso'; EXCEPTION WHEN check_violation THEN NULL; END;
 INSERT INTO bm.movimiento_producto(lote_producto_id,tipo,cantidad_delta,detalle_devolucion_id,fecha) VALUES(lote,'devolucion',1,y,'2024-02-01T12:00:00-05:00');
 PERFORM bm.validar_integridad();
 SELECT margen_prendas INTO n FROM bm.v_margen_diario WHERE dia='2024-02-01';
 IF n<>-23.26 THEN RAISE EXCEPTION 'FAIL margen devolución %',n; END IF;
 SELECT stock_fisico INTO n FROM bm.v_stock_lote_producto WHERE lote_producto_id=lote;
 IF n<>9 THEN RAISE EXCEPTION 'FAIL reingreso %',n; END IF;
 BEGIN
  INSERT INTO bm.reembolso(pedido_id,monto,metodo,estado,fecha_reembolso) VALUES(pedido,133,'TEST','completado','2024-02-01T12:00:00-05:00');
  PERFORM bm.validar_integridad(); RAISE EXCEPTION 'FAIL reembolso excesivo';
 EXCEPTION WHEN check_violation THEN NULL; END;
 INSERT INTO bm.ajuste_pedido(pedido_id,detalle_pedido_id,concepto,monto_subtotal,monto_iva,fecha)
 VALUES(pedido,linea,'TEST descuento posterior',-10,-1.50,'2024-02-02T12:00:00-05:00');
 PERFORM bm.validar_integridad();
 SELECT margen_neto_sin_envio INTO n FROM bm.v_margen_neto_articulo WHERE detalle_pedido_id=linea;
 IF n<>13.26 THEN RAISE EXCEPTION 'FAIL descuento en margen %',n; END IF;
 SELECT margen_prendas INTO n FROM bm.v_margen_diario WHERE dia='2024-02-02';
 IF n<>-10 THEN RAISE EXCEPTION 'FAIL fecha del descuento %',n; END IF;
 -- Historical tax rates, and legitimate exempt/zero-rated operations.
 INSERT INTO bm.tarifa_iva_vigencia(codigo_tarifa,porcentaje,vigente_desde,sustento_normativo)
 VALUES('TEST_CERO',0,'2020-01-01','Prueba de tarifa cero');
 INSERT INTO bm.pedido(cliente_id,fecha_pedido) SELECT cliente_id,'2023-06-01T12:00:00-05:00' FROM bm.pedido p WHERE p.pedido_id=pedido RETURNING pedido_id INTO x;
 INSERT INTO bm.detalle_pedido(pedido_id,variante_id,descripcion_vendida,sku_vendido,cantidad,precio_lista_unitario,precio_unitario_final,fecha_tributaria,codigo_tarifa,porcentaje_iva,tratamiento_iva)
 SELECT x,variante_id,'TEST histórico','TEST-A-S',1,44,44,'2023-06-01','TEST',12,'gravado' FROM bm.detalle_pedido WHERE detalle_pedido_id=linea RETURNING detalle_pedido_id INTO y;
 SELECT subtotal_linea INTO n FROM bm.detalle_pedido WHERE detalle_pedido_id=y;
 IF n<>39.29 THEN RAISE EXCEPTION 'FAIL tarifa histórica %',n; END IF;
 INSERT INTO bm.detalle_pedido(pedido_id,variante_id,descripcion_vendida,sku_vendido,cantidad,precio_lista_unitario,precio_unitario_final,fecha_tributaria,aplica_iva,porcentaje_iva,tratamiento_iva,motivo_tributario)
 SELECT x,variante_id,'TEST exento','TEST-A-S',1,44,44,'2023-06-01',false,0,'exento','Motivo de prueba, no usar como criterio fiscal' FROM bm.detalle_pedido WHERE detalle_pedido_id=linea RETURNING detalle_pedido_id INTO y;
 SELECT subtotal_linea INTO n FROM bm.detalle_pedido WHERE detalle_pedido_id=y;
 IF n<>44 THEN RAISE EXCEPTION 'FAIL operación exenta %',n; END IF;
 INSERT INTO bm.detalle_pedido(pedido_id,variante_id,descripcion_vendida,sku_vendido,cantidad,precio_lista_unitario,precio_unitario_final,fecha_tributaria,aplica_iva,codigo_tarifa,porcentaje_iva,tratamiento_iva,motivo_tributario)
 SELECT x,variante_id,'TEST cero','TEST-A-S',1,44,44,'2023-06-01',true,'TEST_CERO',0,'tarifa_0','Motivo de prueba' FROM bm.detalle_pedido WHERE detalle_pedido_id=linea;
 PERFORM bm.validar_integridad();
 -- Cancel an unshipped unit with its matching credit, without changing past margin.
 UPDATE bm.detalle_pedido SET cantidad_cancelada=1,motivo_cancelacion='TEST cancelación parcial' WHERE detalle_pedido_id=linea;
 INSERT INTO bm.ajuste_pedido(pedido_id,detalle_pedido_id,clase,concepto,monto_subtotal,monto_iva,fecha)
 VALUES(pedido,linea,'cancelacion','TEST cancela una camisa no despachada',-38.26,-5.74,'2024-02-03T12:00:00-05:00');
 PERFORM bm.validar_integridad();
 SELECT margen_neto_sin_envio INTO n FROM bm.v_margen_neto_articulo WHERE detalle_pedido_id=linea;
 IF n<>13.26 THEN RAISE EXCEPTION 'FAIL cancelación modificó margen %',n; END IF;
 INSERT INTO bm.periodo_cerrado(desde,hasta,motivo) VALUES('2024-01-01','2024-01-31','TEST cierre');
 BEGIN
  INSERT INTO bm.pago_pedido(pedido_id,monto,metodo,fecha_pago) VALUES(pedido,1,'TEST','2024-01-15T12:00:00-05:00');
  RAISE EXCEPTION 'FAIL permitió operación en período cerrado';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
 BEGIN
  INSERT INTO bm.detalle_envio(envio_id,detalle_pedido_id,lote_producto_id,cantidad) VALUES(envio,linea,lote,1);
  RAISE EXCEPTION 'FAIL permitió alterar despacho cerrado';
 EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
 -- The RPC itself refuses unknown users and cannot escalate membership.
 PERFORM set_config('request.jwt.claim.sub','',true);
 BEGIN PERFORM bm.registrar_operacion(gen_random_uuid(),acciones,'TEST sin usuario'); RAISE EXCEPTION 'FAIL acceso anónimo'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('request.jwt.claim.sub','83d20ad7-300c-4cd0-9ea7-ff82366f77c2',true);
 PERFORM bm.validar_integridad();
 RAISE NOTICE 'PASS precio final, histórico, recepción, stock, despacho, entrega parcial, idempotencia, tarifas, devolución, costos y autorización';
END $test$;
SET CONSTRAINTS ALL IMMEDIATE;
SET LOCAL ROLE authenticated;
DO $rls$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM bm.pedido) THEN RAISE EXCEPTION 'FAIL miembro no puede leer'; END IF;
 BEGIN INSERT INTO bm.categoria(nombre) VALUES('PROHIBIDO'); RAISE EXCEPTION 'FAIL escritura directa habilitada'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $rls$;
SELECT set_config('request.jwt.claim.sub','9a70e587-27bc-424b-ae80-c80a9995d249',true);
DO $rls$ BEGIN
 IF EXISTS(SELECT 1 FROM bm.pedido) THEN RAISE EXCEPTION 'FAIL usuario externo puede leer'; END IF;
 IF EXISTS(SELECT 1 FROM bm.v_saldo_pedido) THEN RAISE EXCEPTION 'FAIL vista evade RLS'; END IF;
END $rls$;
RESET ROLE;
ROLLBACK;

