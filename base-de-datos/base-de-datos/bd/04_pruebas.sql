-- =====================================================================
-- 04_pruebas.sql · Pruebas automáticas (psql o Query Tool de pgAdmin)
-- Ejecutar DESPUÉS de 01 y 02. Todo ocurre dentro de UNA sola transacción que
-- termina en ROLLBACK: los datos de la base quedan intactos.
-- Si algo falla se lanza 'FALLO [...]'; si todo va bien, el último NOTICE lo confirma.
-- Ids de usuario: 1 = admin, 2 = comercial1, 3 = almacen1.
-- =====================================================================
SET client_min_messages = notice;
BEGIN;

-- ---------- Ayudas de prueba (temporales, desaparecen al cerrar sesión) ----------
CREATE FUNCTION pg_temp.como(p_id integer) RETURNS void LANGUAGE sql AS
$$ SELECT set_config('app.id_usuario', coalesce(p_id::text, ''), false) $$;

CREATE FUNCTION pg_temp.afirmar(p_cond boolean, p_msg text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    IF p_cond IS TRUE THEN RAISE NOTICE 'OK    %', p_msg;
    ELSE RAISE EXCEPTION 'FALLO [%]', p_msg; END IF;
END $$;

-- Comprueba que una sentencia es RECHAZADA con el SQLSTATE esperado
CREATE FUNCTION pg_temp.rechaza(p_nombre text, p_sql text, p_esperado text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE v_state text; v_msg text;
BEGIN
    BEGIN
        EXECUTE p_sql;
    EXCEPTION WHEN OTHERS THEN
        v_state := SQLSTATE; v_msg := SQLERRM;
    END;
    IF v_state IS NULL THEN
        RAISE EXCEPTION 'FALLO [%]: la sentencia NO fue rechazada', p_nombre;
    ELSIF v_state <> p_esperado THEN
        RAISE EXCEPTION 'FALLO [%]: se esperaba % y llegó % (%)', p_nombre, p_esperado, v_state, v_msg;
    END IF;
    RAISE NOTICE 'OK    % -> rechazado (%): %', p_nombre, v_state, v_msg;
END $$;

CREATE FUNCTION pg_temp.stock_de(p_codigo text, p_talla integer) RETURNS integer
LANGUAGE sql AS $$
    SELECT s.stock_disponible FROM stock s JOIN modelos m USING (id_modelo)
     WHERE m.codigo = p_codigo AND s.talla = p_talla $$;

-- =====================================================================
-- === 1. RESTRICCIONES (PRIMARY/FOREIGN KEY, NOT NULL, UNIQUE, CHECK) ===
-- =====================================================================
SELECT pg_temp.como(2);
DO $$ BEGIN
  PERFORM pg_temp.rechaza('cantidad cero',
     'INSERT INTO lineas_pedido (id_pedido,id_modelo,talla,cantidad) VALUES (9,1,40,0)', '23514');
  PERFORM pg_temp.rechaza('cantidad negativa',
     'INSERT INTO lineas_pedido (id_pedido,id_modelo,talla,cantidad) VALUES (9,1,40,-3)', '23514');
  PERFORM pg_temp.rechaza('talla fuera de rango (50)',
     'INSERT INTO lineas_pedido (id_pedido,id_modelo,talla,cantidad) VALUES (9,1,50,1)', '23514');
  PERFORM pg_temp.rechaza('cliente inexistente (FK)',
     'INSERT INTO pedidos (id_cliente) VALUES (999)', '23503');
  PERFORM pg_temp.rechaza('modelo inexistente (FK)',
     'INSERT INTO lineas_pedido (id_pedido,id_modelo,talla,cantidad) VALUES (9,99,40,1)', '23503');
  PERFORM pg_temp.rechaza('color fuera de catálogo',
     $q$INSERT INTO lineas_pedido (id_pedido,id_modelo,talla,cantidad,color_cuerpo,color_franja,color_puntera,color_talon,color_suela,color_cordones)
        VALUES (9,1,41,1,'Morado','Rojo','Rojo','Rojo','Rojo','Rojo')$q$, '23514');
  PERFORM pg_temp.rechaza('personalización incompleta (solo 1 de 6 partes)',
     $q$INSERT INTO lineas_pedido (id_pedido,id_modelo,talla,cantidad,color_cuerpo)
        VALUES (9,1,41,1,'Negro')$q$, '23514');
  PERFORM pg_temp.rechaza('texto en suela sin personalizar',
     $q$INSERT INTO lineas_pedido (id_pedido,id_modelo,talla,cantidad,texto_suela)
        VALUES (9,1,41,1,'HOLA')$q$, '23514');
  PERFORM pg_temp.rechaza('línea duplicada (UNIQUE)',
     'INSERT INTO lineas_pedido (id_pedido,id_modelo,talla,cantidad) VALUES (9,5,40,1)', '23505');
  PERFORM pg_temp.rechaza('email sin arroba',
     $q$INSERT INTO clientes (nombre,email) VALUES ('X','sinarroba')$q$, '23514');
  PERFORM pg_temp.rechaza('email duplicado (UNIQUE)',
     $q$INSERT INTO clientes (nombre,email) VALUES ('X','ana.garcia@example.com')$q$, '23505');
  PERFORM pg_temp.rechaza('cliente sin nombre (NOT NULL)',
     $q$INSERT INTO clientes (nombre,email) VALUES (NULL,'z@example.com')$q$, '23502');
  PERFORM pg_temp.rechaza('stock negativo (CHECK)',
     'UPDATE stock SET stock_disponible = -1 WHERE id_modelo = 1 AND talla = 40', '23514');
END $$;

-- =====================================================================
-- === 2. IDENTIDAD Y PERMISOS (se aplican en la base de datos) ===
-- =====================================================================
DO $$ BEGIN
  PERFORM pg_temp.como(NULL);
  PERFORM pg_temp.rechaza('operación sin usuario autenticado',
     'INSERT INTO pedidos (id_cliente) VALUES (1)', '28000');

  PERFORM pg_temp.como(3);   -- Almacén
  PERFORM pg_temp.rechaza('almacén NO puede crear pedidos',
     'INSERT INTO pedidos (id_cliente) VALUES (1)', '42501');
  PERFORM pg_temp.rechaza('almacén NO puede confirmar',
     $q$UPDATE pedidos SET estado='confirmado' WHERE id_pedido=9$q$, '42501');
  PERFORM pg_temp.rechaza('almacén NO puede editar líneas',
     'UPDATE lineas_pedido SET cantidad = 2 WHERE id_pedido = 9', '42501');
  PERFORM pg_temp.rechaza('almacén NO puede exportar usuarios',
     'SELECT * FROM fn_listar_usuarios()', '42501');
  PERFORM pg_temp.rechaza('almacén NO ve la auditoría',
     'SELECT * FROM fn_auditoria()', '42501');
  PERFORM pg_temp.afirmar((SELECT count(*) FROM fn_stock_bajo(5)) > 0, 'almacén SÍ consulta stock bajo');
  PERFORM pg_temp.afirmar((SELECT count(*) FROM fn_buscar_pedidos()) = 12, 'almacén SÍ consulta pedidos (12)');

  PERFORM pg_temp.como(2);   -- Comercial
  PERFORM pg_temp.rechaza('comercial NO puede entregar',
     $q$UPDATE pedidos SET estado='entregado' WHERE id_pedido=3$q$, '42501');
  PERFORM pg_temp.rechaza('comercial NO puede eliminar pedidos',
     'DELETE FROM pedidos WHERE id_pedido = 9', '42501');
  PERFORM pg_temp.rechaza('comercial NO ve la auditoría',
     'SELECT * FROM fn_auditoria()', '42501');
  PERFORM pg_temp.rechaza('comercial NO gestiona usuarios',
     $q$SELECT fn_crear_usuario('intruso','x1234567','Comercial')$q$, '42501');
  PERFORM pg_temp.afirmar((SELECT count(*) FROM fn_buscar_pedidos(p_cliente => 'halcones')) = 2,
                          'comercial SÍ consulta pedidos (Halcones: 2)');

  PERFORM pg_temp.como(1);   -- Administrador
  PERFORM pg_temp.afirmar((SELECT count(*) FROM fn_auditoria(1000)) > 0, 'admin SÍ ve la auditoría');
  PERFORM pg_temp.afirmar((SELECT count(*) FROM fn_listar_usuarios()) = (SELECT count(*) FROM usuarios), 'admin SÍ exporta usuarios (todos)');
END $$;

-- =====================================================================
-- === 3. LOGIN (bcrypt con sal) ===
-- =====================================================================
SELECT pg_temp.afirmar(fn_login('admin', 'Admin#2026') = 1, 'login correcto');
SELECT pg_temp.afirmar(fn_login('admin', 'incorrecta') IS NULL, 'contraseña incorrecta -> NULL');
SELECT pg_temp.afirmar(fn_login('noexiste', 'x') IS NULL, 'usuario inexistente -> NULL');
SELECT pg_temp.afirmar((SELECT password_hash FROM usuarios WHERE id_usuario = 1) LIKE '$2a$%',
                       'la contraseña se guarda como hash bcrypt, no en texto plano');
SELECT pg_temp.afirmar((SELECT count(DISTINCT password_hash) FROM usuarios) = (SELECT count(*) FROM usuarios),
                       'cada hash lleva sal distinta');

-- =====================================================================
-- === 4. AUTOMATIZACIÓN 1: IMPORTES ===
-- =====================================================================
SELECT pg_temp.como(2);
DO $$
DECLARE v_id integer; v_court40 integer;
BEGIN
  v_court40 := pg_temp.stock_de('court', 40);
  INSERT INTO pedidos (id_cliente) VALUES (1) RETURNING id_pedido INTO v_id;
  PERFORM pg_temp.afirmar((SELECT total FROM pedidos WHERE id_pedido = v_id) = 0, 'pedido nuevo: total 0');

  INSERT INTO lineas_pedido (id_pedido,id_modelo,talla,cantidad) VALUES (v_id, 1, 40, 2);   -- 89 x2
  PERFORM pg_temp.afirmar((SELECT total FROM pedidos WHERE id_pedido = v_id) = 178, 'INSERT línea estándar: total 178');
  PERFORM pg_temp.afirmar((SELECT tipo FROM pedidos WHERE id_pedido = v_id) = 'estandar', 'tipo = estandar');

  INSERT INTO lineas_pedido (id_pedido,id_modelo,talla,cantidad,
         color_cuerpo,color_franja,color_puntera,color_talon,color_suela,color_cordones,texto_suela)
  VALUES (v_id, 2, 41, 1, 'Negro','Rojo','Negro','Negro','Blanco','Rojo','  PRUEBA  ');
  PERFORM pg_temp.afirmar((SELECT precio_unitario FROM lineas_pedido WHERE id_pedido = v_id AND talla = 41) = 129,
                          'precio automático custom: 109 + 15 + 5 = 129');
  PERFORM pg_temp.afirmar((SELECT texto_suela FROM lineas_pedido WHERE id_pedido = v_id AND talla = 41) = 'PRUEBA',
                          'el texto se limpia (espacios)');
  PERFORM pg_temp.afirmar((SELECT total FROM pedidos WHERE id_pedido = v_id) = 307, 'total tras 2.ª línea: 307');
  PERFORM pg_temp.afirmar((SELECT tipo FROM pedidos WHERE id_pedido = v_id) = 'custom', 'tipo pasa a custom');

  UPDATE lineas_pedido SET cantidad = 3 WHERE id_pedido = v_id AND talla = 40;
  PERFORM pg_temp.afirmar((SELECT total FROM pedidos WHERE id_pedido = v_id) = 396, 'UPDATE cantidad 2->3: total 396 (sin sumar dos veces)');

  DELETE FROM lineas_pedido WHERE id_pedido = v_id AND talla = 41;
  PERFORM pg_temp.afirmar((SELECT total FROM pedidos WHERE id_pedido = v_id) = 267, 'DELETE línea: total 267');
  PERFORM pg_temp.afirmar((SELECT tipo FROM pedidos WHERE id_pedido = v_id) = 'estandar', 'sin líneas custom vuelve a estandar');
  PERFORM pg_temp.afirmar(pg_temp.stock_de('court', 40) = v_court40, 'editar líneas NO toca el stock');

  -- =====================================================================
  -- === 5. AUTOMATIZACIÓN 2: EXISTENCIAS ===
  -- =====================================================================
  UPDATE pedidos SET estado = 'confirmado' WHERE id_pedido = v_id;
  PERFORM pg_temp.afirmar(pg_temp.stock_de('court', 40) = v_court40 - 3, 'confirmar descuenta 3 pares');
  PERFORM pg_temp.afirmar((SELECT count(*) FROM log_eventos WHERE tabla='pedidos' AND id_registro = v_id::text
                            AND resumen LIKE '%estado: pendiente -> confirmado%'
                            AND id_usuario = 2) = 1, 'auditoría del cambio de estado con usuario 2');

  UPDATE pedidos SET estado = 'cancelado' WHERE id_pedido = v_id;
  PERFORM pg_temp.afirmar(pg_temp.stock_de('court', 40) = v_court40, 'cancelar confirmado devuelve el stock');

  PERFORM pg_temp.rechaza('un pedido cancelado no se reabre',
      format('UPDATE pedidos SET estado=%L WHERE id_pedido=%s', 'confirmado', v_id), 'P0001');
  PERFORM pg_temp.rechaza('un pedido cancelado no admite líneas nuevas',
      format('INSERT INTO lineas_pedido (id_pedido,id_modelo,talla,cantidad) VALUES (%s,1,42,1)', v_id), 'P0001');
END $$;

DO $$
DECLARE v_id integer; v_court40 integer; v_aero38 integer;
BEGIN
  v_court40 := pg_temp.stock_de('court', 40);
  v_aero38  := pg_temp.stock_de('aero', 38);                      -- 0 pares
  INSERT INTO pedidos (id_cliente) VALUES (2) RETURNING id_pedido INTO v_id;
  INSERT INTO lineas_pedido (id_pedido,id_modelo,talla,cantidad) VALUES (v_id, 1, 40, 1);   -- hay stock
  INSERT INTO lineas_pedido (id_pedido,id_modelo,talla,cantidad) VALUES (v_id, 6, 38, 1);   -- NO hay stock
  PERFORM pg_temp.rechaza('Prueba B: confirmar sin stock suficiente',
      format('UPDATE pedidos SET estado=%L WHERE id_pedido=%s', 'confirmado', v_id), '23514');
  PERFORM pg_temp.afirmar((SELECT estado FROM pedidos WHERE id_pedido = v_id) = 'pendiente', 'el pedido sigue pendiente');
  PERFORM pg_temp.afirmar(pg_temp.stock_de('court', 40) = v_court40, 'sin cambios parciales: la línea con stock NO se descontó');
  PERFORM pg_temp.afirmar(pg_temp.stock_de('aero', 38) = v_aero38 AND v_aero38 = 0, 'stock nunca negativo');

  -- Un pedido sin líneas tampoco se puede confirmar
  INSERT INTO pedidos (id_cliente) VALUES (3) RETURNING id_pedido INTO v_id;
  PERFORM pg_temp.rechaza('pedido sin líneas no se confirma',
      format('UPDATE pedidos SET estado=%L WHERE id_pedido=%s', 'confirmado', v_id), 'P0001');
END $$;

-- Transiciones y pedidos cerrados
DO $$ BEGIN
  PERFORM pg_temp.rechaza('un pedido nuevo no puede nacer confirmado (se saltaría el stock)',
      $q$INSERT INTO pedidos (id_cliente, estado) VALUES (1, 'confirmado')$q$, 'P0001');
  PERFORM pg_temp.rechaza('entregado -> pendiente no permitido',
      $q$UPDATE pedidos SET estado='pendiente' WHERE id_pedido=1$q$, 'P0001');
  PERFORM pg_temp.rechaza('pendiente -> entregado: el comercial no puede entregar',
      $q$UPDATE pedidos SET estado='entregado' WHERE id_pedido=9$q$, '42501');   -- comercial no entrega
  PERFORM pg_temp.rechaza('no se editan líneas de un pedido confirmado',
      'UPDATE lineas_pedido SET cantidad = 2 WHERE id_pedido = 4', 'P0001');
  PERFORM pg_temp.rechaza('no se mueven líneas a otro pedido',
      'UPDATE lineas_pedido SET id_pedido = 8 WHERE id_pedido = 9', 'P0001');
END $$;

-- =====================================================================
-- === 6. TRANSACCIÓN: ROLLBACK revierte datos Y auditoría (Prueba D) ===
-- =====================================================================
SELECT pg_temp.como(2);
CREATE TEMP TABLE _antes (pedidos integer, lineas integer, eventos integer) ON COMMIT DROP;
INSERT INTO _antes
SELECT (SELECT count(*) FROM pedidos), (SELECT count(*) FROM lineas_pedido), (SELECT count(*) FROM log_eventos);

SAVEPOINT prueba_rollback;
INSERT INTO pedidos (id_cliente) VALUES (2);
INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad)
VALUES (currval(pg_get_serial_sequence('pedidos','id_pedido')), 1, 40, 1);

-- Dentro de la transacción el cambio y su auditoría SÍ existen...
SELECT pg_temp.afirmar((SELECT count(*) FROM pedidos) = (SELECT pedidos + 1 FROM _antes), 'antes del rollback: hay 1 pedido más');
SELECT pg_temp.afirmar((SELECT count(*) FROM log_eventos) = (SELECT eventos + 2 FROM _antes),
                       'antes del rollback: hay 2 eventos de auditoría más (pedido y línea)');

ROLLBACK TO SAVEPOINT prueba_rollback;

-- ...y tras el ROLLBACK desaparecen los dos
SELECT pg_temp.afirmar((SELECT count(*) FROM pedidos)       = (SELECT pedidos FROM _antes), 'tras ROLLBACK: el pedido no existe');
SELECT pg_temp.afirmar((SELECT count(*) FROM lineas_pedido) = (SELECT lineas  FROM _antes), 'tras ROLLBACK: la línea no existe');
SELECT pg_temp.afirmar((SELECT count(*) FROM log_eventos)   = (SELECT eventos FROM _antes), 'tras ROLLBACK: los eventos de auditoría tampoco quedan');

-- =====================================================================
-- === 7. AUDITORÍA: quién, cuándo y qué ===
-- =====================================================================
SELECT pg_temp.como(1);
SELECT pg_temp.afirmar(EXISTS (SELECT 1 FROM fn_auditoria(1000) a
        WHERE a.tabla = 'pedidos' AND a.id_registro = '3' AND a.operacion = 'UPDATE'
          AND a.usuario = 'comercial1' AND a.resumen LIKE '%estado: pendiente -> confirmado%'),
       'SO003 confirmado por comercial1 queda auditado');
SELECT pg_temp.afirmar(EXISTS (SELECT 1 FROM fn_auditoria(1000) a
        WHERE a.tabla = 'pedidos' AND a.id_registro = '1' AND a.usuario = 'almacen1'
          AND a.resumen LIKE '%confirmado -> entregado%'),
       'SO001 entregado por almacen1 queda auditado');
SELECT pg_temp.afirmar((SELECT count(*) FROM log_eventos WHERE fecha IS NULL OR id_usuario IS NULL) = 0,
                       'todo evento tiene fecha/hora y usuario');

-- =====================================================================
-- === 8. COHERENCIA GLOBAL ===
-- =====================================================================
SELECT pg_temp.afirmar(NOT EXISTS (
         SELECT 1 FROM pedidos p
          WHERE p.total <> coalesce((SELECT sum(cantidad * precio_unitario) FROM lineas_pedido l
                                      WHERE l.id_pedido = p.id_pedido), 0)),
       'ningún pedido tiene el total desfasado respecto a sus líneas');
SELECT pg_temp.afirmar((SELECT min(stock_disponible) FROM stock) >= 0, 'no hay stock negativo');
SELECT pg_temp.afirmar(NOT EXISTS (
         SELECT 1 FROM pedidos p WHERE p.tipo = 'custom'
            AND NOT EXISTS (SELECT 1 FROM lineas_pedido l WHERE l.id_pedido = p.id_pedido AND l.color_cuerpo IS NOT NULL)),
       'tipo custom <=> existe alguna línea personalizada');

-- Conciliación por modelo y talla
SELECT pg_temp.afirmar(NOT EXISTS (
    SELECT 1
      FROM stock s
      LEFT JOIN (SELECT l.id_modelo, l.talla, sum(l.cantidad) AS vendidos
                   FROM lineas_pedido l JOIN pedidos p USING (id_pedido)
                  WHERE p.estado IN ('confirmado','entregado')
                  GROUP BY l.id_modelo, l.talla) v USING (id_modelo, talla)
     WHERE s.stock_disponible + coalesce(v.vendidos, 0) <>
           CASE WHEN (s.id_modelo, s.talla) = (3, 46) THEN 2
                WHEN (s.id_modelo, s.talla) = (6, 38) THEN 0
                WHEN (s.id_modelo, s.talla) = (5, 39) THEN 4
                WHEN (s.id_modelo, s.talla) = (4, 45) THEN 3
                ELSE 10 + ((s.id_modelo * 7 + s.talla * 3) % 25) END),
    'conciliación: stock actual + pares vendidos = stock inicial en las 54 combinaciones');

-- =====================================================================
-- === 9. USUARIOS: alta, desactivación y login ===
-- =====================================================================
SELECT pg_temp.como(1);
DO $$
DECLARE v_id integer;
BEGIN
  v_id := fn_crear_usuario('comercial2', 'Prueba#2026', 'Comercial');
  PERFORM pg_temp.afirmar(fn_login('comercial2', 'Prueba#2026') = v_id, 'usuario nuevo puede iniciar sesión');
  PERFORM pg_temp.afirmar(EXISTS (SELECT 1 FROM fn_listar_usuarios() WHERE username = 'comercial2'), 'aparece en la siguiente exportación');
  PERFORM fn_cambiar_activo(v_id, false);
  PERFORM pg_temp.afirmar(fn_login('comercial2', 'Prueba#2026') IS NULL, 'usuario desactivado no inicia sesión');
  PERFORM pg_temp.afirmar((SELECT activo FROM fn_listar_usuarios() WHERE username = 'comercial2') = false
                          AND (SELECT count(*) FROM fn_listar_usuarios()) = (SELECT count(*) FROM usuarios),
                          'sigue en la lista como inactivo, sin perder a los demás');
  PERFORM pg_temp.rechaza('no puedes desactivar tu propio usuario', 'SELECT fn_cambiar_activo(1, false)', 'P0001');
  PERFORM pg_temp.rechaza('rol inexistente', $q$SELECT fn_crear_usuario('x','Prueba#2026','Inventado')$q$, 'P0001');
  PERFORM pg_temp.afirmar(NOT EXISTS (SELECT 1 FROM fn_listar_usuarios() l, LATERAL to_jsonb(l) j WHERE j ? 'password_hash'),
                          'la lista exportable no incluye password_hash');
END $$;

-- =====================================================================
-- === 10. INDICADORES = SQL verificable (Prueba J) ===
-- =====================================================================
SELECT pg_temp.como(1);
SELECT pg_temp.afirmar((SELECT valor FROM fn_indicadores() WHERE indicador = 'pedidos_totales')
                     = (SELECT count(*) FROM pedidos), 'indicador pedidos_totales = COUNT(pedidos)');
SELECT pg_temp.afirmar((SELECT valor FROM fn_indicadores() WHERE indicador = 'pares_vendidos')
                     = (SELECT coalesce(sum(l.cantidad),0) FROM lineas_pedido l JOIN pedidos p USING (id_pedido)
                         WHERE p.estado IN ('confirmado','entregado')), 'indicador pares_vendidos = SQL directo');
SELECT pg_temp.afirmar((SELECT valor FROM fn_indicadores() WHERE indicador = 'pares_solicitados')
                     = (SELECT coalesce(sum(l.cantidad),0) FROM lineas_pedido l JOIN pedidos p USING (id_pedido)
                         WHERE p.estado <> 'cancelado'), 'indicador pares_solicitados = SQL directo (sin cancelados)');
SELECT pg_temp.afirmar((SELECT valor FROM fn_indicadores() WHERE indicador = 'importe_ventas')
                     = (SELECT coalesce(sum(total),0) FROM pedidos WHERE estado IN ('confirmado','entregado')),
                       'indicador importe_ventas = SQL directo (sin cancelados ni pendientes)');
SELECT pg_temp.afirmar((SELECT sum(valor) FROM fn_indicadores() WHERE indicador LIKE 'pedidos\_%' AND indicador <> 'pedidos_totales')
                     = (SELECT count(*) FROM pedidos), 'la suma de pedidos por estado = total de pedidos');

DO $$ BEGIN RAISE NOTICE '=== TODAS LAS PRUEBAS SUPERADAS CON ÉXITO ==='; END $$;
ROLLBACK;   -- los datos de la base quedan exactamente como estaban
