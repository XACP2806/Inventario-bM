-- A gift paid directly to a supplier settles the obligation but never moves bM cash.
-- Existing payments retain their original meaning. Audit and immutability triggers
-- already protect every column of confirmed payments, including these new fields.
ALTER TABLE bm.abono_cuenta_pagar
 ADD COLUMN origen_fondos text NOT NULL DEFAULT 'bm' CHECK (origen_fondos IN ('bm','regalo_tercero')),
 ADD COLUMN pagador_nombre varchar(180),
 ADD CONSTRAINT abono_pagador_coherente CHECK (
  (origen_fondos='bm' AND pagador_nombre IS NULL) OR
  (origen_fondos='regalo_tercero' AND nullif(btrim(pagador_nombre),'') IS NOT NULL));
ALTER TABLE bm.pago_costurera
 ADD COLUMN origen_fondos text NOT NULL DEFAULT 'bm' CHECK (origen_fondos IN ('bm','regalo_tercero')),
 ADD COLUMN pagador_nombre varchar(180),
 ADD CONSTRAINT costura_pagador_coherente CHECK (
  (origen_fondos='bm' AND pagador_nombre IS NULL) OR
  (origen_fondos='regalo_tercero' AND nullif(btrim(pagador_nombre),'') IS NOT NULL));

CREATE OR REPLACE VIEW bm.v_caja_diaria WITH(security_invoker=true) AS
 SELECT dia,sum(entrada) entradas,sum(salida) salidas,sum(entrada-salida) flujo_neto FROM (
 SELECT (fecha_pago AT TIME ZONE 'America/Guayaquil')::date dia,monto entrada,0::numeric salida FROM bm.pago_pedido WHERE estado='confirmado'
 UNION ALL SELECT (fecha_reembolso AT TIME ZONE 'America/Guayaquil')::date,0,monto FROM bm.reembolso WHERE estado='completado'
 UNION ALL SELECT (fecha_pago AT TIME ZONE 'America/Guayaquil')::date,0,monto FROM bm.pago_costurera WHERE estado='confirmado' AND origen_fondos='bm'
 UNION ALL SELECT fecha_pago,0,monto FROM bm.abono_cuenta_pagar WHERE estado='confirmado' AND origen_fondos='bm'
 UNION ALL SELECT fecha_cobro,monto,0 FROM bm.abono_cuenta_cobrar WHERE estado='confirmado') eventos GROUP BY dia;

CREATE VIEW bm.v_pagos_regalados WITH(security_invoker=true) AS
 SELECT a.fecha_pago fecha,a.pagador_nombre,'compra_o_deuda'::text destino,a.monto,
 a.cuenta_pagar_id,NULL::bigint encargo_id,a.abono_id pago_id,a.referencia,a.notas,a.registrado_en
 FROM bm.abono_cuenta_pagar a WHERE a.estado='confirmado' AND a.origen_fondos='regalo_tercero'
 UNION ALL
 SELECT (p.fecha_pago AT TIME ZONE 'America/Guayaquil')::date,p.pagador_nombre,'confeccion',p.monto,
 NULL::bigint,p.encargo_id,p.pago_costurera_id,p.referencia,p.notas,p.registrado_en
 FROM bm.pago_costurera p WHERE p.estado='confirmado' AND p.origen_fondos='regalo_tercero';
REVOKE ALL ON bm.v_pagos_regalados FROM PUBLIC,anon;
GRANT SELECT ON bm.v_pagos_regalados TO authenticated,service_role;

COMMENT ON COLUMN bm.pago_costurera.origen_fondos IS 'regalo_tercero: pago directo de un tercero, sin reembolso ni deuda hacia él; excluido de caja bM.';
COMMENT ON COLUMN bm.abono_cuenta_pagar.origen_fondos IS 'regalo_tercero: pago directo de un tercero, sin reembolso ni deuda hacia él; excluido de caja bM.';

CREATE OR REPLACE FUNCTION bm.panel(p_desde date,p_hasta date) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,bm AS $$
DECLARE res jsonb;
BEGIN
 PERFORM bm.perfil();
 IF p_desde IS NULL OR p_hasta IS NULL OR p_hasta<p_desde OR p_hasta-p_desde>3660 THEN RAISE EXCEPTION 'Selecciona un período válido de hasta diez años'; END IF;
 SELECT jsonb_build_object(
 'serie',coalesce((SELECT jsonb_agg(x ORDER BY dia) FROM (
 SELECT d::date dia,coalesce(m.ingreso_sin_iva,0) ventas,coalesce(m.costo,0) costos,
 coalesce(r.resultado_operativo,0) resultado,coalesce(r.margen_prendas,0) margen,
 coalesce(r.gastos_generales_y_mermas,0) gastos,coalesce(c.entradas,0) cobros,coalesce(c.salidas,0) pagos,
 coalesce(g.monto,0) regalos,coalesce(r.costos_finalizados,true) definitivo
 FROM generate_series(p_desde::timestamp,p_hasta::timestamp,'1 day') d
 LEFT JOIN bm.v_margen_diario m ON m.dia=d::date
 LEFT JOIN bm.v_resultado_operativo_diario r ON r.dia=d::date
 LEFT JOIN bm.v_caja_diaria c ON c.dia=d::date
 LEFT JOIN (SELECT fecha,sum(monto) monto FROM bm.v_pagos_regalados WHERE fecha BETWEEN p_desde AND p_hasta GROUP BY fecha) g ON g.fecha=d::date) x),'[]'::jsonb),
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

