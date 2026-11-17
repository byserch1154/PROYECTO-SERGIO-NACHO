-- =====================================================================
-- DEMO_JOSE.sql · Demostración en directo de la base de datos SPEAKE
-- Sergio Sierra y Nacho García · Acceso a Datos
--
-- Cómo se usa en pgAdmin: Query Tool sobre SPEAKE, seleccionar UN bloque
-- con el ratón (desde "-- BLOQUE" hasta el siguiente) y pulsar F5.
-- pgAdmin enseña el resultado del ÚLTIMO SELECT de lo seleccionado.
-- Los bloques que deben dar error lo dicen: el error ES la prueba.
-- Usuarios: 1 = admin, 2 = comercial1, 3 = almacen1
-- =====================================================================


-- BLOQUE 1 · El modelo: tablas y cuántos datos hay ---------------------
SELECT 'clientes' AS tabla, count(*) FROM clientes
UNION ALL SELECT 'modelos', count(*) FROM modelos
UNION ALL SELECT 'pedidos', count(*) FROM pedidos
UNION ALL SELECT 'lineas_pedido', count(*) FROM lineas_pedido
UNION ALL SELECT 'stock (modelo x talla)', count(*) FROM stock
UNION ALL SELECT 'usuarios', count(*) FROM usuarios
UNION ALL SELECT 'log_eventos', count(*) FROM log_eventos;


-- BLOQUE 2 · PRUEBA A · Un club pide 40 pares Custom en 5 tallas -------
-- Lo hace comercial1. NO ponemos precio ni total: los calculan los triggers.
-- Resultado: total = 40 x (109 + 15 Custom + 5 texto) = 5160 €, custom, pendiente
SELECT set_config('app.id_usuario', '2', false);   -- comercial1 en esta sesión
INSERT INTO pedidos (id_cliente) VALUES (2);       -- Club Halcones
INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad,
       color_cuerpo, color_franja, color_puntera, color_talon, color_suela, color_cordones, texto_suela)
SELECT currval(pg_get_serial_sequence('pedidos','id_pedido')), 2, t.talla, t.cantidad,
       'Negro', 'Rojo', 'Negro', 'Rojo', 'Blanco', 'Rojo', 'HALCONES'
  FROM (VALUES (39, 6), (40, 8), (41, 10), (42, 10), (43, 6)) AS t(talla, cantidad);
SELECT referencia, estado, tipo, total
  FROM pedidos WHERE id_pedido = currval(pg_get_serial_sequence('pedidos','id_pedido'));


-- BLOQUE 3 · Stock ANTES de confirmar (SPEAKE Pulse, tallas 39-43) -----
SELECT talla, stock_disponible AS stock_antes FROM stock
 WHERE id_modelo = 2 AND talla BETWEEN 39 AND 43 ORDER BY talla;


-- BLOQUE 4 · Confirmar: el trigger t3_pedidos_stock descuenta ----------
SELECT set_config('app.id_usuario', '2', false);
UPDATE pedidos SET estado = 'confirmado'
 WHERE id_pedido = (SELECT max(id_pedido) FROM pedidos WHERE id_cliente = 2);
SELECT talla, stock_disponible AS stock_despues FROM stock
 WHERE id_modelo = 2 AND talla BETWEEN 39 AND 43 ORDER BY talla;


-- BLOQUE 5 · Auditoría: quién hizo qué y cuándo (log_eventos) ----------
SELECT e.id_evento, e.fecha, e.tabla, e.operacion, e.id_registro, u.username, left(e.resumen, 60) AS resumen
  FROM log_eventos e LEFT JOIN usuarios u USING (id_usuario)
 ORDER BY e.id_evento DESC LIMIT 8;


-- BLOQUE 6 · PRUEBA B · Confirmar sin stock  >>> DEBE DAR ERROR <<< ----
-- Aero talla 40 sí tiene stock, talla 38 tiene 0. Va todo en la misma
-- ejecución: al fallar, PostgreSQL deshace TODO (pedido, líneas y stock).
SELECT set_config('app.id_usuario', '2', false);
INSERT INTO pedidos (id_cliente) VALUES (1);
INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad)
VALUES (currval(pg_get_serial_sequence('pedidos','id_pedido')), 6, 40, 2),
       (currval(pg_get_serial_sequence('pedidos','id_pedido')), 6, 38, 5);
UPDATE pedidos SET estado = 'confirmado'
 WHERE id_pedido = currval(pg_get_serial_sequence('pedidos','id_pedido'));


-- BLOQUE 7 · La PRUEBA B no dejó nada a medias -------------------------
-- Aero 40 sigue igual (no se descontaron sus 2 pares) y no hay pedido nuevo
SELECT (SELECT stock_disponible FROM stock WHERE id_modelo = 6 AND talla = 40) AS aero_40,
       (SELECT stock_disponible FROM stock WHERE id_modelo = 6 AND talla = 38) AS aero_38,
       (SELECT count(*) FROM pedidos) AS pedidos_totales;


-- BLOQUE 8 · PRUEBA C · Cancelar el pedido del club: el stock vuelve ---
SELECT set_config('app.id_usuario', '2', false);
UPDATE pedidos SET estado = 'cancelado'
 WHERE id_pedido = (SELECT max(id_pedido) FROM pedidos WHERE id_cliente = 2);
