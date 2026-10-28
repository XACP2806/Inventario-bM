-- bM v1.3: instalación nueva en esquema privado. No ejecutar sobre v1.2 existente.
-- bM | Sistema de inventario, produccion y ventas
-- Propuesta relacional v1.2, PostgreSQL 15+ (USD, sin tasa de IVA fija)
-- IMPORTANTE: el DDL define estructuras y restricciones locales.
-- Validaciones agregadas (stock no negativo, correspondencia de variantes,
-- limites de devolucion/recepcion y costos asignados) deben implementarse
-- en transacciones o triggers antes de usar el sistema en produccion.

CREATE SCHEMA bm;
SET search_path = bm, pg_catalog;

-- ===== 1. CATALOGO DE PRODUCTOS =====
CREATE TABLE categoria (
    categoria_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL UNIQUE,
    descripcion VARCHAR(250)
);

CREATE TABLE talla (
    talla_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(20) NOT NULL UNIQUE,
    orden SMALLINT NOT NULL DEFAULT 0
);

CREATE TABLE color (
    color_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(60) NOT NULL UNIQUE,
    codigo_hex CHAR(7),
    CONSTRAINT ck_color_hex CHECK (codigo_hex IS NULL OR codigo_hex ~ '^#[0-9A-Fa-f]{6}$')
);

CREATE TABLE articulo (
    articulo_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    categoria_id BIGINT NOT NULL REFERENCES categoria(categoria_id),
    nombre VARCHAR(120) NOT NULL,
    descripcion TEXT,
    precio_final_catalogo NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (precio_final_catalogo >= 0),
    aplica_iva_predeterminado BOOLEAN NOT NULL DEFAULT TRUE,
    porcentaje_iva_predeterminado NUMERIC(5,2) NOT NULL DEFAULT 0
        CHECK (porcentaje_iva_predeterminado BETWEEN 0 AND 100),
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    fecha_alta TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (aplica_iva_predeterminado OR porcentaje_iva_predeterminado = 0)
);

CREATE TABLE variante_articulo (
    variante_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    articulo_id BIGINT NOT NULL REFERENCES articulo(articulo_id),
    color_id BIGINT NOT NULL REFERENCES color(color_id),
    talla_id BIGINT NOT NULL REFERENCES talla(talla_id),
    sku VARCHAR(60) NOT NULL UNIQUE,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE (articulo_id, color_id, talla_id)
);

-- Metraje esperado por tipo de pieza; talla NULL = regla generica del articulo.
-- No fija que tela exacta se debe usar en todos los lotes de produccion.
CREATE TABLE consumo_estimado_tela (
    consumo_estimado_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    articulo_id BIGINT NOT NULL REFERENCES articulo(articulo_id),
    talla_id BIGINT REFERENCES talla(talla_id),
    pieza VARCHAR(60) NOT NULL DEFAULT 'principal',
    metros_por_unidad NUMERIC(12,3) NOT NULL CHECK (metros_por_unidad > 0),
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE NULLS NOT DISTINCT (articulo_id, talla_id, pieza)
);

-- ===== 2. MATERIA PRIMA =====
-- Cada combinacion comercial de tela y color puede tener un registro separado.
CREATE TABLE tela (
    tela_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    composicion VARCHAR(180),
    color_id BIGINT REFERENCES color(color_id),
    ancho_cm NUMERIC(7,2) CHECK (ancho_cm IS NULL OR ancho_cm > 0),
    codigo VARCHAR(60) UNIQUE,
    activa BOOLEAN NOT NULL DEFAULT TRUE
);

-- Permite conservar diferencias de costo por compras/partidas.
CREATE TABLE lote_tela (
    lote_tela_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tela_id BIGINT NOT NULL REFERENCES tela(tela_id),
    proveedor VARCHAR(150),
    referencia_compra VARCHAR(100),
    fecha_compra DATE,
    fecha_ingreso TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    metros_comprados NUMERIC(12,3) NOT NULL CHECK (metros_comprados > 0),
    costo_metro NUMERIC(12,4) NOT NULL CHECK (costo_metro >= 0),
    notas TEXT
);

-- ===== 3. CLIENTES Y PEDIDOS =====
CREATE TABLE cliente (
    cliente_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_completo VARCHAR(150) NOT NULL,
    email VARCHAR(160) UNIQUE,
    telefono VARCHAR(30),
    direccion VARCHAR(250),
    ciudad VARCHAR(80),
    fecha_registro TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (email IS NOT NULL OR telefono IS NOT NULL)
);

CREATE TABLE pedido (
    pedido_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cliente_id BIGINT NOT NULL REFERENCES cliente(cliente_id),
    fecha_pedido TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    fecha_confirmacion TIMESTAMPTZ,
    estado VARCHAR(24) NOT NULL DEFAULT 'borrador'
        CHECK (estado IN ('borrador','confirmado','en_produccion',
                         'parcialmente_enviado','enviado','completado','cancelado')),
    tipo VARCHAR(20) NOT NULL DEFAULT 'venta'
        CHECK (tipo IN ('venta','mixto','bajo_pedido')),
    direccion_entrega VARCHAR(250),
    ciudad_entrega VARCHAR(80),
    costo_envio_cobrado NUMERIC(12,2) NOT NULL DEFAULT 0
        CHECK (costo_envio_cobrado >= 0),
    envio_aplica_iva BOOLEAN NOT NULL DEFAULT FALSE,
    envio_porcentaje_iva NUMERIC(5,2) NOT NULL DEFAULT 0
        CHECK (envio_porcentaje_iva BETWEEN 0 AND 100),
    notas_venta TEXT,
    fecha_actualizacion TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (envio_aplica_iva OR envio_porcentaje_iva = 0)
);

-- Precios historicos de la venta; precio_unitario_venta es ANTES de IVA.
-- La tarifa IVA no es una constante global: se congela en cada linea.
CREATE TABLE detalle_pedido (
    detalle_pedido_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pedido_id BIGINT NOT NULL REFERENCES pedido(pedido_id),
    variante_id BIGINT NOT NULL REFERENCES variante_articulo(variante_id),
    tipo_linea VARCHAR(20) NOT NULL DEFAULT 'venta'
        CHECK (tipo_linea IN ('venta','reemplazo')),
    descripcion_vendida VARCHAR(200) NOT NULL,
    sku_vendido VARCHAR(60) NOT NULL,
    cantidad INTEGER NOT NULL CHECK (cantidad > 0),
    precio_lista_unitario NUMERIC(12,2) NOT NULL CHECK (precio_lista_unitario >= 0),
    precio_unitario_final NUMERIC(12,2) NOT NULL CHECK (precio_unitario_final >= 0),
    precio_unitario_venta NUMERIC(18,8) GENERATED ALWAYS AS
      (precio_unitario_final / (1 + porcentaje_iva / 100)) STORED,
    fecha_tributaria DATE NOT NULL,
    codigo_tarifa VARCHAR(30),
    motivo_tributario TEXT,
    total_linea NUMERIC(14,2) GENERATED ALWAYS AS (cantidad * precio_unitario_final) STORED,
    aplica_iva BOOLEAN NOT NULL DEFAULT TRUE,
    porcentaje_iva NUMERIC(5,2) NOT NULL DEFAULT 0
        CHECK (porcentaje_iva BETWEEN 0 AND 100),
    detalle_venta TEXT,
    subtotal_linea NUMERIC(14,2) GENERATED ALWAYS AS
        (ROUND(cantidad * precio_unitario_final / (1 + porcentaje_iva / 100), 2)) STORED,
    valor_iva_linea NUMERIC(14,2) GENERATED ALWAYS AS
        (cantidad * precio_unitario_final - ROUND(cantidad * precio_unitario_final / (1 + porcentaje_iva / 100), 2)) STORED,
    CHECK (aplica_iva OR porcentaje_iva = 0),
    UNIQUE (detalle_pedido_id, variante_id)
);

-- ===== 4. PRODUCCION EXTERNA Y MOVIMIENTOS DE TELA =====
CREATE TABLE costurera (
    costurera_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_completo VARCHAR(150) NOT NULL,
    telefono VARCHAR(30),
    documento VARCHAR(40) UNIQUE,
    tarifa_referencia NUMERIC(12,2) CHECK (tarifa_referencia IS NULL OR tarifa_referencia >= 0),
    activa BOOLEAN NOT NULL DEFAULT TRUE,
    notas TEXT
);

-- Registra propiedad fisica/ubicacion, no inventario por campo editable.
CREATE TABLE ubicacion_tela (
    ubicacion_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL,
    tipo VARCHAR(20) NOT NULL CHECK (tipo IN ('bodega','costurera')),
    costurera_id BIGINT UNIQUE REFERENCES costurera(costurera_id),
    activa BOOLEAN NOT NULL DEFAULT TRUE,
    CHECK ((tipo = 'costurera' AND costurera_id IS NOT NULL)
        OR (tipo = 'bodega' AND costurera_id IS NULL))
);

CREATE TABLE encargo_costura (
    encargo_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    costurera_id BIGINT NOT NULL REFERENCES costurera(costurera_id),
    fecha_encargo TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    fecha_entrega_estimada TIMESTAMPTZ,
    fecha_cierre TIMESTAMPTZ,
    estado VARCHAR(24) NOT NULL DEFAULT 'pendiente'
        CHECK (estado IN ('pendiente','en_proceso','parcial','recibido','cerrado','cancelado')),
    notas TEXT
);

-- Un mismo encargo admite muchas combinaciones modelo/color/talla.
-- detalle_pedido_id NULL: fabricacion destinada al stock.
-- detalle_pedido_id no NULL: fabricacion vinculada a venta bajo pedido.
CREATE TABLE detalle_encargo_costura (
    detalle_encargo_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    encargo_id BIGINT NOT NULL REFERENCES encargo_costura(encargo_id),
    variante_id BIGINT NOT NULL REFERENCES variante_articulo(variante_id),
    detalle_pedido_id BIGINT,
    cantidad_solicitada INTEGER NOT NULL CHECK (cantidad_solicitada > 0),
    tarifa_mano_obra_unitaria NUMERIC(12,2) NOT NULL CHECK (tarifa_mano_obra_unitaria >= 0),
    notas TEXT,
    UNIQUE (detalle_encargo_id, encargo_id),
    FOREIGN KEY (detalle_pedido_id, variante_id)
        REFERENCES detalle_pedido(detalle_pedido_id, variante_id)
);

-- Una entrega fisica entre ubicaciones es una transferencia; el consumo
-- de tela registra una salida desde la ubicacion de la costurera.
CREATE TABLE movimiento_tela (
    movimiento_tela_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lote_tela_id BIGINT NOT NULL REFERENCES lote_tela(lote_tela_id),
    origen_ubicacion_id BIGINT REFERENCES ubicacion_tela(ubicacion_id),
    destino_ubicacion_id BIGINT REFERENCES ubicacion_tela(ubicacion_id),
    detalle_encargo_id BIGINT REFERENCES detalle_encargo_costura(detalle_encargo_id),
    tipo VARCHAR(22) NOT NULL
        CHECK (tipo IN ('compra','transferencia','consumo','devolucion_tela',
                       'ajuste_entrada','ajuste_salida','merma')),
    metros NUMERIC(12,3) NOT NULL CHECK (metros > 0),
    fecha TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notas TEXT,
    CHECK (origen_ubicacion_id IS NOT NULL OR destino_ubicacion_id IS NOT NULL),
    CHECK (origen_ubicacion_id IS DISTINCT FROM destino_ubicacion_id),
    CHECK (
      (tipo IN ('compra','ajuste_entrada') AND origen_ubicacion_id IS NULL
        AND destino_ubicacion_id IS NOT NULL)
      OR (tipo IN ('transferencia','devolucion_tela')
        AND origen_ubicacion_id IS NOT NULL AND destino_ubicacion_id IS NOT NULL)
      OR (tipo IN ('consumo','ajuste_salida','merma')
        AND origen_ubicacion_id IS NOT NULL AND destino_ubicacion_id IS NULL)
    ),
    CHECK (tipo <> 'consumo' OR detalle_encargo_id IS NOT NULL)
);

-- Un encargo puede recibirse en varias fechas.
CREATE TABLE recepcion_costura (
    recepcion_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    encargo_id BIGINT NOT NULL REFERENCES encargo_costura(encargo_id),
    fecha_recepcion TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notas TEXT,
    UNIQUE (recepcion_id, encargo_id)
);

CREATE TABLE detalle_recepcion_costura (
    detalle_recepcion_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    recepcion_id BIGINT NOT NULL,
    encargo_id BIGINT NOT NULL,
    detalle_encargo_id BIGINT NOT NULL,
    cantidad_recibida INTEGER NOT NULL CHECK (cantidad_recibida > 0),
    cantidad_aceptada INTEGER NOT NULL CHECK (cantidad_aceptada >= 0),
    cantidad_rechazada INTEGER NOT NULL CHECK (cantidad_rechazada >= 0),
    notas TEXT,
    CHECK (cantidad_recibida = cantidad_aceptada + cantidad_rechazada),
    FOREIGN KEY (recepcion_id, encargo_id)
        REFERENCES recepcion_costura(recepcion_id, encargo_id),
    FOREIGN KEY (detalle_encargo_id, encargo_id)
        REFERENCES detalle_encargo_costura(detalle_encargo_id, encargo_id)
);

