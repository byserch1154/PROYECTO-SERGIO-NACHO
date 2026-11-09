/* =============================================================
   SPEAKE · Colores de catálogo
   -------------------------------------------------------------
   Cada modelo se vende en varias combinaciones de color ya
   definidas por la marca (sin pasar por el configurador).
   · Una línea con color de catálogo es ESTÁNDAR: precio base del
     modelo, sin los +15 € de personalización.
   · Una línea personalizada (6 colores elegidos por el cliente) no
     lleva color de catálogo.

   Se puede ejecutar sobre una base con datos: no borra pedidos ni
   clientes (IF NOT EXISTS / ON CONFLICT / CREATE OR REPLACE).
   Orden: 01 -> 02 -> 07 -> 10_integracion_odoo -> 11_colores_catalogo
============================================================= */

CREATE TABLE IF NOT EXISTS colores_catalogo (
    id_color       smallserial PRIMARY KEY,
    id_modelo      smallint NOT NULL REFERENCES modelos(id_modelo),
    codigo         text     NOT NULL UNIQUE,         -- pulse-negro-azul (= nombre de la foto)
    nombre         text     NOT NULL,                -- Negro / Azul
    orden          smallint NOT NULL DEFAULT 1,      -- 1 = la de la foto principal del catálogo
    color_cuerpo   color_t  NOT NULL,
    color_franja   color_t  NOT NULL,
    color_puntera  color_t  NOT NULL,
    color_talon    color_t  NOT NULL,
    color_suela    color_t  NOT NULL,
    color_cordones color_t  NOT NULL,
    color_detalle  color_t  NOT NULL
);
ALTER TABLE colores_catalogo ADD COLUMN IF NOT EXISTS activo boolean NOT NULL DEFAULT true;
ALTER TABLE colores_catalogo DROP CONSTRAINT IF EXISTS colores_catalogo_id_modelo_nombre_key;

-- Combinaciones a la venta: cada una tiene su foto en lenguaje-de-marcas/img/colores/<codigo>.jpg
DROP TABLE IF EXISTS colores_nuevos;
CREATE TEMP TABLE colores_nuevos (modelo text, codigo text, nombre text, orden smallint,
    cuerpo text, franja text, puntera text, talon text, suela text, cordones text, detalle text);
INSERT INTO colores_nuevos VALUES
    ('court',  'court-blanco-azul',    'Blanco / Azul',     1, 'Blanco', 'Blanco',         'Blanco', 'Blanco', 'Blanco', 'Blanco', 'Azul eléctrico'),
    ('court',  'court-blanco-rojo',    'Blanco / Rojo',     2, 'Blanco', 'Blanco',         'Blanco', 'Blanco', 'Blanco', 'Blanco', 'Rojo'),
    ('court',  'court-blanco-verde',   'Blanco / Verde',    3, 'Blanco', 'Blanco',         'Blanco', 'Blanco', 'Blanco', 'Blanco', 'Verde'),
    ('pulse',  'pulse-negro-azul',     'Negro / Azul',      1, 'Negro',  'Azul eléctrico', 'Negro',  'Negro',  'Negro',  'Negro',  'Azul eléctrico'),
    ('pulse',  'pulse-negro-naranja',  'Negro / Naranja',   2, 'Negro',  'Naranja',        'Negro',  'Negro',  'Negro',  'Negro',  'Naranja'),
    ('pulse',  'pulse-negro-verde',    'Negro / Verde',     3, 'Negro',  'Verde',          'Negro',  'Negro',  'Negro',  'Negro',  'Verde'),
    ('high',   'high-blanco-azul',     'Blanco / Azul',     1, 'Blanco', 'Negro',          'Negro',  'Negro',  'Blanco', 'Negro',  'Azul eléctrico'),
    ('high',   'high-blanco-rojo',     'Blanco / Rojo',     2, 'Blanco', 'Negro',          'Negro',  'Negro',  'Blanco', 'Negro',  'Rojo'),
    ('high',   'high-blanco-amarillo', 'Blanco / Amarillo', 3, 'Blanco', 'Negro',          'Negro',  'Negro',  'Blanco', 'Negro',  'Amarillo'),
    ('retro',  'retro-gris-azul',      'Gris / Azul',       1, 'Gris',   'Negro',          'Gris',   'Gris',   'Blanco', 'Blanco', 'Azul eléctrico'),
    ('retro',  'retro-gris-naranja',   'Gris / Naranja',    2, 'Gris',   'Negro',          'Gris',   'Gris',   'Blanco', 'Blanco', 'Naranja'),
    ('retro',  'retro-gris-verde',     'Gris / Verde',      3, 'Gris',   'Negro',          'Gris',   'Gris',   'Blanco', 'Blanco', 'Verde'),
    ('street', 'street-negro-azul',    'Negro / Azul',      1, 'Negro',  'Negro',          'Negro',  'Negro',  'Blanco', 'Negro',  'Azul eléctrico'),
    ('street', 'street-negro-rojo',    'Negro / Rojo',      2, 'Negro',  'Negro',          'Negro',  'Negro',  'Blanco', 'Negro',  'Rojo'),
    ('street', 'street-negro-verde',   'Negro / Verde',     3, 'Negro',  'Negro',          'Negro',  'Negro',  'Blanco', 'Negro',  'Verde'),
    ('aero',   'aero-negro-azul',      'Negro / Azul',      1, 'Negro',  'Azul eléctrico', 'Negro',  'Negro',  'Blanco', 'Negro',  'Azul eléctrico'),
    ('aero',   'aero-negro-amarillo',  'Negro / Amarillo',  2, 'Negro',  'Amarillo',       'Negro',  'Negro',  'Blanco', 'Negro',  'Amarillo'),
    ('aero',   'aero-negro-rojo',      'Negro / Rojo',      3, 'Negro',  'Rojo',           'Negro',  'Negro',  'Blanco', 'Negro',  'Rojo');