SELECT p.referencia, p.estado, s.talla, s.stock_disponible AS stock_tras_cancelar
  FROM stock s
  CROSS JOIN (SELECT referencia, estado FROM pedidos
               WHERE id_pedido = (SELECT max(id_pedido) FROM pedidos WHERE id_cliente = 2)) p
 WHERE s.id_modelo = 2 AND s.talla BETWEEN 39 AND 43 ORDER BY s.talla;


-- BLOQUE 9 · PRUEBA D (1/2) · Abrir transacción y crear un pedido ------
BEGIN;
SELECT set_config('app.id_usuario', '2', true);
INSERT INTO pedidos (id_cliente) VALUES (3);
SELECT (SELECT count(*) FROM pedidos) AS pedidos_dentro,
       (SELECT max(id_evento) FROM log_eventos) AS ultimo_evento_dentro;


-- BLOQUE 10 · PRUEBA D (2/2) · ROLLBACK: desaparecen el pedido y su log --
ROLLBACK;
SELECT (SELECT count(*) FROM pedidos) AS pedidos_despues,
       (SELECT max(id_evento) FROM log_eventos) AS ultimo_evento_despues;


-- BLOQUE 11 · Permisos: almacén NO puede confirmar  >>> DEBE DAR ERROR <<<
-- Lo comprueba el trigger t1_pedidos_permisos, no la pantalla.
SELECT set_config('app.id_usuario', '3', false);   -- almacen1
UPDATE pedidos SET estado = 'confirmado' WHERE estado = 'pendiente';


-- BLOQUE 12 · Restricción CHECK cantidad > 0  >>> DEBE DAR ERROR <<< ---
SELECT set_config('app.id_usuario', '2', false);
INSERT INTO pedidos (id_cliente) VALUES (5);
INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad)
VALUES (currval(pg_get_serial_sequence('pedidos','id_pedido')), 1, 40, 0);


-- BLOQUE 13 · Dominio de tallas 38-46  >>> DEBE DAR ERROR <<< ----------
SELECT set_config('app.id_usuario', '2', false);
INSERT INTO pedidos (id_cliente) VALUES (5);
INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad)
VALUES (currval(pg_get_serial_sequence('pedidos','id_pedido')), 1, 50, 2);


-- BLOQUE 14 · Clave ajena: cliente inexistente  >>> DEBE DAR ERROR <<< -
SELECT set_config('app.id_usuario', '2', false);
INSERT INTO pedidos (id_cliente) VALUES (999);


-- BLOQUE 15 · Importes (1/3) · Pedido de 2 líneas: total 5 x 89 = 445 --
BEGIN;
SELECT set_config('app.id_usuario', '1', true);    -- admin
INSERT INTO pedidos (id_cliente) VALUES (5);
INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad)
VALUES (currval(pg_get_serial_sequence('pedidos','id_pedido')), 1, 41, 2),
       (currval(pg_get_serial_sequence('pedidos','id_pedido')), 1, 42, 3);
SELECT referencia, total AS total_con_2_lineas FROM pedidos
 WHERE id_pedido = currval(pg_get_serial_sequence('pedidos','id_pedido'));


-- BLOQUE 16 · Importes (2/3) · DELETE de una línea: total 2 x 89 = 178 -
DELETE FROM lineas_pedido
 WHERE id_pedido = currval(pg_get_serial_sequence('pedidos','id_pedido')) AND talla = 42;
SELECT referencia, total AS total_tras_borrar FROM pedidos
 WHERE id_pedido = currval(pg_get_serial_sequence('pedidos','id_pedido'));


-- BLOQUE 17 · Importes (3/3) · Deshacer la prueba ---------------------
ROLLBACK;
SELECT count(*) AS pedidos FROM pedidos;


-- BLOQUE 18 · Consulta: pares vendidos por talla (qué tallas fabricar) -
SELECT l.talla, sum(l.cantidad) AS pares
  FROM lineas_pedido l JOIN pedidos p USING (id_pedido)
 WHERE p.estado IN ('confirmado', 'entregado')
 GROUP BY l.talla ORDER BY l.talla;


-- BLOQUE 19 · HAVING: clientes con 10 pares o más (trato de equipo) ----
SELECT c.nombre, count(DISTINCT p.id_pedido) AS pedidos, sum(l.cantidad) AS pares
  FROM clientes c JOIN pedidos p USING (id_cliente) JOIN lineas_pedido l USING (id_pedido)
 WHERE p.estado IN ('confirmado', 'entregado')
 GROUP BY c.nombre HAVING sum(l.cantidad) >= 10 ORDER BY pares DESC;


-- BLOQUE 20 · Subconsulta: modelos con menos stock que la media --------
SELECT m.nombre, sum(s.stock_disponible) AS stock_total
  FROM modelos m JOIN stock s USING (id_modelo)
 GROUP BY m.nombre
HAVING sum(s.stock_disponible) < (SELECT avg(t) FROM (SELECT sum(stock_disponible) AS t FROM stock GROUP BY id_modelo) x)
 ORDER BY stock_total;


-- BLOQUE 21 · Indicadores del panel (calculados por PostgreSQL) --------
SELECT set_config('app.id_usuario', '1', false);
SELECT * FROM fn_indicadores();


-- BLOQUE 22 · Ficha de fabricación que se exporta para Java (PSP) ------
SELECT * FROM v_ficha_fabricacion;
