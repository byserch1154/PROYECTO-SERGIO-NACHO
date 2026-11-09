-- =====================================================================
-- SPEAKE · Sneaker Factory · Acceso a Datos
-- 01_esquema.sql  ·  Tablas, restricciones, funciones y triggers
-- PostgreSQL 14+   ·   Ejecutar sobre una base de datos VACÍA:
--   createdb sneaker_factory
--   psql -d sneaker_factory -v ON_ERROR_STOP=1 -f 01_esquema.sql
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- bcrypt: crypt() / gen_salt()

-- ---------------------------------------------------------------------
-- 0. DOMINIOS (valores permitidos, iguales a los del configurador web)
-- ---------------------------------------------------------------------
CREATE DOMAIN talla_t AS smallint
    CHECK (VALUE BETWEEN 38 AND 46);

CREATE DOMAIN color_t AS text
    CHECK (VALUE IN ('Negro','Blanco','Azul eléctrico','Rojo',
                     'Verde','Amarillo','Naranja','Gris'));

-- ---------------------------------------------------------------------
-- 1. SEGURIDAD: roles de la aplicación, usuarios y matriz de permisos
--    (roles FUNCIONALES de la app, distintos de los roles de PostgreSQL)
-- ---------------------------------------------------------------------
CREATE TABLE roles (
    id_rol   smallserial PRIMARY KEY,
    nombre   text NOT NULL UNIQUE
);

CREATE TABLE permisos (
    id_rol     smallint NOT NULL REFERENCES roles(id_rol),
    operacion  text     NOT NULL CHECK (operacion IN (
                   'consultar_pedidos','crear_pedido','editar_pedido',
                   'confirmar_pedido','cancelar_pedido','entregar_pedido',
                   'eliminar_pedido','consultar_stock','ver_auditoria',
                   'gestionar_usuarios','exportar_usuarios')),
    permitido  boolean  NOT NULL,
    PRIMARY KEY (id_rol, operacion)
);