INSERT INTO colores_catalogo (id_modelo, codigo, nombre, orden, color_cuerpo, color_franja,
                              color_puntera, color_talon, color_suela, color_cordones, color_detalle)
SELECT m.id_modelo, v.codigo, v.nombre, v.orden, v.cuerpo, v.franja, v.puntera, v.talon,
       v.suela, v.cordones, v.detalle
  FROM colores_nuevos v JOIN modelos m ON m.codigo = v.modelo
ON CONFLICT (codigo) DO UPDATE
   SET nombre = EXCLUDED.nombre, orden = EXCLUDED.orden, activo = true,
       color_cuerpo = EXCLUDED.color_cuerpo, color_franja = EXCLUDED.color_franja,
       color_puntera = EXCLUDED.color_puntera, color_talon = EXCLUDED.color_talon,
       color_suela = EXCLUDED.color_suela, color_cordones = EXCLUDED.color_cordones,
       color_detalle = EXCLUDED.color_detalle;

-- Combinaciones que ya no se venden: se dejan de mostrar (no se borran si algún pedido las usa)
UPDATE colores_catalogo SET activo = false
 WHERE codigo NOT IN (SELECT codigo FROM colores_nuevos);
DROP TABLE colores_nuevos;

-- La línea guarda qué combinación se compró
ALTER TABLE lineas_pedido ADD COLUMN IF NOT EXISTS id_color smallint REFERENCES colores_catalogo(id_color);

DELETE FROM colores_catalogo c
 WHERE NOT c.activo
   AND NOT EXISTS (SELECT 1 FROM lineas_pedido l WHERE l.id_color = c.id_color);

-- O color de catálogo o personalización, nunca las dos cosas
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_color_catalogo_estandar') THEN
        ALTER TABLE lineas_pedido ADD CONSTRAINT ck_color_catalogo_estandar
            CHECK (id_color IS NULL OR color_cuerpo IS NULL);
    END IF;
END $$;

-- El color tiene que ser del mismo modelo de la línea
CREATE OR REPLACE FUNCTION fn_lineas_color_catalogo() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.id_color IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM colores_catalogo c
         WHERE c.id_color = NEW.id_color AND c.id_modelo = NEW.id_modelo) THEN
        RAISE EXCEPTION 'Ese color de catálogo no corresponde al modelo de la línea';
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS t1b_lineas_color ON lineas_pedido;
CREATE TRIGGER t1b_lineas_color
    BEFORE INSERT OR UPDATE ON lineas_pedido
    FOR EACH ROW EXECUTE FUNCTION fn_lineas_color_catalogo();

-- La misma talla en dos colores distintos son dos líneas válidas
DROP INDEX IF EXISTS ux_linea_pedido;
CREATE UNIQUE INDEX ux_linea_pedido ON lineas_pedido (
    id_pedido, id_modelo, talla, coalesce(id_color, 0),
    coalesce(color_cuerpo::text, ''),  coalesce(color_franja::text, ''),
    coalesce(color_puntera::text, ''), coalesce(color_talon::text, ''),
    coalesce(color_suela::text, ''),   coalesce(color_cordones::text, ''),
    coalesce(texto_suela, ''));

-- Detalle del pedido para el panel: muestra el color de catálogo en las líneas estándar
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
           CASE WHEN l.color_cuerpo IS NOT NULL THEN
                concat_ws(' / ', l.color_cuerpo, l.color_franja, l.color_puntera,
                          l.color_talon, l.color_suela, l.color_cordones)
                WHEN cc.nombre IS NOT NULL THEN 'Color de catálogo: ' || cc.nombre
           END,
           l.texto_suela::text
      FROM pedidos p
      JOIN clientes c USING (id_cliente)
      LEFT JOIN lineas_pedido l ON l.id_pedido = p.id_pedido
      LEFT JOIN modelos m ON m.id_modelo = l.id_modelo
      LEFT JOIN colores_catalogo cc ON cc.id_color = l.id_color
     WHERE p.referencia = p_referencia
     ORDER BY l.talla, l.id_linea;
END $$;

-- Odoo también recibe el color de catálogo (va en la descripción de la línea)
DROP FUNCTION IF EXISTS fn_pedido_para_odoo(text);
CREATE FUNCTION fn_pedido_para_odoo(p_referencia text)
RETURNS TABLE (referencia text, estado text, tipo text,
               cliente text, email text, telefono text, tipo_cliente text,
               modelo text, talla smallint, cantidad integer, precio_unitario numeric,
               personalizacion text, texto_suela text, color_catalogo text)
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
           l.texto_suela::text,
           cc.nombre
      FROM pedidos p
      JOIN clientes c USING (id_cliente)
      JOIN lineas_pedido l ON l.id_pedido = p.id_pedido
      JOIN modelos m ON m.id_modelo = l.id_modelo
      LEFT JOIN colores_catalogo cc ON cc.id_color = l.id_color
     WHERE p.referencia = p_referencia
     ORDER BY l.talla, l.id_linea;
END $$;
