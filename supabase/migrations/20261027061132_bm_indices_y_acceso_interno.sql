-- Cover all columns of composite foreign keys used by the production flow.
CREATE INDEX idx_dec_pedido_variante ON bm.detalle_encargo_costura(detalle_pedido_id, variante_id);
CREATE INDEX idx_dent_envio_compuesto ON bm.detalle_entrega(detalle_envio_id, envio_id);
CREATE INDEX idx_dent_entrega_compuesta ON bm.detalle_entrega(entrega_id, envio_id);
CREATE INDEX idx_drec_encargo_compuesto ON bm.detalle_recepcion_costura(detalle_encargo_id, encargo_id);
CREATE INDEX idx_drec_recepcion_compuesta ON bm.detalle_recepcion_costura(recepcion_id, encargo_id);

-- Internal control tables are intentionally inaccessible to API roles.
-- These restrictive policies grant no access and keep that intent explicit.
CREATE POLICY sin_acceso_directo ON bm.control_escritura AS RESTRICTIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY sin_acceso_directo ON bm.usuario_bm AS RESTRICTIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY sin_acceso_directo ON bm.periodo_cerrado AS RESTRICTIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY sin_acceso_directo ON bm.operacion AS RESTRICTIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY sin_acceso_directo ON bm.auditoria AS RESTRICTIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
CREATE POLICY sin_acceso_directo ON bm.recurso AS RESTRICTIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
