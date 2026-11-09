-- =====================================================================
-- 02_datos.sql  ·  Roles, usuarios ficticios, catálogo, stock y pedidos
-- Ejecutar DESPUÉS de 01_esquema.sql
--   psql -d sneaker_factory -v ON_ERROR_STOP=1 -f 02_datos.sql
-- Las contraseñas de abajo son FICTICIAS (cámbialas); se guardan con bcrypt.
-- =====================================================================

-- ---------- Roles y matriz de permisos ----------
INSERT INTO roles (nombre) VALUES ('Administrador'), ('Comercial'), ('Almacén');

INSERT INTO permisos (id_rol, operacion, permitido)
SELECT r.id_rol, o.op,
       CASE r.nombre
         WHEN 'Administrador' THEN true
         WHEN 'Comercial' THEN o.op IN ('consultar_pedidos','crear_pedido','editar_pedido',
                                        'confirmar_pedido','cancelar_pedido','consultar_stock')
         WHEN 'Almacén'   THEN o.op IN ('consultar_pedidos','consultar_stock','entregar_pedido')
       END
  FROM roles r
 CROSS JOIN (VALUES ('consultar_pedidos'),('crear_pedido'),('editar_pedido'),
                    ('confirmar_pedido'),('cancelar_pedido'),('entregar_pedido'),
                    ('eliminar_pedido'),('consultar_stock'),('ver_auditoria'),
                    ('gestionar_usuarios'),('exportar_usuarios')) o(op);

-- ---------- Usuarios ficticios (uno por rol) ----------
INSERT INTO usuarios (username, password_hash, id_rol)
SELECT u.username, crypt(u.pw, gen_salt('bf', 10)), r.id_rol
  FROM (VALUES ('admin',       'Admin#2026',     'Administrador'),
               ('comercial1',  'Comercial#2026', 'Comercial'),
               ('almacen1',    'Almacen#2026',   'Almacén')) u(username, pw, rol)
  JOIN roles r ON r.nombre = u.rol;

-- ---------- Catálogo (los 6 modelos de la web) ----------
INSERT INTO modelos (codigo, nombre, categoria, precio_base) VALUES
    ('court',  'SPEAKE Court',  'Urbano',     89),
    ('pulse',  'SPEAKE Pulse',  'Deportivo', 109),
    ('high',   'SPEAKE High',   'Baloncesto', 99),
    ('retro',  'SPEAKE Retro',  'Retro',      95),
    ('street', 'SPEAKE Street', 'Street',     92),
    ('aero',   'SPEAKE Aero',   'Running',   105);

-- ---------- Clientes (ficticios) ----------
INSERT INTO clientes (nombre, email, telefono, tipo, fecha_alta) VALUES
    ('Ana García',               'ana.garcia@example.com',    '600000001', 'particular', '2026-07-20'),
    ('Club Halcones',            'info@halcones.example.com', '600000002', 'club',       '2026-07-25'),
    ('Pedro Ruiz',               'pedro.ruiz@example.com',    '600000003', 'particular', '2026-08-01'),
    ('Peña Los Linces',          'linces@example.com',        '600000004', 'equipo',     '2026-08-15'),
    ('Marta Sánchez',            'marta.s@example.com',       '600000005', 'particular', '2026-08-28'),
    ('Escuela Deportiva Norte',  'escuela@norte.example.com', '600000006', 'club',       '2026-09-10');

-- ---------- Stock inicial: 6 modelos x tallas 38-46 (no uniforme) ----------
INSERT INTO stock (id_modelo, talla, stock_disponible)
SELECT m.id_modelo, t, 10 + ((m.id_modelo * 7 + t * 3) % 25)
  FROM modelos m, generate_series(38, 46) t;

-- Algunas existencias bajas para probar alertas y rechazos
UPDATE stock SET stock_disponible = 2 WHERE id_modelo = 3 AND talla = 46;   -- High 46
UPDATE stock SET stock_disponible = 0 WHERE id_modelo = 6 AND talla = 38;   -- Aero 38
UPDATE stock SET stock_disponible = 4 WHERE id_modelo = 5 AND talla = 39;   -- Street 39
UPDATE stock SET stock_disponible = 3 WHERE id_modelo = 4 AND talla = 45;   -- Retro 45

