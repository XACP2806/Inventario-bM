-- Preserve all existing balances and append the customer's display name.
CREATE OR REPLACE VIEW bm.v_saldo_pedido WITH (security_invoker=true) AS
SELECT e.pedido_id, e.cliente_id, e.estado, e.total_neto_pedido,
       e.dinero_recibido, e.dinero_reembolsado,
       e.total_neto_pedido-(e.dinero_recibido-e.dinero_reembolsado) AS saldo_pendiente,
       c.nombre_completo AS cliente_nombre
FROM bm.v_estado_cuenta_pedido e
LEFT JOIN bm.cliente c ON c.cliente_id=e.cliente_id;
