-- Add optimistic checks to the existing authorized, audited, idempotent gateway.
-- No new functions, permissions or changes to existing business records.
CREATE OR REPLACE FUNCTION bm.registrar_operacion(p_id uuid,p_acciones jsonb,p_motivo text) RETURNS jsonb
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
     -- Compare the reviewed values under the same writer lock as the transaction.
     -- A second device must review again instead of overwriting a newer invoice total.
     IF accion ? 'esperado' THEN
       IF jsonb_typeof(accion->'esperado') IS DISTINCT FROM 'object' OR accion->'esperado'='{}'::jsonb THEN
         RAISE EXCEPTION 'Valores esperados invalidos';
       END IF;
       EXECUTE format('SELECT to_jsonb(t.*) FROM bm.%I t WHERE t.%I=$1 FOR UPDATE',tabla,clave)
         INTO resultado USING destino;
       IF resultado IS NULL OR NOT (resultado @> (accion->'esperado')) THEN
         RAISE EXCEPTION 'La compra cambió desde la revisión. Pulsa Corregir y vuelve a revisar antes de guardar.' USING ERRCODE='40001';
       END IF;
     END IF;
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
 -- Drain only bM integrity triggers while still inside this authorized gateway.
 -- Deferred triggers otherwise run after returning to the API's restricted role.
 SET CONSTRAINTS bm.z_integridad IMMEDIATE;
 -- Subsequent operations in the same transaction must remain atomic batches.
 SET CONSTRAINTS bm.z_integridad DEFERRED;
 UPDATE bm.operacion SET respuesta=resultados WHERE operacion_id=p_id;
 RETURN resultados;
END $$;