CREATE TABLE usuarios (
    id_usuario     serial PRIMARY KEY,
    username       text   NOT NULL UNIQUE CHECK (length(username) >= 3),
    password_hash  text   NOT NULL,                 -- bcrypt con sal, nunca texto plano
    id_rol         smallint NOT NULL REFERENCES roles(id_rol),
    activo         boolean  NOT NULL DEFAULT true,
    fecha_creacion timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 2. NEGOCIO
-- ---------------------------------------------------------------------
CREATE TABLE clientes (
    id_cliente serial PRIMARY KEY,
    nombre     text NOT NULL,
    email      text NOT NULL UNIQUE CHECK (email LIKE '%_@_%'),
    telefono   text,
    tipo       text NOT NULL DEFAULT 'particular'
               CHECK (tipo IN ('particular','club','equipo')),
    fecha_alta date NOT NULL DEFAULT current_date
);

CREATE TABLE modelos (
    id_modelo    smallserial PRIMARY KEY,
    codigo       text NOT NULL UNIQUE,              -- court, pulse, high, retro, street, aero
    nombre       text NOT NULL,
    categoria    text NOT NULL,
    precio_base  numeric(8,2) NOT NULL CHECK (precio_base > 0)
);

CREATE TABLE pedidos (
    id_pedido   serial PRIMARY KEY,
    -- Referencia común con Odoo / PSP: SO001, SO002...  (se calcula sola)
    referencia  text GENERATED ALWAYS AS ('SO' || lpad(id_pedido::text, 3, '0')) STORED,
    id_cliente  integer NOT NULL REFERENCES clientes(id_cliente),
    fecha       date    NOT NULL DEFAULT current_date,
    estado      text    NOT NULL DEFAULT 'pendiente'
                CHECK (estado IN ('pendiente','confirmado','entregado','cancelado')),
    tipo        text    NOT NULL DEFAULT 'estandar'          -- lo mantiene un trigger
                CHECK (tipo IN ('estandar','custom')),
    total       numeric(10,2) NOT NULL DEFAULT 0 CHECK (total >= 0),  -- lo mantiene un trigger
    creado_por  integer REFERENCES usuarios(id_usuario),
    UNIQUE (referencia)
);

CREATE TABLE lineas_pedido (
    id_linea        serial PRIMARY KEY,
    id_pedido       integer  NOT NULL REFERENCES pedidos(id_pedido),   -- sin ON DELETE CASCADE
    id_modelo       smallint NOT NULL REFERENCES modelos(id_modelo),
    talla           talla_t  NOT NULL,
    cantidad        integer  NOT NULL CHECK (cantidad > 0),
    precio_unitario numeric(8,2) NOT NULL CHECK (precio_unitario >= 0), -- si va NULL lo calcula un trigger
    -- Personalización (mismas 6 partes que el configurador web)
    color_cuerpo    color_t,
    color_franja    color_t,
    color_puntera   color_t,
    color_talon     color_t,
    color_suela     color_t,
    color_cordones  color_t,
    texto_suela     varchar(12),
    -- o va sin personalizar (6 NULL) o con las 6 partes definidas
    CONSTRAINT ck_personalizacion_completa CHECK (
        num_nonnulls(color_cuerpo, color_franja, color_puntera,
                     color_talon, color_suela, color_cordones) IN (0, 6)),
    CONSTRAINT ck_texto_solo_custom CHECK (
        texto_suela IS NULL OR color_cuerpo IS NOT NULL)
);

-- Clave de duplicidad documentada: mismo pedido + modelo + talla + personalización
CREATE UNIQUE INDEX ux_linea_pedido ON lineas_pedido (
    id_pedido, id_modelo, talla,
    coalesce(color_cuerpo::text,''),  coalesce(color_franja::text,''),
    coalesce(color_puntera::text,''), coalesce(color_talon::text,''),
    coalesce(color_suela::text,''),   coalesce(color_cordones::text,''),
    coalesce(texto_suela,''));

CREATE INDEX ix_lineas_pedido ON lineas_pedido (id_pedido);
CREATE INDEX ix_pedidos_cliente ON pedidos (id_cliente);
CREATE INDEX ix_pedidos_fecha_estado ON pedidos (fecha, estado);

CREATE TABLE stock (
    id_modelo        smallint NOT NULL REFERENCES modelos(id_modelo),
    talla            talla_t  NOT NULL,
    stock_disponible integer  NOT NULL DEFAULT 0 CHECK (stock_disponible >= 0),
    fecha_corte      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id_modelo, talla)
);

-- ---------------------------------------------------------------------
-- 3. AUDITORÍA
-- ---------------------------------------------------------------------
CREATE TABLE log_eventos (
    id_evento   bigserial PRIMARY KEY,
    fecha       timestamptz NOT NULL DEFAULT now(),   -- now() = inicio de la transacción
    tabla       text    NOT NULL,
    operacion   text    NOT NULL CHECK (operacion IN ('INSERT','UPDATE','DELETE')),
    id_registro text    NOT NULL,
    id_usuario  integer NOT NULL REFERENCES usuarios(id_usuario),
    resumen     text    NOT NULL
);
CREATE INDEX ix_log_fecha ON log_eventos (fecha);

-- =====================================================================
-- 4. IDENTIDAD Y PERMISOS
--    Java abre cada transacción con:
--        SELECT set_config('app.id_usuario', '<id>', true);
--    (true = solo dura hasta COMMIT/ROLLBACK, es seguro con pools JDBC)
-- =====================================================================

CREATE FUNCTION fn_login(p_username text, p_password text)
RETURNS integer LANGUAGE sql STABLE AS $$
    SELECT id_usuario FROM usuarios
     WHERE username = p_username AND activo
       AND password_hash = crypt(p_password, password_hash);
$$;

CREATE FUNCTION fn_usuario_actual() RETURNS integer
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v text := current_setting('app.id_usuario', true);
    u integer;
BEGIN
    IF v IS NULL OR v = '' THEN
        RAISE EXCEPTION 'Operación sin usuario autenticado'
              USING ERRCODE = '28000';
    END IF;
    SELECT id_usuario INTO u FROM usuarios WHERE id_usuario = v::integer AND activo;
    IF u IS NULL THEN
        RAISE EXCEPTION 'Usuario % inexistente o inactivo', v
              USING ERRCODE = '28000';
    END IF;
    RETURN u;