-- 1 lote de producto por linea de recepcion aceptada.
-- Sus costos son snapshots: no cambian al modificarse los precios del catalogo.
CREATE TABLE lote_producto (
    variante_id BIGINT NOT NULL REFERENCES variante_articulo(variante_id),
    lote_producto_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    detalle_recepcion_id BIGINT NOT NULL UNIQUE
        REFERENCES detalle_recepcion_costura(detalle_recepcion_id),
    fecha_alta TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    costo_tela_unitario NUMERIC(12,4) NOT NULL DEFAULT 0 CHECK (costo_tela_unitario >= 0),
    costo_mano_obra_unitario NUMERIC(12,4) NOT NULL DEFAULT 0
        CHECK (costo_mano_obra_unitario >= 0),
    costo_insumos_unitario NUMERIC(12,4) NOT NULL DEFAULT 0
        CHECK (costo_insumos_unitario >= 0),
    costo_total_unitario NUMERIC(12,4) GENERATED ALWAYS AS
        (costo_tela_unitario + costo_mano_obra_unitario + costo_insumos_unitario) STORED,
    costo_finalizado BOOLEAN NOT NULL DEFAULT FALSE,
    notas TEXT
);

-- ===== 5. GASTOS Y PAGOS DE COSTURA =====
CREATE TABLE tipo_gasto (
    tipo_gasto_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL UNIQUE,
    descripcion VARCHAR(250),
    activo BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE gasto (
    gasto_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo_gasto_id BIGINT NOT NULL REFERENCES tipo_gasto(tipo_gasto_id),
    encargo_id BIGINT REFERENCES encargo_costura(encargo_id),
    proveedor VARCHAR(150),
    descripcion TEXT NOT NULL,
    cantidad NUMERIC(12,3) NOT NULL DEFAULT 1 CHECK (cantidad > 0),
    unidad VARCHAR(30) NOT NULL DEFAULT 'unidad',
    costo_unitario NUMERIC(12,4) NOT NULL CHECK (costo_unitario >= 0),
    costo_total NUMERIC(14,2) GENERATED ALWAYS AS
        (ROUND(cantidad * costo_unitario, 2)) STORED,
    fecha_gasto TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notas TEXT
);

-- Solo gastos asignados a produccion se reparten entre prendas.
-- El resto queda como gasto general. No se mantiene stock de insumos.
CREATE TABLE asignacion_gasto_produccion (
    asignacion_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    gasto_id BIGINT NOT NULL REFERENCES gasto(gasto_id),
    detalle_encargo_id BIGINT NOT NULL REFERENCES detalle_encargo_costura(detalle_encargo_id),
    monto_asignado NUMERIC(12,2) NOT NULL CHECK (monto_asignado > 0),
    UNIQUE (gasto_id, detalle_encargo_id)
);

CREATE TABLE pago_costurera (
    pago_costurera_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    encargo_id BIGINT NOT NULL REFERENCES encargo_costura(encargo_id),
    fecha_pago TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    monto NUMERIC(12,2) NOT NULL CHECK (monto > 0),
    metodo VARCHAR(40) NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'confirmado'
        CHECK (estado IN ('pendiente','confirmado','anulado')),
    referencia VARCHAR(100),
    notas TEXT
);

-- ===== 6. COBROS, ENVIOS, DEVOLUCIONES =====
CREATE TABLE pago_pedido (
    pago_pedido_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pedido_id BIGINT NOT NULL REFERENCES pedido(pedido_id),
    fecha_pago TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    monto NUMERIC(12,2) NOT NULL CHECK (monto > 0),
    metodo VARCHAR(40) NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'confirmado'
        CHECK (estado IN ('pendiente','confirmado','anulado')),
    referencia VARCHAR(100),
    notas TEXT
);

-- Varios envios por pedido; costo real separadamente del cobro al cliente.
CREATE TABLE envio (
    envio_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pedido_id BIGINT NOT NULL REFERENCES pedido(pedido_id),
    transportadora VARCHAR(100),
    numero_guia VARCHAR(80) UNIQUE,
    direccion_entrega VARCHAR(250) NOT NULL,
    ciudad_entrega VARCHAR(80),
    fecha_envio TIMESTAMPTZ,
    fecha_entrega TIMESTAMPTZ,
    estado VARCHAR(24) NOT NULL DEFAULT 'preparando'
        CHECK (estado IN ('preparando','despachado','parcialmente_entregado',
                         'entregado','incidencia','cancelado')),
    costo_real_transportadora NUMERIC(12,2) NOT NULL DEFAULT 0
        CHECK (costo_real_transportadora >= 0),
    notas TEXT
);

-- Relaciona cada unidad despachada con un lote y, por ello, con su costo.
CREATE TABLE detalle_envio (
    detalle_envio_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    envio_id BIGINT NOT NULL REFERENCES envio(envio_id),
    detalle_pedido_id BIGINT NOT NULL REFERENCES detalle_pedido(detalle_pedido_id),
    lote_producto_id BIGINT NOT NULL REFERENCES lote_producto(lote_producto_id),
    cantidad INTEGER NOT NULL CHECK (cantidad > 0),
    UNIQUE (envio_id, detalle_pedido_id, lote_producto_id)
);

CREATE TABLE devolucion_pedido (
    devolucion_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pedido_id BIGINT NOT NULL REFERENCES pedido(pedido_id),
    fecha_solicitud TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    fecha_resolucion TIMESTAMPTZ,
    tipo VARCHAR(20) NOT NULL CHECK (tipo IN ('devolucion','cambio','mixto')),
    estado VARCHAR(24) NOT NULL DEFAULT 'solicitada'
        CHECK (estado IN ('solicitada','recibida','aprobada','resuelta','rechazada','cancelada')),
    motivo TEXT,
    notas TEXT
);

-- El credito consta por separado del desembolso real (reembolso).
-- Referencia el envio para saber exactamente que lote volvio.
CREATE TABLE detalle_devolucion (
    detalle_devolucion_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    devolucion_id BIGINT NOT NULL REFERENCES devolucion_pedido(devolucion_id),
    detalle_envio_id BIGINT NOT NULL REFERENCES detalle_envio(detalle_envio_id),
    cantidad INTEGER NOT NULL CHECK (cantidad > 0),
    condicion VARCHAR(24) NOT NULL
        CHECK (condicion IN ('nuevo','usado','defectuoso','no_recibido')),
    reingresa_inventario BOOLEAN NOT NULL DEFAULT FALSE,
    credito_subtotal NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (credito_subtotal >= 0),
    credito_iva NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (credito_iva >= 0),
    credito_total NUMERIC(12,2) GENERATED ALWAYS AS
        (credito_subtotal + credito_iva) STORED,
    detalle_pedido_reemplazo_id BIGINT REFERENCES detalle_pedido(detalle_pedido_id),
    motivo TEXT
);

CREATE TABLE reembolso (
    reembolso_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pedido_id BIGINT NOT NULL REFERENCES pedido(pedido_id),
    devolucion_id BIGINT REFERENCES devolucion_pedido(devolucion_id),
    fecha_reembolso TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    monto NUMERIC(12,2) NOT NULL CHECK (monto > 0),
    metodo VARCHAR(40) NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'pendiente'
        CHECK (estado IN ('pendiente','completado','anulado')),
    referencia VARCHAR(100),
    notas TEXT
);

-- Ajustes por descuentos adicionales, cancelaciones o cargos extra.
-- Los creditos por productos devueltos se llevan en detalle_devolucion
-- para impedir que se resten dos veces.
CREATE TABLE ajuste_pedido (
    detalle_pedido_id BIGINT REFERENCES detalle_pedido(detalle_pedido_id),
    destino VARCHAR(10) NOT NULL DEFAULT 'prenda' CHECK (destino IN ('prenda','envio')),
    CHECK ((destino='prenda') = (detalle_pedido_id IS NOT NULL)),
    ajuste_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pedido_id BIGINT NOT NULL REFERENCES pedido(pedido_id),
    fecha TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    concepto VARCHAR(200) NOT NULL,
    monto_subtotal NUMERIC(12,2) NOT NULL,
    monto_iva NUMERIC(12,2) NOT NULL DEFAULT 0,
    monto_total NUMERIC(12,2) GENERATED ALWAYS AS
        (monto_subtotal + monto_iva) STORED,
    CHECK (monto_subtotal <> 0 OR monto_iva <> 0)
);

-- ===== 7. KARDEX DE ARTICULOS TERMINADOS =====
-- Cada lote tiene una sola variante, derivada de su recepcion de costura.
-- Un movimiento positivo ingresa; negativo consume o da de baja.
CREATE TABLE movimiento_producto (
    movimiento_producto_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lote_producto_id BIGINT NOT NULL REFERENCES lote_producto(lote_producto_id),
    tipo VARCHAR(24) NOT NULL CHECK (tipo IN
        ('produccion','venta','devolucion','ajuste_positivo','ajuste_negativo','merma')),
    cantidad_delta INTEGER NOT NULL CHECK (cantidad_delta <> 0),
    detalle_envio_id BIGINT UNIQUE REFERENCES detalle_envio(detalle_envio_id),
    detalle_devolucion_id BIGINT UNIQUE REFERENCES detalle_devolucion(detalle_devolucion_id),
    fecha TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notas TEXT,
    CHECK ((tipo IN ('produccion','devolucion','ajuste_positivo') AND cantidad_delta > 0)
        OR (tipo IN ('venta','ajuste_negativo','merma') AND cantidad_delta < 0)),
    CHECK (tipo <> 'venta' OR detalle_envio_id IS NOT NULL),
    CHECK (tipo <> 'devolucion' OR detalle_devolucion_id IS NOT NULL)
);

-- La reserva aparta existencias disponibles sin sacarlas fisicamente.
CREATE TABLE reserva_producto (
    reserva_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    detalle_pedido_id BIGINT NOT NULL REFERENCES detalle_pedido(detalle_pedido_id),
    lote_producto_id BIGINT NOT NULL REFERENCES lote_producto(lote_producto_id),
    cantidad INTEGER NOT NULL CHECK (cantidad > 0),
    estado VARCHAR(20) NOT NULL DEFAULT 'activa'
        CHECK (estado IN ('activa','consumida','liberada')),
    fecha TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ===== 8. CONSULTAS OPERATIVAS =====
-- Saldos por lote y ubicacion. Se derivan del historial de movimientos.
CREATE VIEW v_existencia_tela WITH (security_invoker=true) AS
SELECT lt.lote_tela_id, lt.tela_id, ut.ubicacion_id, ut.nombre AS ubicacion,
       COALESCE(SUM(
           CASE WHEN mt.destino_ubicacion_id = ut.ubicacion_id THEN mt.metros ELSE 0 END
         - CASE WHEN mt.origen_ubicacion_id = ut.ubicacion_id THEN mt.metros ELSE 0 END
       ),0)::NUMERIC(14,3) AS metros_disponibles
FROM lote_tela lt
CROSS JOIN ubicacion_tela ut
LEFT JOIN movimiento_tela mt ON mt.lote_tela_id = lt.lote_tela_id
  AND (mt.origen_ubicacion_id = ut.ubicacion_id OR mt.destino_ubicacion_id = ut.ubicacion_id)
GROUP BY lt.lote_tela_id, lt.tela_id, ut.ubicacion_id, ut.nombre;

CREATE VIEW v_stock_lote_producto WITH (security_invoker=true) AS
SELECT lp.lote_producto_id, dec.variante_id,
       COALESCE(SUM(mp.cantidad_delta),0)::INTEGER AS stock_fisico,
       COALESCE((SELECT SUM(rp.cantidad) FROM reserva_producto rp
                 WHERE rp.lote_producto_id = lp.lote_producto_id
                   AND rp.estado = 'activa'),0)::INTEGER AS stock_reservado,
       (COALESCE(SUM(mp.cantidad_delta),0)
        - COALESCE((SELECT SUM(rp.cantidad) FROM reserva_producto rp
                    WHERE rp.lote_producto_id = lp.lote_producto_id
                      AND rp.estado = 'activa'),0))::INTEGER AS stock_disponible
FROM lote_producto lp
JOIN detalle_recepcion_costura drc ON drc.detalle_recepcion_id = lp.detalle_recepcion_id
JOIN detalle_encargo_costura dec ON dec.detalle_encargo_id = drc.detalle_encargo_id
LEFT JOIN movimiento_producto mp ON mp.lote_producto_id = lp.lote_producto_id
GROUP BY lp.lote_producto_id, dec.variante_id;

CREATE VIEW v_stock_variante WITH (security_invoker=true) AS
SELECT va.variante_id, va.sku,
       COALESCE(SUM(vs.stock_fisico),0)::INTEGER AS stock_fisico,
       COALESCE(SUM(vs.stock_reservado),0)::INTEGER AS stock_reservado,
       COALESCE(SUM(vs.stock_disponible),0)::INTEGER AS stock_disponible
FROM variante_articulo va
LEFT JOIN v_stock_lote_producto vs ON vs.variante_id = va.variante_id
GROUP BY va.variante_id, va.sku;

-- Incluye ventas originales/reemplazos, transporte cobrado, notas de ajuste,
-- devoluciones aprobadas y flujos de efectivo confirmados.
CREATE VIEW v_estado_cuenta_pedido WITH (security_invoker=true) AS
SELECT p.pedido_id, p.cliente_id, p.estado,
       COALESCE((SELECT SUM(dp.subtotal_linea + dp.valor_iva_linea)
                 FROM detalle_pedido dp WHERE dp.pedido_id = p.pedido_id),0)
         + p.costo_envio_cobrado
         + (CASE WHEN p.envio_aplica_iva
                 THEN ROUND(p.costo_envio_cobrado*p.envio_porcentaje_iva/100,2)
                 ELSE 0 END)
         + COALESCE((SELECT SUM(ap.monto_total) FROM ajuste_pedido ap
                     WHERE ap.pedido_id = p.pedido_id),0)
         - COALESCE((SELECT SUM(dd.credito_total)
                     FROM detalle_devolucion dd
                     JOIN devolucion_pedido dev ON dev.devolucion_id = dd.devolucion_id
                     WHERE dev.pedido_id=p.pedido_id
                       AND dev.estado IN ('aprobada','resuelta')),0)
       AS total_neto_pedido,
       COALESCE((SELECT SUM(pp.monto) FROM pago_pedido pp
                 WHERE pp.pedido_id=p.pedido_id AND pp.estado='confirmado'),0)
       AS dinero_recibido,
       COALESCE((SELECT SUM(r.monto) FROM reembolso r
                 WHERE r.pedido_id=p.pedido_id AND r.estado='completado'),0)
       AS dinero_reembolsado
FROM pedido p;

CREATE VIEW v_saldo_pedido WITH (security_invoker=true) AS
SELECT pedido_id, cliente_id, estado, total_neto_pedido, dinero_recibido,
       dinero_reembolsado,
       total_neto_pedido - (dinero_recibido-dinero_reembolsado) AS saldo_pendiente
FROM v_estado_cuenta_pedido;

-- Margen comercial por lote efectivamente despachado; SIN IVA, SIN devoluciones
-- y SIN costo de transporte. Si costo_finalizado=false, es provisional.


-- Margen por linea de envio DESPUES de devoluciones aprobadas.
-- Solo se reincorpora el costo si el producto devuelto vuelve a inventario.
-- No incluye el costo real/cobrado del transporte ni los gastos generales.


-- ===== 9. INDICES PARA FKS Y OPERACION DIARIA =====
CREATE INDEX idx_variante_articulo_articulo ON variante_articulo(articulo_id);
CREATE INDEX idx_tela_lote_tipo ON lote_tela(tela_id);
CREATE INDEX idx_pedido_cliente_fecha ON pedido(cliente_id, fecha_pedido DESC);
CREATE INDEX idx_detalle_pedido_pedido ON detalle_pedido(pedido_id);
CREATE INDEX idx_encargo_costurera_fecha ON encargo_costura(costurera_id, fecha_encargo DESC);
CREATE INDEX idx_detalle_encargo_encargo ON detalle_encargo_costura(encargo_id);
CREATE INDEX idx_mov_tela_lote_fecha ON movimiento_tela(lote_tela_id, fecha DESC);
CREATE INDEX idx_mov_tela_origen ON movimiento_tela(origen_ubicacion_id);
CREATE INDEX idx_mov_tela_destino ON movimiento_tela(destino_ubicacion_id);
CREATE INDEX idx_mov_tela_encargo ON movimiento_tela(detalle_encargo_id);
CREATE INDEX idx_recepcion_encargo ON recepcion_costura(encargo_id);
CREATE INDEX idx_detalle_recepcion_encargo ON detalle_recepcion_costura(detalle_encargo_id);
CREATE INDEX idx_gasto_tipo_fecha ON gasto(tipo_gasto_id, fecha_gasto DESC);
CREATE INDEX idx_asignacion_gasto_detalle ON asignacion_gasto_produccion(detalle_encargo_id);
CREATE INDEX idx_pago_pedido_pedido ON pago_pedido(pedido_id);
CREATE INDEX idx_pago_costurera_encargo ON pago_costurera(encargo_id);
CREATE INDEX idx_envio_pedido ON envio(pedido_id);
CREATE INDEX idx_detalle_envio_pedido ON detalle_envio(detalle_pedido_id);
CREATE INDEX idx_detalle_envio_lote ON detalle_envio(lote_producto_id);
CREATE INDEX idx_devolucion_pedido ON devolucion_pedido(pedido_id);
CREATE INDEX idx_detalle_devolucion_envio ON detalle_devolucion(detalle_envio_id);
CREATE INDEX idx_reembolso_pedido ON reembolso(pedido_id);
CREATE INDEX idx_ajuste_pedido ON ajuste_pedido(pedido_id);
CREATE INDEX idx_mov_producto_lote_fecha ON movimiento_producto(lote_producto_id, fecha DESC);
CREATE INDEX idx_reserva_producto_lote ON reserva_producto(lote_producto_id);
CREATE UNIQUE INDEX uq_reserva_activa_lote_detalle
  ON reserva_producto(detalle_pedido_id, lote_producto_id) WHERE estado = 'activa';


-- ===== 10. COMPRAS DE TELA Y DOCUMENTOS TRIBUTARIOS (v1.1) =====
-- Separa una orden de compra de la compra/factura realmente recibida.
CREATE TABLE proveedor (
    proveedor_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre_legal VARCHAR(180) NOT NULL,
    nombre_comercial VARCHAR(180),
    ruc VARCHAR(13) UNIQUE,
    telefono VARCHAR(30),
    direccion TEXT,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    CHECK (ruc IS NULL OR ruc ~ '^[0-9]{13}$')
);

CREATE TABLE orden_compra_tela (
    orden_compra_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    proveedor_id BIGINT REFERENCES proveedor(proveedor_id),
    fecha_orden DATE NOT NULL DEFAULT CURRENT_DATE,
    local_previsto VARCHAR(180),
    estado VARCHAR(20) NOT NULL DEFAULT 'borrador'
        CHECK (estado IN ('borrador','enviada','parcial','recibida','cancelada')),
    notas TEXT
);

CREATE TABLE detalle_orden_compra_tela (
    detalle_orden_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    orden_compra_id BIGINT NOT NULL REFERENCES orden_compra_tela(orden_compra_id),
    tela_id BIGINT NOT NULL REFERENCES tela(tela_id),
    metros_solicitados NUMERIC(12,3) NOT NULL CHECK (metros_solicitados > 0),
    precio_estimado_metro_sin_iva NUMERIC(12,4)
        CHECK (precio_estimado_metro_sin_iva IS NULL OR precio_estimado_metro_sin_iva >= 0),
    notas TEXT
);

CREATE TABLE compra (
    compra_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    proveedor_id BIGINT NOT NULL REFERENCES proveedor(proveedor_id),
    orden_compra_id BIGINT REFERENCES orden_compra_tela(orden_compra_id),
    fecha_compra DATE NOT NULL DEFAULT CURRENT_DATE,
    fecha_emision_documento DATE,
    local_compra VARCHAR(180),
    tipo_comprobante VARCHAR(25) NOT NULL DEFAULT 'factura'
        CHECK (tipo_comprobante IN ('factura','liquidacion_compra','otro','sin_comprobante')),
    numero_factura VARCHAR(30),  -- p.ej. 001-001-000000123 (si aplica)
    clave_acceso CHAR(49) UNIQUE,  -- factura electronica (si aplica)
    estado_verificacion VARCHAR(25) NOT NULL DEFAULT 'pendiente'
        CHECK (estado_verificacion IN ('pendiente','verificado','observado','sin_comprobante')),
    comprobante_archivo_url TEXT,
    notas TEXT,
    CHECK (clave_acceso IS NULL OR clave_acceso ~ '^[0-9]{49}$')
);
CREATE UNIQUE INDEX uq_compra_factura_proveedor
  ON compra(proveedor_id, tipo_comprobante, numero_factura)
  WHERE numero_factura IS NOT NULL;

-- IVA facturado se guarda como figura en el documento (puede haber redondeos).
-- Un detalle puede corresponder a tela o a un gasto/servicio sin inventario.
CREATE TABLE detalle_compra (
    detalle_compra_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    compra_id BIGINT NOT NULL REFERENCES compra(compra_id),
    tipo VARCHAR(20) NOT NULL CHECK (tipo IN ('tela','insumo','servicio','otro')),
    tela_id BIGINT REFERENCES tela(tela_id),
    descripcion VARCHAR(250) NOT NULL,
    unidad VARCHAR(30) NOT NULL DEFAULT 'metro',
    cantidad NUMERIC(12,3) NOT NULL CHECK (cantidad > 0),
    precio_unitario_sin_iva NUMERIC(12,4) NOT NULL CHECK (precio_unitario_sin_iva >= 0),
    descuento_sin_iva NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (descuento_sin_iva >= 0),
    iva_porcentaje NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (iva_porcentaje BETWEEN 0 AND 100),
    iva_facturado NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (iva_facturado >= 0),
    otros_cargos_facturados NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (otros_cargos_facturados >= 0),
    subtotal_sin_iva NUMERIC(14,2) GENERATED ALWAYS AS
       (ROUND(cantidad*precio_unitario_sin_iva-descuento_sin_iva,2)) STORED,
    total_facturado NUMERIC(14,2) GENERATED ALWAYS AS
       (ROUND(cantidad*precio_unitario_sin_iva-descuento_sin_iva,2)
          + iva_facturado + otros_cargos_facturados) STORED,
    CHECK (tipo <> 'tela' OR (tela_id IS NOT NULL AND unidad = 'metro')),
    CHECK (tipo = 'tela' OR tela_id IS NULL),
    CHECK (descuento_sin_iva <= cantidad*precio_unitario_sin_iva)
);

-- Conecta las entradas físicas con la factura que sustenta su costo.
-- El costo_metro del lote es snapshot inventariable, NO siempre precio con IVA.
ALTER TABLE lote_tela
  ADD COLUMN detalle_compra_id BIGINT REFERENCES detalle_compra(detalle_compra_id);

-- Los gastos de botones/etiquetas podrán vincularse a un comprobante sin
-- que ello implique llevar inventario físico de botones o etiquetas.
ALTER TABLE gasto
  ADD COLUMN detalle_compra_id BIGINT UNIQUE REFERENCES detalle_compra(detalle_compra_id);
ALTER TABLE gasto
  ADD COLUMN proveedor_id BIGINT REFERENCES proveedor(proveedor_id);

-- ===== 11. CREDITO TRIBUTARIO IVA (documentación y evaluación) =====
-- El régimen/condición tributaria debe confirmarse con el contador y versionarse.
CREATE TABLE configuracion_tributaria (
    configuracion_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    razon_social VARCHAR(180),
    ruc VARCHAR(13),
    regimen VARCHAR(45) NOT NULL DEFAULT 'general',
    tipo_contribuyente VARCHAR(25) NOT NULL DEFAULT 'persona_natural'
        CHECK (tipo_contribuyente IN ('persona_natural','sociedad')),
    obligado_a_llevar_contabilidad BOOLEAN, -- NULL = verificar condiciones de RUC
    agente_retencion BOOLEAN NOT NULL DEFAULT FALSE,
    valido_desde DATE NOT NULL,
    valido_hasta DATE,
    notas TEXT,
    CHECK (ruc IS NULL OR ruc ~ '^[0-9]{13}$'),
    CHECK (valido_hasta IS NULL OR valido_hasta >= valido_desde)
);

CREATE TABLE periodo_iva (
    periodo_iva_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    periodicidad VARCHAR(12) NOT NULL CHECK (periodicidad IN ('mensual','semestral')),
    estado VARCHAR(20) NOT NULL DEFAULT 'abierto'
       CHECK (estado IN ('abierto','revisado','declarado')),
    factor_proporcionalidad NUMERIC(7,6)
       CHECK (factor_proporcionalidad BETWEEN 0 AND 1),
    saldo_credito_anterior NUMERIC(14,2) NOT NULL DEFAULT 0
       CHECK (saldo_credito_anterior >= 0),
    ajustes_credito NUMERIC(14,2) NOT NULL DEFAULT 0,
    notas TEXT,
    CHECK (fecha_fin >= fecha_inicio),
    UNIQUE (fecha_inicio, fecha_fin)
);

-- La decisión del crédito se realiza por línea de comprobante, no por lote.
-- 'pendiente' NO se cuenta como crédito aprobado; no basta marcar una casilla.
CREATE TABLE credito_iva_compra (
    credito_iva_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    detalle_compra_id BIGINT NOT NULL UNIQUE REFERENCES detalle_compra(detalle_compra_id),
    periodo_iva_id BIGINT REFERENCES periodo_iva(periodo_iva_id),
    estado VARCHAR(20) NOT NULL DEFAULT 'pendiente'
        CHECK (estado IN ('pendiente','aprobado','rechazado')),
    tratamiento VARCHAR(25) NOT NULL DEFAULT 'sin_evaluar'
        CHECK (tratamiento IN ('sin_evaluar','total','proporcional','no_creditable')),
    iva_elegible NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (iva_elegible >= 0),
    factor_aplicado NUMERIC(7,6) NOT NULL DEFAULT 0 CHECK (factor_aplicado BETWEEN 0 AND 1),
    credito_aprobado NUMERIC(12,2) GENERATED ALWAYS AS
        (CASE WHEN estado = 'aprobado' THEN ROUND(iva_elegible*factor_aplicado,2)
              ELSE 0 END) STORED,
    fecha_revision TIMESTAMPTZ,
    notas TEXT,
    CHECK (estado <> 'aprobado' OR periodo_iva_id IS NOT NULL)
);

-- IVA 0%, exento y no objeto no son equivalentes. La bandera aplica_iva del
-- esquema original sigue operativa, pero esta clasificación se requiere
-- antes de usar comprobantes para reportes tributarios definitivos.
ALTER TABLE detalle_pedido
  ADD COLUMN tratamiento_iva VARCHAR(20) NOT NULL DEFAULT 'por_definir'
   CHECK (tratamiento_iva IN ('por_definir','gravado','tarifa_0','exento','no_objeto'));

-- Documento fiscal de venta emitido: distinto al pedido comercial.
-- Permite distintos comprobantes para un pedido con despachos parciales.
-- Captura fiscal: emisión electrónica real se realiza con servicio SRI aparte.
CREATE TABLE comprobante_venta (
    comprobante_venta_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pedido_id BIGINT NOT NULL REFERENCES pedido(pedido_id),
    fecha_emision DATE NOT NULL,
    tipo_comprobante VARCHAR(20) NOT NULL DEFAULT 'factura'
      CHECK (tipo_comprobante IN ('factura','nota_credito','nota_debito')),
    numero_comprobante VARCHAR(30) NOT NULL,
    clave_acceso CHAR(49) UNIQUE,
    estado_sri VARCHAR(25) NOT NULL DEFAULT 'pendiente'
      CHECK (estado_sri IN ('pendiente','autorizado','rechazado','anulado')),
    subtotal_sin_iva NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (subtotal_sin_iva >= 0),
    valor_iva NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (valor_iva >= 0),
    documento_relacionado_id BIGINT REFERENCES comprobante_venta(comprobante_venta_id),
    notas TEXT,
    CHECK (clave_acceso IS NULL OR clave_acceso ~ '^[0-9]{49}$')
);

-- Retenciones emitidas y recibidas: requieren el comprobante de sustento
-- y su tratamiento no se debe confundir con crédito por IVA de compras.
CREATE TABLE retencion_iva (
    retencion_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo VARCHAR(12) NOT NULL CHECK (tipo IN ('recibida','emitida')),
    compra_id BIGINT REFERENCES compra(compra_id),
    comprobante_venta_id BIGINT REFERENCES comprobante_venta(comprobante_venta_id),
    periodo_iva_id BIGINT REFERENCES periodo_iva(periodo_iva_id),
    fecha_emision DATE NOT NULL,
    numero_comprobante VARCHAR(30),
    clave_acceso CHAR(49) UNIQUE,
    monto_retencion NUMERIC(12,2) NOT NULL CHECK (monto_retencion > 0),
    estado VARCHAR(15) NOT NULL DEFAULT 'pendiente'
      CHECK (estado IN ('pendiente','validada','anulada')),
    notas TEXT,
    CHECK (clave_acceso IS NULL OR clave_acceso ~ '^[0-9]{49}$'),
    CHECK (num_nonnulls(compra_id, comprobante_venta_id) = 1)
);

-- ===== 12. OBLIGACIONES FINANCIERAS NO CUBIERTAS POR PEDIDOS/COSTURA =====
-- NO se duplican los saldos originales: saldos de clientes por pedido y
-- costureras por recepciones se calculan en sus vistas específicas.
CREATE TABLE cuenta_pagar (
    cuenta_pagar_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    compra_id BIGINT UNIQUE REFERENCES compra(compra_id),
    proveedor_id BIGINT REFERENCES proveedor(proveedor_id),
    costurera_id BIGINT REFERENCES costurera(costurera_id),
    tercero_nombre VARCHAR(180),
    descripcion VARCHAR(250) NOT NULL,
    fecha_origen DATE NOT NULL DEFAULT CURRENT_DATE,
    fecha_vencimiento DATE,
    monto_original NUMERIC(14,2) NOT NULL CHECK (monto_original > 0),
    estado VARCHAR(20) NOT NULL DEFAULT 'vigente'
      CHECK (estado IN ('vigente','anulada')),
    notas TEXT,
    CHECK (num_nonnulls(proveedor_id,costurera_id,tercero_nombre)=1)
);

CREATE TABLE abono_cuenta_pagar (
    abono_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cuenta_pagar_id BIGINT NOT NULL REFERENCES cuenta_pagar(cuenta_pagar_id),
    fecha_pago DATE NOT NULL DEFAULT CURRENT_DATE,
    monto NUMERIC(14,2) NOT NULL CHECK (monto > 0),
    metodo VARCHAR(40) NOT NULL,
    estado VARCHAR(15) NOT NULL DEFAULT 'confirmado'
      CHECK (estado IN ('pendiente','confirmado','anulado')),
    referencia VARCHAR(100),
    notas TEXT
);

-- Préstamos u otras cuentas por cobrar no originadas en pedido.
CREATE TABLE cuenta_cobrar (
    cuenta_cobrar_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cliente_id BIGINT REFERENCES cliente(cliente_id),
    tercero_nombre VARCHAR(180),
    descripcion VARCHAR(250) NOT NULL,
    fecha_origen DATE NOT NULL DEFAULT CURRENT_DATE,
    fecha_vencimiento DATE,
    monto_original NUMERIC(14,2) NOT NULL CHECK (monto_original > 0),
    estado VARCHAR(20) NOT NULL DEFAULT 'vigente'
       CHECK (estado IN ('vigente','anulada')),
    notas TEXT,
    CHECK (num_nonnulls(cliente_id,tercero_nombre)=1)
);

CREATE TABLE abono_cuenta_cobrar (
    abono_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cuenta_cobrar_id BIGINT NOT NULL REFERENCES cuenta_cobrar(cuenta_cobrar_id),
    fecha_cobro DATE NOT NULL DEFAULT CURRENT_DATE,
    monto NUMERIC(14,2) NOT NULL CHECK (monto > 0),
    metodo VARCHAR(40) NOT NULL,
    estado VARCHAR(15) NOT NULL DEFAULT 'confirmado'
      CHECK (estado IN ('pendiente','confirmado','anulado')),
    referencia VARCHAR(100),
    notas TEXT
);

-- ===== 13. VISTAS DE COSTOS, DEUDAS Y TRIBUTACIÓN =====
-- Costo 'con IVA' muestra lo desembolsado por metro; costo inventariable
-- resta el crédito IVA aprobado, no el potencial. Otros cargos van al costo
-- solo si son directamente atribuibles: validar con contabilidad.
CREATE VIEW v_costo_compra_tela WITH (security_invoker=true) AS
SELECT dc.detalle_compra_id, dc.compra_id, dc.tela_id,
       dc.cantidad AS metros,
       ROUND(dc.subtotal_sin_iva/dc.cantidad,4) AS precio_metro_sin_iva,
       ROUND((dc.subtotal_sin_iva+dc.iva_facturado)/dc.cantidad,4)
           AS precio_metro_con_iva,
       dc.iva_facturado,
       COALESCE(ci.credito_aprobado,0) AS iva_credito_aprobado,
       ROUND((dc.total_facturado-COALESCE(ci.credito_aprobado,0)) / dc.cantidad,4)
           AS costo_inventariable_metro_estimado,
       CASE WHEN ci.estado='aprobado' THEN 'revisado' ELSE 'provisional' END
           AS estado_costo
FROM detalle_compra dc
LEFT JOIN credito_iva_compra ci ON ci.detalle_compra_id=dc.detalle_compra_id
WHERE dc.tipo='tela';

CREATE VIEW v_saldo_costurera_encargo WITH (security_invoker=true) AS
SELECT ec.encargo_id, ec.costurera_id, c.nombre_completo,
       COALESCE(dev.monto_devengado,0)::NUMERIC(14,2) AS monto_devengado,
       COALESCE(pag.monto_pagado,0)::NUMERIC(14,2) AS monto_pagado,
       (COALESCE(dev.monto_devengado,0)-COALESCE(pag.monto_pagado,0))::NUMERIC(14,2)
           AS saldo_por_pagar
FROM encargo_costura ec
JOIN costurera c ON c.costurera_id=ec.costurera_id
LEFT JOIN (
 SELECT dec.encargo_id,
        SUM(drc.cantidad_aceptada*dec.tarifa_mano_obra_unitaria) AS monto_devengado
 FROM detalle_recepcion_costura drc
 JOIN detalle_encargo_costura dec ON dec.detalle_encargo_id=drc.detalle_encargo_id
 GROUP BY dec.encargo_id
) dev ON dev.encargo_id=ec.encargo_id
LEFT JOIN (
 SELECT encargo_id,SUM(monto) AS monto_pagado FROM pago_costurera
 WHERE estado='confirmado' GROUP BY encargo_id
) pag ON pag.encargo_id=ec.encargo_id;

CREATE VIEW v_saldo_cuenta_pagar WITH (security_invoker=true) AS
SELECT cp.cuenta_pagar_id, cp.compra_id, cp.proveedor_id, cp.costurera_id,
       cp.tercero_nombre, cp.fecha_vencimiento, cp.descripcion, cp.monto_original,
       COALESCE(SUM(a.monto) FILTER (WHERE a.estado='confirmado'),0)::NUMERIC(14,2)
          AS total_pagado,
       (cp.monto_original-COALESCE(SUM(a.monto)
          FILTER (WHERE a.estado='confirmado'),0))::NUMERIC(14,2) AS saldo_pendiente
FROM cuenta_pagar cp
LEFT JOIN abono_cuenta_pagar a ON a.cuenta_pagar_id=cp.cuenta_pagar_id
WHERE cp.estado='vigente'
GROUP BY cp.cuenta_pagar_id;

CREATE VIEW v_saldo_cuenta_cobrar WITH (security_invoker=true) AS
SELECT cc.cuenta_cobrar_id, cc.cliente_id, cc.tercero_nombre,
       cc.fecha_vencimiento, cc.descripcion, cc.monto_original,
       COALESCE(SUM(a.monto) FILTER (WHERE a.estado='confirmado'),0)::NUMERIC(14,2)
          AS total_cobrado,
       (cc.monto_original-COALESCE(SUM(a.monto)
          FILTER (WHERE a.estado='confirmado'),0))::NUMERIC(14,2) AS saldo_pendiente
FROM cuenta_cobrar cc
LEFT JOIN abono_cuenta_cobrar a ON a.cuenta_cobrar_id=cc.cuenta_cobrar_id
WHERE cc.estado='vigente'
GROUP BY cc.cuenta_cobrar_id;

-- Resumen de apoyo: no reemplaza la declaración SRI; revisar tasas,
-- documentos tributarios, notas de crédito, prorrata y retenciones.
CREATE VIEW v_resumen_iva_periodo WITH (security_invoker=true) AS
SELECT pi.periodo_iva_id, pi.fecha_inicio, pi.fecha_fin, pi.estado,
       COALESCE((SELECT SUM(CASE WHEN cv.tipo_comprobante='nota_credito'
                                  THEN -cv.valor_iva ELSE cv.valor_iva END)
                 FROM comprobante_venta cv
                 WHERE cv.estado_sri='autorizado'
                   AND cv.fecha_emision BETWEEN pi.fecha_inicio AND pi.fecha_fin),0)
          AS iva_ventas_documentadas,
       COALESCE((SELECT SUM(ci.credito_aprobado)
                 FROM credito_iva_compra ci
                 WHERE ci.periodo_iva_id=pi.periodo_iva_id),0)
          AS credito_iva_compras_aprobado,
       COALESCE((SELECT SUM(ri.monto_retencion)
                 FROM retencion_iva ri
                 WHERE ri.periodo_iva_id=pi.periodo_iva_id
                   AND ri.tipo='recibida' AND ri.estado='validada'),0)
          AS iva_retenido_por_terceros,
       pi.saldo_credito_anterior, pi.ajustes_credito
FROM periodo_iva pi;

CREATE INDEX idx_orden_compra_proveedor ON orden_compra_tela(proveedor_id);
CREATE INDEX idx_detalle_orden_compra ON detalle_orden_compra_tela(orden_compra_id);
CREATE INDEX idx_compra_proveedor_fecha ON compra(proveedor_id,fecha_compra DESC);
CREATE INDEX idx_detalle_compra_compra ON detalle_compra(compra_id);
CREATE INDEX idx_credito_iva_periodo ON credito_iva_compra(periodo_iva_id);
CREATE INDEX idx_cuenta_pagar_proveedor ON cuenta_pagar(proveedor_id);
CREATE INDEX idx_cuenta_cobrar_cliente ON cuenta_cobrar(cliente_id);
CREATE INDEX idx_comprobante_venta_pedido ON comprobante_venta(pedido_id);
CREATE INDEX idx_retencion_periodo ON retencion_iva(periodo_iva_id);



-- ===== 14. ENTREGA FISICA PARCIAL + SEGUIMIENTO POR CAMISA (v1.2) =====
-- Los 'envios' representan salida logistica; una recepcion confirmada puede ser
-- menor que las unidades despachadas y suceder en varias fechas.
-- Las entregas personales / retiro en tienda utilizan 'envio' como despacho
-- interno sin requerir transportadora ni numero de guia.
ALTER TABLE envio
  ADD COLUMN modalidad_entrega VARCHAR(25) NOT NULL DEFAULT 'transportadora'
  CHECK (modalidad_entrega IN ('transportadora','mensajeria','entrega_personal','retiro'));

-- Cantidades canceladas liberan compromisos, PERO no crean por si solas
-- credito contable: hay que registrar ajuste y, de ser necesario, nota de
-- credito SRI en la misma operacion de negocio.
ALTER TABLE detalle_pedido
  ADD COLUMN cantidad_cancelada INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN motivo_cancelacion TEXT,
  ADD CONSTRAINT ck_detalle_cantidad_cancelada
      CHECK (cantidad_cancelada >= 0 AND cantidad_cancelada <= cantidad);

CREATE TABLE entrega_pedido (
    entrega_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    envio_id BIGINT NOT NULL REFERENCES envio(envio_id),
    fecha_entrega TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    receptor_nombre VARCHAR(150),
    comprobante_recepcion_url TEXT,
    estado VARCHAR(20) NOT NULL DEFAULT 'borrador'
      CHECK (estado IN ('borrador','confirmada','anulada')),
    observaciones TEXT,
    UNIQUE (entrega_id, envio_id)
);

-- Se duplican envio_id en las FKs compuestas para asegurar que una
-- entrega no pueda incluir una linea despachada en otro envio.
ALTER TABLE detalle_envio
  ADD CONSTRAINT uq_detalle_envio_y_envio UNIQUE (detalle_envio_id, envio_id);

CREATE TABLE detalle_entrega (
    detalle_entrega_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    entrega_id BIGINT NOT NULL,
    envio_id BIGINT NOT NULL,
    detalle_envio_id BIGINT NOT NULL,
    cantidad_entregada INTEGER NOT NULL CHECK (cantidad_entregada > 0),
    notas TEXT,
    FOREIGN KEY (entrega_id, envio_id)
      REFERENCES entrega_pedido(entrega_id, envio_id),
    FOREIGN KEY (detalle_envio_id, envio_id)
      REFERENCES detalle_envio(detalle_envio_id, envio_id),
    UNIQUE (entrega_id, detalle_envio_id)
);

-- Cada renglon calcula unidades solicitadas, canceladas, despachadas,
-- recibidas por el cliente, en transito y aun por despachar.
-- Una devolucion posterior NO borra una entrega historica: se registra
-- aparte en detalle_devolucion y genera, si aplica, una linea de reemplazo.
CREATE VIEW v_cumplimiento_detalle_pedido WITH (security_invoker=true) AS
SELECT dp.detalle_pedido_id,
       dp.pedido_id,
       dp.variante_id,
       dp.sku_vendido,
       dp.descripcion_vendida,
       dp.cantidad AS cantidad_original,
       dp.cantidad_cancelada,
       (dp.cantidad - dp.cantidad_cancelada)::INTEGER AS cantidad_comprometida,
       COALESCE(s.cantidad_despachada,0)::INTEGER AS cantidad_despachada,
       COALESCE(r.cantidad_entregada,0)::INTEGER AS cantidad_entregada,
       GREATEST(dp.cantidad - dp.cantidad_cancelada
                - COALESCE(s.cantidad_despachada,0),0)::INTEGER AS pendiente_despacho,
       GREATEST(COALESCE(s.cantidad_despachada,0)
                - COALESCE(r.cantidad_entregada,0),0)::INTEGER AS despachado_no_entregado,
       GREATEST(dp.cantidad - dp.cantidad_cancelada
                - COALESCE(r.cantidad_entregada,0),0)::INTEGER AS pendiente_entrega,
       CASE
          WHEN dp.cantidad - dp.cantidad_cancelada = 0 THEN 'cancelado'
          WHEN COALESCE(r.cantidad_entregada,0) >= dp.cantidad - dp.cantidad_cancelada
               THEN 'entregado'
          WHEN COALESCE(r.cantidad_entregada,0) > 0 THEN 'parcialmente_entregado'
          ELSE 'pendiente'
       END AS estado_entrega_linea
FROM detalle_pedido dp
LEFT JOIN (
    SELECT de.detalle_pedido_id, SUM(de.cantidad)::INTEGER AS cantidad_despachada
    FROM detalle_envio de
    JOIN envio e ON e.envio_id = de.envio_id
    WHERE e.estado IN ('despachado','parcialmente_entregado','entregado','incidencia')
    GROUP BY de.detalle_pedido_id
) s ON s.detalle_pedido_id = dp.detalle_pedido_id
LEFT JOIN (
    SELECT de.detalle_pedido_id, SUM(dent.cantidad_entregada)::INTEGER AS cantidad_entregada
    FROM detalle_entrega dent
    JOIN entrega_pedido ent ON ent.entrega_id=dent.entrega_id
    JOIN detalle_envio de ON de.detalle_envio_id=dent.detalle_envio_id
    JOIN envio e ON e.envio_id=de.envio_id
    WHERE ent.estado='confirmada' AND e.estado IN ('despachado','parcialmente_entregado','entregado','incidencia')
    GROUP BY de.detalle_pedido_id
) r ON r.detalle_pedido_id=dp.detalle_pedido_id;

-- Estado de entrega *derivado*, independiente de pedido.estado, del pago,
-- de la facturacion y del estado logistico de cada envio.
CREATE VIEW v_estado_entrega_pedido WITH (security_invoker=true) AS
SELECT p.pedido_id, p.cliente_id, p.fecha_pedido,
       p.estado AS estado_comercial,
       COALESCE(SUM(cd.cantidad_original),0)::INTEGER AS unidades_solicitadas,
       COALESCE(SUM(cd.cantidad_cancelada),0)::INTEGER AS unidades_canceladas,
       COALESCE(SUM(cd.cantidad_comprometida),0)::INTEGER AS unidades_por_cumplir,
       COALESCE(SUM(cd.cantidad_despachada),0)::INTEGER AS unidades_despachadas,
       COALESCE(SUM(cd.cantidad_entregada),0)::INTEGER AS unidades_entregadas,
       COALESCE(SUM(cd.pendiente_despacho),0)::INTEGER AS unidades_por_despachar,
       COALESCE(SUM(cd.despachado_no_entregado),0)::INTEGER AS unidades_en_transito,
       COALESCE(SUM(cd.pendiente_entrega),0)::INTEGER AS unidades_pendientes_entrega,
       CASE
         WHEN p.estado='cancelado' THEN 'cancelado'
         WHEN COUNT(cd.detalle_pedido_id)=0 THEN 'sin_articulos'
         WHEN COALESCE(SUM(cd.cantidad_comprometida),0)=0 THEN 'cancelado'
         WHEN COALESCE(SUM(cd.cantidad_entregada),0)
              >= COALESCE(SUM(cd.cantidad_comprometida),0) THEN 'entregado'
         WHEN COALESCE(SUM(cd.cantidad_entregada),0)>0 THEN 'parcialmente_entregado'
         ELSE 'pendiente'
       END AS estado_entrega
FROM pedido p
LEFT JOIN v_cumplimiento_detalle_pedido cd ON cd.pedido_id=p.pedido_id
GROUP BY p.pedido_id, p.cliente_id, p.fecha_pedido, p.estado;

-- Para la pantalla 'Pedidos por entregar': incluye pendientes y parciales.
CREATE VIEW v_pedidos_por_entregar WITH (security_invoker=true) AS
SELECT ep.*, c.nombre_completo AS nombre_cliente
FROM v_estado_entrega_pedido ep
JOIN cliente c ON c.cliente_id=ep.cliente_id
WHERE ep.estado_comercial NOT IN ('borrador','cancelado')
  AND ep.estado_entrega IN ('pendiente','parcialmente_entregado');

-- Para la pantalla 'Pedidos entregados': solo confirmaciones reales.
CREATE VIEW v_pedidos_entregados WITH (security_invoker=true) AS
SELECT ep.*, c.nombre_completo AS nombre_cliente
FROM v_estado_entrega_pedido ep
JOIN cliente c ON c.cliente_id=ep.cliente_id
WHERE ep.estado_comercial <> 'cancelado'
  AND ep.estado_entrega='entregado';

CREATE INDEX idx_entrega_envio_fecha ON entrega_pedido(envio_id,fecha_entrega DESC);
CREATE INDEX idx_detalle_entrega_linea_envio ON detalle_entrega(detalle_envio_id);
CREATE INDEX idx_pedido_estado_fecha ON pedido(estado, fecha_pedido DESC);

-- ===== 15. VERSIONADO DE TARIFAS IVA =====
-- Nunca escribir tasas historicas de Ecuador de forma automatica ni fija.
-- El sistema aplica la tasa por fecha y operacion, bajo validacion tributaria.
CREATE TABLE tarifa_iva_vigencia (
    tarifa_iva_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo_tarifa VARCHAR(30) NOT NULL, -- p.ej. 'general', 'tarifa_cero'
    porcentaje NUMERIC(5,2) NOT NULL CHECK (porcentaje BETWEEN 0 AND 100),
    vigente_desde DATE NOT NULL,
    vigente_hasta DATE,
    sustento_normativo TEXT,
    notas TEXT,
    UNIQUE (codigo_tarifa, vigente_desde),
    CHECK (vigente_hasta IS NULL OR vigente_hasta >= vigente_desde)
);

-- Reglas criticas para la capa de aplicacion/transacciones:
-- 1) Confirmar entregas solo para despachos efectivamente realizados.
-- 2) SUM(detalle_entrega.cantidad_entregada) confirmada <= detalle_envio.cantidad.
-- 3) Entregado + pendiente despacho no sobrepasa cantidad_comprometida.
-- 4) Despachado <= cantidad_comprometida; bloquear nuevas cancelaciones si
--    existen entregas o despachos que exceden el nuevo compromiso.
-- 5) Confirmar despacho y consumo de inventario en una unica transaccion.
-- 6) Nunca duplicar entregas por reintentos: confirmar eventos con idempotencia.
-- 7) Si se devuelve producto, NO restar unidades entregadas historicas;
--    registrar devolucion/reemplazo y su nota de credito cuando corresponda.
-- 8) No actualizar totales financieros por una simple entrega: obligaciones
--    e impuestos dependen de sus propios hechos y comprobantes.
-- 9) Para pedidos preexistentes marcados 'entregado' en v1.1, migrar el
--    historial real a entrega_pedido y detalle_entrega antes de usar vistas:
--    la marca antigua envio.estado='entregado' no sustituye comprobacion.
-- 10) No permitir superposiciones por codigo_tarifa de vigencias IVA.



