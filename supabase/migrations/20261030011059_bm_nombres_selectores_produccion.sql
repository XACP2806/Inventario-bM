-- Read-only labels for production selectors; no changes to business records or permissions.
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

 -- Labels are derived only for these two resources. Keep their original IDs and fields.
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
      co.nombre_completo,'Encargo '||d.encargo_id,'Prenda '||d.detalle_encargo_id)) AS fila
    FROM bm.detalle_encargo_costura d
    JOIN bm.variante_articulo v USING(variante_id)
    JOIN bm.articulo a USING(articulo_id)
    JOIN bm.color c USING(color_id)
    JOIN bm.talla ta USING(talla_id)
    JOIN bm.encargo_costura e USING(encargo_id)
    JOIN bm.costurera co USING(costurera_id)
   $query$;
 END IF;
 -- Search/count before pagination so names remain searchable across all pages.
 EXECUTE format('SELECT count(*) FROM (%s) t WHERE ($1='''' OR fila::text ILIKE ''%%''||$1||''%%'') AND NOT EXISTS(SELECT 1 FROM jsonb_each_text($2) f WHERE fila->>f.key IS DISTINCT FROM f.value)',fuente)
 INTO total USING p_buscar,p_filtros;
 EXECUTE format('SELECT coalesce(jsonb_agg(fila),''[]''::jsonb) FROM (SELECT fila FROM (%s) t WHERE ($1='''' OR fila::text ILIKE ''%%''||$1||''%%'') AND NOT EXISTS(SELECT 1 FROM jsonb_each_text($2) f WHERE fila->>f.key IS DISTINCT FROM f.value) ORDER BY fila->>''registrado_en'' DESC NULLS LAST,fila::text LIMIT $3 OFFSET $4) s',fuente)
 INTO res USING p_buscar,p_filtros,p_limite,p_offset;
 RETURN jsonb_build_object('rows',res,'total',total);
END $$;