END $$;

CREATE FUNCTION fn_tiene_permiso(p_operacion text) RETURNS boolean
LANGUAGE sql STABLE AS $$
    SELECT coalesce((SELECT p.permitido
                       FROM usuarios u JOIN permisos p ON p.id_rol = u.id_rol
                      WHERE u.id_usuario = fn_usuario_actual()
                        AND p.operacion = p_operacion), false);
$$;

CREATE FUNCTION fn_exigir_permiso(p_operacion text) RETURNS void
LANGUAGE plpgsql STABLE AS $$
BEGIN
    IF NOT fn_tiene_permiso(p_operacion) THEN
        RAISE EXCEPTION 'Permiso denegado: su rol no puede ejecutar "%"', p_operacion
              USING ERRCODE = '42501';
    END IF;
END $$;

-- =====================================================================
-- 5. TRIGGERS DE PEDIDOS
--    Orden de ejecución (los triggers del mismo momento se ejecutan por
--    orden alfabético de nombre):
--      BEFORE: t1_permisos -> t2_validar
--      AFTER : t3_stock, t4_auditoria
-- =====================================================================

-- 5.1 Permisos sobre pedidos (se aplican en la base de datos, no en Java)
CREATE FUNCTION fn_pedidos_permisos() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM fn_exigir_permiso('crear_pedido');
        -- Un pedido nuevo siempre nace pendiente: confirmarlo es una transición
        -- (UPDATE) que descuenta stock. Si pudiera nacer confirmado se saltaría el stock.
        IF NEW.estado <> 'pendiente' THEN
            RAISE EXCEPTION 'Un pedido nuevo debe crearse como pendiente (recibido: %)', NEW.estado;
        END IF;
        NEW.creado_por := fn_usuario_actual();
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.estado IS DISTINCT FROM NEW.estado THEN
            PERFORM fn_exigir_permiso(CASE NEW.estado
                WHEN 'confirmado' THEN 'confirmar_pedido'
                WHEN 'cancelado'  THEN 'cancelar_pedido'
                WHEN 'entregado'  THEN 'entregar_pedido'
                ELSE 'editar_pedido' END);
        ELSIF OLD.id_cliente IS DISTINCT FROM NEW.id_cliente
           OR OLD.fecha      IS DISTINCT FROM NEW.fecha THEN
            PERFORM fn_exigir_permiso('editar_pedido');
        END IF;   -- cambios de total/tipo son derivados (los hace otro trigger)
        RETURN NEW;
    ELSE
        PERFORM fn_exigir_permiso('eliminar_pedido');
        RETURN OLD;
    END IF;
END $$;

CREATE TRIGGER t1_pedidos_permisos
    BEFORE INSERT OR UPDATE OR DELETE ON pedidos
    FOR EACH ROW EXECUTE FUNCTION fn_pedidos_permisos();

-- 5.2 Validación: transiciones de estado y pedidos no editables
CREATE FUNCTION fn_pedidos_validar() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.estado <> 'pendiente' THEN
            RAISE EXCEPTION 'Solo se pueden eliminar pedidos pendientes (%: %)', OLD.referencia, OLD.estado;
        END IF;
        RETURN OLD;
    END IF;

    IF NEW.estado IS DISTINCT FROM OLD.estado THEN
        IF NOT ((OLD.estado = 'pendiente'  AND NEW.estado IN ('confirmado','cancelado'))
             OR (OLD.estado = 'confirmado' AND NEW.estado IN ('entregado','cancelado'))) THEN
            RAISE EXCEPTION 'Transición no permitida en %: % -> %', OLD.referencia, OLD.estado, NEW.estado;
        END IF;
        IF NEW.estado = 'confirmado'
           AND NOT EXISTS (SELECT 1 FROM lineas_pedido WHERE id_pedido = NEW.id_pedido) THEN
            RAISE EXCEPTION 'No se puede confirmar % sin líneas', OLD.referencia;
        END IF;
    ELSIF OLD.estado <> 'pendiente'
          AND (OLD.id_cliente IS DISTINCT FROM NEW.id_cliente
            OR OLD.fecha      IS DISTINCT FROM NEW.fecha) THEN
        RAISE EXCEPTION 'El pedido % está % y ya no es editable', OLD.referencia, OLD.estado;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER t2_pedidos_validar
    BEFORE UPDATE OR DELETE ON pedidos
    FOR EACH ROW EXECUTE FUNCTION fn_pedidos_validar();