-- REGLAS DE IMPLEMENTACIÓN ADICIONALES (v1.1 + v1.2):
-- L. En una compra con factura, verificar proveedor/RUC, clave SRI y montos
--    de documento antes de declarar crédito tributario (no basta existencia).
-- M. credito_iva_compra.iva_elegible <= detalle_compra.iva_facturado;
--    verificar tratamiento fiscal, destino y proporcionalidad según régimen.
-- N. Evitar duplicar el gasto al registrar simultáneamente detalle_compra
--    y gasto. Los costos inventariables deben reconciliarse con lote_tela.
-- O. Vincular compra y cuenta_pagar una sola vez por factura. Pagar costura
--    usando pago_costurera; NO crear otra cuenta_pagar por el mismo encargo.
-- P. Saldos negativos por anticipos o exceso de abonos son saldos a favor;
--    no borrarlos ni convertirlos silenciosamente en deuda cero.
-- Q. Las órdenes de compra no ingresan stock; ingreso solo al recibir.
-- R. Reconciliar comprobantes_venta con líneas del pedido y devoluciones;
--    notas de crédito y retenciones requieren validación documental.
-- S. Reportes IVA son auxiliares, no formulario oficial del SRI. Actualizar
--    parámetros tributarios según el régimen del contribuyente y normativa.

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
   IF TG_TABLE_NAME='lote_producto' AND (a->>'costo_finalizado')::boolean AND
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
   IF TG_TABLE_NAME='pedido' AND (a->>'estado')<>'borrador' THEN
     IF (b->>'estado')='borrador' OR (a-ARRAY['estado','notas_venta','actualizado_en','fecha_actualizacion']) IS DISTINCT FROM
       (b-ARRAY['estado','notas_venta','actualizado_en','fecha_actualizacion']) THEN RAISE EXCEPTION 'Pedido confirmado inmutable'; END IF;
   END IF;
   IF TG_TABLE_NAME='detalle_encargo_costura' AND EXISTS(SELECT 1 FROM bm.detalle_recepcion_costura WHERE detalle_encargo_id=(a->>'detalle_encargo_id')::bigint)
     THEN RAISE EXCEPTION 'Encargo con recepción: no cambiar cantidades ni tarifa'; END IF;
   IF TG_TABLE_NAME='lote_tela' AND EXISTS(SELECT 1 FROM bm.movimiento_tela WHERE lote_tela_id=(a->>'lote_tela_id')::bigint AND tipo='consumo')
     AND (a-ARRAY['notas','actualizado_en']) IS DISTINCT FROM (b-ARRAY['notas','actualizado_en'])
     THEN RAISE EXCEPTION 'Tela ya consumida: costo y origen inmutables'; END IF;
   IF TG_TABLE_NAME IN ('pago_pedido','pago_costurera','reembolso','abono_cuenta_pagar','abono_cuenta_cobrar') AND
     a->>'estado' NOT IN ('pendiente') AND
     ((a-ARRAY['estado','actualizado_en','notas']) IS DISTINCT FROM (b-ARRAY['estado','actualizado_en','notas'])
       OR b->>'estado' NOT IN (a->>'estado','anulado'))
     THEN RAISE EXCEPTION 'Pago registrado: solo se permite anulación documentada'; END IF;
   IF TG_TABLE_NAME='detalle_envio' AND EXISTS(SELECT 1 FROM bm.envio WHERE envio_id=(a->>'envio_id')::bigint AND estado<>'preparando')
     THEN RAISE EXCEPTION 'Despacho realizado inmutable'; END IF;
   IF TG_TABLE_NAME='envio' AND (a->>'estado')<>'preparando' AND
      ((a-ARRAY['estado','fecha_entrega','notas','actualizado_en']) IS DISTINCT FROM (b-ARRAY['estado','fecha_entrega','notas','actualizado_en'])
       OR (b->>'estado') IN ('preparando','cancelado')) THEN RAISE EXCEPTION 'Despacho realizado: resolver mediante devolución o incidencia'; END IF;
   IF TG_TABLE_NAME='detalle_entrega' AND EXISTS(SELECT 1 FROM bm.entrega_pedido WHERE entrega_id=(a->>'entrega_id')::bigint AND estado<>'borrador')
     THEN RAISE EXCEPTION 'Entrega confirmada inmutable'; END IF;
   IF TG_TABLE_NAME='entrega_pedido' AND (a->>'estado')<>'borrador' THEN RAISE EXCEPTION 'Entrega confirmada inmutable'; END IF;
   IF TG_TABLE_NAME='detalle_devolucion' AND EXISTS(SELECT 1 FROM bm.devolucion_pedido WHERE devolucion_id=(a->>'devolucion_id')::bigint AND estado IN ('aprobada','resuelta'))
     THEN RAISE EXCEPTION 'Devolucion aprobada inmutable'; END IF;
   IF TG_TABLE_NAME='devolucion_pedido' AND (a->>'estado') IN ('aprobada','resuelta') AND
     ((a-ARRAY['estado','actualizado_en']) IS DISTINCT FROM (b-ARRAY['estado','actualizado_en']) OR (b->>'estado') NOT IN ('aprobada','resuelta'))
     THEN RAISE EXCEPTION 'No reescribir devolución aprobada'; END IF;
   IF TG_TABLE_NAME='tarifa_iva_vigencia' AND EXISTS(SELECT 1 FROM bm.detalle_pedido dp WHERE dp.codigo_tarifa=(a->>'codigo_tarifa') AND dp.fecha_tributaria BETWEEN (a->>'vigente_desde')::date AND coalesce((a->>'vigente_hasta')::date,'infinity'::date))
      AND ((b->>'porcentaje')::numeric<>(a->>'porcentaje')::numeric OR (b->>'codigo_tarifa')<>(a->>'codigo_tarifa') OR (b->>'vigente_desde')::date<>(a->>'vigente_desde')::date)
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

