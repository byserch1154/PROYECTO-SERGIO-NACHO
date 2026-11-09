-- =====================================================================
-- 07_web_backend.sql · Ampliación para el backend Express (web pública)
-- Ejecutar DESPUÉS de 01_esquema.sql y 02_datos.sql:
--   psql -d sneaker_factory -v ON_ERROR_STOP=1 -f 07_web_backend.sql
--
-- Las solicitudes Custom que llegan desde la web pública también deben
-- quedar asociadas a un usuario autenticado en log_eventos. Para ello se
-- crea el rol funcional "Web" y su usuario técnico "web_publica":
--   · Solo puede CREAR pedidos (siempre nacen 'pendiente') y añadir sus
--     líneas. No puede consultar, confirmar, cancelar ni ver auditoría.
--   · Su contraseña es aleatoria y nadie la conoce: no puede iniciar
--     sesión en el panel. Solo lo usa el servidor en POST /api/solicitudes.
-- Un comercial revisa después la solicitud y la confirma desde el panel.
-- =====================================================================

INSERT INTO roles (nombre) VALUES ('Web') ON CONFLICT (nombre) DO NOTHING;

INSERT INTO permisos (id_rol, operacion, permitido)
SELECT r.id_rol, o.op, o.op IN ('crear_pedido', 'editar_pedido')
  FROM roles r
 CROSS JOIN (VALUES ('consultar_pedidos'),('crear_pedido'),('editar_pedido'),
                    ('confirmar_pedido'),('cancelar_pedido'),('entregar_pedido'),
                    ('eliminar_pedido'),('consultar_stock'),('ver_auditoria'),
                    ('gestionar_usuarios'),('exportar_usuarios')) o(op)
 WHERE r.nombre = 'Web'
ON CONFLICT (id_rol, operacion) DO NOTHING;

INSERT INTO usuarios (username, password_hash, id_rol)
SELECT 'web_publica', crypt(gen_random_uuid()::text, gen_salt('bf', 10)), r.id_rol
  FROM roles r WHERE r.nombre = 'Web'
ON CONFLICT (username) DO NOTHING;

-- Clientes que entran por la web: se identifican por email (UNIQUE).
-- Si ya existe se reutiliza (no se duplica) y se actualiza nombre/teléfono.
CREATE OR REPLACE FUNCTION fn_cliente_web(p_nombre text, p_email text,
                                          p_telefono text, p_tipo text)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_id integer;
BEGIN
    PERFORM fn_exigir_permiso('crear_pedido');
    INSERT INTO clientes (nombre, email, telefono, tipo)
    VALUES (btrim(p_nombre), lower(btrim(p_email)), nullif(btrim(p_telefono), ''),
            coalesce(p_tipo, 'particular'))
    ON CONFLICT (email) DO UPDATE
       SET nombre = EXCLUDED.nombre,
           telefono = coalesce(EXCLUDED.telefono, clientes.telefono)
    RETURNING id_cliente INTO v_id;
    RETURN v_id;
END $$;

-- Detalle de un pedido (cabecera + líneas) con control de permisos
CREATE OR REPLACE FUNCTION fn_detalle_pedido(p_referencia text)
RETURNS TABLE (referencia text, fecha date, cliente text, estado text, tipo text,
               total numeric, id_linea integer, modelo text, talla smallint,
               cantidad integer, precio_unitario numeric, personalizacion text,
               texto_suela text)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    PERFORM fn_exigir_permiso('consultar_pedidos');
    RETURN QUERY
    SELECT p.referencia, p.fecha, c.nombre, p.estado, p.tipo, p.total,
           l.id_linea, m.nombre, l.talla::smallint, l.cantidad, l.precio_unitario,
           CASE WHEN l.color_cuerpo IS NULL THEN NULL ELSE
                concat_ws(' / ', l.color_cuerpo, l.color_franja, l.color_puntera,
                          l.color_talon, l.color_suela, l.color_cordones) END,
           l.texto_suela::text
      FROM pedidos p
      JOIN clientes c USING (id_cliente)
      LEFT JOIN lineas_pedido l ON l.id_pedido = p.id_pedido
      LEFT JOIN modelos m ON m.id_modelo = l.id_modelo
     WHERE p.referencia = p_referencia
     ORDER BY l.talla, l.id_linea;
END $$;

-- Análisis por modelo y por talla (solo ventas: confirmados + entregados)
CREATE OR REPLACE FUNCTION fn_analisis_modelos()
RETURNS TABLE (modelo text, pedidos bigint, pares bigint, importe numeric)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    PERFORM fn_exigir_permiso('consultar_pedidos');
    RETURN QUERY
    SELECT m.nombre,
           count(DISTINCT p.id_pedido),                       -- pedidos, no líneas
           coalesce(sum(l.cantidad) FILTER (WHERE p.id_pedido IS NOT NULL), 0)::bigint,
           coalesce(sum(l.cantidad * l.precio_unitario) FILTER (WHERE p.id_pedido IS NOT NULL), 0)
      FROM modelos m
      LEFT JOIN lineas_pedido l ON l.id_modelo = m.id_modelo
      LEFT JOIN pedidos p ON p.id_pedido = l.id_pedido AND p.estado IN ('confirmado','entregado')
     GROUP BY m.nombre
     ORDER BY 3 DESC, 1;
END $$;

CREATE OR REPLACE FUNCTION fn_analisis_tallas()
RETURNS TABLE (talla smallint, pares bigint)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    PERFORM fn_exigir_permiso('consultar_pedidos');
    RETURN QUERY
    SELECT t::smallint, coalesce(sum(l.cantidad) FILTER (WHERE p.id_pedido IS NOT NULL), 0)::bigint
      FROM generate_series(38, 46) t
      LEFT JOIN lineas_pedido l ON l.talla = t
      LEFT JOIN pedidos p ON p.id_pedido = l.id_pedido AND p.estado IN ('confirmado','entregado')
     GROUP BY t ORDER BY t;
END $$;

-- Cifras de control para la conciliación con Python (df12_reconciliacion)
CREATE OR REPLACE VIEW v_reconciliacion AS
    SELECT 'pedidos_totales' AS indicador, count(*)::numeric AS valor FROM pedidos
    UNION ALL SELECT 'lineas_totales', count(*)::numeric FROM lineas_pedido
    UNION ALL SELECT 'pedidos_venta', count(*)::numeric FROM pedidos WHERE estado IN ('confirmado','entregado')
    UNION ALL SELECT 'pares_vendidos', coalesce(sum(l.cantidad),0)::numeric
                FROM lineas_pedido l JOIN pedidos p USING (id_pedido) WHERE p.estado IN ('confirmado','entregado')
    UNION ALL SELECT 'importe_ventas', coalesce(sum(total),0) FROM pedidos WHERE estado IN ('confirmado','entregado')
    UNION ALL SELECT 'clientes_con_venta', count(DISTINCT id_cliente)::numeric FROM pedidos WHERE estado IN ('confirmado','entregado');