-- 5.3 AUTOMATIZACIÓN 2 · EXISTENCIAS
--     Solo reacciona a CAMBIOS DE ESTADO (no a editar líneas):
--       pendiente  -> confirmado : descuenta stock (rechaza si no hay)
--       confirmado -> cancelado  : devuelve el stock descontado
--       resto de transiciones    : no tocan stock
--     Modifica: stock.   No dispara más triggers (stock no tiene).
CREATE FUNCTION fn_pedidos_stock() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    r record;
BEGIN
    IF OLD.estado = 'pendiente' AND NEW.estado = 'confirmado' THEN
        FOR r IN SELECT l.id_modelo, l.talla, sum(l.cantidad)::integer AS q, m.nombre
                   FROM lineas_pedido l JOIN modelos m USING (id_modelo)
                  WHERE l.id_pedido = NEW.id_pedido
                  GROUP BY l.id_modelo, l.talla, m.nombre
                  ORDER BY l.id_modelo, l.talla            -- orden fijo: evita interbloqueos
        LOOP
            UPDATE stock
               SET stock_disponible = stock_disponible - r.q, fecha_corte = now()
             WHERE id_modelo = r.id_modelo AND talla = r.talla
               AND stock_disponible >= r.q;
            IF NOT FOUND THEN
                RAISE EXCEPTION 'Stock insuficiente para % talla % (se piden % pares)',
                      r.nombre, r.talla, r.q USING ERRCODE = '23514';
            END IF;
        END LOOP;
    ELSIF OLD.estado = 'confirmado' AND NEW.estado = 'cancelado' THEN
        UPDATE stock s
           SET stock_disponible = s.stock_disponible + x.q, fecha_corte = now()
          FROM (SELECT id_modelo, talla, sum(cantidad)::integer AS q
                  FROM lineas_pedido WHERE id_pedido = NEW.id_pedido
                 GROUP BY id_modelo, talla) x
         WHERE s.id_modelo = x.id_modelo AND s.talla = x.talla;
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER t3_pedidos_stock
    AFTER UPDATE OF estado ON pedidos
    FOR EACH ROW WHEN (OLD.estado IS DISTINCT FROM NEW.estado)
    EXECUTE FUNCTION fn_pedidos_stock();

-- 5.4 AUDITORÍA (genérica: sirve para pedidos y lineas_pedido)
--     TG_ARGV[0] = nombre de la columna clave.
--     Se ejecuta dentro de la transacción: si hay ROLLBACK, el log desaparece.
CREATE FUNCTION fn_auditar() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_reg   jsonb := to_jsonb(CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END);
    v_res   text;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_res := 'alta ' || v_reg::text;
    ELSIF TG_OP = 'DELETE' THEN
        v_res := 'baja ' || v_reg::text;
    ELSE
        SELECT string_agg(o.key || ': ' || coalesce(o.value,'NULL') || ' -> ' || coalesce(n.value,'NULL'),
                          '; ' ORDER BY o.key)
          INTO v_res
          FROM jsonb_each_text(to_jsonb(OLD)) AS o(key, value)
          JOIN jsonb_each_text(to_jsonb(NEW)) AS n(key, value) ON n.key = o.key
         WHERE o.value IS DISTINCT FROM n.value;
    END IF;

    INSERT INTO log_eventos (tabla, operacion, id_registro, id_usuario, resumen)
    VALUES (TG_TABLE_NAME, TG_OP, v_reg ->> TG_ARGV[0], fn_usuario_actual(), v_res);
    RETURN NULL;
END $$;

-- En pedidos solo se auditan cambios relevantes (estado, cliente, fecha);
-- total y tipo son derivados y se recalculan solos.
CREATE TRIGGER t4_pedidos_audit_altabaja
    AFTER INSERT OR DELETE ON pedidos
    FOR EACH ROW EXECUTE FUNCTION fn_auditar('id_pedido');

