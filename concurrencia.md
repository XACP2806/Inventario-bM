# Comprobación pendiente con dos conexiones PostgreSQL independientes

Ejecutar en un entorno de prueba o sin actividad del negocio. Este ensayo retiene temporalmente el bloqueo global de escritura; no cambia datos al terminar. Usar dos conexiones directas independientes, manteniendo abierta la primera transacción. No sirve ejecutar los bloques consecutivamente en una sola conexión.

## Conexión A: adquirir y mantener el bloqueo

```sql
BEGIN;
UPDATE bm.control_escritura SET revision=revision+1 WHERE id;
-- Dejar abierta esta transacción mientras se ejecuta B.
```

## Conexión B: comprobar que otra escritura espera

```sql
BEGIN;
SET LOCAL lock_timeout='500ms';
DO $$
BEGIN
  BEGIN
    UPDATE bm.control_escritura SET revision=revision+1 WHERE id;
    RAISE EXCEPTION 'FALLO: la segunda escritura no fue bloqueada';
  EXCEPTION WHEN lock_not_available THEN
    RAISE NOTICE 'CORRECTO: bloqueo de la segunda escritura confirmado';
  END;
END $$;
ROLLBACK;
```

Volver a A y ejecutar `ROLLBACK;`. En B repetir una actualización dentro de `BEGIN; ... ROLLBACK;`: ahora debe poder ejecutarse. No dejar A abierta al finalizar, incluso si falla el ensayo.

Esto verifica únicamente el bloqueo global de escritura. La integración de la aplicación debe añadir pruebas con dos ventas que compitan por la última unidad y con reintentos del mismo UUID, comprobando que no se dupliquen operaciones ni se genere stock negativo.
