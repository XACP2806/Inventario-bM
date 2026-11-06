-- One row per fabric, across all lots and locations. Transfers cancel out.
CREATE VIEW bm.v_tela_disponible WITH (security_invoker=true) AS
SELECT tela_id, tela_nombre,
       SUM(metros_disponibles)::numeric(14,3) AS metros_disponibles
FROM bm.v_existencia_tela
GROUP BY tela_id, tela_nombre;

REVOKE ALL ON bm.v_tela_disponible FROM PUBLIC, anon;
GRANT SELECT ON bm.v_tela_disponible TO authenticated;