CREATE TRIGGER t4_pedidos_audit_cambios
    AFTER UPDATE ON pedidos
    FOR EACH ROW WHEN (OLD.estado     IS DISTINCT FROM NEW.estado
                    OR OLD.id_cliente IS DISTINCT FROM NEW.id_cliente
                    OR OLD.fecha      IS DISTINCT FROM NEW.fecha)
    EXECUTE FUNCTION fn_auditar('id_pedido');

-- =====================================================================
-- 6. TRIGGERS DE LÍNEAS
--      BEFORE: t1_lineas_antes   (permiso, pedido editable, precio)
--      AFTER : t2_lineas_total   (AUTOMATIZACIÓN 1 · importes)
--              t3_lineas_audit
-- =====================================================================

-- 6.1 Antes de tocar una línea: permiso + pedido pendiente + precio automático
CREATE FUNCTION fn_lineas_antes() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_estado text;
    v_base   numeric(8,2);
BEGIN
    PERFORM fn_exigir_permiso('editar_pedido');

    SELECT estado INTO v_estado FROM pedidos
     WHERE id_pedido = CASE WHEN TG_OP = 'DELETE' THEN OLD.id_pedido ELSE NEW.id_pedido END;
    IF v_estado IS DISTINCT FROM 'pendiente' THEN
        RAISE EXCEPTION 'No se pueden modificar líneas: el pedido no existe o está % ', v_estado;
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;

    IF TG_OP = 'UPDATE' AND NEW.id_pedido <> OLD.id_pedido THEN
        RAISE EXCEPTION 'Una línea no se puede mover a otro pedido';
    END IF;

    NEW.texto_suela := nullif(btrim(NEW.texto_suela), '');

    -- Precio automático: base del modelo + 15 € si es personalizada + 5 € si lleva texto
    IF NEW.precio_unitario IS NULL THEN
        SELECT precio_base INTO v_base FROM modelos WHERE id_modelo = NEW.id_modelo;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'El modelo % no existe en el catálogo', NEW.id_modelo
                  USING ERRCODE = '23503';
        END IF;
        NEW.precio_unitario := v_base
            + CASE WHEN NEW.color_cuerpo IS NOT NULL THEN 15 ELSE 0 END
            + CASE WHEN NEW.texto_suela  IS NOT NULL THEN 5  ELSE 0 END;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER t1_lineas_antes
    BEFORE INSERT OR UPDATE OR DELETE ON lineas_pedido
    FOR EACH ROW EXECUTE FUNCTION fn_lineas_antes();

-- 6.2 AUTOMATIZACIÓN 1 · IMPORTES
--     El total se RECALCULA desde las líneas (nunca se suma sobre el valor
--     anterior), así no hay totales duplicados ni incoherentes.
--     También deriva pedidos.tipo (custom si alguna línea está personalizada).
--     Modifica: pedidos (total, tipo). Sus triggers lo ignoran: ni se
--     audita ni toca stock (no cambia estado) => sin recursión.
CREATE FUNCTION fn_lineas_total() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    v_id integer := CASE WHEN TG_OP = 'DELETE' THEN OLD.id_pedido ELSE NEW.id_pedido END;
BEGIN
    UPDATE pedidos p
       SET total = coalesce((SELECT sum(l.cantidad * l.precio_unitario)
                               FROM lineas_pedido l WHERE l.id_pedido = p.id_pedido), 0),
           tipo  = CASE WHEN EXISTS (SELECT 1 FROM lineas_pedido l
                                      WHERE l.id_pedido = p.id_pedido
                                        AND l.color_cuerpo IS NOT NULL)
                        THEN 'custom' ELSE 'estandar' END
     WHERE p.id_pedido = v_id;
    RETURN NULL;
END $$;

CREATE TRIGGER t2_lineas_total
    AFTER INSERT OR UPDATE OR DELETE ON lineas_pedido
    FOR EACH ROW EXECUTE FUNCTION fn_lineas_total();

CREATE TRIGGER t3_lineas_audit
    AFTER INSERT OR UPDATE OR DELETE ON lineas_pedido
    FOR EACH ROW EXECUTE FUNCTION fn_auditar('id_linea');

