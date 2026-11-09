/* =============================================================
   SPEAKE · Integración con Odoo
   -------------------------------------------------------------
   Odoo tiene su propia base de datos y no se toca desde aquí: los
   pedidos se envían por su API (lo hace el backend, src/odoo.js).
   Este script solo guarda en SPEAKE qué pedido de Odoo corresponde
   a cada pedido nuestro y si el envío fue bien.

   Se puede ejecutar sobre una base que ya tiene datos: no borra ni
   modifica nada (CREATE ... IF NOT EXISTS / CREATE OR REPLACE).
   Orden: 01_esquema -> 02_datos -> 07_web_backend -> 10_integracion_odoo
============================================================= */

CREATE TABLE IF NOT EXISTS pedidos_odoo (
    id_pedido    integer PRIMARY KEY REFERENCES pedidos(id_pedido) ON DELETE CASCADE,
    pedido_odoo  text,                    -- nombre en Odoo, p. ej. S00012
    id_odoo      integer,                 -- id interno de sale.order
    estado       text NOT NULL CHECK (estado IN ('enviado', 'error')),
    mensaje      text,
    actualizado  timestamptz NOT NULL DEFAULT now()
);

-- Datos que necesita Odoo para crear el pedido de venta (cliente + líneas).
-- Solo quien puede confirmar pedidos puede enviarlos, y solo si ya son una venta.
DROP FUNCTION IF EXISTS fn_pedido_para_odoo(text);  -- 11_colores_catalogo.sql la amplía
CREATE FUNCTION fn_pedido_para_odoo(p_referencia text)
RETURNS TABLE (referencia text, estado text, tipo text,
               cliente text, email text, telefono text, tipo_cliente text,
               modelo text, talla smallint, cantidad integer, precio_unitario numeric,
               personalizacion text, texto_suela text)
LANGUAGE plpgsql STABLE AS $$
DECLARE v_estado text;
BEGIN
    PERFORM fn_exigir_permiso('confirmar_pedido');

    SELECT p.estado INTO v_estado FROM pedidos p WHERE p.referencia = p_referencia;
    IF v_estado IS NULL THEN
        RAISE EXCEPTION 'No existe el pedido %', p_referencia;
    END IF;
    IF v_estado NOT IN ('confirmado', 'entregado') THEN
        RAISE EXCEPTION 'El pedido % está %: solo se envían a Odoo los pedidos confirmados',
                        p_referencia, v_estado;
    END IF;

    RETURN QUERY
    SELECT p.referencia, p.estado, p.tipo,
           c.nombre, c.email, c.telefono, c.tipo,
           m.nombre, l.talla::smallint, l.cantidad, l.precio_unitario,
           CASE WHEN l.color_cuerpo IS NULL THEN NULL ELSE
                concat_ws(' / ', l.color_cuerpo, l.color_franja, l.color_puntera,
                          l.color_talon, l.color_suela, l.color_cordones) END,
           l.texto_suela::text
      FROM pedidos p
      JOIN clientes c USING (id_cliente)
      JOIN lineas_pedido l ON l.id_pedido = p.id_pedido
      JOIN modelos m ON m.id_modelo = l.id_modelo
     WHERE p.referencia = p_referencia
     ORDER BY l.talla, l.id_linea;
END $$;

-- Apunta el resultado del envío (se sobrescribe si se reenvía)
CREATE OR REPLACE FUNCTION fn_registrar_envio_odoo(p_referencia text, p_estado text,
                                                   p_pedido_odoo text, p_id_odoo integer,
                                                   p_mensaje text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
    PERFORM fn_exigir_permiso('confirmar_pedido');
    INSERT INTO pedidos_odoo (id_pedido, pedido_odoo, id_odoo, estado, mensaje)
    SELECT id_pedido, p_pedido_odoo, p_id_odoo, p_estado, left(p_mensaje, 300)
      FROM pedidos WHERE referencia = p_referencia
    ON CONFLICT (id_pedido) DO UPDATE
       SET pedido_odoo = coalesce(EXCLUDED.pedido_odoo, pedidos_odoo.pedido_odoo),
           id_odoo     = coalesce(EXCLUDED.id_odoo, pedidos_odoo.id_odoo),
           estado      = EXCLUDED.estado,
           mensaje     = EXCLUDED.mensaje,
           actualizado = now();
END $$;

-- Para el panel: estado de sincronización de cada pedido
CREATE OR REPLACE VIEW v_pedidos_odoo AS
SELECT p.referencia, o.pedido_odoo, o.estado, o.mensaje, o.actualizado
  FROM pedidos_odoo o
  JOIN pedidos p USING (id_pedido);
