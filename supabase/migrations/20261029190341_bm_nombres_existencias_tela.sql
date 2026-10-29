-- Append the fabric name without changing the existing columns or stock calculation.
CREATE OR REPLACE VIEW bm.v_existencia_tela WITH (security_invoker=true) AS
SELECT lt.lote_tela_id, lt.tela_id, ut.ubicacion_id, ut.nombre AS ubicacion,
 COALESCE(SUM(
   CASE WHEN mt.destino_ubicacion_id=ut.ubicacion_id THEN mt.metros ELSE 0 END
   - CASE WHEN mt.origen_ubicacion_id=ut.ubicacion_id THEN mt.metros ELSE 0 END
 ),0)::numeric(14,3) AS metros_disponibles,
 t.nombre AS tela_nombre
FROM bm.lote_tela lt
JOIN bm.tela t ON t.tela_id=lt.tela_id
CROSS JOIN bm.ubicacion_tela ut
LEFT JOIN bm.movimiento_tela mt ON mt.lote_tela_id=lt.lote_tela_id
 AND (mt.origen_ubicacion_id=ut.ubicacion_id OR mt.destino_ubicacion_id=ut.ubicacion_id)
GROUP BY lt.lote_tela_id,lt.tela_id,ut.ubicacion_id,ut.nombre,t.nombre;
