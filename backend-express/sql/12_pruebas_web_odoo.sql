-- =====================================================================
-- 12_pruebas_web_odoo.sql · Pruebas de los colores de catálogo y del envío a Odoo
-- Se ejecuta en pgAdmin (Query Tool -> abrir -> F5) DESPUÉS de 10 y 11.
-- Todo va dentro de UNA transacción que termina en ROLLBACK: no cambia ningún dato.
-- Si algo falla sale 'FALLO [...]'; si todo va bien, el último aviso lo confirma.
-- =====================================================================
SET client_min_messages = notice;
BEGIN;

-- ---------- Ayudas de prueba (temporales) ----------
CREATE FUNCTION pg_temp.como(p_usuario text) RETURNS void LANGUAGE sql AS
$$ SELECT set_config('app.id_usuario',
          (SELECT id_usuario::text FROM usuarios WHERE username = p_usuario), false) $$;

CREATE FUNCTION pg_temp.afirmar(p_cond boolean, p_msg text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    IF p_cond IS TRUE THEN RAISE NOTICE 'OK    %', p_msg;
    ELSE RAISE EXCEPTION 'FALLO [%]', p_msg; END IF;
END $$;

CREATE FUNCTION pg_temp.rechaza(p_nombre text, p_sql text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_msg text;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        v_msg := SQLERRM;
    END;
    IF v_msg IS NULL THEN
        RAISE EXCEPTION 'FALLO [%]: la sentencia NO fue rechazada', p_nombre;
    END IF;
    RAISE NOTICE 'OK    % -> rechazado: %', p_nombre, v_msg;
END $$;

CREATE FUNCTION pg_temp.color(p_codigo text) RETURNS smallint LANGUAGE sql AS
$$ SELECT id_color FROM colores_catalogo WHERE codigo = p_codigo $$;

CREATE FUNCTION pg_temp.modelo(p_codigo text) RETURNS smallint LANGUAGE sql AS
$$ SELECT id_modelo FROM modelos WHERE codigo = p_codigo $$;

-- =====================================================================
-- === 1. CATÁLOGO DE COLORES ===
-- =====================================================================
SELECT pg_temp.afirmar((SELECT count(*) FROM colores_catalogo WHERE activo) = 18,
                       '18 colores de catálogo a la venta');
SELECT pg_temp.afirmar((SELECT bool_and(n = 3) FROM (SELECT count(*) AS n FROM colores_catalogo
                         WHERE activo GROUP BY id_modelo) x)
                       AND (SELECT count(DISTINCT id_modelo) FROM colores_catalogo WHERE activo) = 6,
                       'cada uno de los 6 modelos tiene 3 colores');

-- =====================================================================
-- === 2. PEDIDO ESTÁNDAR CON COLOR DE CATÁLOGO ===
-- =====================================================================
SELECT pg_temp.como('comercial1');
CREATE TEMP TABLE _p AS
WITH p AS (INSERT INTO pedidos (id_cliente) VALUES (1) RETURNING id_pedido, referencia)
SELECT * FROM p;

INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad, id_color)
SELECT id_pedido, pg_temp.modelo('pulse'), 42, 2, pg_temp.color('pulse-negro-naranja') FROM _p;

SELECT pg_temp.afirmar((SELECT precio_unitario FROM lineas_pedido WHERE id_pedido = (SELECT id_pedido FROM _p))
                       = (SELECT precio_base FROM modelos WHERE codigo = 'pulse'),
                       'color de catálogo = precio base del modelo (sin +15 de personalización)');
SELECT pg_temp.afirmar((SELECT tipo FROM pedidos WHERE id_pedido = (SELECT id_pedido FROM _p)) = 'estandar',
                       'un pedido con color de catálogo es estándar');

-- La misma talla en otro color es otra línea válida
INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad, id_color)
SELECT id_pedido, pg_temp.modelo('pulse'), 42, 1, pg_temp.color('pulse-negro-verde') FROM _p;
SELECT pg_temp.afirmar((SELECT count(*) FROM lineas_pedido WHERE id_pedido = (SELECT id_pedido FROM _p)) = 2,
                       'misma talla en dos colores distintos = dos líneas');