-- =====================================================================
-- 7. FUNCIONES DE CONSULTA CON PERMISOS (las usará Java con JDBC)
--    Un valor NULL en un filtro significa "sin restricción".
-- =====================================================================

CREATE FUNCTION fn_buscar_pedidos(
    p_cliente text DEFAULT NULL, p_modelo text DEFAULT NULL,
    p_estado  text DEFAULT NULL, p_desde  date DEFAULT NULL,
    p_hasta   date DEFAULT NULL)
RETURNS TABLE (referencia text, fecha date, cliente text, estado text,
               tipo text, pares integer, total numeric)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    PERFORM fn_exigir_permiso('consultar_pedidos');
    RETURN QUERY
    SELECT p.referencia, p.fecha, c.nombre, p.estado, p.tipo,
           coalesce((SELECT sum(l.cantidad) FROM lineas_pedido l
                      WHERE l.id_pedido = p.id_pedido), 0)::integer,
           p.total
      FROM pedidos p JOIN clientes c USING (id_cliente)
     WHERE (p_cliente IS NULL OR c.nombre ILIKE '%' || p_cliente || '%')
       AND (p_estado  IS NULL OR p.estado = p_estado)
       AND (p_desde   IS NULL OR p.fecha >= p_desde)
       AND (p_hasta   IS NULL OR p.fecha <= p_hasta)
       AND (p_modelo  IS NULL OR EXISTS (
              SELECT 1 FROM lineas_pedido l JOIN modelos m USING (id_modelo)
               WHERE l.id_pedido = p.id_pedido AND m.codigo = p_modelo))
     ORDER BY p.fecha DESC, p.id_pedido DESC;
END $$;

CREATE FUNCTION fn_stock_bajo(p_umbral integer DEFAULT 5)
RETURNS TABLE (modelo text, talla smallint, stock_disponible integer)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    PERFORM fn_exigir_permiso('consultar_stock');
    RETURN QUERY
    SELECT m.nombre, s.talla::smallint, s.stock_disponible
      FROM stock s JOIN modelos m USING (id_modelo)
     WHERE s.stock_disponible <= p_umbral
     ORDER BY s.stock_disponible, m.nombre, s.talla;
END $$;

-- Ventas = pedidos confirmados + entregados (los cancelados y pendientes no cuentan)
CREATE FUNCTION fn_indicadores()
RETURNS TABLE (indicador text, valor numeric)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    PERFORM fn_exigir_permiso('consultar_pedidos');
    RETURN QUERY
    SELECT 'pedidos_totales', count(*)::numeric FROM pedidos
    UNION ALL
    -- pares solicitados = pares de pedidos no cancelados (actividad)
    SELECT 'pares_solicitados', coalesce(sum(l.cantidad),0)::numeric
      FROM lineas_pedido l JOIN pedidos p USING (id_pedido)
     WHERE p.estado <> 'cancelado'
    UNION ALL
    -- pares vendidos = pares de pedidos confirmados o entregados (ventas)
    SELECT 'pares_vendidos', coalesce(sum(l.cantidad),0)::numeric
      FROM lineas_pedido l JOIN pedidos p USING (id_pedido)
     WHERE p.estado IN ('confirmado','entregado')
    UNION ALL
    SELECT 'importe_ventas', coalesce(sum(total),0)
      FROM pedidos WHERE estado IN ('confirmado','entregado')
    UNION ALL
    SELECT 'pedidos_' || e.estado, count(p.id_pedido)::numeric
      FROM (VALUES ('pendiente'),('confirmado'),('entregado'),('cancelado')) e(estado)
      LEFT JOIN pedidos p ON p.estado = e.estado
     GROUP BY e.estado;
END $$;

-- =====================================================================
-- 8. VISTAS · CONTRATO DE DATOS CON PSP Y PYTHON
--    Los nombres de columna son los del enunciado de Ampliación de Python.
-- =====================================================================
CREATE VIEW v_export_clientes AS
    SELECT id_cliente, nombre, tipo FROM clientes;           -- sin email/teléfono