CREATE FUNCTION bm.validar_integridad() RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,bm AS $$
BEGIN
IF EXISTS(SELECT 1 FROM bm.ajuste_pedido a WHERE a.destino='prenda' AND a.clase<>'cancelacion' AND NOT EXISTS(SELECT 1 FROM bm.detalle_envio d JOIN bm.envio e USING(envio_id) WHERE d.detalle_pedido_id=a.detalle_pedido_id AND e.estado IN ('despachado','parcialmente_entregado','entregado','incidencia') AND e.fecha_envio<=a.fecha)) THEN RAISE EXCEPTION 'Ajuste comercial requiere despacho previo; negociar precio en borrador antes del despacho' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.v_saldo_pedido WHERE total_neto_pedido<0) THEN RAISE EXCEPTION 'Crédito total excede valor neto del pedido' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.pedido p WHERE p.estado NOT IN ('borrador','cancelado') AND (p.fecha_confirmacion IS NULL OR p.fecha_confirmacion<p.fecha_pedido OR NOT EXISTS(SELECT 1 FROM bm.detalle_pedido d WHERE d.pedido_id=p.pedido_id))) THEN RAISE EXCEPTION 'Pedido confirmado requiere líneas y fecha de confirmación' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.detalle_pedido d WHERE coalesce((SELECT sum(a.monto_subtotal+a.monto_iva) FROM bm.ajuste_pedido a WHERE a.detalle_pedido_id=d.detalle_pedido_id AND a.clase='cancelacion'),0)<>-d.cantidad_cancelada*d.precio_unitario_final) THEN RAISE EXCEPTION 'Cancelación requiere ajuste económico exacto' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.pedido p JOIN bm.detalle_pedido d USING(pedido_id) WHERE p.estado='cancelado' AND d.cantidad_cancelada<>d.cantidad) THEN RAISE EXCEPTION 'Pedido cancelado conserva compromisos' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.ajuste_pedido a JOIN bm.detalle_pedido d USING(detalle_pedido_id) WHERE abs(a.monto_iva-round(a.monto_subtotal*d.porcentaje_iva/100,2))>0.01) THEN RAISE EXCEPTION 'IVA del ajuste no corresponde a su línea' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.pedido p WHERE p.costo_envio_cobrado>0 AND p.envio_tratamiento_iva IN ('gravado','tarifa_0') AND NOT EXISTS(SELECT 1 FROM bm.tarifa_iva_vigencia t WHERE t.codigo_tarifa=p.envio_codigo_tarifa AND t.porcentaje=p.envio_porcentaje_iva AND p.envio_fecha_tributaria BETWEEN t.vigente_desde AND coalesce(t.vigente_hasta,'infinity'::date))) THEN RAISE EXCEPTION 'Tarifa de envío no corresponde a su fecha' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.v_stock_lote_producto WHERE stock_fisico<0 OR stock_disponible<0) THEN RAISE EXCEPTION 'Stock físico o disponible negativo' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM (SELECT sum(delta) OVER(PARTITION BY lote_producto_id ORDER BY fecha) saldo FROM (SELECT lote_producto_id,fecha,sum(cantidad_delta) delta FROM bm.movimiento_producto GROUP BY 1,2) d) s WHERE saldo<0) THEN RAISE EXCEPTION 'Stock histórico de prendas negativo' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM (SELECT sum(delta) OVER(PARTITION BY lote_tela_id,ubicacion ORDER BY fecha) saldo FROM (SELECT lote_tela_id,ubicacion,fecha,sum(delta) delta FROM (SELECT lote_tela_id,destino_ubicacion_id ubicacion,fecha,metros delta FROM bm.movimiento_tela WHERE destino_ubicacion_id IS NOT NULL UNION ALL SELECT lote_tela_id,origen_ubicacion_id,fecha,-metros FROM bm.movimiento_tela WHERE origen_ubicacion_id IS NOT NULL) m GROUP BY 1,2,3) d) s WHERE saldo<0) THEN RAISE EXCEPTION 'Saldo histórico de tela negativo' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.detalle_envio de JOIN bm.envio e USING(envio_id) JOIN bm.detalle_pedido dp USING(detalle_pedido_id) JOIN bm.lote_producto lp USING(lote_producto_id) WHERE e.pedido_id<>dp.pedido_id OR lp.variante_id<>dp.variante_id) THEN RAISE EXCEPTION 'Pedido, variante o lote incompatible en envío' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.reserva_producto r JOIN bm.detalle_pedido d USING(detalle_pedido_id) JOIN bm.pedido p USING(pedido_id) JOIN bm.lote_producto l USING(lote_producto_id) WHERE r.estado='activa' AND (l.variante_id<>d.variante_id OR p.estado IN ('borrador','cancelado'))) THEN RAISE EXCEPTION 'Reserva incompatible o de pedido no confirmado' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.reserva_producto r JOIN bm.v_cumplimiento_detalle_pedido c USING(detalle_pedido_id) WHERE r.estado='activa' GROUP BY r.detalle_pedido_id,c.pendiente_despacho HAVING sum(r.cantidad)>c.pendiente_despacho) THEN RAISE EXCEPTION 'Reservas exceden compromiso pendiente' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.lote_producto l JOIN bm.detalle_recepcion_costura r USING(detalle_recepcion_id) JOIN bm.detalle_encargo_costura e USING(detalle_encargo_id) WHERE l.variante_id<>e.variante_id OR r.cantidad_aceptada=0) THEN RAISE EXCEPTION 'Lote no coincide con recepción o no hay prendas aceptadas' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.detalle_recepcion_costura r JOIN bm.detalle_encargo_costura e USING(detalle_encargo_id) GROUP BY e.detalle_encargo_id,e.cantidad_solicitada HAVING sum(r.cantidad_recibida)>e.cantidad_solicitada) THEN RAISE EXCEPTION 'Recepción excede encargo' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.detalle_recepcion_costura r JOIN bm.recepcion_costura rc USING(recepcion_id) LEFT JOIN bm.lote_producto l USING(detalle_recepcion_id) LEFT JOIN bm.movimiento_producto m ON m.lote_producto_id=l.lote_producto_id AND m.tipo='produccion' WHERE r.cantidad_aceptada>0 AND (m.movimiento_producto_id IS NULL OR m.cantidad_delta<>r.cantidad_aceptada OR m.fecha<>rc.fecha_recepcion)) THEN RAISE EXCEPTION 'Toda recepción aceptada requiere lote y movimiento de producción exacto' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.movimiento_producto m JOIN bm.lote_producto l USING(lote_producto_id) JOIN bm.detalle_recepcion_costura r USING(detalle_recepcion_id) JOIN bm.recepcion_costura rc USING(recepcion_id) WHERE m.tipo='produccion' AND (m.cantidad_delta<>r.cantidad_aceptada OR m.fecha<>rc.fecha_recepcion)) THEN RAISE EXCEPTION 'Producción debe coincidir con cantidad y fecha de recepción' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.v_cumplimiento_detalle_pedido WHERE cantidad_despachada>cantidad_comprometida OR cantidad_entregada>cantidad_despachada) THEN RAISE EXCEPTION 'Despacho excede pedido o entrega excede despacho' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.detalle_entrega d JOIN bm.entrega_pedido e USING(entrega_id) JOIN bm.detalle_envio s USING(detalle_envio_id) WHERE e.estado='confirmada' GROUP BY s.detalle_envio_id,s.cantidad HAVING sum(d.cantidad_entregada)>s.cantidad) THEN RAISE EXCEPTION 'Recepciones de cliente exceden línea de despacho' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.entrega_pedido d JOIN bm.envio e USING(envio_id) WHERE d.estado='confirmada' AND (e.estado NOT IN ('despachado','parcialmente_entregado','entregado','incidencia') OR d.fecha_entrega<e.fecha_envio OR NOT EXISTS(SELECT 1 FROM bm.detalle_entrega x WHERE x.entrega_id=d.entrega_id))) THEN RAISE EXCEPTION 'Entrega sin despacho real o anterior al despacho' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.envio e JOIN bm.pedido p USING(pedido_id) WHERE e.estado IN ('despachado','parcialmente_entregado','entregado','incidencia') AND (e.fecha_envio IS NULL OR e.fecha_envio<p.fecha_pedido OR p.estado IN ('borrador','cancelado') OR NOT EXISTS(SELECT 1 FROM bm.detalle_envio d WHERE d.envio_id=e.envio_id))) THEN RAISE EXCEPTION 'Despacho sin fecha, sin líneas o de pedido no confirmado' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.detalle_envio d JOIN bm.envio e USING(envio_id) LEFT JOIN bm.movimiento_producto m ON m.detalle_envio_id=d.detalle_envio_id WHERE (e.estado IN ('despachado','parcialmente_entregado','entregado','incidencia') AND (m.movimiento_producto_id IS NULL OR m.tipo<>'venta' OR m.cantidad_delta<>-d.cantidad OR m.lote_producto_id<>d.lote_producto_id OR m.fecha<>e.fecha_envio)) OR (e.estado IN ('preparando','cancelado') AND m.movimiento_producto_id IS NOT NULL)) THEN RAISE EXCEPTION 'Despacho y salida de inventario deben coincidir exactamente' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.detalle_devolucion dd JOIN bm.devolucion_pedido d USING(devolucion_id) JOIN bm.detalle_envio de USING(detalle_envio_id) JOIN bm.envio e USING(envio_id) LEFT JOIN bm.detalle_pedido rp ON rp.detalle_pedido_id=dd.detalle_pedido_reemplazo_id WHERE d.pedido_id<>e.pedido_id OR (rp.detalle_pedido_id IS NOT NULL AND (rp.pedido_id<>d.pedido_id OR rp.tipo_linea<>'reemplazo'))) THEN RAISE EXCEPTION 'Devolución o reemplazo corresponde a otro pedido' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.detalle_devolucion dd JOIN bm.devolucion_pedido d USING(devolucion_id) JOIN bm.detalle_envio de USING(detalle_envio_id) JOIN bm.detalle_pedido dp USING(detalle_pedido_id) WHERE d.estado IN ('aprobada','resuelta') GROUP BY de.detalle_envio_id,de.cantidad,dp.cantidad,dp.subtotal_linea,dp.valor_iva_linea HAVING sum(dd.cantidad)>de.cantidad OR sum(dd.credito_subtotal)>round(de.cantidad*dp.subtotal_linea/dp.cantidad,2) OR sum(dd.credito_iva)>round(de.cantidad*dp.valor_iva_linea/dp.cantidad,2)) THEN RAISE EXCEPTION 'Devolución excede cantidad o importe vendido' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.devolucion_pedido d JOIN bm.detalle_devolucion dd USING(devolucion_id) JOIN bm.detalle_envio de USING(detalle_envio_id) JOIN bm.envio e USING(envio_id) WHERE d.estado IN ('aprobada','resuelta') AND (d.fecha_resolucion IS NULL OR d.fecha_resolucion<e.fecha_envio OR e.estado IN ('preparando','cancelado'))) THEN RAISE EXCEPTION 'Devolución aprobada sin fecha o anterior al despacho' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.detalle_devolucion dd JOIN bm.devolucion_pedido d USING(devolucion_id) JOIN bm.detalle_envio de USING(detalle_envio_id) LEFT JOIN bm.movimiento_producto m USING(detalle_devolucion_id) WHERE (d.estado IN ('aprobada','resuelta') AND dd.reingresa_inventario AND (m.movimiento_producto_id IS NULL OR m.tipo<>'devolucion' OR m.lote_producto_id<>de.lote_producto_id OR m.cantidad_delta<>dd.cantidad OR m.fecha<d.fecha_resolucion)) OR ((d.estado NOT IN ('aprobada','resuelta') OR NOT dd.reingresa_inventario) AND m.movimiento_producto_id IS NOT NULL)) THEN RAISE EXCEPTION 'Devolución aprobada y reingreso de stock deben coincidir' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.reembolso r JOIN bm.devolucion_pedido d USING(devolucion_id) WHERE r.pedido_id<>d.pedido_id OR (r.estado='completado' AND d.estado NOT IN ('aprobada','resuelta'))) THEN RAISE EXCEPTION 'Reembolso de otro pedido o de devolución no aprobada' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.v_saldo_pedido WHERE dinero_reembolsado>dinero_recibido OR (dinero_reembolsado>0 AND saldo_pendiente>0)) THEN RAISE EXCEPTION 'Reembolso supera dinero cobrado o saldo a favor' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.ajuste_pedido a JOIN bm.detalle_pedido d USING(detalle_pedido_id) WHERE a.pedido_id<>d.pedido_id) THEN RAISE EXCEPTION 'Ajuste de otro pedido' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.detalle_pedido d WHERE d.subtotal_linea+coalesce((SELECT sum(monto_subtotal) FROM bm.ajuste_pedido a WHERE a.detalle_pedido_id=d.detalle_pedido_id),0)-coalesce((SELECT sum(dd.credito_subtotal) FROM bm.detalle_devolucion dd JOIN bm.devolucion_pedido dev USING(devolucion_id) JOIN bm.detalle_envio de USING(detalle_envio_id) WHERE de.detalle_pedido_id=d.detalle_pedido_id AND dev.estado IN ('aprobada','resuelta')),0)<0) THEN RAISE EXCEPTION 'Descuento deja importe de prenda negativo' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.detalle_pedido d JOIN bm.pedido p USING(pedido_id) WHERE p.estado<>'borrador' AND d.tratamiento_iva='por_definir') THEN RAISE EXCEPTION 'Pedido confirmado sin clasificación tributaria' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.detalle_pedido d WHERE d.tratamiento_iva IN ('gravado','tarifa_0') AND NOT EXISTS(SELECT 1 FROM bm.tarifa_iva_vigencia t WHERE t.codigo_tarifa=d.codigo_tarifa AND t.porcentaje=d.porcentaje_iva AND d.fecha_tributaria BETWEEN t.vigente_desde AND coalesce(t.vigente_hasta,'infinity'::date))) THEN RAISE EXCEPTION 'Tarifa no corresponde a fecha tributaria' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.tarifa_iva_vigencia a JOIN bm.tarifa_iva_vigencia b ON a.tarifa_iva_id<b.tarifa_iva_id AND a.codigo_tarifa=b.codigo_tarifa AND a.vigente_desde<=coalesce(b.vigente_hasta,'infinity'::date) AND b.vigente_desde<=coalesce(a.vigente_hasta,'infinity'::date)) THEN RAISE EXCEPTION 'Vigencias IVA superpuestas' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.periodo_iva a JOIN bm.periodo_iva b ON a.periodo_iva_id<b.periodo_iva_id AND a.fecha_inicio<=b.fecha_fin AND b.fecha_inicio<=a.fecha_fin) THEN RAISE EXCEPTION 'Periodos IVA superpuestos' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.credito_iva_compra c JOIN bm.detalle_compra d USING(detalle_compra_id) JOIN bm.compra f USING(compra_id) WHERE c.iva_elegible>d.iva_facturado OR (c.estado='aprobado' AND (f.estado_verificacion<>'verificado' OR f.tipo_comprobante='sin_comprobante' OR f.numero_factura IS NULL))) THEN RAISE EXCEPTION 'Crédito IVA excede factura o carece de verificación' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.comprobante_venta n JOIN bm.comprobante_venta f ON f.comprobante_venta_id=n.documento_relacionado_id WHERE n.pedido_id<>f.pedido_id OR f.tipo_comprobante<>'factura' OR n.fecha_emision<f.fecha_emision) THEN RAISE EXCEPTION 'Documento relacionado de otro pedido o sin factura origen' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.comprobante_venta n JOIN bm.comprobante_venta f ON f.comprobante_venta_id=n.documento_relacionado_id WHERE n.tipo_comprobante='nota_credito' AND n.estado_sri='autorizado' GROUP BY f.comprobante_venta_id,f.subtotal_sin_iva,f.valor_iva HAVING sum(n.subtotal_sin_iva)>f.subtotal_sin_iva OR sum(n.valor_iva)>f.valor_iva) THEN RAISE EXCEPTION 'Notas de crédito exceden factura' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.asignacion_gasto_produccion a JOIN bm.gasto g USING(gasto_id) GROUP BY g.gasto_id,g.costo_total HAVING sum(a.monto_asignado)>g.costo_total) THEN RAISE EXCEPTION 'Asignaciones exceden gasto' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.asignacion_gasto_produccion a JOIN bm.gasto g USING(gasto_id) JOIN bm.detalle_encargo_costura e USING(detalle_encargo_id) WHERE g.encargo_id IS NOT NULL AND g.encargo_id<>e.encargo_id) THEN RAISE EXCEPTION 'Gasto asignado a otro encargo' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.gasto g JOIN bm.detalle_compra d USING(detalle_compra_id) WHERE d.tipo='tela' OR EXISTS(SELECT 1 FROM bm.lote_tela l WHERE l.detalle_compra_id=d.detalle_compra_id)) THEN RAISE EXCEPTION 'Compra duplicada como tela y gasto o tipo incorrecto' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.lote_tela l JOIN bm.detalle_compra d USING(detalle_compra_id) WHERE d.tipo<>'tela' OR d.tela_id<>l.tela_id UNION ALL SELECT 1 FROM bm.lote_tela l JOIN bm.detalle_compra d USING(detalle_compra_id) GROUP BY d.detalle_compra_id,d.cantidad HAVING sum(l.metros_comprados)>d.cantidad) THEN RAISE EXCEPTION 'Lote de tela de otra compra o cantidad excedida' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.lote_tela l WHERE coalesce((SELECT sum(metros) FROM bm.movimiento_tela m WHERE m.lote_tela_id=l.lote_tela_id AND tipo='compra'),0)<>l.metros_comprados) THEN RAISE EXCEPTION 'Entrada de compra no coincide con lote' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.movimiento_tela m JOIN bm.detalle_encargo_costura d USING(detalle_encargo_id) JOIN bm.encargo_costura e ON e.encargo_id=d.encargo_id JOIN bm.ubicacion_tela u ON u.ubicacion_id=m.origen_ubicacion_id WHERE m.tipo='consumo' AND (u.tipo<>'costurera' OR u.costurera_id<>e.costurera_id)) THEN RAISE EXCEPTION 'Consumo de tela de otra costurera' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.lote_producto l JOIN bm.detalle_recepcion_costura r USING(detalle_recepcion_id) JOIN bm.detalle_encargo_costura d USING(detalle_encargo_id) JOIN bm.encargo_costura e ON e.encargo_id=d.encargo_id WHERE l.costo_finalizado AND (e.estado<>'cerrado' OR l.costo_mano_obra_unitario<>d.tarifa_mano_obra_unitaria OR abs(l.costo_tela_unitario-coalesce((SELECT sum(m.metros*t.costo_metro) FROM bm.movimiento_tela m JOIN bm.lote_tela t USING(lote_tela_id) WHERE m.tipo='consumo' AND m.detalle_encargo_id=d.detalle_encargo_id),0)/nullif((SELECT sum(x.cantidad_aceptada) FROM bm.detalle_recepcion_costura x WHERE x.detalle_encargo_id=d.detalle_encargo_id),0))>0.0001 OR abs(l.costo_insumos_unitario-coalesce((SELECT sum(a.monto_asignado) FROM bm.asignacion_gasto_produccion a WHERE a.detalle_encargo_id=d.detalle_encargo_id),0)/nullif((SELECT sum(x.cantidad_aceptada) FROM bm.detalle_recepcion_costura x WHERE x.detalle_encargo_id=d.detalle_encargo_id),0))>0.0001)) THEN RAISE EXCEPTION 'Costo final no conciliado con tela, mano de obra o gastos' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.cuenta_pagar c JOIN bm.compra f USING(compra_id) WHERE c.proveedor_id IS DISTINCT FROM f.proveedor_id) THEN RAISE EXCEPTION 'Proveedor de deuda no coincide con compra' USING ERRCODE='23514'; END IF;
IF EXISTS(SELECT 1 FROM bm.cuenta_pagar c JOIN bm.abono_cuenta_pagar a USING(cuenta_pagar_id) WHERE c.estado='anulada' AND a.estado='confirmado' UNION ALL SELECT 1 FROM bm.cuenta_cobrar c JOIN bm.abono_cuenta_cobrar a USING(cuenta_cobrar_id) WHERE c.estado='anulada' AND a.estado='confirmado') THEN RAISE EXCEPTION 'Cuenta anulada mantiene abonos confirmados' USING ERRCODE='23514'; END IF;
END $$;

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

