-- Customer names in all six sales summaries; existing calculations and authorization stay intact.
CREATE OR REPLACE FUNCTION bm.datos(p_tabla text,p_limite integer DEFAULT 50,p_offset integer DEFAULT 0,p_buscar text DEFAULT '',p_filtros jsonb DEFAULT '{}') RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,bm AS $$
DECLARE res jsonb; total bigint; admin boolean; col text; fuente text;
BEGIN
 PERFORM bm.perfil();
 SELECT rol='administrador' INTO admin FROM bm.usuario_bm WHERE usuario_id=auth.uid();
 IF NOT EXISTS(SELECT 1 FROM bm.recurso WHERE tabla=p_tabla) AND NOT EXISTS(SELECT 1 FROM pg_views WHERE schemaname='bm' AND viewname=p_tabla)
    AND NOT (admin AND p_tabla IN ('auditoria','periodo_cerrado')) THEN RAISE EXCEPTION 'Consulta no permitida' USING ERRCODE='42501'; END IF;
 IF p_limite NOT BETWEEN 1 AND 200 OR p_offset NOT BETWEEN 0 AND 1000000 OR jsonb_typeof(p_filtros)<>'object' OR length(p_buscar)>200 THEN RAISE EXCEPTION 'Consulta inválida'; END IF;
 FOR col IN SELECT jsonb_object_keys(p_filtros) LOOP
   IF NOT EXISTS(SELECT 1 FROM pg_attribute WHERE attrelid=format('bm.%I',p_tabla)::regclass AND attname=col AND attnum>0 AND NOT attisdropped) THEN RAISE EXCEPTION 'Filtro inválido'; END IF;
 END LOOP;

 -- Enrich only the explicitly listed resources, preserving their original IDs and fields.
 -- The existing membership check and resource/filter allowlists above still apply.
 fuente:=format('SELECT to_jsonb(t) AS fila FROM bm.%I t',p_tabla);
 IF p_tabla='lote_tela' THEN
   fuente:=$query$
    SELECT to_jsonb(l)||jsonb_build_object('_etiqueta',concat_ws(' · ',t.nombre,'Lote '||l.lote_tela_id)) AS fila
    FROM bm.lote_tela l JOIN bm.tela t USING(tela_id)
   $query$;
 ELSIF p_tabla='detalle_encargo_costura' THEN
   fuente:=$query$
    SELECT to_jsonb(d)||jsonb_build_object('_etiqueta',concat_ws(' · ',a.nombre,c.nombre,'Talla '||ta.nombre,
      co.nombre_completo,'Encargo '||d.encargo_id,'Prenda '||d.detalle_encargo_id),
      '_prenda',concat_ws(' · ',a.nombre,c.nombre,'Talla '||ta.nombre),
      '_taller',co.nombre_completo,'_estado_encargo',e.estado,
      '_recibidas',coalesce(r.recibidas,0),'_aceptadas',coalesce(r.aceptadas,0),'_rechazadas',coalesce(r.rechazadas,0),
      '_pendientes_recibir',greatest(d.cantidad_solicitada-coalesce(r.recibidas,0),0),
      '_recepcion',CASE WHEN e.estado='cancelado' THEN 'Cancelado'
        WHEN coalesce(r.recibidas,0)=0 THEN 'Pendiente'
        WHEN r.recibidas<d.cantidad_solicitada THEN CASE WHEN r.rechazadas>0 THEN 'Parcial con rechazos' ELSE 'Parcial' END
        WHEN r.rechazadas>0 THEN 'Recibido con rechazos' ELSE 'Recibido' END) AS fila
    FROM bm.detalle_encargo_costura d
    JOIN bm.variante_articulo v USING(variante_id)
    JOIN bm.articulo a USING(articulo_id)
    JOIN bm.color c USING(color_id)
    JOIN bm.talla ta USING(talla_id)
    JOIN bm.encargo_costura e USING(encargo_id)
    JOIN bm.costurera co USING(costurera_id)
    LEFT JOIN LATERAL (SELECT sum(cantidad_recibida) recibidas,sum(cantidad_aceptada) aceptadas,sum(cantidad_rechazada) rechazadas FROM bm.detalle_recepcion_costura r WHERE r.detalle_encargo_id=d.detalle_encargo_id) r ON true
   $query$;
 ELSIF p_tabla IN ('v_saldo_pedido','v_pedidos_por_entregar','v_pedidos_entregados','v_cumplimiento_detalle_pedido','v_estado_entrega_pedido','v_estado_cuenta_pedido') THEN
   fuente:=format($query$
    SELECT to_jsonb(t)||jsonb_build_object('_cliente',c.nombre_completo) AS fila
    FROM bm.%I t
    LEFT JOIN bm.pedido p ON p.pedido_id=t.pedido_id
    LEFT JOIN bm.cliente c ON c.cliente_id=p.cliente_id
   $query$,p_tabla);
 END IF;
 -- Search/count before pagination so names remain searchable across all pages.
 EXECUTE format('SELECT count(*) FROM (%s) t WHERE ($1='''' OR fila::text ILIKE ''%%''||$1||''%%'') AND NOT EXISTS(SELECT 1 FROM jsonb_each_text($2) f WHERE fila->>f.key IS DISTINCT FROM f.value)',fuente)
 INTO total USING p_buscar,p_filtros;
 EXECUTE format('SELECT coalesce(jsonb_agg(fila),''[]''::jsonb) FROM (SELECT fila FROM (%s) t WHERE ($1='''' OR fila::text ILIKE ''%%''||$1||''%%'') AND NOT EXISTS(SELECT 1 FROM jsonb_each_text($2) f WHERE fila->>f.key IS DISTINCT FROM f.value) ORDER BY fila->>''registrado_en'' DESC NULLS LAST,fila::text LIMIT $3 OFFSET $4) s',fuente)
 INTO res USING p_buscar,p_filtros,p_limite,p_offset;
 RETURN jsonb_build_object('rows',res,'total',total);
END $$;