CREATE VIEW v_export_modelos AS
    SELECT id_modelo, nombre AS modelo, categoria FROM modelos;

CREATE VIEW v_export_pedidos AS
    SELECT id_pedido, fecha, id_cliente, estado, tipo FROM pedidos;

CREATE VIEW v_export_lineas_pedido AS
    SELECT id_linea, id_pedido, id_modelo, talla, cantidad, precio_unitario
      FROM lineas_pedido;

CREATE VIEW v_export_stock AS
    SELECT id_modelo, talla, stock_disponible, fecha_corte::date AS fecha_corte
      FROM stock;

-- Ficha de fabricación (entrada de PSP): pedidos custom confirmados
CREATE VIEW v_ficha_fabricacion AS
    SELECT p.referencia, c.nombre AS cliente, m.nombre AS modelo,
           l.color_cuerpo, l.color_franja, l.color_puntera, l.color_talon,
           l.color_suela, l.color_cordones, l.texto_suela,
           l.talla, l.cantidad
      FROM lineas_pedido l
      JOIN pedidos  p USING (id_pedido)
      JOIN clientes c USING (id_cliente)
      JOIN modelos  m USING (id_modelo)
     WHERE p.estado = 'confirmado' AND l.color_cuerpo IS NOT NULL
     ORDER BY p.referencia, l.talla;

-- =====================================================================
-- 9. GESTIÓN DE USUARIOS Y AUDITORÍA CON PERMISOS
--    (las usará Java; el permiso se comprueba aquí, no solo en la interfaz)
-- =====================================================================

CREATE FUNCTION fn_crear_usuario(p_username text, p_password text, p_rol text)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_id integer;
BEGIN
    PERFORM fn_exigir_permiso('gestionar_usuarios');
    INSERT INTO usuarios (username, password_hash, id_rol)
    SELECT p_username, crypt(p_password, gen_salt('bf', 10)), r.id_rol
      FROM roles r WHERE r.nombre = p_rol
    RETURNING id_usuario INTO v_id;
    IF v_id IS NULL THEN
        RAISE EXCEPTION 'El rol "%" no existe', p_rol;
    END IF;
    RETURN v_id;
END $$;

CREATE FUNCTION fn_cambiar_activo(p_id integer, p_activo boolean) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM fn_exigir_permiso('gestionar_usuarios');
    IF NOT p_activo AND p_id = fn_usuario_actual() THEN
        RAISE EXCEPTION 'No puedes desactivar tu propio usuario';
    END IF;
    UPDATE usuarios SET activo = p_activo WHERE id_usuario = p_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Usuario % inexistente', p_id; END IF;
END $$;

CREATE FUNCTION fn_cambiar_rol(p_id integer, p_rol text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    PERFORM fn_exigir_permiso('gestionar_usuarios');
    UPDATE usuarios SET id_rol = (SELECT id_rol FROM roles WHERE nombre = p_rol)
     WHERE id_usuario = p_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Usuario % o rol "%" inexistente', p_id, p_rol; END IF;
END $$;

-- Datos para usuarios_sneaker.json: NUNCA incluye password_hash
CREATE FUNCTION fn_listar_usuarios()
RETURNS TABLE (id_usuario integer, username text, rol text, activo boolean,
               fecha_creacion timestamptz)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    PERFORM fn_exigir_permiso('exportar_usuarios');
    RETURN QUERY
    SELECT u.id_usuario, u.username, r.nombre, u.activo, u.fecha_creacion
      FROM usuarios u JOIN roles r USING (id_rol) ORDER BY u.id_usuario;
END $$;

CREATE FUNCTION fn_auditoria(p_limite integer DEFAULT 100)
RETURNS TABLE (id_evento bigint, fecha timestamptz, tabla text, operacion text,
               id_registro text, usuario text, resumen text)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    PERFORM fn_exigir_permiso('ver_auditoria');
    RETURN QUERY
    SELECT e.id_evento, e.fecha, e.tabla, e.operacion, e.id_registro, u.username, e.resumen
      FROM log_eventos e JOIN usuarios u USING (id_usuario)
     ORDER BY e.id_evento DESC LIMIT p_limite;
END $$;