ALTER TABLE bm.categoria ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.categoria FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.categoria FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.categoria FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.categoria DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.categoria ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.categoria FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'categoria',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.categoria'::regclass AND i.indisprimary;
ALTER TABLE bm.talla ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.talla FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.talla FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.talla FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.talla DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.talla ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.talla FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'talla',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.talla'::regclass AND i.indisprimary;
ALTER TABLE bm.color ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.color FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.color FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.color FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.color DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.color ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.color FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'color',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.color'::regclass AND i.indisprimary;
ALTER TABLE bm.articulo ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.articulo FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.articulo FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.articulo FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.articulo DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.articulo ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.articulo FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'articulo',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.articulo'::regclass AND i.indisprimary;
ALTER TABLE bm.variante_articulo ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.variante_articulo FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.variante_articulo FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.variante_articulo FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.variante_articulo DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.variante_articulo ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.variante_articulo FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'variante_articulo',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.variante_articulo'::regclass AND i.indisprimary;
ALTER TABLE bm.consumo_estimado_tela ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.consumo_estimado_tela FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.consumo_estimado_tela FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.consumo_estimado_tela FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.consumo_estimado_tela DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.consumo_estimado_tela ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.consumo_estimado_tela FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'consumo_estimado_tela',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.consumo_estimado_tela'::regclass AND i.indisprimary;
ALTER TABLE bm.tela ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.tela FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.tela FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.tela FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.tela DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.tela ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.tela FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'tela',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.tela'::regclass AND i.indisprimary;
ALTER TABLE bm.lote_tela ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.lote_tela FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.lote_tela FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha_ingreso');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.lote_tela FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.lote_tela DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.lote_tela ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.lote_tela FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'lote_tela',a.attname,'fecha_ingreso' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.lote_tela'::regclass AND i.indisprimary;
ALTER TABLE bm.cliente ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.cliente FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.cliente FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.cliente FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.cliente DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.cliente ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.cliente FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'cliente',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.cliente'::regclass AND i.indisprimary;
ALTER TABLE bm.pedido ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.pedido FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.pedido FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha_pedido');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.pedido FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.pedido DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.pedido ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.pedido FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'pedido',a.attname,'fecha_pedido' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.pedido'::regclass AND i.indisprimary;
ALTER TABLE bm.detalle_pedido ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.detalle_pedido FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.detalle_pedido FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.detalle_pedido FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.detalle_pedido DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.detalle_pedido ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.detalle_pedido FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'detalle_pedido',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.detalle_pedido'::regclass AND i.indisprimary;
ALTER TABLE bm.costurera ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.costurera FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.costurera FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.costurera FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.costurera DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.costurera ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.costurera FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'costurera',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.costurera'::regclass AND i.indisprimary;
ALTER TABLE bm.ubicacion_tela ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.ubicacion_tela FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.ubicacion_tela FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.ubicacion_tela FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.ubicacion_tela DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.ubicacion_tela ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.ubicacion_tela FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'ubicacion_tela',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.ubicacion_tela'::regclass AND i.indisprimary;
ALTER TABLE bm.encargo_costura ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.encargo_costura FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.encargo_costura FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha_encargo');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.encargo_costura FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.encargo_costura DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.encargo_costura ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.encargo_costura FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'encargo_costura',a.attname,'fecha_encargo' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.encargo_costura'::regclass AND i.indisprimary;
ALTER TABLE bm.detalle_encargo_costura ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.detalle_encargo_costura FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.detalle_encargo_costura FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.detalle_encargo_costura FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.detalle_encargo_costura DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.detalle_encargo_costura ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.detalle_encargo_costura FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'detalle_encargo_costura',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.detalle_encargo_costura'::regclass AND i.indisprimary;
ALTER TABLE bm.movimiento_tela ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.movimiento_tela FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.movimiento_tela FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.movimiento_tela FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.movimiento_tela DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.movimiento_tela ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.movimiento_tela FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'movimiento_tela',a.attname,'fecha' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.movimiento_tela'::regclass AND i.indisprimary;
ALTER TABLE bm.recepcion_costura ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.recepcion_costura FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.recepcion_costura FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha_recepcion');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.recepcion_costura FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.recepcion_costura DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.recepcion_costura ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.recepcion_costura FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'recepcion_costura',a.attname,'fecha_recepcion' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.recepcion_costura'::regclass AND i.indisprimary;
ALTER TABLE bm.detalle_recepcion_costura ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.detalle_recepcion_costura FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.detalle_recepcion_costura FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.detalle_recepcion_costura FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.detalle_recepcion_costura DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.detalle_recepcion_costura ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.detalle_recepcion_costura FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'detalle_recepcion_costura',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.detalle_recepcion_costura'::regclass AND i.indisprimary;
ALTER TABLE bm.lote_producto ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.lote_producto FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.lote_producto FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha_alta');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.lote_producto FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.lote_producto DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.lote_producto ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.lote_producto FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'lote_producto',a.attname,'fecha_alta' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.lote_producto'::regclass AND i.indisprimary;
ALTER TABLE bm.tipo_gasto ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.tipo_gasto FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.tipo_gasto FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.tipo_gasto FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.tipo_gasto DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.tipo_gasto ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.tipo_gasto FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'tipo_gasto',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.tipo_gasto'::regclass AND i.indisprimary;
ALTER TABLE bm.gasto ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.gasto FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.gasto FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha_gasto');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.gasto FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.gasto DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.gasto ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.gasto FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'gasto',a.attname,'fecha_gasto' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.gasto'::regclass AND i.indisprimary;
ALTER TABLE bm.asignacion_gasto_produccion ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.asignacion_gasto_produccion FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.asignacion_gasto_produccion FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.asignacion_gasto_produccion FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.asignacion_gasto_produccion DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.asignacion_gasto_produccion ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.asignacion_gasto_produccion FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'asignacion_gasto_produccion',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.asignacion_gasto_produccion'::regclass AND i.indisprimary;
ALTER TABLE bm.pago_costurera ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.pago_costurera FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.pago_costurera FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha_pago');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.pago_costurera FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.pago_costurera DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.pago_costurera ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.pago_costurera FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'pago_costurera',a.attname,'fecha_pago' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.pago_costurera'::regclass AND i.indisprimary;
ALTER TABLE bm.pago_pedido ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.pago_pedido FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.pago_pedido FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha_pago');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.pago_pedido FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.pago_pedido DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.pago_pedido ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.pago_pedido FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'pago_pedido',a.attname,'fecha_pago' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.pago_pedido'::regclass AND i.indisprimary;
ALTER TABLE bm.envio ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.envio FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.envio FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.envio FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.envio DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.envio ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.envio FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'envio',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.envio'::regclass AND i.indisprimary;
ALTER TABLE bm.detalle_envio ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.detalle_envio FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.detalle_envio FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.detalle_envio FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.detalle_envio DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.detalle_envio ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.detalle_envio FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'detalle_envio',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.detalle_envio'::regclass AND i.indisprimary;
ALTER TABLE bm.devolucion_pedido ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.devolucion_pedido FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.devolucion_pedido FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha_solicitud');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.devolucion_pedido FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.devolucion_pedido DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.devolucion_pedido ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.devolucion_pedido FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'devolucion_pedido',a.attname,'fecha_solicitud' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.devolucion_pedido'::regclass AND i.indisprimary;
ALTER TABLE bm.detalle_devolucion ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.detalle_devolucion FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.detalle_devolucion FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.detalle_devolucion FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.detalle_devolucion DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.detalle_devolucion ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.detalle_devolucion FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'detalle_devolucion',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.detalle_devolucion'::regclass AND i.indisprimary;
ALTER TABLE bm.reembolso ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.reembolso FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.reembolso FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha_reembolso');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.reembolso FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.reembolso DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.reembolso ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.reembolso FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'reembolso',a.attname,'fecha_reembolso' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.reembolso'::regclass AND i.indisprimary;
ALTER TABLE bm.ajuste_pedido ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.ajuste_pedido FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.ajuste_pedido FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.ajuste_pedido FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.ajuste_pedido DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.ajuste_pedido ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.ajuste_pedido FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'ajuste_pedido',a.attname,'fecha' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.ajuste_pedido'::regclass AND i.indisprimary;
ALTER TABLE bm.movimiento_producto ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.movimiento_producto FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.movimiento_producto FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.movimiento_producto FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.movimiento_producto DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.movimiento_producto ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.movimiento_producto FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'movimiento_producto',a.attname,'fecha' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.movimiento_producto'::regclass AND i.indisprimary;
ALTER TABLE bm.reserva_producto ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.reserva_producto FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.reserva_producto FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.reserva_producto FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.reserva_producto DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.reserva_producto ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.reserva_producto FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'reserva_producto',a.attname,'fecha' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.reserva_producto'::regclass AND i.indisprimary;
ALTER TABLE bm.proveedor ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.proveedor FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.proveedor FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.proveedor FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.proveedor DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.proveedor ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.proveedor FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'proveedor',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.proveedor'::regclass AND i.indisprimary;
ALTER TABLE bm.orden_compra_tela ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.orden_compra_tela FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.orden_compra_tela FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha_orden');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.orden_compra_tela FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.orden_compra_tela DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.orden_compra_tela ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.orden_compra_tela FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'orden_compra_tela',a.attname,'fecha_orden' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.orden_compra_tela'::regclass AND i.indisprimary;
ALTER TABLE bm.detalle_orden_compra_tela ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.detalle_orden_compra_tela FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.detalle_orden_compra_tela FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.detalle_orden_compra_tela FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.detalle_orden_compra_tela DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.detalle_orden_compra_tela ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.detalle_orden_compra_tela FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'detalle_orden_compra_tela',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.detalle_orden_compra_tela'::regclass AND i.indisprimary;
ALTER TABLE bm.compra ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.compra FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.compra FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha_compra');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.compra FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.compra DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.compra ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.compra FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'compra',a.attname,'fecha_compra' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.compra'::regclass AND i.indisprimary;
ALTER TABLE bm.detalle_compra ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.detalle_compra FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.detalle_compra FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.detalle_compra FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.detalle_compra DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.detalle_compra ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.detalle_compra FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'detalle_compra',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.detalle_compra'::regclass AND i.indisprimary;
ALTER TABLE bm.configuracion_tributaria ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.configuracion_tributaria FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.configuracion_tributaria FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.configuracion_tributaria FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.configuracion_tributaria DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.configuracion_tributaria ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.configuracion_tributaria FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'configuracion_tributaria',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.configuracion_tributaria'::regclass AND i.indisprimary;
ALTER TABLE bm.periodo_iva ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.periodo_iva FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.periodo_iva FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.periodo_iva FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.periodo_iva DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.periodo_iva ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.periodo_iva FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'periodo_iva',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.periodo_iva'::regclass AND i.indisprimary;
ALTER TABLE bm.credito_iva_compra ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.credito_iva_compra FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.credito_iva_compra FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.credito_iva_compra FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.credito_iva_compra DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.credito_iva_compra ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.credito_iva_compra FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'credito_iva_compra',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.credito_iva_compra'::regclass AND i.indisprimary;
ALTER TABLE bm.comprobante_venta ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.comprobante_venta FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.comprobante_venta FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha_emision');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.comprobante_venta FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.comprobante_venta DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.comprobante_venta ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.comprobante_venta FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'comprobante_venta',a.attname,'fecha_emision' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.comprobante_venta'::regclass AND i.indisprimary;
ALTER TABLE bm.retencion_iva ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.retencion_iva FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.retencion_iva FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha_emision');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.retencion_iva FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.retencion_iva DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.retencion_iva ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.retencion_iva FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'retencion_iva',a.attname,'fecha_emision' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.retencion_iva'::regclass AND i.indisprimary;
ALTER TABLE bm.cuenta_pagar ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.cuenta_pagar FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.cuenta_pagar FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha_origen');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.cuenta_pagar FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.cuenta_pagar DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.cuenta_pagar ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.cuenta_pagar FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'cuenta_pagar',a.attname,'fecha_origen' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.cuenta_pagar'::regclass AND i.indisprimary;
ALTER TABLE bm.abono_cuenta_pagar ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.abono_cuenta_pagar FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.abono_cuenta_pagar FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha_pago');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.abono_cuenta_pagar FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.abono_cuenta_pagar DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.abono_cuenta_pagar ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.abono_cuenta_pagar FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'abono_cuenta_pagar',a.attname,'fecha_pago' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.abono_cuenta_pagar'::regclass AND i.indisprimary;
ALTER TABLE bm.cuenta_cobrar ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.cuenta_cobrar FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.cuenta_cobrar FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha_origen');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.cuenta_cobrar FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.cuenta_cobrar DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.cuenta_cobrar ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.cuenta_cobrar FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'cuenta_cobrar',a.attname,'fecha_origen' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.cuenta_cobrar'::regclass AND i.indisprimary;
ALTER TABLE bm.abono_cuenta_cobrar ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.abono_cuenta_cobrar FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.abono_cuenta_cobrar FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha_cobro');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.abono_cuenta_cobrar FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.abono_cuenta_cobrar DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.abono_cuenta_cobrar ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.abono_cuenta_cobrar FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'abono_cuenta_cobrar',a.attname,'fecha_cobro' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.abono_cuenta_cobrar'::regclass AND i.indisprimary;
ALTER TABLE bm.entrega_pedido ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.entrega_pedido FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.entrega_pedido FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('fecha_entrega');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.entrega_pedido FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.entrega_pedido DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.entrega_pedido ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.entrega_pedido FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'entrega_pedido',a.attname,'fecha_entrega' FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.entrega_pedido'::regclass AND i.indisprimary;
ALTER TABLE bm.detalle_entrega ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.detalle_entrega FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.detalle_entrega FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.detalle_entrega FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.detalle_entrega DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.detalle_entrega ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.detalle_entrega FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'detalle_entrega',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.detalle_entrega'::regclass AND i.indisprimary;
ALTER TABLE bm.tarifa_iva_vigencia ADD COLUMN registrado_en timestamptz NOT NULL DEFAULT clock_timestamp(), ADD COLUMN registrado_por uuid, ADD COLUMN actualizado_en timestamptz NOT NULL DEFAULT clock_timestamp();
CREATE TRIGGER a_serializar BEFORE INSERT OR UPDATE OR DELETE ON bm.tarifa_iva_vigencia FOR EACH STATEMENT EXECUTE FUNCTION bm.serializar();
CREATE TRIGGER b_historial BEFORE INSERT OR UPDATE OR DELETE ON bm.tarifa_iva_vigencia FOR EACH ROW EXECUTE FUNCTION bm.proteger_historial('');
CREATE TRIGGER z_auditar AFTER INSERT OR UPDATE OR DELETE ON bm.tarifa_iva_vigencia FOR EACH ROW EXECUTE FUNCTION bm.auditar();
CREATE CONSTRAINT TRIGGER z_integridad AFTER INSERT OR UPDATE OR DELETE ON bm.tarifa_iva_vigencia DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION bm.comprobar_integridad();
ALTER TABLE bm.tarifa_iva_vigencia ENABLE ROW LEVEL SECURITY;
CREATE POLICY lectura_miembros ON bm.tarifa_iva_vigencia FOR SELECT TO authenticated USING ((SELECT bm.puede_leer()));
INSERT INTO bm.recurso(tabla,clave,fecha_operacion) SELECT 'tarifa_iva_vigencia',a.attname,NULL FROM pg_index i JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=ANY(i.indkey) WHERE i.indrelid='bm.tarifa_iva_vigencia'::regclass AND i.indisprimary;


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


