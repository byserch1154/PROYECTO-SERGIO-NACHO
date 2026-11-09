-- =====================================================================
-- 06_transacciones.sql · DEMOSTRACIÓN de transacciones (apartados 3.2, 3.4 y 3.6)
-- Ejemplo ejecutable. Usa DOS terminales psql contra la misma base:
--   Terminal A: ejecuta este script paso a paso.
--   Terminal B: en los puntos marcados "(B)" ejecuta:
--       SELECT set_config('app.id_usuario','1',false);   -- admin
--       SELECT id_evento, tabla, operacion, id_registro, resumen FROM fn_auditoria(5);
-- Al terminar, la base queda con los mismos 12 pedidos de partida
-- (las secuencias avanzan: es normal, una secuencia no se revierte).
-- =====================================================================

-- ---------------------------------------------------------------------
-- DEMO 1 · COMMIT: el cambio y su auditoría se hacen visibles a los demás
-- Usuario: comercial1 (id 2). set_config(..., true) = identidad SOLO durante
-- esta transacción (así lo hará Java con JDBC).
-- ---------------------------------------------------------------------
BEGIN;
SELECT set_config('app.id_usuario', '2', true);

INSERT INTO pedidos (id_cliente) VALUES (1);                       -- INSERT
INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad)
VALUES (currval(pg_get_serial_sequence('pedidos','id_pedido')), 1, 41, 2);

-- Total calculado por el trigger (2 x 89 = 178) y auditoría ya escrita
SELECT referencia, estado, tipo, total FROM pedidos
 WHERE id_pedido = currval(pg_get_serial_sequence('pedidos','id_pedido'));
SELECT id_evento, fecha, tabla, operacion, id_registro, id_usuario
  FROM log_eventos ORDER BY id_evento DESC LIMIT 2;

-- (B) AHORA, en la otra terminal: fn_auditoria(5) NO muestra estos 2 eventos
--     todavía, porque la transacción de A no se ha confirmado.
COMMIT;
-- (B) Ejecuta de nuevo fn_auditoria(5): ya aparecen, con usuario comercial1 y hora.

-- ---------------------------------------------------------------------
-- DEMO 2 · ROLLBACK: se deshace el dato Y su auditoría
-- ---------------------------------------------------------------------
BEGIN;
SELECT set_config('app.id_usuario', '2', true);
INSERT INTO pedidos (id_cliente) VALUES (2);
INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad)
VALUES (currval(pg_get_serial_sequence('pedidos','id_pedido')), 2, 42, 1);
SELECT count(*) AS pedidos_dentro_de_la_transaccion FROM pedidos;   -- 14
ROLLBACK;
SELECT count(*) AS pedidos_tras_rollback FROM pedidos;              -- 13 (12 + demo 1)
-- (B) fn_auditoria(5): no hay eventos del pedido deshecho.

-- ---------------------------------------------------------------------
-- DEMO 3 · STOCK: confirmar descuenta, cancelar devuelve (todo se deshace al final)
-- ---------------------------------------------------------------------
BEGIN;
SELECT set_config('app.id_usuario', '2', true);
INSERT INTO pedidos (id_cliente) VALUES (3);
INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad)
VALUES (currval(pg_get_serial_sequence('pedidos','id_pedido')), 3, 41, 4);

SELECT stock_disponible AS stock_antes FROM stock WHERE id_modelo = 3 AND talla = 41;       -- 28
UPDATE pedidos SET estado = 'confirmado'
 WHERE id_pedido = currval(pg_get_serial_sequence('pedidos','id_pedido'));                  -- UPDATE
SELECT stock_disponible AS stock_tras_confirmar FROM stock WHERE id_modelo = 3 AND talla = 41; -- 24
UPDATE pedidos SET estado = 'cancelado'
 WHERE id_pedido = currval(pg_get_serial_sequence('pedidos','id_pedido'));
SELECT stock_disponible AS stock_tras_cancelar FROM stock WHERE id_modelo = 3 AND talla = 41;  -- 28

-- Confirmar sin stock suficiente: se rechaza y NO queda ningún cambio parcial
SAVEPOINT intento;
INSERT INTO pedidos (id_cliente) VALUES (3);
INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad)
VALUES (currval(pg_get_serial_sequence('pedidos','id_pedido')), 6, 38, 1);   -- Aero 38: stock 0
UPDATE pedidos SET estado = 'confirmado'
 WHERE id_pedido = currval(pg_get_serial_sequence('pedidos','id_pedido'));   -- ERROR: Stock insuficiente
ROLLBACK TO SAVEPOINT intento;
ROLLBACK;

-- ---------------------------------------------------------------------
-- DEMO 4 · DELETE: solo el Administrador, solo pedidos pendientes, líneas primero
-- (no hay ON DELETE CASCADE a propósito, para evitar borrados accidentales)
-- ---------------------------------------------------------------------
BEGIN;
SELECT set_config('app.id_usuario', '1', true);
DELETE FROM lineas_pedido WHERE id_pedido = (SELECT max(id_pedido) FROM pedidos);
DELETE FROM pedidos       WHERE id_pedido = (SELECT max(id_pedido) FROM pedidos);
COMMIT;
SELECT count(*) AS pedidos_final FROM pedidos;                       -- 12 otra vez
