-- Private application API. The bm schema stays unexposed to PostgREST.
ALTER TABLE bm.usuario_bm ADD COLUMN nombre text NOT NULL DEFAULT 'Usuario';

CREATE FUNCTION bm.perfil() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,bm AS $$
DECLARE r bm.usuario_bm;
BEGIN
 SELECT * INTO r FROM bm.usuario_bm WHERE usuario_id=auth.uid() AND activo;
 IF NOT FOUND THEN RAISE EXCEPTION 'Tu cuenta no tiene acceso al inventario. Contacta al administrador.' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object('id',r.usuario_id,'nombre',r.nombre,'rol',r.rol);
END $$;

CREATE FUNCTION bm.datos(p_tabla text,p_limite integer DEFAULT 50,p_offset integer DEFAULT 0,p_buscar text DEFAULT '',p_filtros jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,bm AS $$
DECLARE res jsonb; total bigint; admin boolean; col text;
BEGIN
 PERFORM bm.perfil();
 SELECT rol='administrador' INTO admin FROM bm.usuario_bm WHERE usuario_id=auth.uid();
 IF NOT EXISTS(SELECT 1 FROM bm.recurso WHERE tabla=p_tabla) AND NOT EXISTS(SELECT 1 FROM pg_views WHERE schemaname='bm' AND viewname=p_tabla)
    AND NOT (admin AND p_tabla IN ('auditoria','periodo_cerrado')) THEN RAISE EXCEPTION 'Consulta no permitida' USING ERRCODE='42501'; END IF;
 IF p_limite NOT BETWEEN 1 AND 200 OR p_offset NOT BETWEEN 0 AND 1000000 OR jsonb_typeof(p_filtros)<>'object' OR length(p_buscar)>200 THEN RAISE EXCEPTION 'Consulta inválida'; END IF;
 FOR col IN SELECT jsonb_object_keys(p_filtros) LOOP
   IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=format('bm.%I',p_tabla)::regclass AND attname=col AND attnum>0 AND NOT attisdropped) THEN RAISE EXCEPTION 'Filtro inválido'; END IF;
 END LOOP;
 EXECUTE format('SELECT count(*) FROM bm.%I t WHERE ($1='''' OR to_jsonb(t)::text ILIKE ''%%''||$1||''%%'') AND NOT EXISTS(SELECT 1 FROM jsonb_each_text($2) f WHERE to_jsonb(t)->>f.key IS DISTINCT FROM f.value)',p_tabla) INTO total USING p_buscar,p_filtros;
 EXECUTE format('SELECT coalesce(jsonb_agg(row),''[]''::jsonb) FROM (SELECT to_jsonb(t) row FROM bm.%I t WHERE ($1='''' OR to_jsonb(t)::text ILIKE ''%%''||$1||''%%'') AND NOT EXISTS(SELECT 1 FROM jsonb_each_text($2) f WHERE to_jsonb(t)->>f.key IS DISTINCT FROM f.value) ORDER BY to_jsonb(t)->>''registrado_en'' DESC NULLS LAST,to_jsonb(t)::text LIMIT $3 OFFSET $4) s',p_tabla)
 INTO res USING p_buscar,p_filtros,p_limite,p_offset;
 RETURN jsonb_build_object('rows',res,'total',total);
END $$;