-- =====================================================================
-- PEDIDOS: se crean como el usuario "comercial1" (id 2). Cada operación
-- queda auditada con ese usuario en log_eventos.
-- =====================================================================
SELECT set_config('app.id_usuario', '2', false);

INSERT INTO pedidos (id_pedido, id_cliente, fecha) VALUES
    ( 1, 1, '2026-08-05'), ( 2, 3, '2026-08-12'), ( 3, 2, '2026-08-20'),
    ( 4, 5, '2026-09-02'), ( 5, 4, '2026-09-08'), ( 6, 1, '2026-09-15'),
    ( 7, 3, '2026-09-21'), ( 8, 6, '2026-09-28'), ( 9, 5, '2026-10-03'),
    (10, 2, '2026-10-10'), (11, 1, '2026-10-18'), (12, 4, '2026-10-25');
SELECT setval(pg_get_serial_sequence('pedidos','id_pedido'), 12);

-- Líneas estándar (precio_unitario NULL => lo calcula el trigger)
INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad) VALUES
    ( 1, 1, 42, 1),                         -- SO001 Court 42
    ( 2, 5, 43, 1), ( 2, 6, 43, 1),         -- SO002 Street + Aero (dos líneas)
    ( 4, 3, 41, 1),                         -- SO004 High 41
    ( 7, 4, 43, 2),                         -- SO007 Retro 43 x2
    ( 8, 1, 39, 5), ( 8, 1, 40, 5), ( 8, 1, 41, 5),   -- SO008 Court x15 (3 tallas)
    ( 9, 5, 40, 1),                         -- SO009 Street 40
    (11, 2, 42, 2),                         -- SO011 Pulse 42 x2
    (12, 6, 44, 3);                         -- SO012 Aero 44 x3

-- SO003 · CASO COMÚN: Club Halcones, 40 pares Pulse personalizados, tallas 38-46
INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad,
       color_cuerpo, color_franja, color_puntera, color_talon, color_suela, color_cordones, texto_suela)
SELECT 3, 2, t.talla, t.cantidad,
       'Negro','Azul eléctrico','Negro','Gris','Blanco','Azul eléctrico','HALCONES'
  FROM (VALUES (38,2),(39,3),(40,4),(41,6),(42,8),(43,7),(44,5),(45,3),(46,2)) t(talla, cantidad);

-- SO005 · Peña Los Linces, 12 pares Court personalizados
INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad,
       color_cuerpo, color_franja, color_puntera, color_talon, color_suela, color_cordones, texto_suela)
SELECT 5, 1, t.talla, t.cantidad,
       'Blanco','Rojo','Blanco','Rojo','Blanco','Negro','LINCES'
  FROM (VALUES (40,3),(42,5),(44,4)) t(talla, cantidad);

-- SO006 · Ana García, 1 par Aero personalizado (sin texto)
INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad,
       color_cuerpo, color_franja, color_puntera, color_talon, color_suela, color_cordones)
VALUES (6, 6, 41, 1, 'Gris','Verde','Gris','Verde','Blanco','Amarillo');

-- SO010 · Club Halcones, 20 pares High personalizados (quedará PENDIENTE)
INSERT INTO lineas_pedido (id_pedido, id_modelo, talla, cantidad,
       color_cuerpo, color_franja, color_puntera, color_talon, color_suela, color_cordones, texto_suela)
VALUES (10, 3, 42, 10, 'Negro','Rojo','Rojo','Negro','Blanco','Rojo','HALCONES'),
       (10, 3, 43, 10, 'Negro','Rojo','Rojo','Negro','Blanco','Rojo','HALCONES');

-- ---------- Ciclo de vida: confirmar, cancelar (como Comercial) ----------
UPDATE pedidos SET estado = 'confirmado' WHERE id_pedido IN (1,2,3,4,5,6,7,11);  -- descuenta stock
UPDATE pedidos SET estado = 'cancelado'  WHERE id_pedido = 7;                    -- devuelve stock
UPDATE pedidos SET estado = 'cancelado'  WHERE id_pedido = 12;                   -- pendiente -> cancelado

-- ---------- Entregas (como Almacén, id 3) ----------
SELECT set_config('app.id_usuario', '3', false);
UPDATE pedidos SET estado = 'entregado' WHERE id_pedido IN (1,2,11);

SELECT set_config('app.id_usuario', '', false);   -- sesión sin usuario otra vez
