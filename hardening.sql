-- v1.3: business writes are serialized for this small, single-brand inventory.
-- Updating a real mutex row also prevents stale snapshots under repeatable read.
CREATE TABLE bm.control_escritura (id boolean PRIMARY KEY DEFAULT true CHECK(id), revision bigint NOT NULL DEFAULT 0);
INSERT INTO bm.control_escritura DEFAULT VALUES;
CREATE TABLE bm.usuario_bm (
 usuario_id uuid PRIMARY KEY REFERENCES auth.users(id),
 rol text NOT NULL CHECK(rol IN ('administrador','operador','consulta')),
 activo boolean NOT NULL DEFAULT true
);
CREATE TABLE bm.periodo_cerrado (
 periodo_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 desde date NOT NULL, hasta date NOT NULL CHECK(hasta>=desde),
 motivo text NOT NULL CHECK(length(trim(motivo))>0),
 registrado_en timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE bm.operacion (
 operacion_id uuid PRIMARY KEY, usuario_id uuid NOT NULL REFERENCES auth.users(id),
 solicitud jsonb NOT NULL, respuesta jsonb, motivo text NOT NULL,
 registrado_en timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE bm.auditoria (
 auditoria_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 tabla text NOT NULL, accion text NOT NULL, anterior jsonb, nuevo jsonb,
 usuario_id uuid, usuario_sql text NOT NULL, operacion_id uuid,
 registrado_en timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE bm.recurso (tabla text PRIMARY KEY, clave text NOT NULL, fecha_operacion text);
ALTER TABLE bm.ajuste_pedido ADD COLUMN clase text NOT NULL DEFAULT 'descuento'
 CHECK(clase IN ('descuento','cargo','cancelacion'));
ALTER TABLE bm.ajuste_pedido ADD CONSTRAINT ajuste_signo CHECK
 ((clase='cargo' AND monto_subtotal>0) OR (clase IN ('descuento','cancelacion') AND monto_subtotal<=0 AND monto_iva<=0));
ALTER TABLE bm.pedido ADD COLUMN envio_tratamiento_iva text NOT NULL DEFAULT 'no_objeto'
 CHECK(envio_tratamiento_iva IN ('gravado','tarifa_0','exento','no_objeto')),
 ADD COLUMN envio_motivo_tributario text,
 ADD COLUMN envio_fecha_tributaria date,
 ADD COLUMN envio_codigo_tarifa text;
ALTER TABLE bm.pedido ADD CONSTRAINT envio_iva_coherente CHECK
 (costo_envio_cobrado=0 OR
 (envio_tratamiento_iva='gravado' AND envio_aplica_iva AND envio_porcentaje_iva>0 AND envio_fecha_tributaria IS NOT NULL AND envio_codigo_tarifa IS NOT NULL) OR
 (envio_tratamiento_iva<>'gravado' AND envio_porcentaje_iva=0 AND nullif(trim(envio_motivo_tributario),'') IS NOT NULL));

CREATE FUNCTION bm.puede_leer() RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=pg_catalog,bm AS $$
 SELECT auth.uid() IS NOT NULL AND EXISTS(SELECT 1 FROM bm.usuario_bm WHERE usuario_id=auth.uid() AND activo);
$$;
CREATE FUNCTION bm.serializar() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,bm AS $$
BEGIN
 UPDATE bm.control_escritura SET revision=revision+1 WHERE id;
 RETURN NULL;
END $$;

CREATE FUNCTION bm.fecha_efectiva(p_tabla text,p_fila jsonb) RETURNS timestamptz
LANGUAGE plpgsql STABLE SET search_path=pg_catalog,bm AS $$
DECLARE campo text; valor text; fecha timestamptz;
BEGIN
 SELECT fecha_operacion INTO campo FROM bm.recurso WHERE tabla=p_tabla;
 IF campo IS NOT NULL THEN
   valor:=p_fila->>campo;
   RETURN CASE WHEN length(valor)=10 THEN (valor::date+time '12:00') AT TIME ZONE 'America/Guayaquil' ELSE valor::timestamptz END;
 END IF;
 CASE p_tabla
 WHEN 'detalle_pedido' THEN SELECT fecha_pedido INTO fecha FROM bm.pedido WHERE pedido_id=(p_fila->>'pedido_id')::bigint;
 WHEN 'detalle_envio' THEN SELECT coalesce(e.fecha_envio,p.fecha_pedido) INTO fecha FROM bm.envio e JOIN bm.pedido p USING(pedido_id) WHERE e.envio_id=(p_fila->>'envio_id')::bigint;
 WHEN 'envio' THEN SELECT fecha_pedido INTO fecha FROM bm.pedido WHERE pedido_id=(p_fila->>'pedido_id')::bigint; fecha:=coalesce((p_fila->>'fecha_envio')::timestamptz,fecha);
 WHEN 'detalle_entrega' THEN SELECT fecha_entrega INTO fecha FROM bm.entrega_pedido WHERE entrega_id=(p_fila->>'entrega_id')::bigint;
 WHEN 'detalle_devolucion' THEN SELECT coalesce(fecha_resolucion,fecha_solicitud) INTO fecha FROM bm.devolucion_pedido WHERE devolucion_id=(p_fila->>'devolucion_id')::bigint;
 WHEN 'detalle_recepcion_costura' THEN SELECT fecha_recepcion INTO fecha FROM bm.recepcion_costura WHERE recepcion_id=(p_fila->>'recepcion_id')::bigint;
 WHEN 'detalle_encargo_costura' THEN SELECT fecha_encargo INTO fecha FROM bm.encargo_costura WHERE encargo_id=(p_fila->>'encargo_id')::bigint;
 WHEN 'asignacion_gasto_produccion' THEN SELECT fecha_gasto INTO fecha FROM bm.gasto WHERE gasto_id=(p_fila->>'gasto_id')::bigint;
 WHEN 'detalle_compra' THEN SELECT (fecha_compra+time '12:00') AT TIME ZONE 'America/Guayaquil' INTO fecha FROM bm.compra WHERE compra_id=(p_fila->>'compra_id')::bigint;
 WHEN 'credito_iva_compra' THEN SELECT (p.fecha_inicio+time '12:00') AT TIME ZONE 'America/Guayaquil' INTO fecha FROM bm.periodo_iva p WHERE periodo_iva_id=(p_fila->>'periodo_iva_id')::bigint;
 WHEN 'periodo_iva' THEN fecha:=((p_fila->>'fecha_inicio')::date+time '12:00') AT TIME ZONE 'America/Guayaquil';
 ELSE NULL;
 END CASE;
 RETURN fecha;
END $$;

-- Effective business timestamps are editable on insertion; recorded timestamps are not.
CREATE FUNCTION bm.proteger_historial() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,bm AS $$
DECLARE a jsonb; b jsonb; campo text:=TG_ARGV[0]; fecha date; estado_padre text; permitidas text[];
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'No borrar historial de %. Anular o registrar ajuste.',TG_TABLE_NAME; END IF;
 IF TG_OP='INSERT' THEN
   NEW.registrado_en:=clock_timestamp(); NEW.registrado_por:=auth.uid();
 ELSE
   NEW.registrado_en:=OLD.registrado_en; NEW.registrado_por:=OLD.registrado_por;
 END IF;
 NEW.actualizado_en:=clock_timestamp();
 a:=CASE WHEN TG_OP='UPDATE' THEN to_jsonb(OLD) ELSE '{}'::jsonb END; b:=to_jsonb(NEW);
 -- Generated fields in NEW are not computed yet in a BEFORE trigger.
 SELECT coalesce(array_agg(attname::text),'{}'::text[]) INTO permitidas FROM pg_attribute WHERE attrelid=TG_RELID AND attgenerated<>'';
 a:=a-permitidas; b:=b-permitidas;
 IF EXISTS(SELECT 1 FROM pg_attribute c JOIN pg_type t ON t.oid=c.atttypid WHERE c.attrelid=TG_RELID AND c.attnum>0 AND t.typcategory='N' AND b->>c.attname IN ('NaN','Infinity','-Infinity')) THEN RAISE EXCEPTION 'Solo números finitos'; END IF;
 fecha:=(bm.fecha_efectiva(TG_TABLE_NAME,b) AT TIME ZONE 'America/Guayaquil')::date;
 IF fecha IS NOT NULL THEN
   IF EXISTS(SELECT 1 FROM bm.periodo_cerrado WHERE fecha BETWEEN desde AND hasta
     OR (TG_OP='UPDATE' AND (bm.fecha_efectiva(TG_TABLE_NAME,a) AT TIME ZONE 'America/Guayaquil')::date BETWEEN desde AND hasta))
     THEN RAISE EXCEPTION 'Periodo cerrado: %',fecha; END IF;
 END IF;
 IF TG_OP='UPDATE' THEN
   IF TG_TABLE_NAME IN ('movimiento_producto','movimiento_tela','recepcion_costura','detalle_recepcion_costura','ajuste_pedido')
     THEN RAISE EXCEPTION 'Hecho histórico inmutable: %',TG_TABLE_NAME; END IF;
   IF TG_TABLE_NAME='lote_producto' AND OLD.costo_finalizado AND
       (a-ARRAY['actualizado_en','notas']) IS DISTINCT FROM (b-ARRAY['actualizado_en','notas'])
     THEN RAISE EXCEPTION 'Costo finalizado: no modificar'; END IF;
   IF TG_TABLE_NAME='detalle_pedido' THEN
     SELECT estado INTO estado_padre FROM bm.pedido WHERE pedido_id=OLD.pedido_id;
     IF estado_padre<>'borrador' AND
       (a-ARRAY['cantidad_cancelada','motivo_cancelacion','actualizado_en']) IS DISTINCT FROM
       (b-ARRAY['cantidad_cancelada','motivo_cancelacion','actualizado_en'])
       THEN RAISE EXCEPTION 'Linea confirmada inmutable; usar ajustes o reemplazo'; END IF;
     IF NEW.cantidad_cancelada<OLD.cantidad_cancelada THEN RAISE EXCEPTION 'No revertir cancelación histórica'; END IF;
   END IF;
   IF TG_TABLE_NAME='pedido' AND OLD.estado<>'borrador' THEN
     IF NEW.estado='borrador' OR (a-ARRAY['estado','notas_venta','actualizado_en','fecha_actualizacion']) IS DISTINCT FROM
       (b-ARRAY['estado','notas_venta','actualizado_en','fecha_actualizacion']) THEN RAISE EXCEPTION 'Pedido confirmado inmutable'; END IF;
   END IF;
   IF TG_TABLE_NAME='detalle_encargo_costura' AND EXISTS(SELECT 1 FROM bm.detalle_recepcion_costura WHERE detalle_encargo_id=OLD.detalle_encargo_id)
     THEN RAISE EXCEPTION 'Encargo con recepción: no cambiar cantidades ni tarifa'; END IF;
   IF TG_TABLE_NAME='lote_tela' AND EXISTS(SELECT 1 FROM bm.movimiento_tela WHERE lote_tela_id=OLD.lote_tela_id AND tipo='consumo')
     AND (a-ARRAY['notas','actualizado_en']) IS DISTINCT FROM (b-ARRAY['notas','actualizado_en'])
     THEN RAISE EXCEPTION 'Tela ya consumida: costo y origen inmutables'; END IF;
   IF TG_TABLE_NAME IN ('pago_pedido','pago_costurera','reembolso','abono_cuenta_pagar','abono_cuenta_cobrar') AND
     a->>'estado' NOT IN ('pendiente') AND
     ((a-ARRAY['estado','actualizado_en','notas']) IS DISTINCT FROM (b-ARRAY['estado','actualizado_en','notas'])
       OR b->>'estado' NOT IN (a->>'estado','anulado'))
     THEN RAISE EXCEPTION 'Pago registrado: solo se permite anulación documentada'; END IF;
   IF TG_TABLE_NAME='detalle_envio' AND EXISTS(SELECT 1 FROM bm.envio WHERE envio_id=OLD.envio_id AND estado<>'preparando')
     THEN RAISE EXCEPTION 'Despacho realizado inmutable'; END IF;
   IF TG_TABLE_NAME='envio' AND OLD.estado<>'preparando' AND
      ((a-ARRAY['estado','fecha_entrega','notas','actualizado_en']) IS DISTINCT FROM (b-ARRAY['estado','fecha_entrega','notas','actualizado_en'])
       OR NEW.estado IN ('preparando','cancelado')) THEN RAISE EXCEPTION 'Despacho realizado: resolver mediante devolución o incidencia'; END IF;
   IF TG_TABLE_NAME='detalle_entrega' AND EXISTS(SELECT 1 FROM bm.entrega_pedido WHERE entrega_id=OLD.entrega_id AND estado<>'borrador')
     THEN RAISE EXCEPTION 'Entrega confirmada inmutable'; END IF;
   IF TG_TABLE_NAME='entrega_pedido' AND OLD.estado<>'borrador' THEN RAISE EXCEPTION 'Entrega confirmada inmutable'; END IF;
   IF TG_TABLE_NAME='detalle_devolucion' AND EXISTS(SELECT 1 FROM bm.devolucion_pedido WHERE devolucion_id=OLD.devolucion_id AND estado IN ('aprobada','resuelta'))
     THEN RAISE EXCEPTION 'Devolucion aprobada inmutable'; END IF;
   IF TG_TABLE_NAME='devolucion_pedido' AND OLD.estado IN ('aprobada','resuelta') AND
     ((a-ARRAY['estado','actualizado_en']) IS DISTINCT FROM (b-ARRAY['estado','actualizado_en']) OR NEW.estado NOT IN ('aprobada','resuelta'))
     THEN RAISE EXCEPTION 'No reescribir devolución aprobada'; END IF;
   IF TG_TABLE_NAME='tarifa_iva_vigencia' AND EXISTS(SELECT 1 FROM bm.detalle_pedido dp WHERE dp.codigo_tarifa=OLD.codigo_tarifa AND dp.fecha_tributaria BETWEEN OLD.vigente_desde AND coalesce(OLD.vigente_hasta,'infinity'::date))
      AND (NEW.porcentaje<>OLD.porcentaje OR NEW.codigo_tarifa<>OLD.codigo_tarifa OR NEW.vigente_desde<>OLD.vigente_desde)
     THEN RAISE EXCEPTION 'Tarifa utilizada: preservar porcentaje y fecha de inicio'; END IF;
   IF TG_TABLE_NAME='comprobante_venta' AND a->>'estado_sri'='autorizado' AND
      ((a-ARRAY['estado_sri','actualizado_en','notas']) IS DISTINCT FROM (b-ARRAY['estado_sri','actualizado_en','notas']) OR b->>'estado_sri' NOT IN ('autorizado','anulado'))
      THEN RAISE EXCEPTION 'Comprobante autorizado inmutable'; END IF;
   IF TG_TABLE_NAME='periodo_iva' AND a->>'estado'='declarado' THEN RAISE EXCEPTION 'Periodo declarado inmutable'; END IF;
 END IF;
 RETURN NEW;
END $$;

CREATE FUNCTION bm.auditar() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,bm AS $$
BEGIN
 INSERT INTO bm.auditoria(tabla,accion,anterior,nuevo,usuario_id,usuario_sql,operacion_id)
 VALUES(TG_TABLE_NAME,TG_OP,CASE WHEN TG_OP='INSERT' THEN NULL ELSE to_jsonb(OLD) END,
 to_jsonb(NEW),auth.uid(),session_user,nullif(current_setting('bm.operacion_id',true),'')::uuid);
 RETURN NULL;
END $$;

-- Validate classification before deriving taxes. No hard-coded national rate.
ALTER TABLE bm.detalle_pedido ADD CONSTRAINT tratamiento_coherente CHECK (
 (tratamiento_iva='por_definir') OR
 (tratamiento_iva='gravado' AND aplica_iva AND porcentaje_iva>0 AND codigo_tarifa IS NOT NULL) OR
 (tratamiento_iva IN ('tarifa_0','exento','no_objeto') AND porcentaje_iva=0
   AND nullif(trim(motivo_tributario),'') IS NOT NULL
   AND (tratamiento_iva='tarifa_0' OR NOT aplica_iva))
);
ALTER TABLE bm.detalle_devolucion ADD CONSTRAINT no_reingreso_sin_prenda CHECK (NOT reingresa_inventario OR condicion<>'no_recibido');
ALTER TABLE bm.movimiento_producto ADD CONSTRAINT referencia_exclusiva CHECK (
 (tipo='venta' AND detalle_envio_id IS NOT NULL AND detalle_devolucion_id IS NULL) OR
 (tipo='devolucion' AND detalle_devolucion_id IS NOT NULL AND detalle_envio_id IS NULL) OR
 (tipo NOT IN ('venta','devolucion') AND detalle_envio_id IS NULL AND detalle_devolucion_id IS NULL)
);
CREATE UNIQUE INDEX produccion_unica_lote ON bm.movimiento_producto(lote_producto_id) WHERE tipo='produccion';
CREATE UNIQUE INDEX comprobante_numero_unico ON bm.comprobante_venta(tipo_comprobante,numero_comprobante);
ALTER TABLE bm.comprobante_venta ADD CONSTRAINT documento_relacionado_requerido CHECK (
 (tipo_comprobante='factura' AND documento_relacionado_id IS NULL) OR
 (tipo_comprobante<>'factura' AND documento_relacionado_id IS NOT NULL)
);
ALTER TABLE bm.retencion_iva ADD CONSTRAINT retencion_origen CHECK (
 (tipo='emitida' AND compra_id IS NOT NULL AND comprobante_venta_id IS NULL) OR
 (tipo='recibida' AND comprobante_venta_id IS NOT NULL AND compra_id IS NULL)
);
ALTER TABLE bm.credito_iva_compra ADD CONSTRAINT credito_tratamiento CHECK (
 estado<>'aprobado' OR (fecha_revision IS NOT NULL AND
 ((tratamiento='total' AND factor_aplicado=1) OR
 (tratamiento='proporcional' AND factor_aplicado>0 AND factor_aplicado<1) OR
 (tratamiento='no_creditable' AND factor_aplicado=0)))
);

-- VALIDATION_FUNCTION

CREATE FUNCTION bm.comprobar_integridad() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,bm AS $$
BEGIN PERFORM bm.validar_integridad(); RETURN NULL; END $$;

-- The source ledgers are authoritative. Returns reverse cost only on a real movement.
CREATE VIEW bm.v_eventos_margen WITH(security_invoker=true) AS
 SELECT 'venta'::text tipo, e.fecha_envio fecha, e.pedido_id, dp.detalle_pedido_id,
 dp.variante_id, de.lote_producto_id, de.detalle_envio_id,
 de.cantidad*dp.subtotal_linea/dp.cantidad ingreso_sin_iva,
 de.cantidad*lp.costo_total_unitario costo, lp.costo_finalizado
 FROM bm.detalle_envio de JOIN bm.envio e USING(envio_id)
 JOIN bm.detalle_pedido dp USING(detalle_pedido_id) JOIN bm.lote_producto lp USING(lote_producto_id)
 WHERE e.estado IN ('despachado','parcialmente_entregado','entregado','incidencia')
 UNION ALL
 SELECT 'devolucion',d.fecha_resolucion,d.pedido_id,de.detalle_pedido_id,dp.variante_id,
 de.lote_producto_id,de.detalle_envio_id,-dd.credito_subtotal,0,lp.costo_finalizado
 FROM bm.detalle_devolucion dd JOIN bm.devolucion_pedido d USING(devolucion_id)
 JOIN bm.detalle_envio de USING(detalle_envio_id) JOIN bm.detalle_pedido dp USING(detalle_pedido_id)
 JOIN bm.lote_producto lp USING(lote_producto_id) WHERE d.estado IN ('aprobada','resuelta')
 UNION ALL
 SELECT 'reingreso',mp.fecha,d.pedido_id,de.detalle_pedido_id,dp.variante_id,
 mp.lote_producto_id,de.detalle_envio_id,0,-mp.cantidad_delta*lp.costo_total_unitario,lp.costo_finalizado
 FROM bm.movimiento_producto mp JOIN bm.detalle_devolucion dd USING(detalle_devolucion_id)
 JOIN bm.devolucion_pedido d USING(devolucion_id) JOIN bm.detalle_envio de ON de.detalle_envio_id=dd.detalle_envio_id
 JOIN bm.detalle_pedido dp USING(detalle_pedido_id) JOIN bm.lote_producto lp ON lp.lote_producto_id=mp.lote_producto_id
 WHERE mp.tipo='devolucion' AND d.estado IN ('aprobada','resuelta')
 UNION ALL
 SELECT 'ajuste',a.fecha,a.pedido_id,a.detalle_pedido_id,dp.variante_id,NULL::bigint,NULL::bigint,
 a.monto_subtotal,0,true
 FROM bm.ajuste_pedido a JOIN bm.detalle_pedido dp USING(detalle_pedido_id)
 -- A post-sale concession is recognized once at its own date, not redistributed
 -- over shipments later. Pre-sale negotiated prices belong on the draft line.
 WHERE a.destino='prenda' AND a.clase<>'cancelacion';

CREATE VIEW bm.v_margen_detalle_envio WITH(security_invoker=true) AS
 SELECT detalle_envio_id,pedido_id,detalle_pedido_id,variante_id,lote_producto_id,fecha,
 round(ingreso_sin_iva,2) ingreso_sin_iva, round(costo,2) costo_fabricacion,
 round(ingreso_sin_iva-costo,2) margen_bruto_predevoluciones,costo_finalizado
 FROM bm.v_eventos_margen WHERE tipo='venta';
CREATE VIEW bm.v_margen_neto_articulo WITH(security_invoker=true) AS
 SELECT pedido_id,detalle_pedido_id,variante_id,round(sum(ingreso_sin_iva),2) ingreso_neto_sin_iva,
 round(sum(costo),2) costo_neto_producto,round(sum(ingreso_sin_iva-costo),2) margen_neto_sin_envio,
 bool_and(costo_finalizado) costo_finalizado FROM bm.v_eventos_margen GROUP BY pedido_id,detalle_pedido_id,variante_id;
CREATE VIEW bm.v_margen_diario WITH(security_invoker=true) AS
 SELECT (fecha AT TIME ZONE 'America/Guayaquil')::date dia,
 round(sum(ingreso_sin_iva),2) ingreso_sin_iva,round(sum(costo),2) costo,
 round(sum(ingreso_sin_iva-costo),2) margen_prendas,bool_and(costo_finalizado) costo_finalizado
 FROM bm.v_eventos_margen GROUP BY 1;
CREATE VIEW bm.v_caja_diaria WITH(security_invoker=true) AS
 SELECT dia,sum(entrada) entradas,sum(salida) salidas,sum(entrada-salida) flujo_neto FROM (
 SELECT (fecha_pago AT TIME ZONE 'America/Guayaquil')::date dia,monto entrada,0::numeric salida FROM bm.pago_pedido WHERE estado='confirmado'
 UNION ALL SELECT (fecha_reembolso AT TIME ZONE 'America/Guayaquil')::date,0,monto FROM bm.reembolso WHERE estado='completado'
 UNION ALL SELECT (fecha_pago AT TIME ZONE 'America/Guayaquil')::date,0,monto FROM bm.pago_costurera WHERE estado='confirmado'
 UNION ALL SELECT fecha_pago,0,monto FROM bm.abono_cuenta_pagar WHERE estado='confirmado'
 UNION ALL SELECT fecha_cobro,monto,0 FROM bm.abono_cuenta_cobrar WHERE estado='confirmado') eventos GROUP BY dia;

CREATE VIEW bm.v_resultado_operativo_diario WITH(security_invoker=true) AS
 SELECT dia,round(sum(margen),2) margen_prendas,round(sum(envio),2) resultado_envios,
 round(sum(gasto),2) gastos_generales_y_mermas,round(sum(margen+envio-gasto),2) resultado_operativo,
 bool_and(definitivo) costos_finalizados FROM (
 SELECT dia,margen_prendas margen,0::numeric envio,0::numeric gasto,costo_finalizado definitivo FROM bm.v_margen_diario
 UNION ALL SELECT (fecha_confirmacion AT TIME ZONE 'America/Guayaquil')::date,0,costo_envio_cobrado,0,true FROM bm.pedido WHERE estado NOT IN ('borrador','cancelado')
 UNION ALL SELECT (fecha_envio AT TIME ZONE 'America/Guayaquil')::date,0,-costo_real_transportadora,0,true FROM bm.envio WHERE estado IN ('despachado','parcialmente_entregado','entregado','incidencia')
 UNION ALL SELECT (fecha AT TIME ZONE 'America/Guayaquil')::date,0,monto_subtotal,0,true FROM bm.ajuste_pedido WHERE destino='envio'
 UNION ALL SELECT (g.fecha_gasto AT TIME ZONE 'America/Guayaquil')::date,0,0,g.costo_total-coalesce((SELECT sum(a.monto_asignado) FROM bm.asignacion_gasto_produccion a WHERE a.gasto_id=g.gasto_id),0),true FROM bm.gasto g
 UNION ALL SELECT (m.fecha AT TIME ZONE 'America/Guayaquil')::date,0,0,-m.cantidad_delta*l.costo_total_unitario,l.costo_finalizado FROM bm.movimiento_producto m JOIN bm.lote_producto l USING(lote_producto_id) WHERE m.tipo IN ('merma','ajuste_negativo')
 UNION ALL SELECT (m.fecha AT TIME ZONE 'America/Guayaquil')::date,0,0,m.metros*l.costo_metro,true FROM bm.movimiento_tela m JOIN bm.lote_tela l USING(lote_tela_id) WHERE m.tipo IN ('merma','ajuste_salida')
 ) e GROUP BY dia;

-- All inserts and updates are grouped in one idempotent transaction via this gateway.
-- Table and column names come from pg_catalog and a closed allowlist, never raw SQL.
CREATE FUNCTION bm.registrar_operacion(p_id uuid,p_acciones jsonb,p_motivo text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,bm AS $$
DECLARE rol_usuario text; existente bm.operacion; accion jsonb; datos jsonb; tabla text; clave text;
 columnas text; valores text; asignacion text; resultado jsonb; resultados jsonb:='[]'; refs jsonb:='{}';
 k text; v jsonb; ref text; destino bigint;
BEGIN
 SELECT rol INTO rol_usuario FROM bm.usuario_bm WHERE usuario_id=auth.uid() AND activo;
 IF auth.uid() IS NULL OR rol_usuario IS NULL OR rol_usuario='consulta' THEN RAISE EXCEPTION 'Acceso de escritura no autorizado' USING ERRCODE='42501'; END IF;
 IF p_id IS NULL OR p_motivo IS NULL OR length(trim(p_motivo))<3 OR jsonb_typeof(p_acciones)<>'array'
 OR jsonb_array_length(p_acciones) NOT BETWEEN 1 AND 250 THEN RAISE EXCEPTION 'Operacion, motivo y 1..250 acciones requeridos'; END IF;
 UPDATE bm.control_escritura SET revision=revision+1 WHERE id;
 SELECT * INTO existente FROM bm.operacion WHERE operacion_id=p_id;
 IF FOUND THEN
   IF existente.usuario_id<>auth.uid() OR existente.solicitud<>p_acciones OR existente.motivo<>p_motivo THEN RAISE EXCEPTION 'Identificador ya utilizado con otros datos'; END IF;
   RETURN existente.respuesta;
 END IF;
 INSERT INTO bm.operacion(operacion_id,usuario_id,solicitud,motivo) VALUES(p_id,auth.uid(),p_acciones,p_motivo);
 PERFORM set_config('bm.operacion_id',p_id::text,true);
 FOR accion IN SELECT value FROM jsonb_array_elements(p_acciones) LOOP
   tabla:=accion->>'tabla'; clave:=NULL;
   SELECT r.clave INTO clave FROM bm.recurso r WHERE r.tabla=accion->>'tabla';
   IF clave IS NULL THEN RAISE EXCEPTION 'Recurso no permitido: %',tabla; END IF;
   IF tabla IN ('tarifa_iva_vigencia','configuracion_tributaria','periodo_iva','credito_iva_compra','comprobante_venta','retencion_iva') AND rol_usuario<>'administrador'
     THEN RAISE EXCEPTION 'Requiere administrador'; END IF;
   datos:=accion->'datos';
   IF jsonb_typeof(datos)<>'object' OR datos='{}'::jsonb THEN RAISE EXCEPTION 'Datos vacios o invalidos'; END IF;
   FOR k,v IN SELECT * FROM jsonb_each(datos) LOOP
     IF jsonb_typeof(v)='object' AND v ? '$ref' THEN
       ref:=v->>'$ref'; IF NOT refs ? ref THEN RAISE EXCEPTION 'Referencia desconocida: %',ref; END IF;
       datos:=jsonb_set(datos,ARRAY[k],refs->ref);
     END IF;
     IF k IN (clave,'registrado_en','registrado_por','actualizado_en') OR NOT EXISTS(
       SELECT 1 FROM pg_attribute WHERE attrelid=format('bm.%I',tabla)::regclass AND attname=k
       AND attnum>0 AND NOT attisdropped AND attgenerated='' AND attidentity='')
       THEN RAISE EXCEPTION 'Columna no editable: %.%',tabla,k; END IF;
   END LOOP;
   SELECT string_agg(format('%I',key),',' ORDER BY key),
     string_agg(format('x.%I',key),',' ORDER BY key),
     string_agg(format('%I=x.%I',key,key),',' ORDER BY key)
   INTO columnas,valores,asignacion FROM jsonb_object_keys(datos) key;
   IF accion->>'accion'='insertar' THEN
     EXECUTE format('INSERT INTO bm.%I (%s) SELECT %s FROM jsonb_populate_record(NULL::bm.%I,$1) x RETURNING to_jsonb(%I.*)',tabla,columnas,valores,tabla,tabla)
       INTO resultado USING datos;
   ELSIF accion->>'accion'='actualizar' THEN
     destino:=CASE WHEN jsonb_typeof(accion->'id')='object' THEN (refs->>(accion->'id'->>'$ref'))::bigint ELSE (accion->>'id')::bigint END;
     EXECUTE format('UPDATE bm.%I t SET %s FROM jsonb_populate_record(NULL::bm.%I,$1) x WHERE t.%I=$2 RETURNING to_jsonb(t.*)',tabla,asignacion,tabla,clave)
       INTO resultado USING datos,destino;
     IF resultado IS NULL THEN RAISE EXCEPTION 'Registro no encontrado'; END IF;
   ELSE RAISE EXCEPTION 'Accion no permitida'; END IF;
   IF accion ? 'ref' THEN
     IF refs ? (accion->>'ref') THEN RAISE EXCEPTION 'Alias duplicado'; END IF;
     refs:=jsonb_set(refs,ARRAY[accion->>'ref'],resultado->clave);
   END IF;
   resultados:=resultados||jsonb_build_array(resultado);
 END LOOP;
 PERFORM bm.validar_integridad();
 UPDATE bm.operacion SET respuesta=resultados WHERE operacion_id=p_id;
 RETURN resultados;
END $$;
CREATE FUNCTION public.bm_registrar_operacion(p_id uuid,p_acciones jsonb,p_motivo text) RETURNS jsonb
LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS $$ SELECT bm.registrar_operacion(p_id,p_acciones,p_motivo) $$;

-- GENERATED_SETUP

-- Add missing leading-column FK indexes without duplicating existing indexes.
DO $$ DECLARE r record; BEGIN
 FOR r IN SELECT c.conrelid::regclass AS rel,c.conname,a.attname FROM pg_constraint c
 JOIN pg_attribute a ON a.attrelid=c.conrelid AND a.attnum=c.conkey[1]
 WHERE c.contype='f' AND c.connamespace='bm'::regnamespace AND NOT EXISTS
 (SELECT 1 FROM pg_index i WHERE i.indrelid=c.conrelid AND i.indkey[0]=c.conkey[1])
 LOOP EXECUTE format('CREATE INDEX %I ON %s (%I)','fk_'||r.conname,r.rel,r.attname); END LOOP;
END $$;
REVOKE ALL ON SCHEMA bm FROM PUBLIC,anon,authenticated;
REVOKE ALL ON ALL TABLES IN SCHEMA bm FROM PUBLIC,anon,authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA bm FROM PUBLIC,anon,authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA bm FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.bm_registrar_operacion(uuid,jsonb,text) FROM PUBLIC,anon;
GRANT USAGE ON SCHEMA bm TO authenticated;
GRANT EXECUTE ON FUNCTION bm.puede_leer(),bm.registrar_operacion(uuid,jsonb,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bm_registrar_operacion(uuid,jsonb,text) TO authenticated;
DO $$ DECLARE r record; BEGIN
 FOR r IN SELECT tablename FROM pg_tables WHERE schemaname='bm' LOOP
   EXECUTE format('ALTER TABLE bm.%I ENABLE ROW LEVEL SECURITY',r.tablename);
 END LOOP;
 FOR r IN SELECT tabla FROM bm.recurso LOOP EXECUTE format('GRANT SELECT ON bm.%I TO authenticated',r.tabla); END LOOP;
 FOR r IN SELECT viewname FROM pg_views WHERE schemaname='bm' LOOP
   EXECUTE format('ALTER VIEW bm.%I SET (security_invoker=true)',r.viewname);
   EXECUTE format('GRANT SELECT ON bm.%I TO authenticated',r.viewname);
 END LOOP;
END $$;
ALTER DEFAULT PRIVILEGES IN SCHEMA bm REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
RESET search_path;