SELECT pg_temp.afirmar((SELECT personalizacion FROM fn_detalle_pedido((SELECT referencia FROM _p)) LIMIT 1)
                       LIKE 'Color de catálogo:%', 'el detalle del pedido muestra el color de catálogo');

-- =====================================================================
-- === 3. REGLAS QUE PROTEGEN LOS COLORES ===
-- =====================================================================
DO $$ BEGIN
  PERFORM pg_temp.rechaza('color de otro modelo (Court con color de Pulse)',
     format('INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad, id_color) VALUES (%s, %s, 40, 1, %s)',
            (SELECT id_pedido FROM _p), pg_temp.modelo('court'), pg_temp.color('pulse-negro-azul')));
  PERFORM pg_temp.rechaza('color de catálogo y personalización a la vez',
     format('INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad, id_color, color_cuerpo, color_franja,
             color_puntera, color_talon, color_suela, color_cordones)
             VALUES (%s, %s, 41, 1, %s, ''Rojo'',''Rojo'',''Rojo'',''Rojo'',''Rojo'',''Rojo'')',
            (SELECT id_pedido FROM _p), pg_temp.modelo('pulse'), pg_temp.color('pulse-negro-azul')));
  PERFORM pg_temp.rechaza('color que no existe',
     format('INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad, id_color) VALUES (%s, %s, 43, 1, 9999)',
            (SELECT id_pedido FROM _p), pg_temp.modelo('pulse')));
END $$;

-- =====================================================================
-- === 4. ENVÍO A ODOO: SOLO PEDIDOS CONFIRMADOS Y CON PERMISO ===
-- =====================================================================
DO $$ BEGIN
  PERFORM pg_temp.rechaza('enviar a Odoo un pedido pendiente',
     format('SELECT * FROM fn_pedido_para_odoo(%L)', (SELECT referencia FROM _p)));
END $$;

UPDATE pedidos SET estado = 'confirmado' WHERE id_pedido = (SELECT id_pedido FROM _p);

SELECT pg_temp.afirmar((SELECT count(*) FROM fn_pedido_para_odoo((SELECT referencia FROM _p))) = 2,
                       'un pedido confirmado se puede enviar a Odoo (2 líneas)');
SELECT pg_temp.afirmar((SELECT bool_and(color_catalogo IS NOT NULL AND email IS NOT NULL)
                          FROM fn_pedido_para_odoo((SELECT referencia FROM _p))),
                       'Odoo recibe el correo del cliente y el color de cada línea');

SELECT pg_temp.como('almacen1');
DO $$ BEGIN
  PERFORM pg_temp.rechaza('Almacén no puede enviar pedidos a Odoo',
     format('SELECT * FROM fn_pedido_para_odoo(%L)', (SELECT referencia FROM _p)));
END $$;

-- =====================================================================
-- === 5. REGISTRO DEL ENVÍO (pedidos_odoo) ===
-- =====================================================================
SELECT pg_temp.como('comercial1');
SELECT fn_registrar_envio_odoo((SELECT referencia FROM _p), 'error', NULL, NULL, 'Odoo apagado');
SELECT pg_temp.afirmar((SELECT estado FROM v_pedidos_odoo WHERE referencia = (SELECT referencia FROM _p)) = 'error',
                       'un fallo de Odoo queda apuntado como error');

SELECT fn_registrar_envio_odoo((SELECT referencia FROM _p), 'enviado', 'S09999', 9999, 'creado en Odoo');
SELECT pg_temp.afirmar((SELECT pedido_odoo || '/' || estado FROM v_pedidos_odoo
                         WHERE referencia = (SELECT referencia FROM _p)) = 'S09999/enviado',
                       'al reenviar se actualiza la misma fila (no se duplica)');
SELECT pg_temp.afirmar((SELECT count(*) FROM pedidos_odoo WHERE id_pedido = (SELECT id_pedido FROM _p)) = 1,
                       'un pedido de SPEAKE corresponde a un solo pedido de Odoo');

DO $$ BEGIN RAISE NOTICE '=== TODAS LAS PRUEBAS DE COLORES Y ODOO SUPERADAS ==='; END $$;
ROLLBACK;   -- los datos de la base quedan exactamente como estaban