CREATE FUNCTION bm.panel(p_desde date,p_hasta date) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,bm AS $$
DECLARE res jsonb;
BEGIN
 PERFORM bm.perfil();
 IF p_desde IS NULL OR p_hasta IS NULL OR p_hasta<p_desde OR p_hasta-p_desde>3660 THEN RAISE EXCEPTION 'Selecciona un período válido de hasta diez años'; END IF;
 SELECT jsonb_build_object(
 'serie',coalesce((SELECT jsonb_agg(x ORDER BY dia) FROM (
 SELECT d::date dia,coalesce(m.ingreso_sin_iva,0) ventas,coalesce(m.costo,0) costos,
 coalesce(r.resultado_operativo,0) resultado,coalesce(r.margen_prendas,0) margen,
 coalesce(r.gastos_generales_y_mermas,0) gastos,coalesce(c.entradas,0) cobros,coalesce(c.salidas,0) pagos,
 coalesce(r.costos_finalizados,true) definitivo
 FROM generate_series(p_desde::timestamp,p_hasta::timestamp,'1 day') d
 LEFT JOIN bm.v_margen_diario m ON m.dia=d::date
 LEFT JOIN bm.v_resultado_operativo_diario r ON r.dia=d::date
 LEFT JOIN bm.v_caja_diaria c ON c.dia=d::date) x),'[]'::jsonb),
 'stock',coalesce((SELECT sum(stock_disponible) FROM bm.v_stock_variante),0),
 'reservadas',coalesce((SELECT sum(stock_reservado) FROM bm.v_stock_variante),0),
 'por_cobrar',coalesce((SELECT sum(greatest(saldo_pendiente,0)) FROM bm.v_saldo_pedido WHERE estado NOT IN ('borrador','cancelado')),0),
 'produccion', (SELECT count(*) FROM bm.encargo_costura WHERE estado IN ('pendiente','en_proceso','parcial')),
 'pedidos', (SELECT count(*) FROM bm.pedido WHERE estado NOT IN ('borrador','cancelado') AND (fecha_pedido AT TIME ZONE 'America/Guayaquil')::date BETWEEN p_desde AND p_hasta),
 'unidades',coalesce((SELECT sum(de.cantidad) FROM bm.detalle_envio de JOIN bm.envio e USING(envio_id) WHERE e.estado IN ('despachado','parcialmente_entregado','entregado','incidencia') AND (e.fecha_envio AT TIME ZONE 'America/Guayaquil')::date BETWEEN p_desde AND p_hasta),0),
 'productos',coalesce((SELECT jsonb_agg(x) FROM (SELECT a.nombre,c.nombre color,t.nombre talla,v.sku,round(sum(e.ingreso_sin_iva),2) ventas,round(sum(e.ingreso_sin_iva-e.costo),2) margen,bool_and(e.costo_finalizado) definitivo FROM bm.v_eventos_margen e JOIN bm.variante_articulo v USING(variante_id) JOIN bm.articulo a USING(articulo_id) JOIN bm.color c USING(color_id) JOIN bm.talla t USING(talla_id) WHERE (e.fecha AT TIME ZONE 'America/Guayaquil')::date BETWEEN p_desde AND p_hasta GROUP BY a.nombre,c.nombre,t.nombre,v.sku ORDER BY sum(e.ingreso_sin_iva) DESC LIMIT 20) x),'[]'::jsonb)
 ) INTO res;
 RETURN res;
END $$;

CREATE FUNCTION bm.usuarios() RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,bm AS $$
BEGIN
 IF (bm.perfil()->>'rol')<>'administrador' THEN RAISE EXCEPTION 'Requiere administrador' USING ERRCODE='42501'; END IF;
 RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id',b.usuario_id,'nombre',b.nombre,'rol',b.rol,'activo',b.activo,'email',u.email)),'[]') FROM bm.usuario_bm b JOIN auth.users u ON u.id=b.usuario_id);
END $$;
CREATE FUNCTION bm.gestionar_usuario(p_usuario uuid,p_nombre text,p_rol text,p_activo boolean) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,bm AS $$
BEGIN
 IF (bm.perfil()->>'rol')<>'administrador' THEN RAISE EXCEPTION 'Requiere administrador' USING ERRCODE='42501'; END IF;
 UPDATE bm.control_escritura SET revision=revision+1 WHERE id;
 IF length(trim(p_nombre)) NOT BETWEEN 1 AND 100 OR p_rol NOT IN ('administrador','operador','consulta') OR p_activo IS NULL THEN RAISE EXCEPTION 'Datos de usuario inválidos'; END IF;
 IF p_usuario=auth.uid() AND (p_rol<>'administrador' OR NOT p_activo) THEN RAISE EXCEPTION 'No puedes quitar tu propio acceso de administrador'; END IF;
 INSERT INTO bm.usuario_bm(usuario_id,nombre,rol,activo) VALUES(p_usuario,trim(p_nombre),p_rol,p_activo)
 ON CONFLICT(usuario_id) DO UPDATE SET nombre=excluded.nombre,rol=excluded.rol,activo=excluded.activo;
 INSERT INTO bm.auditoria(tabla,accion,nuevo,usuario_id,usuario_sql) VALUES('usuario_bm','ACCESO',jsonb_build_object('usuario',p_usuario,'nombre',p_nombre,'rol',p_rol,'activo',p_activo),auth.uid(),session_user);
END $$;
CREATE FUNCTION bm.cerrar_periodo(p_desde date,p_hasta date,p_motivo text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,bm AS $$
BEGIN
 IF (bm.perfil()->>'rol')<>'administrador' THEN RAISE EXCEPTION 'Requiere administrador' USING ERRCODE='42501'; END IF;
 UPDATE bm.control_escritura SET revision=revision+1 WHERE id;
 IF p_hasta<p_desde OR p_desde IS NULL OR p_hasta IS NULL OR p_hasta>=(now() AT TIME ZONE 'America/Guayaquil')::date OR length(trim(p_motivo))<5 THEN RAISE EXCEPTION 'Revisa fechas y motivo del cierre'; END IF;
 INSERT INTO bm.periodo_cerrado(desde,hasta,motivo) VALUES(p_desde,p_hasta,p_motivo);
 INSERT INTO bm.auditoria(tabla,accion,nuevo,usuario_id,usuario_sql) VALUES('periodo_cerrado','CIERRE',jsonb_build_object('desde',p_desde,'hasta',p_hasta,'motivo',p_motivo),auth.uid(),session_user);
END $$;

CREATE FUNCTION public.bm_perfil() RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS $$ SELECT bm.perfil() $$;
CREATE FUNCTION public.bm_datos(p_tabla text,p_limite integer DEFAULT 50,p_offset integer DEFAULT 0,p_buscar text DEFAULT '',p_filtros jsonb DEFAULT '{}') RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS $$ SELECT bm.datos(p_tabla,p_limite,p_offset,p_buscar,p_filtros) $$;
CREATE FUNCTION public.bm_panel(p_desde date,p_hasta date) RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS $$ SELECT bm.panel(p_desde,p_hasta) $$;
CREATE FUNCTION public.bm_usuarios() RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS $$ SELECT bm.usuarios() $$;
CREATE FUNCTION public.bm_gestionar_usuario(p_usuario uuid,p_nombre text,p_rol text,p_activo boolean) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS $$ SELECT bm.gestionar_usuario(p_usuario,p_nombre,p_rol,p_activo) $$;
CREATE FUNCTION public.bm_cerrar_periodo(p_desde date,p_hasta date,p_motivo text) RETURNS void LANGUAGE sql SECURITY INVOKER SET search_path=pg_catalog AS $$ SELECT bm.cerrar_periodo(p_desde,p_hasta,p_motivo) $$;
DO $$ DECLARE r record; BEGIN
 FOR r IN SELECT p.oid::regprocedure sig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE (n.nspname='bm' AND p.proname IN ('perfil','datos','panel','usuarios','gestionar_usuario','cerrar_periodo')) OR (n.nspname='public' AND p.proname IN ('bm_perfil','bm_datos','bm_panel','bm_usuarios','bm_gestionar_usuario','bm_cerrar_periodo')) LOOP
 EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon',r.sig);
 EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',r.sig);
 END LOOP;
END $$;
NOTIFY pgrst,'reload schema';
