--
-- PostgreSQL database dump
--

\restrict WRTbTxUPirbLz10tWh2fAihJVeWF6fbGfELyf4nZScrDAIyfxOkx1adhxv4L50h

-- Dumped from database version 14.24
-- Dumped by pg_dump version 14.24

-- Started on 2026-11-10 13:32:11

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 2 (class 3079 OID 32769)
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- TOC entry 3588 (class 0 OID 0)
-- Dependencies: 2
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- TOC entry 920 (class 1247 OID 32810)
-- Name: color_t; Type: DOMAIN; Schema: public; Owner: postgres
--

CREATE DOMAIN public.color_t AS text
	CONSTRAINT color_t_check CHECK ((VALUE = ANY (ARRAY['Negro'::text, 'Blanco'::text, 'Azul eléctrico'::text, 'Rojo'::text, 'Verde'::text, 'Amarillo'::text, 'Naranja'::text, 'Gris'::text])));


ALTER DOMAIN public.color_t OWNER TO postgres;

--
-- TOC entry 916 (class 1247 OID 32807)
-- Name: talla_t; Type: DOMAIN; Schema: public; Owner: postgres
--

CREATE DOMAIN public.talla_t AS smallint
	CONSTRAINT talla_t_check CHECK (((VALUE >= 38) AND (VALUE <= 46)));


ALTER DOMAIN public.talla_t OWNER TO postgres;

--
-- TOC entry 307 (class 1255 OID 33051)
-- Name: fn_analisis_modelos(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_analisis_modelos() RETURNS TABLE(modelo text, pedidos bigint, pares bigint, importe numeric)
    LANGUAGE plpgsql STABLE
    AS $$
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


ALTER FUNCTION public.fn_analisis_modelos() OWNER TO postgres;

--
-- TOC entry 308 (class 1255 OID 33052)
-- Name: fn_analisis_tallas(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_analisis_tallas() RETURNS TABLE(talla smallint, pares bigint)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    PERFORM fn_exigir_permiso('consultar_pedidos');
    RETURN QUERY
    SELECT t::smallint, coalesce(sum(l.cantidad) FILTER (WHERE p.id_pedido IS NOT NULL), 0)::bigint
      FROM generate_series(38, 46) t
      LEFT JOIN lineas_pedido l ON l.talla = t
      LEFT JOIN pedidos p ON p.id_pedido = l.id_pedido AND p.estado IN ('confirmado','entregado')
     GROUP BY t ORDER BY t;
END $$;


ALTER FUNCTION public.fn_analisis_tallas() OWNER TO postgres;

--
-- TOC entry 297 (class 1255 OID 32978)
-- Name: fn_auditar(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_auditar() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


ALTER FUNCTION public.fn_auditar() OWNER TO postgres;

--
-- TOC entry 305 (class 1255 OID 33018)
-- Name: fn_auditoria(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_auditoria(p_limite integer DEFAULT 100) RETURNS TABLE(id_evento bigint, fecha timestamp with time zone, tabla text, operacion text, id_registro text, usuario text, resumen text)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    PERFORM fn_exigir_permiso('ver_auditoria');
    RETURN QUERY
    SELECT e.id_evento, e.fecha, e.tabla, e.operacion, e.id_registro, u.username, e.resumen
      FROM log_eventos e JOIN usuarios u USING (id_usuario)
     ORDER BY e.id_evento DESC LIMIT p_limite;
END $$;


ALTER FUNCTION public.fn_auditoria(p_limite integer) OWNER TO postgres;

--
-- TOC entry 300 (class 1255 OID 32986)
-- Name: fn_buscar_pedidos(text, text, text, date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_buscar_pedidos(p_cliente text DEFAULT NULL::text, p_modelo text DEFAULT NULL::text, p_estado text DEFAULT NULL::text, p_desde date DEFAULT NULL::date, p_hasta date DEFAULT NULL::date) RETURNS TABLE(referencia text, fecha date, cliente text, estado text, tipo text, pares integer, total numeric)
    LANGUAGE plpgsql STABLE
    AS $$
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


ALTER FUNCTION public.fn_buscar_pedidos(p_cliente text, p_modelo text, p_estado text, p_desde date, p_hasta date) OWNER TO postgres;

--
-- TOC entry 303 (class 1255 OID 33015)
-- Name: fn_cambiar_activo(integer, boolean); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_cambiar_activo(p_id integer, p_activo boolean) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM fn_exigir_permiso('gestionar_usuarios');
    IF NOT p_activo AND p_id = fn_usuario_actual() THEN
        RAISE EXCEPTION 'No puedes desactivar tu propio usuario';
    END IF;
    UPDATE usuarios SET activo = p_activo WHERE id_usuario = p_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Usuario % inexistente', p_id; END IF;
END $$;


ALTER FUNCTION public.fn_cambiar_activo(p_id integer, p_activo boolean) OWNER TO postgres;

--
-- TOC entry 304 (class 1255 OID 33016)
-- Name: fn_cambiar_rol(integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_cambiar_rol(p_id integer, p_rol text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM fn_exigir_permiso('gestionar_usuarios');
    UPDATE usuarios SET id_rol = (SELECT id_rol FROM roles WHERE nombre = p_rol)
     WHERE id_usuario = p_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Usuario % o rol "%" inexistente', p_id, p_rol; END IF;
END $$;


ALTER FUNCTION public.fn_cambiar_rol(p_id integer, p_rol text) OWNER TO postgres;

--
-- TOC entry 306 (class 1255 OID 33049)
-- Name: fn_cliente_web(text, text, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_cliente_web(p_nombre text, p_email text, p_telefono text, p_tipo text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
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


ALTER FUNCTION public.fn_cliente_web(p_nombre text, p_email text, p_telefono text, p_tipo text) OWNER TO postgres;

--
-- TOC entry 302 (class 1255 OID 33014)
-- Name: fn_crear_usuario(text, text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_crear_usuario(p_username text, p_password text, p_rol text) RETURNS integer
    LANGUAGE plpgsql
    AS $$
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


ALTER FUNCTION public.fn_crear_usuario(p_username text, p_password text, p_rol text) OWNER TO postgres;

--
-- TOC entry 313 (class 1255 OID 33050)
-- Name: fn_detalle_pedido(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_detalle_pedido(p_referencia text) RETURNS TABLE(referencia text, fecha date, cliente text, estado text, tipo text, total numeric, id_linea integer, modelo text, talla smallint, cantidad integer, precio_unitario numeric, personalizacion text, texto_suela text)
    LANGUAGE plpgsql STABLE
    AS $$
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


ALTER FUNCTION public.fn_detalle_pedido(p_referencia text) OWNER TO postgres;

--
-- TOC entry 282 (class 1255 OID 32971)
-- Name: fn_exigir_permiso(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_exigir_permiso(p_operacion text) RETURNS void
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    IF NOT fn_tiene_permiso(p_operacion) THEN
        RAISE EXCEPTION 'Permiso denegado: su rol no puede ejecutar "%"', p_operacion
              USING ERRCODE = '42501';
    END IF;
END $$;


ALTER FUNCTION public.fn_exigir_permiso(p_operacion text) OWNER TO postgres;

--
-- TOC entry 310 (class 1255 OID 32988)
-- Name: fn_indicadores(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_indicadores() RETURNS TABLE(indicador text, valor numeric)
    LANGUAGE plpgsql STABLE
    AS $$
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


ALTER FUNCTION public.fn_indicadores() OWNER TO postgres;

--
-- TOC entry 298 (class 1255 OID 32981)
-- Name: fn_lineas_antes(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_lineas_antes() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


ALTER FUNCTION public.fn_lineas_antes() OWNER TO postgres;

--
-- TOC entry 312 (class 1255 OID 41006)
-- Name: fn_lineas_color_catalogo(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_lineas_color_catalogo() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.id_color IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM colores_catalogo c
         WHERE c.id_color = NEW.id_color AND c.id_modelo = NEW.id_modelo) THEN
        RAISE EXCEPTION 'Ese color de catálogo no corresponde al modelo de la línea';
    END IF;
    RETURN NEW;
END $$;


ALTER FUNCTION public.fn_lineas_color_catalogo() OWNER TO postgres;

--
-- TOC entry 299 (class 1255 OID 32983)
-- Name: fn_lineas_total(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_lineas_total() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


ALTER FUNCTION public.fn_lineas_total() OWNER TO postgres;

--
-- TOC entry 283 (class 1255 OID 33017)
-- Name: fn_listar_usuarios(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_listar_usuarios() RETURNS TABLE(id_usuario integer, username text, rol text, activo boolean, fecha_creacion timestamp with time zone)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    PERFORM fn_exigir_permiso('exportar_usuarios');
    RETURN QUERY
    SELECT u.id_usuario, u.username, r.nombre, u.activo, u.fecha_creacion
      FROM usuarios u JOIN roles r USING (id_rol) ORDER BY u.id_usuario;
END $$;


ALTER FUNCTION public.fn_listar_usuarios() OWNER TO postgres;

--
-- TOC entry 279 (class 1255 OID 32968)
-- Name: fn_login(text, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_login(p_username text, p_password text) RETURNS integer
    LANGUAGE sql STABLE
    AS $$
    SELECT id_usuario FROM usuarios
     WHERE username = p_username AND activo
       AND password_hash = crypt(p_password, password_hash);
$$;


ALTER FUNCTION public.fn_login(p_username text, p_password text) OWNER TO postgres;

--
-- TOC entry 314 (class 1255 OID 41020)
-- Name: fn_pedido_para_odoo(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_pedido_para_odoo(p_referencia text) RETURNS TABLE(referencia text, estado text, tipo text, cliente text, email text, telefono text, tipo_cliente text, modelo text, talla smallint, cantidad integer, precio_unitario numeric, personalizacion text, texto_suela text, color_catalogo text)
    LANGUAGE plpgsql STABLE
    AS $$
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


ALTER FUNCTION public.fn_pedido_para_odoo(p_referencia text) OWNER TO postgres;

--
-- TOC entry 309 (class 1255 OID 32972)
-- Name: fn_pedidos_permisos(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_pedidos_permisos() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


ALTER FUNCTION public.fn_pedidos_permisos() OWNER TO postgres;

--
-- TOC entry 296 (class 1255 OID 32976)
-- Name: fn_pedidos_stock(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_pedidos_stock() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


ALTER FUNCTION public.fn_pedidos_stock() OWNER TO postgres;

--
-- TOC entry 295 (class 1255 OID 32974)
-- Name: fn_pedidos_validar(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_pedidos_validar() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


ALTER FUNCTION public.fn_pedidos_validar() OWNER TO postgres;

--
-- TOC entry 311 (class 1255 OID 40975)
-- Name: fn_registrar_envio_odoo(text, text, text, integer, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_registrar_envio_odoo(p_referencia text, p_estado text, p_pedido_odoo text, p_id_odoo integer, p_mensaje text) RETURNS void
    LANGUAGE plpgsql
    AS $$
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


ALTER FUNCTION public.fn_registrar_envio_odoo(p_referencia text, p_estado text, p_pedido_odoo text, p_id_odoo integer, p_mensaje text) OWNER TO postgres;

--
-- TOC entry 301 (class 1255 OID 32987)
-- Name: fn_stock_bajo(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_stock_bajo(p_umbral integer DEFAULT 5) RETURNS TABLE(modelo text, talla smallint, stock_disponible integer)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
    PERFORM fn_exigir_permiso('consultar_stock');
    RETURN QUERY
    SELECT m.nombre, s.talla::smallint, s.stock_disponible
      FROM stock s JOIN modelos m USING (id_modelo)
     WHERE s.stock_disponible <= p_umbral
     ORDER BY s.stock_disponible, m.nombre, s.talla;
END $$;


ALTER FUNCTION public.fn_stock_bajo(p_umbral integer) OWNER TO postgres;

--
-- TOC entry 281 (class 1255 OID 32970)
-- Name: fn_tiene_permiso(text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_tiene_permiso(p_operacion text) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
    SELECT coalesce((SELECT p.permitido
                       FROM usuarios u JOIN permisos p ON p.id_rol = u.id_rol
                      WHERE u.id_usuario = fn_usuario_actual()
                        AND p.operacion = p_operacion), false);
$$;


ALTER FUNCTION public.fn_tiene_permiso(p_operacion text) OWNER TO postgres;

--
-- TOC entry 280 (class 1255 OID 32969)
-- Name: fn_usuario_actual(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_usuario_actual() RETURNS integer
    LANGUAGE plpgsql STABLE
    AS $$
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


ALTER FUNCTION public.fn_usuario_actual() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 222 (class 1259 OID 32856)
-- Name: clientes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.clientes (
    id_cliente integer NOT NULL,
    nombre text NOT NULL,
    email text NOT NULL,
    telefono text,
    tipo text DEFAULT 'particular'::text NOT NULL,
    fecha_alta date DEFAULT CURRENT_DATE NOT NULL,
    CONSTRAINT clientes_email_check CHECK ((email ~~ '%_@_%'::text)),
    CONSTRAINT clientes_tipo_check CHECK ((tipo = ANY (ARRAY['particular'::text, 'club'::text, 'equipo'::text])))
);


ALTER TABLE public.clientes OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 32855)
-- Name: clientes_id_cliente_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.clientes_id_cliente_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.clientes_id_cliente_seq OWNER TO postgres;

--
-- TOC entry 3589 (class 0 OID 0)
-- Dependencies: 221
-- Name: clientes_id_cliente_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.clientes_id_cliente_seq OWNED BY public.clientes.id_cliente;


--
-- TOC entry 242 (class 1259 OID 40982)
-- Name: colores_catalogo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.colores_catalogo (
    id_color smallint NOT NULL,
    id_modelo smallint NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    orden smallint DEFAULT 1 NOT NULL,
    color_cuerpo public.color_t NOT NULL,
    color_franja public.color_t NOT NULL,
    color_puntera public.color_t NOT NULL,
    color_talon public.color_t NOT NULL,
    color_suela public.color_t NOT NULL,
    color_cordones public.color_t NOT NULL,
    color_detalle public.color_t NOT NULL,
    activo boolean DEFAULT true NOT NULL
);


ALTER TABLE public.colores_catalogo OWNER TO postgres;

--
-- TOC entry 241 (class 1259 OID 40981)
-- Name: colores_catalogo_id_color_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.colores_catalogo_id_color_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.colores_catalogo_id_color_seq OWNER TO postgres;

--
-- TOC entry 3590 (class 0 OID 0)
-- Dependencies: 241
-- Name: colores_catalogo_id_color_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.colores_catalogo_id_color_seq OWNED BY public.colores_catalogo.id_color;


--
-- TOC entry 228 (class 1259 OID 32912)
-- Name: lineas_pedido; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.lineas_pedido (
    id_linea integer NOT NULL,
    id_pedido integer NOT NULL,
    id_modelo smallint NOT NULL,
    talla public.talla_t NOT NULL,
    cantidad integer NOT NULL,
    precio_unitario numeric(8,2) NOT NULL,
    color_cuerpo public.color_t,
    color_franja public.color_t,
    color_puntera public.color_t,
    color_talon public.color_t,
    color_suela public.color_t,
    color_cordones public.color_t,
    texto_suela character varying(12),
    id_color smallint,
    CONSTRAINT ck_color_catalogo_estandar CHECK (((id_color IS NULL) OR (color_cuerpo IS NULL))),
    CONSTRAINT ck_personalizacion_completa CHECK ((num_nonnulls(color_cuerpo, color_franja, color_puntera, color_talon, color_suela, color_cordones) = ANY (ARRAY[0, 6]))),
    CONSTRAINT ck_texto_solo_custom CHECK (((texto_suela IS NULL) OR (color_cuerpo IS NOT NULL))),
    CONSTRAINT lineas_pedido_cantidad_check CHECK ((cantidad > 0)),
    CONSTRAINT lineas_pedido_precio_unitario_check CHECK ((precio_unitario >= (0)::numeric))
);


ALTER TABLE public.lineas_pedido OWNER TO postgres;

--
-- TOC entry 227 (class 1259 OID 32911)
-- Name: lineas_pedido_id_linea_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.lineas_pedido_id_linea_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.lineas_pedido_id_linea_seq OWNER TO postgres;

--
-- TOC entry 3591 (class 0 OID 0)
-- Dependencies: 227
-- Name: lineas_pedido_id_linea_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.lineas_pedido_id_linea_seq OWNED BY public.lineas_pedido.id_linea;


--
-- TOC entry 231 (class 1259 OID 32952)
-- Name: log_eventos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.log_eventos (
    id_evento bigint NOT NULL,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    tabla text NOT NULL,
    operacion text NOT NULL,
    id_registro text NOT NULL,
    id_usuario integer NOT NULL,
    resumen text NOT NULL,
    CONSTRAINT log_eventos_operacion_check CHECK ((operacion = ANY (ARRAY['INSERT'::text, 'UPDATE'::text, 'DELETE'::text])))
);


ALTER TABLE public.log_eventos OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 32951)
-- Name: log_eventos_id_evento_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.log_eventos_id_evento_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.log_eventos_id_evento_seq OWNER TO postgres;

--
-- TOC entry 3592 (class 0 OID 0)
-- Dependencies: 230
-- Name: log_eventos_id_evento_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.log_eventos_id_evento_seq OWNED BY public.log_eventos.id_evento;


--
-- TOC entry 224 (class 1259 OID 32871)
-- Name: modelos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.modelos (
    id_modelo smallint NOT NULL,
    codigo text NOT NULL,
    nombre text NOT NULL,
    categoria text NOT NULL,
    precio_base numeric(8,2) NOT NULL,
    CONSTRAINT modelos_precio_base_check CHECK ((precio_base > (0)::numeric))
);


ALTER TABLE public.modelos OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 32870)
-- Name: modelos_id_modelo_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.modelos_id_modelo_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.modelos_id_modelo_seq OWNER TO postgres;

--
-- TOC entry 3593 (class 0 OID 0)
-- Dependencies: 223
-- Name: modelos_id_modelo_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.modelos_id_modelo_seq OWNED BY public.modelos.id_modelo;


--
-- TOC entry 226 (class 1259 OID 32883)
-- Name: pedidos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pedidos (
    id_pedido integer NOT NULL,
    referencia text GENERATED ALWAYS AS (('SO'::text || lpad((id_pedido)::text, 3, '0'::text))) STORED,
    id_cliente integer NOT NULL,
    fecha date DEFAULT CURRENT_DATE NOT NULL,
    estado text DEFAULT 'pendiente'::text NOT NULL,
    tipo text DEFAULT 'estandar'::text NOT NULL,
    total numeric(10,2) DEFAULT 0 NOT NULL,
    creado_por integer,
    CONSTRAINT pedidos_estado_check CHECK ((estado = ANY (ARRAY['pendiente'::text, 'confirmado'::text, 'entregado'::text, 'cancelado'::text]))),
    CONSTRAINT pedidos_tipo_check CHECK ((tipo = ANY (ARRAY['estandar'::text, 'custom'::text]))),
    CONSTRAINT pedidos_total_check CHECK ((total >= (0)::numeric))
);


ALTER TABLE public.pedidos OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 32882)
-- Name: pedidos_id_pedido_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.pedidos_id_pedido_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.pedidos_id_pedido_seq OWNER TO postgres;

--
-- TOC entry 3594 (class 0 OID 0)
-- Dependencies: 225
-- Name: pedidos_id_pedido_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.pedidos_id_pedido_seq OWNED BY public.pedidos.id_pedido;


--
-- TOC entry 239 (class 1259 OID 40960)
-- Name: pedidos_odoo; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.pedidos_odoo (
    id_pedido integer NOT NULL,
    pedido_odoo text,
    id_odoo integer,
    estado text NOT NULL,
    mensaje text,
    actualizado timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pedidos_odoo_estado_check CHECK ((estado = ANY (ARRAY['enviado'::text, 'error'::text])))
);


ALTER TABLE public.pedidos_odoo OWNER TO postgres;

--
-- TOC entry 218 (class 1259 OID 32823)
-- Name: permisos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.permisos (
    id_rol smallint NOT NULL,
    operacion text NOT NULL,
    permitido boolean NOT NULL,
    CONSTRAINT permisos_operacion_check CHECK ((operacion = ANY (ARRAY['consultar_pedidos'::text, 'crear_pedido'::text, 'editar_pedido'::text, 'confirmar_pedido'::text, 'cancelar_pedido'::text, 'entregar_pedido'::text, 'eliminar_pedido'::text, 'consultar_stock'::text, 'ver_auditoria'::text, 'gestionar_usuarios'::text, 'exportar_usuarios'::text])))
);


ALTER TABLE public.permisos OWNER TO postgres;

--
-- TOC entry 217 (class 1259 OID 32813)
-- Name: roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.roles (
    id_rol smallint NOT NULL,
    nombre text NOT NULL
);


ALTER TABLE public.roles OWNER TO postgres;

--
-- TOC entry 216 (class 1259 OID 32812)
-- Name: roles_id_rol_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.roles_id_rol_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.roles_id_rol_seq OWNER TO postgres;

--
-- TOC entry 3595 (class 0 OID 0)
-- Dependencies: 216
-- Name: roles_id_rol_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.roles_id_rol_seq OWNED BY public.roles.id_rol;


--
-- TOC entry 229 (class 1259 OID 32938)
-- Name: stock; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stock (
    id_modelo smallint NOT NULL,
    talla public.talla_t NOT NULL,
    stock_disponible integer DEFAULT 0 NOT NULL,
    fecha_corte timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT stock_stock_disponible_check CHECK ((stock_disponible >= 0))
);


ALTER TABLE public.stock OWNER TO postgres;

--
-- TOC entry 220 (class 1259 OID 32837)
-- Name: usuarios; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.usuarios (
    id_usuario integer NOT NULL,
    username text NOT NULL,
    password_hash text NOT NULL,
    id_rol smallint NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    fecha_creacion timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT usuarios_username_check CHECK ((length(username) >= 3))
);


ALTER TABLE public.usuarios OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 32836)
-- Name: usuarios_id_usuario_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.usuarios_id_usuario_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.usuarios_id_usuario_seq OWNER TO postgres;

--
-- TOC entry 3596 (class 0 OID 0)
-- Dependencies: 219
-- Name: usuarios_id_usuario_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.usuarios_id_usuario_seq OWNED BY public.usuarios.id_usuario;


--
-- TOC entry 232 (class 1259 OID 32989)
-- Name: v_export_clientes; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_export_clientes AS
 SELECT clientes.id_cliente,
    clientes.nombre,
    clientes.tipo
   FROM public.clientes;


ALTER TABLE public.v_export_clientes OWNER TO postgres;

--
-- TOC entry 235 (class 1259 OID 33001)
-- Name: v_export_lineas_pedido; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_export_lineas_pedido AS
 SELECT lineas_pedido.id_linea,
    lineas_pedido.id_pedido,
    lineas_pedido.id_modelo,
    lineas_pedido.talla,
    lineas_pedido.cantidad,
    lineas_pedido.precio_unitario
   FROM public.lineas_pedido;


ALTER TABLE public.v_export_lineas_pedido OWNER TO postgres;

--
-- TOC entry 233 (class 1259 OID 32993)
-- Name: v_export_modelos; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_export_modelos AS
 SELECT modelos.id_modelo,
    modelos.nombre AS modelo,
    modelos.categoria
   FROM public.modelos;


ALTER TABLE public.v_export_modelos OWNER TO postgres;

--
-- TOC entry 234 (class 1259 OID 32997)
-- Name: v_export_pedidos; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_export_pedidos AS
 SELECT pedidos.id_pedido,
    pedidos.fecha,
    pedidos.id_cliente,
    pedidos.estado,
    pedidos.tipo
   FROM public.pedidos;


ALTER TABLE public.v_export_pedidos OWNER TO postgres;

--
-- TOC entry 236 (class 1259 OID 33005)
-- Name: v_export_stock; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_export_stock AS
 SELECT stock.id_modelo,
    stock.talla,
    stock.stock_disponible,
    (stock.fecha_corte)::date AS fecha_corte
   FROM public.stock;


ALTER TABLE public.v_export_stock OWNER TO postgres;

--
-- TOC entry 237 (class 1259 OID 33009)
-- Name: v_ficha_fabricacion; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_ficha_fabricacion AS
 SELECT p.referencia,
    c.nombre AS cliente,
    m.nombre AS modelo,
    l.color_cuerpo,
    l.color_franja,
    l.color_puntera,
    l.color_talon,
    l.color_suela,
    l.color_cordones,
    l.texto_suela,
    l.talla,
    l.cantidad
   FROM (((public.lineas_pedido l
     JOIN public.pedidos p USING (id_pedido))
     JOIN public.clientes c USING (id_cliente))
     JOIN public.modelos m USING (id_modelo))
  WHERE ((p.estado = 'confirmado'::text) AND (l.color_cuerpo IS NOT NULL))
  ORDER BY p.referencia, l.talla;


ALTER TABLE public.v_ficha_fabricacion OWNER TO postgres;

--
-- TOC entry 240 (class 1259 OID 40976)
-- Name: v_pedidos_odoo; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_pedidos_odoo AS
 SELECT p.referencia,
    o.pedido_odoo,
    o.estado,
    o.mensaje,
    o.actualizado
   FROM (public.pedidos_odoo o
     JOIN public.pedidos p USING (id_pedido));


ALTER TABLE public.v_pedidos_odoo OWNER TO postgres;

--
-- TOC entry 238 (class 1259 OID 33053)
-- Name: v_reconciliacion; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_reconciliacion AS
 SELECT 'pedidos_totales'::text AS indicador,
    (count(*))::numeric AS valor
   FROM public.pedidos
UNION ALL
 SELECT 'lineas_totales'::text AS indicador,
    (count(*))::numeric AS valor
   FROM public.lineas_pedido
UNION ALL
 SELECT 'pedidos_venta'::text AS indicador,
    (count(*))::numeric AS valor
   FROM public.pedidos
  WHERE (pedidos.estado = ANY (ARRAY['confirmado'::text, 'entregado'::text]))
UNION ALL
 SELECT 'pares_vendidos'::text AS indicador,
    (COALESCE(sum(l.cantidad), (0)::bigint))::numeric AS valor
   FROM (public.lineas_pedido l
     JOIN public.pedidos p USING (id_pedido))
  WHERE (p.estado = ANY (ARRAY['confirmado'::text, 'entregado'::text]))
UNION ALL
 SELECT 'importe_ventas'::text AS indicador,
    COALESCE(sum(pedidos.total), (0)::numeric) AS valor
   FROM public.pedidos
  WHERE (pedidos.estado = ANY (ARRAY['confirmado'::text, 'entregado'::text]))
UNION ALL
 SELECT 'clientes_con_venta'::text AS indicador,
    (count(DISTINCT pedidos.id_cliente))::numeric AS valor
   FROM public.pedidos
  WHERE (pedidos.estado = ANY (ARRAY['confirmado'::text, 'entregado'::text]));


ALTER TABLE public.v_reconciliacion OWNER TO postgres;

--
-- TOC entry 3325 (class 2604 OID 32859)
-- Name: clientes id_cliente; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clientes ALTER COLUMN id_cliente SET DEFAULT nextval('public.clientes_id_cliente_seq'::regclass);


--
-- TOC entry 3355 (class 2604 OID 40985)
-- Name: colores_catalogo id_color; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.colores_catalogo ALTER COLUMN id_color SET DEFAULT nextval('public.colores_catalogo_id_color_seq'::regclass);


--
-- TOC entry 3341 (class 2604 OID 32915)
-- Name: lineas_pedido id_linea; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lineas_pedido ALTER COLUMN id_linea SET DEFAULT nextval('public.lineas_pedido_id_linea_seq'::regclass);


--
-- TOC entry 3350 (class 2604 OID 32955)
-- Name: log_eventos id_evento; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.log_eventos ALTER COLUMN id_evento SET DEFAULT nextval('public.log_eventos_id_evento_seq'::regclass);


--
-- TOC entry 3330 (class 2604 OID 32874)
-- Name: modelos id_modelo; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.modelos ALTER COLUMN id_modelo SET DEFAULT nextval('public.modelos_id_modelo_seq'::regclass);


--
-- TOC entry 3332 (class 2604 OID 32886)
-- Name: pedidos id_pedido; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pedidos ALTER COLUMN id_pedido SET DEFAULT nextval('public.pedidos_id_pedido_seq'::regclass);


--
-- TOC entry 3319 (class 2604 OID 32816)
-- Name: roles id_rol; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles ALTER COLUMN id_rol SET DEFAULT nextval('public.roles_id_rol_seq'::regclass);


--
-- TOC entry 3321 (class 2604 OID 32840)
-- Name: usuarios id_usuario; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuarios ALTER COLUMN id_usuario SET DEFAULT nextval('public.usuarios_id_usuario_seq'::regclass);


--
-- TOC entry 3570 (class 0 OID 32856)
-- Dependencies: 222
-- Data for Name: clientes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.clientes (id_cliente, nombre, email, telefono, tipo, fecha_alta) FROM stdin;
1	Ana García	ana.garcia@example.com	600000001	particular	2026-07-20
2	Club Halcones	info@halcones.example.com	600000002	club	2026-07-25
3	Pedro Ruiz	pedro.ruiz@example.com	600000003	particular	2026-08-01
4	Peña Los Linces	linces@example.com	600000004	equipo	2026-08-15
5	Marta Sánchez	marta.s@example.com	600000005	particular	2026-08-28
6	Escuela Deportiva Norte	escuela@norte.example.com	600000006	club	2026-09-10
28	PRUEBA1	pruea@gamil.com	666666666	particular	2026-11-09
32	SERGIO	serio@gmai.com	\N	particular	2026-11-10
30	sss	prueba@odoo.com	\N	particular	2026-11-09
\.


--
-- TOC entry 3582 (class 0 OID 40982)
-- Dependencies: 242
-- Data for Name: colores_catalogo; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.colores_catalogo (id_color, id_modelo, codigo, nombre, orden, color_cuerpo, color_franja, color_puntera, color_talon, color_suela, color_cordones, color_detalle, activo) FROM stdin;
3	1	court-blanco-azul	Blanco / Azul	1	Blanco	Blanco	Blanco	Blanco	Blanco	Blanco	Azul eléctrico	t
1	1	court-blanco-rojo	Blanco / Rojo	2	Blanco	Blanco	Blanco	Blanco	Blanco	Blanco	Rojo	t
21	1	court-blanco-verde	Blanco / Verde	3	Blanco	Blanco	Blanco	Blanco	Blanco	Blanco	Verde	t
6	2	pulse-negro-azul	Negro / Azul	1	Negro	Azul eléctrico	Negro	Negro	Negro	Negro	Azul eléctrico	t
5	2	pulse-negro-naranja	Negro / Naranja	2	Negro	Naranja	Negro	Negro	Negro	Negro	Naranja	t
24	2	pulse-negro-verde	Negro / Verde	3	Negro	Verde	Negro	Negro	Negro	Negro	Verde	t
25	3	high-blanco-azul	Blanco / Azul	1	Blanco	Negro	Negro	Negro	Blanco	Negro	Azul eléctrico	t
8	3	high-blanco-rojo	Blanco / Rojo	2	Blanco	Negro	Negro	Negro	Blanco	Negro	Rojo	t
27	3	high-blanco-amarillo	Blanco / Amarillo	3	Blanco	Negro	Negro	Negro	Blanco	Negro	Amarillo	t
28	4	retro-gris-azul	Gris / Azul	1	Gris	Negro	Gris	Gris	Blanco	Blanco	Azul eléctrico	t
10	4	retro-gris-naranja	Gris / Naranja	2	Gris	Negro	Gris	Gris	Blanco	Blanco	Naranja	t
30	4	retro-gris-verde	Gris / Verde	3	Gris	Negro	Gris	Gris	Blanco	Blanco	Verde	t
31	5	street-negro-azul	Negro / Azul	1	Negro	Negro	Negro	Negro	Blanco	Negro	Azul eléctrico	t
13	5	street-negro-rojo	Negro / Rojo	2	Negro	Negro	Negro	Negro	Blanco	Negro	Rojo	t
33	5	street-negro-verde	Negro / Verde	3	Negro	Negro	Negro	Negro	Blanco	Negro	Verde	t
18	6	aero-negro-azul	Negro / Azul	1	Negro	Azul eléctrico	Negro	Negro	Blanco	Negro	Azul eléctrico	t
16	6	aero-negro-amarillo	Negro / Amarillo	2	Negro	Amarillo	Negro	Negro	Blanco	Negro	Amarillo	t
36	6	aero-negro-rojo	Negro / Rojo	3	Negro	Rojo	Negro	Negro	Blanco	Negro	Rojo	t
\.


--
-- TOC entry 3576 (class 0 OID 32912)
-- Dependencies: 228
-- Data for Name: lineas_pedido; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.lineas_pedido (id_linea, id_pedido, id_modelo, talla, cantidad, precio_unitario, color_cuerpo, color_franja, color_puntera, color_talon, color_suela, color_cordones, texto_suela, id_color) FROM stdin;
1	1	1	42	1	89.00	\N	\N	\N	\N	\N	\N	\N	\N
2	2	5	43	1	92.00	\N	\N	\N	\N	\N	\N	\N	\N
3	2	6	43	1	105.00	\N	\N	\N	\N	\N	\N	\N	\N
4	4	3	41	1	99.00	\N	\N	\N	\N	\N	\N	\N	\N
5	7	4	43	2	95.00	\N	\N	\N	\N	\N	\N	\N	\N
6	8	1	39	5	89.00	\N	\N	\N	\N	\N	\N	\N	\N
7	8	1	40	5	89.00	\N	\N	\N	\N	\N	\N	\N	\N
8	8	1	41	5	89.00	\N	\N	\N	\N	\N	\N	\N	\N
9	9	5	40	1	92.00	\N	\N	\N	\N	\N	\N	\N	\N
10	11	2	42	2	109.00	\N	\N	\N	\N	\N	\N	\N	\N
11	12	6	44	3	105.00	\N	\N	\N	\N	\N	\N	\N	\N
12	3	2	38	2	129.00	Negro	Azul eléctrico	Negro	Gris	Blanco	Azul eléctrico	HALCONES	\N
13	3	2	39	3	129.00	Negro	Azul eléctrico	Negro	Gris	Blanco	Azul eléctrico	HALCONES	\N
14	3	2	40	4	129.00	Negro	Azul eléctrico	Negro	Gris	Blanco	Azul eléctrico	HALCONES	\N
15	3	2	41	6	129.00	Negro	Azul eléctrico	Negro	Gris	Blanco	Azul eléctrico	HALCONES	\N
16	3	2	42	8	129.00	Negro	Azul eléctrico	Negro	Gris	Blanco	Azul eléctrico	HALCONES	\N
17	3	2	43	7	129.00	Negro	Azul eléctrico	Negro	Gris	Blanco	Azul eléctrico	HALCONES	\N
18	3	2	44	5	129.00	Negro	Azul eléctrico	Negro	Gris	Blanco	Azul eléctrico	HALCONES	\N
19	3	2	45	3	129.00	Negro	Azul eléctrico	Negro	Gris	Blanco	Azul eléctrico	HALCONES	\N
20	3	2	46	2	129.00	Negro	Azul eléctrico	Negro	Gris	Blanco	Azul eléctrico	HALCONES	\N
21	5	1	40	3	109.00	Blanco	Rojo	Blanco	Rojo	Blanco	Negro	LINCES	\N
22	5	1	42	5	109.00	Blanco	Rojo	Blanco	Rojo	Blanco	Negro	LINCES	\N
23	5	1	44	4	109.00	Blanco	Rojo	Blanco	Rojo	Blanco	Negro	LINCES	\N
24	6	6	41	1	120.00	Gris	Verde	Gris	Verde	Blanco	Amarillo	\N	\N
25	10	3	42	10	119.00	Negro	Rojo	Rojo	Negro	Blanco	Rojo	HALCONES	\N
26	10	3	43	10	119.00	Negro	Rojo	Rojo	Negro	Blanco	Rojo	HALCONES	\N
117	58	1	41	1	104.00	Blanco	Blanco	Blanco	Blanco	Blanco	Blanco	\N	\N
118	59	2	42	1	109.00	\N	\N	\N	\N	\N	\N	\N	24
124	61	2	40	1	109.00	\N	\N	\N	\N	\N	\N	\N	6
125	62	3	41	1	99.00	\N	\N	\N	\N	\N	\N	\N	25
126	63	2	43	1	109.00	\N	\N	\N	\N	\N	\N	\N	6
127	64	1	39	1	104.00	Blanco	Blanco	Blanco	Blanco	Blanco	Blanco	\N	\N
128	64	1	40	1	104.00	Blanco	Blanco	Blanco	Blanco	Blanco	Blanco	\N	\N
129	65	2	40	1	124.00	Blanco	Blanco	Blanco	Blanco	Blanco	Blanco	\N	\N
130	66	2	40	1	124.00	Blanco	Blanco	Blanco	Blanco	Blanco	Blanco	\N	\N
\.


--
-- TOC entry 3579 (class 0 OID 32952)
-- Dependencies: 231
-- Data for Name: log_eventos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.log_eventos (id_evento, fecha, tabla, operacion, id_registro, id_usuario, resumen) FROM stdin;
1	2026-11-05 10:24:50.408017+01	pedidos	INSERT	1	2	alta {"tipo": "estandar", "fecha": "2026-08-05", "total": 0.00, "estado": "pendiente", "id_pedido": 1, "creado_por": 2, "id_cliente": 1, "referencia": "SO001"}
2	2026-11-05 10:24:50.408017+01	pedidos	INSERT	2	2	alta {"tipo": "estandar", "fecha": "2026-08-12", "total": 0.00, "estado": "pendiente", "id_pedido": 2, "creado_por": 2, "id_cliente": 3, "referencia": "SO002"}
3	2026-11-05 10:24:50.408017+01	pedidos	INSERT	3	2	alta {"tipo": "estandar", "fecha": "2026-08-20", "total": 0.00, "estado": "pendiente", "id_pedido": 3, "creado_por": 2, "id_cliente": 2, "referencia": "SO003"}
4	2026-11-05 10:24:50.408017+01	pedidos	INSERT	4	2	alta {"tipo": "estandar", "fecha": "2026-09-02", "total": 0.00, "estado": "pendiente", "id_pedido": 4, "creado_por": 2, "id_cliente": 5, "referencia": "SO004"}
5	2026-11-05 10:24:50.408017+01	pedidos	INSERT	5	2	alta {"tipo": "estandar", "fecha": "2026-09-08", "total": 0.00, "estado": "pendiente", "id_pedido": 5, "creado_por": 2, "id_cliente": 4, "referencia": "SO005"}
6	2026-11-05 10:24:50.408017+01	pedidos	INSERT	6	2	alta {"tipo": "estandar", "fecha": "2026-09-15", "total": 0.00, "estado": "pendiente", "id_pedido": 6, "creado_por": 2, "id_cliente": 1, "referencia": "SO006"}
7	2026-11-05 10:24:50.408017+01	pedidos	INSERT	7	2	alta {"tipo": "estandar", "fecha": "2026-09-21", "total": 0.00, "estado": "pendiente", "id_pedido": 7, "creado_por": 2, "id_cliente": 3, "referencia": "SO007"}
8	2026-11-05 10:24:50.408017+01	pedidos	INSERT	8	2	alta {"tipo": "estandar", "fecha": "2026-09-28", "total": 0.00, "estado": "pendiente", "id_pedido": 8, "creado_por": 2, "id_cliente": 6, "referencia": "SO008"}
9	2026-11-05 10:24:50.408017+01	pedidos	INSERT	9	2	alta {"tipo": "estandar", "fecha": "2026-10-03", "total": 0.00, "estado": "pendiente", "id_pedido": 9, "creado_por": 2, "id_cliente": 5, "referencia": "SO009"}
10	2026-11-05 10:24:50.408017+01	pedidos	INSERT	10	2	alta {"tipo": "estandar", "fecha": "2026-10-10", "total": 0.00, "estado": "pendiente", "id_pedido": 10, "creado_por": 2, "id_cliente": 2, "referencia": "SO010"}
11	2026-11-05 10:24:50.408017+01	pedidos	INSERT	11	2	alta {"tipo": "estandar", "fecha": "2026-10-18", "total": 0.00, "estado": "pendiente", "id_pedido": 11, "creado_por": 2, "id_cliente": 1, "referencia": "SO011"}
12	2026-11-05 10:24:50.408017+01	pedidos	INSERT	12	2	alta {"tipo": "estandar", "fecha": "2026-10-25", "total": 0.00, "estado": "pendiente", "id_pedido": 12, "creado_por": 2, "id_cliente": 4, "referencia": "SO012"}
13	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	1	2	alta {"talla": 42, "cantidad": 1, "id_linea": 1, "id_modelo": 1, "id_pedido": 1, "color_suela": null, "color_talon": null, "texto_suela": null, "color_cuerpo": null, "color_franja": null, "color_puntera": null, "color_cordones": null, "precio_unitario": 89.00}
14	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	2	2	alta {"talla": 43, "cantidad": 1, "id_linea": 2, "id_modelo": 5, "id_pedido": 2, "color_suela": null, "color_talon": null, "texto_suela": null, "color_cuerpo": null, "color_franja": null, "color_puntera": null, "color_cordones": null, "precio_unitario": 92.00}
15	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	3	2	alta {"talla": 43, "cantidad": 1, "id_linea": 3, "id_modelo": 6, "id_pedido": 2, "color_suela": null, "color_talon": null, "texto_suela": null, "color_cuerpo": null, "color_franja": null, "color_puntera": null, "color_cordones": null, "precio_unitario": 105.00}
16	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	4	2	alta {"talla": 41, "cantidad": 1, "id_linea": 4, "id_modelo": 3, "id_pedido": 4, "color_suela": null, "color_talon": null, "texto_suela": null, "color_cuerpo": null, "color_franja": null, "color_puntera": null, "color_cordones": null, "precio_unitario": 99.00}
17	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	5	2	alta {"talla": 43, "cantidad": 2, "id_linea": 5, "id_modelo": 4, "id_pedido": 7, "color_suela": null, "color_talon": null, "texto_suela": null, "color_cuerpo": null, "color_franja": null, "color_puntera": null, "color_cordones": null, "precio_unitario": 95.00}
18	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	6	2	alta {"talla": 39, "cantidad": 5, "id_linea": 6, "id_modelo": 1, "id_pedido": 8, "color_suela": null, "color_talon": null, "texto_suela": null, "color_cuerpo": null, "color_franja": null, "color_puntera": null, "color_cordones": null, "precio_unitario": 89.00}
19	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	7	2	alta {"talla": 40, "cantidad": 5, "id_linea": 7, "id_modelo": 1, "id_pedido": 8, "color_suela": null, "color_talon": null, "texto_suela": null, "color_cuerpo": null, "color_franja": null, "color_puntera": null, "color_cordones": null, "precio_unitario": 89.00}
20	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	8	2	alta {"talla": 41, "cantidad": 5, "id_linea": 8, "id_modelo": 1, "id_pedido": 8, "color_suela": null, "color_talon": null, "texto_suela": null, "color_cuerpo": null, "color_franja": null, "color_puntera": null, "color_cordones": null, "precio_unitario": 89.00}
21	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	9	2	alta {"talla": 40, "cantidad": 1, "id_linea": 9, "id_modelo": 5, "id_pedido": 9, "color_suela": null, "color_talon": null, "texto_suela": null, "color_cuerpo": null, "color_franja": null, "color_puntera": null, "color_cordones": null, "precio_unitario": 92.00}
22	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	10	2	alta {"talla": 42, "cantidad": 2, "id_linea": 10, "id_modelo": 2, "id_pedido": 11, "color_suela": null, "color_talon": null, "texto_suela": null, "color_cuerpo": null, "color_franja": null, "color_puntera": null, "color_cordones": null, "precio_unitario": 109.00}
23	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	11	2	alta {"talla": 44, "cantidad": 3, "id_linea": 11, "id_modelo": 6, "id_pedido": 12, "color_suela": null, "color_talon": null, "texto_suela": null, "color_cuerpo": null, "color_franja": null, "color_puntera": null, "color_cordones": null, "precio_unitario": 105.00}
24	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	12	2	alta {"talla": 38, "cantidad": 2, "id_linea": 12, "id_modelo": 2, "id_pedido": 3, "color_suela": "Blanco", "color_talon": "Gris", "texto_suela": "HALCONES", "color_cuerpo": "Negro", "color_franja": "Azul eléctrico", "color_puntera": "Negro", "color_cordones": "Azul eléctrico", "precio_unitario": 129.00}
25	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	13	2	alta {"talla": 39, "cantidad": 3, "id_linea": 13, "id_modelo": 2, "id_pedido": 3, "color_suela": "Blanco", "color_talon": "Gris", "texto_suela": "HALCONES", "color_cuerpo": "Negro", "color_franja": "Azul eléctrico", "color_puntera": "Negro", "color_cordones": "Azul eléctrico", "precio_unitario": 129.00}
26	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	14	2	alta {"talla": 40, "cantidad": 4, "id_linea": 14, "id_modelo": 2, "id_pedido": 3, "color_suela": "Blanco", "color_talon": "Gris", "texto_suela": "HALCONES", "color_cuerpo": "Negro", "color_franja": "Azul eléctrico", "color_puntera": "Negro", "color_cordones": "Azul eléctrico", "precio_unitario": 129.00}
27	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	15	2	alta {"talla": 41, "cantidad": 6, "id_linea": 15, "id_modelo": 2, "id_pedido": 3, "color_suela": "Blanco", "color_talon": "Gris", "texto_suela": "HALCONES", "color_cuerpo": "Negro", "color_franja": "Azul eléctrico", "color_puntera": "Negro", "color_cordones": "Azul eléctrico", "precio_unitario": 129.00}
28	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	16	2	alta {"talla": 42, "cantidad": 8, "id_linea": 16, "id_modelo": 2, "id_pedido": 3, "color_suela": "Blanco", "color_talon": "Gris", "texto_suela": "HALCONES", "color_cuerpo": "Negro", "color_franja": "Azul eléctrico", "color_puntera": "Negro", "color_cordones": "Azul eléctrico", "precio_unitario": 129.00}
29	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	17	2	alta {"talla": 43, "cantidad": 7, "id_linea": 17, "id_modelo": 2, "id_pedido": 3, "color_suela": "Blanco", "color_talon": "Gris", "texto_suela": "HALCONES", "color_cuerpo": "Negro", "color_franja": "Azul eléctrico", "color_puntera": "Negro", "color_cordones": "Azul eléctrico", "precio_unitario": 129.00}
30	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	18	2	alta {"talla": 44, "cantidad": 5, "id_linea": 18, "id_modelo": 2, "id_pedido": 3, "color_suela": "Blanco", "color_talon": "Gris", "texto_suela": "HALCONES", "color_cuerpo": "Negro", "color_franja": "Azul eléctrico", "color_puntera": "Negro", "color_cordones": "Azul eléctrico", "precio_unitario": 129.00}
31	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	19	2	alta {"talla": 45, "cantidad": 3, "id_linea": 19, "id_modelo": 2, "id_pedido": 3, "color_suela": "Blanco", "color_talon": "Gris", "texto_suela": "HALCONES", "color_cuerpo": "Negro", "color_franja": "Azul eléctrico", "color_puntera": "Negro", "color_cordones": "Azul eléctrico", "precio_unitario": 129.00}
32	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	20	2	alta {"talla": 46, "cantidad": 2, "id_linea": 20, "id_modelo": 2, "id_pedido": 3, "color_suela": "Blanco", "color_talon": "Gris", "texto_suela": "HALCONES", "color_cuerpo": "Negro", "color_franja": "Azul eléctrico", "color_puntera": "Negro", "color_cordones": "Azul eléctrico", "precio_unitario": 129.00}
33	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	21	2	alta {"talla": 40, "cantidad": 3, "id_linea": 21, "id_modelo": 1, "id_pedido": 5, "color_suela": "Blanco", "color_talon": "Rojo", "texto_suela": "LINCES", "color_cuerpo": "Blanco", "color_franja": "Rojo", "color_puntera": "Blanco", "color_cordones": "Negro", "precio_unitario": 109.00}
34	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	22	2	alta {"talla": 42, "cantidad": 5, "id_linea": 22, "id_modelo": 1, "id_pedido": 5, "color_suela": "Blanco", "color_talon": "Rojo", "texto_suela": "LINCES", "color_cuerpo": "Blanco", "color_franja": "Rojo", "color_puntera": "Blanco", "color_cordones": "Negro", "precio_unitario": 109.00}
35	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	23	2	alta {"talla": 44, "cantidad": 4, "id_linea": 23, "id_modelo": 1, "id_pedido": 5, "color_suela": "Blanco", "color_talon": "Rojo", "texto_suela": "LINCES", "color_cuerpo": "Blanco", "color_franja": "Rojo", "color_puntera": "Blanco", "color_cordones": "Negro", "precio_unitario": 109.00}
36	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	24	2	alta {"talla": 41, "cantidad": 1, "id_linea": 24, "id_modelo": 6, "id_pedido": 6, "color_suela": "Blanco", "color_talon": "Verde", "texto_suela": null, "color_cuerpo": "Gris", "color_franja": "Verde", "color_puntera": "Gris", "color_cordones": "Amarillo", "precio_unitario": 120.00}
37	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	25	2	alta {"talla": 42, "cantidad": 10, "id_linea": 25, "id_modelo": 3, "id_pedido": 10, "color_suela": "Blanco", "color_talon": "Negro", "texto_suela": "HALCONES", "color_cuerpo": "Negro", "color_franja": "Rojo", "color_puntera": "Rojo", "color_cordones": "Rojo", "precio_unitario": 119.00}
38	2026-11-05 10:24:50.408017+01	lineas_pedido	INSERT	26	2	alta {"talla": 43, "cantidad": 10, "id_linea": 26, "id_modelo": 3, "id_pedido": 10, "color_suela": "Blanco", "color_talon": "Negro", "texto_suela": "HALCONES", "color_cuerpo": "Negro", "color_franja": "Rojo", "color_puntera": "Rojo", "color_cordones": "Rojo", "precio_unitario": 119.00}
39	2026-11-05 10:24:50.408017+01	pedidos	UPDATE	1	2	estado: pendiente -> confirmado
40	2026-11-05 10:24:50.408017+01	pedidos	UPDATE	2	2	estado: pendiente -> confirmado
41	2026-11-05 10:24:50.408017+01	pedidos	UPDATE	3	2	estado: pendiente -> confirmado
42	2026-11-05 10:24:50.408017+01	pedidos	UPDATE	4	2	estado: pendiente -> confirmado
43	2026-11-05 10:24:50.408017+01	pedidos	UPDATE	5	2	estado: pendiente -> confirmado
44	2026-11-05 10:24:50.408017+01	pedidos	UPDATE	6	2	estado: pendiente -> confirmado
45	2026-11-05 10:24:50.408017+01	pedidos	UPDATE	7	2	estado: pendiente -> confirmado
46	2026-11-05 10:24:50.408017+01	pedidos	UPDATE	11	2	estado: pendiente -> confirmado
47	2026-11-05 10:24:50.408017+01	pedidos	UPDATE	7	2	estado: confirmado -> cancelado
48	2026-11-05 10:24:50.408017+01	pedidos	UPDATE	12	2	estado: pendiente -> cancelado
49	2026-11-05 10:24:50.408017+01	pedidos	UPDATE	1	3	estado: confirmado -> entregado
50	2026-11-05 10:24:50.408017+01	pedidos	UPDATE	2	3	estado: confirmado -> entregado
51	2026-11-05 10:24:50.408017+01	pedidos	UPDATE	11	3	estado: confirmado -> entregado
131	2026-11-09 12:28:22.29645+01	pedidos	UPDATE	59	1	estado: pendiente -> confirmado
127	2026-11-09 09:49:10.954834+01	pedidos	INSERT	58	4	alta {"tipo": "estandar", "fecha": "2026-11-09", "total": 0.00, "estado": "pendiente", "id_pedido": 58, "creado_por": 4, "id_cliente": 28, "referencia": "SO058"}
128	2026-11-09 09:49:10.954834+01	lineas_pedido	INSERT	117	4	alta {"talla": 41, "cantidad": 1, "id_linea": 117, "id_modelo": 1, "id_pedido": 58, "color_suela": "Blanco", "color_talon": "Blanco", "texto_suela": null, "color_cuerpo": "Blanco", "color_franja": "Blanco", "color_puntera": "Blanco", "color_cordones": "Blanco", "precio_unitario": 104.00}
129	2026-11-09 12:25:43.567027+01	pedidos	INSERT	59	4	alta {"tipo": "estandar", "fecha": "2026-11-09", "total": 0.00, "estado": "pendiente", "id_pedido": 59, "creado_por": 4, "id_cliente": 28, "referencia": "SO059"}
130	2026-11-09 12:25:43.567027+01	lineas_pedido	INSERT	118	4	alta {"talla": 42, "cantidad": 1, "id_color": 24, "id_linea": 118, "id_modelo": 2, "id_pedido": 59, "color_suela": null, "color_talon": null, "texto_suela": null, "color_cuerpo": null, "color_franja": null, "color_puntera": null, "color_cordones": null, "precio_unitario": 109.00}
136	2026-11-09 13:24:11.061956+01	pedidos	INSERT	61	4	alta {"tipo": "estandar", "fecha": "2026-11-09", "total": 0.00, "estado": "pendiente", "id_pedido": 61, "creado_por": 4, "id_cliente": 30, "referencia": "SO061"}
137	2026-11-09 13:24:11.061956+01	lineas_pedido	INSERT	124	4	alta {"talla": 40, "cantidad": 1, "id_color": 6, "id_linea": 124, "id_modelo": 2, "id_pedido": 61, "color_suela": null, "color_talon": null, "texto_suela": null, "color_cuerpo": null, "color_franja": null, "color_puntera": null, "color_cordones": null, "precio_unitario": 109.00}
138	2026-11-09 13:24:26.694262+01	pedidos	UPDATE	61	1	estado: pendiente -> confirmado
139	2026-11-09 13:26:05.274419+01	pedidos	INSERT	62	4	alta {"tipo": "estandar", "fecha": "2026-11-09", "total": 0.00, "estado": "pendiente", "id_pedido": 62, "creado_por": 4, "id_cliente": 28, "referencia": "SO062"}
140	2026-11-09 13:26:05.274419+01	lineas_pedido	INSERT	125	4	alta {"talla": 41, "cantidad": 1, "id_color": 25, "id_linea": 125, "id_modelo": 3, "id_pedido": 62, "color_suela": null, "color_talon": null, "texto_suela": null, "color_cuerpo": null, "color_franja": null, "color_puntera": null, "color_cordones": null, "precio_unitario": 99.00}
141	2026-11-09 13:26:13.139306+01	pedidos	UPDATE	62	1	estado: pendiente -> confirmado
142	2026-11-10 11:03:49.76737+01	pedidos	INSERT	63	4	alta {"tipo": "estandar", "fecha": "2026-11-10", "total": 0.00, "estado": "pendiente", "id_pedido": 63, "creado_por": 4, "id_cliente": 32, "referencia": "SO063"}
143	2026-11-10 11:03:49.76737+01	lineas_pedido	INSERT	126	4	alta {"talla": 43, "cantidad": 1, "id_color": 6, "id_linea": 126, "id_modelo": 2, "id_pedido": 63, "color_suela": null, "color_talon": null, "texto_suela": null, "color_cuerpo": null, "color_franja": null, "color_puntera": null, "color_cordones": null, "precio_unitario": 109.00}
144	2026-11-10 11:04:25.843624+01	pedidos	UPDATE	63	1	estado: pendiente -> confirmado
145	2026-11-10 11:06:14.771929+01	pedidos	UPDATE	63	1	estado: confirmado -> entregado
146	2026-11-10 11:12:58.406125+01	pedidos	INSERT	64	4	alta {"tipo": "estandar", "fecha": "2026-11-10", "total": 0.00, "estado": "pendiente", "id_pedido": 64, "creado_por": 4, "id_cliente": 30, "referencia": "SO064"}
147	2026-11-10 11:12:58.406125+01	lineas_pedido	INSERT	127	4	alta {"talla": 39, "cantidad": 1, "id_color": null, "id_linea": 127, "id_modelo": 1, "id_pedido": 64, "color_suela": "Blanco", "color_talon": "Blanco", "texto_suela": null, "color_cuerpo": "Blanco", "color_franja": "Blanco", "color_puntera": "Blanco", "color_cordones": "Blanco", "precio_unitario": 104.00}
148	2026-11-10 11:12:58.406125+01	lineas_pedido	INSERT	128	4	alta {"talla": 40, "cantidad": 1, "id_color": null, "id_linea": 128, "id_modelo": 1, "id_pedido": 64, "color_suela": "Blanco", "color_talon": "Blanco", "texto_suela": null, "color_cuerpo": "Blanco", "color_franja": "Blanco", "color_puntera": "Blanco", "color_cordones": "Blanco", "precio_unitario": 104.00}
149	2026-11-10 11:13:06.992702+01	pedidos	UPDATE	64	1	estado: pendiente -> confirmado
150	2026-11-10 11:14:28.667698+01	pedidos	INSERT	65	4	alta {"tipo": "estandar", "fecha": "2026-11-10", "total": 0.00, "estado": "pendiente", "id_pedido": 65, "creado_por": 4, "id_cliente": 30, "referencia": "SO065"}
151	2026-11-10 11:14:28.667698+01	lineas_pedido	INSERT	129	4	alta {"talla": 40, "cantidad": 1, "id_color": null, "id_linea": 129, "id_modelo": 2, "id_pedido": 65, "color_suela": "Blanco", "color_talon": "Blanco", "texto_suela": null, "color_cuerpo": "Blanco", "color_franja": "Blanco", "color_puntera": "Blanco", "color_cordones": "Blanco", "precio_unitario": 124.00}
152	2026-11-10 11:14:44.328886+01	pedidos	UPDATE	65	1	estado: pendiente -> confirmado
153	2026-11-10 11:15:30.417806+01	pedidos	INSERT	66	4	alta {"tipo": "estandar", "fecha": "2026-11-10", "total": 0.00, "estado": "pendiente", "id_pedido": 66, "creado_por": 4, "id_cliente": 30, "referencia": "SO066"}
154	2026-11-10 11:15:30.417806+01	lineas_pedido	INSERT	130	4	alta {"talla": 40, "cantidad": 1, "id_color": null, "id_linea": 130, "id_modelo": 2, "id_pedido": 66, "color_suela": "Blanco", "color_talon": "Blanco", "texto_suela": null, "color_cuerpo": "Blanco", "color_franja": "Blanco", "color_puntera": "Blanco", "color_cordones": "Blanco", "precio_unitario": 124.00}
155	2026-11-10 11:15:38.467111+01	pedidos	UPDATE	66	1	estado: pendiente -> confirmado
156	2026-11-10 12:00:17.121818+01	pedidos	UPDATE	8	1	estado: pendiente -> confirmado
157	2026-11-10 12:18:06.973102+01	pedidos	UPDATE	10	1	estado: pendiente -> confirmado
158	2026-11-10 12:18:33.960949+01	pedidos	UPDATE	58	1	estado: pendiente -> confirmado
\.


--
-- TOC entry 3572 (class 0 OID 32871)
-- Dependencies: 224
-- Data for Name: modelos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.modelos (id_modelo, codigo, nombre, categoria, precio_base) FROM stdin;
1	court	SPEAKE Court	Urbano	89.00
2	pulse	SPEAKE Pulse	Deportivo	109.00
3	high	SPEAKE High	Baloncesto	99.00
4	retro	SPEAKE Retro	Retro	95.00
5	street	SPEAKE Street	Street	92.00
6	aero	SPEAKE Aero	Running	105.00
\.


--
-- TOC entry 3574 (class 0 OID 32883)
-- Dependencies: 226
-- Data for Name: pedidos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.pedidos (id_pedido, id_cliente, fecha, estado, tipo, total, creado_por) FROM stdin;
9	5	2026-10-03	pendiente	estandar	92.00	2
59	28	2026-11-09	confirmado	estandar	109.00	4
61	30	2026-11-09	confirmado	estandar	109.00	4
62	28	2026-11-09	confirmado	estandar	99.00	4
63	32	2026-11-10	entregado	estandar	109.00	4
3	2	2026-08-20	confirmado	custom	5160.00	2
4	5	2026-09-02	confirmado	estandar	99.00	2
5	4	2026-09-08	confirmado	custom	1308.00	2
6	1	2026-09-15	confirmado	custom	120.00	2
7	3	2026-09-21	cancelado	estandar	190.00	2
12	4	2026-10-25	cancelado	estandar	315.00	2
1	1	2026-08-05	entregado	estandar	89.00	2
2	3	2026-08-12	entregado	estandar	197.00	2
11	1	2026-10-18	entregado	estandar	218.00	2
64	30	2026-11-10	confirmado	custom	208.00	4
65	30	2026-11-10	confirmado	custom	124.00	4
66	30	2026-11-10	confirmado	custom	124.00	4
8	6	2026-09-28	confirmado	estandar	1335.00	2
10	2	2026-10-10	confirmado	custom	2380.00	2
58	28	2026-11-09	confirmado	custom	104.00	4
\.


--
-- TOC entry 3580 (class 0 OID 40960)
-- Dependencies: 239
-- Data for Name: pedidos_odoo; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.pedidos_odoo (id_pedido, pedido_odoo, id_odoo, estado, mensaje, actualizado) FROM stdin;
59	S00008	8	enviado	creado en Odoo	2026-11-09 12:28:23.303221+01
61	S00010	10	enviado	creado en Odoo	2026-11-09 13:24:27.582642+01
62	S00011	11	enviado	creado en Odoo	2026-11-09 13:26:13.774909+01
63	\N	\N	error	Odoo: usuario o contraseña incorrectos	2026-11-10 11:06:23.234768+01
64	\N	\N	error	Odoo: usuario o contraseña incorrectos	2026-11-10 11:13:31.7033+01
65	S00012	12	enviado	creado en Odoo	2026-11-10 11:14:45.264501+01
66	S00013	13	enviado	creado en Odoo	2026-11-10 11:15:39.201426+01
8	S00014	14	enviado	creado en Odoo	2026-11-10 12:00:18.144278+01
10	S00015	15	enviado	creado en Odoo	2026-11-10 12:18:07.894726+01
58	S00016	16	enviado	creado en Odoo	2026-11-10 12:18:34.417217+01
\.


--
-- TOC entry 3566 (class 0 OID 32823)
-- Dependencies: 218
-- Data for Name: permisos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.permisos (id_rol, operacion, permitido) FROM stdin;
1	consultar_pedidos	t
1	crear_pedido	t
1	editar_pedido	t
1	confirmar_pedido	t
1	cancelar_pedido	t
1	entregar_pedido	t
1	eliminar_pedido	t
1	consultar_stock	t
1	ver_auditoria	t
1	gestionar_usuarios	t
1	exportar_usuarios	t
2	consultar_pedidos	t
2	crear_pedido	t
2	editar_pedido	t
2	confirmar_pedido	t
2	cancelar_pedido	t
2	entregar_pedido	f
2	eliminar_pedido	f
2	consultar_stock	t
2	ver_auditoria	f
2	gestionar_usuarios	f
2	exportar_usuarios	f
3	consultar_pedidos	t
3	crear_pedido	f
3	editar_pedido	f
3	confirmar_pedido	f
3	cancelar_pedido	f
3	entregar_pedido	t
3	eliminar_pedido	f
3	consultar_stock	t
3	ver_auditoria	f
3	gestionar_usuarios	f
3	exportar_usuarios	f
4	consultar_pedidos	f
4	crear_pedido	t
4	editar_pedido	t
4	confirmar_pedido	f
4	cancelar_pedido	f
4	entregar_pedido	f
4	eliminar_pedido	f
4	consultar_stock	f
4	ver_auditoria	f
4	gestionar_usuarios	f
4	exportar_usuarios	f
\.


--
-- TOC entry 3565 (class 0 OID 32813)
-- Dependencies: 217
-- Data for Name: roles; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.roles (id_rol, nombre) FROM stdin;
1	Administrador
2	Comercial
3	Almacén
4	Web
\.


--
-- TOC entry 3577 (class 0 OID 32938)
-- Dependencies: 229
-- Data for Name: stock; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.stock (id_modelo, talla, stock_disponible, fecha_corte) FROM stdin;
1	38	31	2026-11-05 10:24:50.408017+01
3	38	20	2026-11-05 10:24:50.408017+01
4	38	27	2026-11-05 10:24:50.408017+01
5	38	34	2026-11-05 10:24:50.408017+01
3	39	23	2026-11-05 10:24:50.408017+01
4	39	30	2026-11-05 10:24:50.408017+01
6	39	19	2026-11-05 10:24:50.408017+01
3	40	26	2026-11-05 10:24:50.408017+01
4	40	33	2026-11-05 10:24:50.408017+01
5	40	15	2026-11-05 10:24:50.408017+01
6	40	22	2026-11-05 10:24:50.408017+01
4	41	11	2026-11-05 10:24:50.408017+01
5	41	18	2026-11-05 10:24:50.408017+01
4	42	14	2026-11-05 10:24:50.408017+01
5	42	21	2026-11-05 10:24:50.408017+01
6	42	28	2026-11-05 10:24:50.408017+01
1	43	21	2026-11-05 10:24:50.408017+01
3	44	13	2026-11-05 10:24:50.408017+01
4	44	20	2026-11-05 10:24:50.408017+01
5	44	27	2026-11-05 10:24:50.408017+01
6	44	34	2026-11-05 10:24:50.408017+01
1	45	27	2026-11-05 10:24:50.408017+01
3	45	16	2026-11-05 10:24:50.408017+01
5	45	30	2026-11-05 10:24:50.408017+01
6	45	12	2026-11-05 10:24:50.408017+01
1	46	30	2026-11-05 10:24:50.408017+01
4	46	26	2026-11-05 10:24:50.408017+01
5	46	33	2026-11-05 10:24:50.408017+01
6	46	15	2026-11-05 10:24:50.408017+01
3	46	2	2026-11-05 10:24:50.408017+01
6	38	0	2026-11-05 10:24:50.408017+01
5	39	4	2026-11-05 10:24:50.408017+01
4	45	3	2026-11-05 10:24:50.408017+01
5	43	23	2026-11-05 10:24:50.408017+01
6	43	30	2026-11-05 10:24:50.408017+01
2	38	11	2026-11-05 10:24:50.408017+01
2	39	13	2026-11-05 10:24:50.408017+01
2	41	16	2026-11-05 10:24:50.408017+01
2	44	26	2026-11-05 10:24:50.408017+01
2	45	31	2026-11-05 10:24:50.408017+01
2	46	10	2026-11-05 10:24:50.408017+01
1	42	12	2026-11-05 10:24:50.408017+01
1	44	20	2026-11-05 10:24:50.408017+01
6	41	24	2026-11-05 10:24:50.408017+01
4	43	17	2026-11-05 10:24:50.408017+01
2	42	14	2026-11-09 12:28:22.29645+01
3	41	27	2026-11-09 13:26:13.139306+01
2	43	20	2026-11-10 11:04:25.843624+01
2	40	12	2026-11-10 11:15:38.467111+01
1	39	28	2026-11-10 12:00:17.121818+01
1	40	3	2026-11-10 12:00:17.121818+01
3	42	22	2026-11-10 12:18:06.973102+01
3	43	0	2026-11-10 12:18:06.973102+01
1	41	9	2026-11-10 12:18:33.960949+01
\.


--
-- TOC entry 3568 (class 0 OID 32837)
-- Dependencies: 220
-- Data for Name: usuarios; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.usuarios (id_usuario, username, password_hash, id_rol, activo, fecha_creacion) FROM stdin;
1	admin	$2a$10$8mPrn68S2B31SU0zebxv8el2NPmv6Q26/uwn7h3CyczGHtS/rPo0K	1	t	2026-11-05 10:24:50.408017+01
2	comercial1	$2a$10$PuxmumNbVoyA.XQoeaqYZu3fsuMs6T5P/8FO7.Q8PjZsMV/JDV6aq	2	t	2026-11-05 10:24:50.408017+01
3	almacen1	$2a$10$dbxFxXOBySOxiRSRAY/Szeef.8FRYhuMAJSsVKImdiYst2DS1U3ii	3	t	2026-11-05 10:24:50.408017+01
4	web_publica	$2a$10$AcHE7RUMuFqfiBnaQOt8feQrS7a01x4qDJW3m/v9ATdRRKnI/JsDm	4	t	2026-11-06 12:57:01.941834+01
\.


--
-- TOC entry 3597 (class 0 OID 0)
-- Dependencies: 221
-- Name: clientes_id_cliente_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.clientes_id_cliente_seq', 35, true);


--
-- TOC entry 3598 (class 0 OID 0)
-- Dependencies: 241
-- Name: colores_catalogo_id_color_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.colores_catalogo_id_color_seq', 36, true);


--
-- TOC entry 3599 (class 0 OID 0)
-- Dependencies: 227
-- Name: lineas_pedido_id_linea_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.lineas_pedido_id_linea_seq', 130, true);


--
-- TOC entry 3600 (class 0 OID 0)
-- Dependencies: 230
-- Name: log_eventos_id_evento_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.log_eventos_id_evento_seq', 158, true);


--
-- TOC entry 3601 (class 0 OID 0)
-- Dependencies: 223
-- Name: modelos_id_modelo_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.modelos_id_modelo_seq', 6, true);


--
-- TOC entry 3602 (class 0 OID 0)
-- Dependencies: 225
-- Name: pedidos_id_pedido_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.pedidos_id_pedido_seq', 66, true);


--
-- TOC entry 3603 (class 0 OID 0)
-- Dependencies: 216
-- Name: roles_id_rol_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.roles_id_rol_seq', 4, true);


--
-- TOC entry 3604 (class 0 OID 0)
-- Dependencies: 219
-- Name: usuarios_id_usuario_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.usuarios_id_usuario_seq', 5, true);


--
-- TOC entry 3369 (class 2606 OID 32869)
-- Name: clientes clientes_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clientes
    ADD CONSTRAINT clientes_email_key UNIQUE (email);


--
-- TOC entry 3371 (class 2606 OID 32867)
-- Name: clientes clientes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.clientes
    ADD CONSTRAINT clientes_pkey PRIMARY KEY (id_cliente);


--
-- TOC entry 3394 (class 2606 OID 40992)
-- Name: colores_catalogo colores_catalogo_codigo_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.colores_catalogo
    ADD CONSTRAINT colores_catalogo_codigo_key UNIQUE (codigo);


--
-- TOC entry 3396 (class 2606 OID 40990)
-- Name: colores_catalogo colores_catalogo_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.colores_catalogo
    ADD CONSTRAINT colores_catalogo_pkey PRIMARY KEY (id_color);


--
-- TOC entry 3384 (class 2606 OID 32923)
-- Name: lineas_pedido lineas_pedido_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lineas_pedido
    ADD CONSTRAINT lineas_pedido_pkey PRIMARY KEY (id_linea);


--
-- TOC entry 3390 (class 2606 OID 32961)
-- Name: log_eventos log_eventos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.log_eventos
    ADD CONSTRAINT log_eventos_pkey PRIMARY KEY (id_evento);


--
-- TOC entry 3373 (class 2606 OID 32881)
-- Name: modelos modelos_codigo_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.modelos
    ADD CONSTRAINT modelos_codigo_key UNIQUE (codigo);


--
-- TOC entry 3375 (class 2606 OID 32879)
-- Name: modelos modelos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.modelos
    ADD CONSTRAINT modelos_pkey PRIMARY KEY (id_modelo);


--
-- TOC entry 3392 (class 2606 OID 40968)
-- Name: pedidos_odoo pedidos_odoo_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pedidos_odoo
    ADD CONSTRAINT pedidos_odoo_pkey PRIMARY KEY (id_pedido);


--
-- TOC entry 3379 (class 2606 OID 32898)
-- Name: pedidos pedidos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pedidos
    ADD CONSTRAINT pedidos_pkey PRIMARY KEY (id_pedido);


--
-- TOC entry 3381 (class 2606 OID 32900)
-- Name: pedidos pedidos_referencia_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pedidos
    ADD CONSTRAINT pedidos_referencia_key UNIQUE (referencia);


--
-- TOC entry 3363 (class 2606 OID 32830)
-- Name: permisos permisos_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.permisos
    ADD CONSTRAINT permisos_pkey PRIMARY KEY (id_rol, operacion);


--
-- TOC entry 3359 (class 2606 OID 32822)
-- Name: roles roles_nombre_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_nombre_key UNIQUE (nombre);


--
-- TOC entry 3361 (class 2606 OID 32820)
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id_rol);


--
-- TOC entry 3387 (class 2606 OID 32945)
-- Name: stock stock_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock
    ADD CONSTRAINT stock_pkey PRIMARY KEY (id_modelo, talla);


--
-- TOC entry 3365 (class 2606 OID 32847)
-- Name: usuarios usuarios_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_pkey PRIMARY KEY (id_usuario);


--
-- TOC entry 3367 (class 2606 OID 32849)
-- Name: usuarios usuarios_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_username_key UNIQUE (username);


--
-- TOC entry 3382 (class 1259 OID 32935)
-- Name: ix_lineas_pedido; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_lineas_pedido ON public.lineas_pedido USING btree (id_pedido);


--
-- TOC entry 3388 (class 1259 OID 32967)
-- Name: ix_log_fecha; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_log_fecha ON public.log_eventos USING btree (fecha);


--
-- TOC entry 3376 (class 1259 OID 32936)
-- Name: ix_pedidos_cliente; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_pedidos_cliente ON public.pedidos USING btree (id_cliente);


--
-- TOC entry 3377 (class 1259 OID 32937)
-- Name: ix_pedidos_fecha_estado; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX ix_pedidos_fecha_estado ON public.pedidos USING btree (fecha, estado);


--
-- TOC entry 3385 (class 1259 OID 41019)
-- Name: ux_linea_pedido; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX ux_linea_pedido ON public.lineas_pedido USING btree (id_pedido, id_modelo, talla, COALESCE((id_color)::integer, 0), COALESCE((color_cuerpo)::text, ''::text), COALESCE((color_franja)::text, ''::text), COALESCE((color_puntera)::text, ''::text), COALESCE((color_talon)::text, ''::text), COALESCE((color_suela)::text, ''::text), COALESCE((color_cordones)::text, ''::text), COALESCE(texto_suela, ''::character varying));


--
-- TOC entry 3416 (class 2620 OID 32982)
-- Name: lineas_pedido t1_lineas_antes; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER t1_lineas_antes BEFORE INSERT OR DELETE OR UPDATE ON public.lineas_pedido FOR EACH ROW EXECUTE FUNCTION public.fn_lineas_antes();


--
-- TOC entry 3412 (class 2620 OID 32973)
-- Name: pedidos t1_pedidos_permisos; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER t1_pedidos_permisos BEFORE INSERT OR DELETE OR UPDATE ON public.pedidos FOR EACH ROW EXECUTE FUNCTION public.fn_pedidos_permisos();


--
-- TOC entry 3413 (class 2620 OID 41018)
-- Name: lineas_pedido t1b_lineas_color; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER t1b_lineas_color BEFORE INSERT OR UPDATE ON public.lineas_pedido FOR EACH ROW EXECUTE FUNCTION public.fn_lineas_color_catalogo();


--
-- TOC entry 3415 (class 2620 OID 32984)
-- Name: lineas_pedido t2_lineas_total; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER t2_lineas_total AFTER INSERT OR DELETE OR UPDATE ON public.lineas_pedido FOR EACH ROW EXECUTE FUNCTION public.fn_lineas_total();


--
-- TOC entry 3411 (class 2620 OID 32975)
-- Name: pedidos t2_pedidos_validar; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER t2_pedidos_validar BEFORE DELETE OR UPDATE ON public.pedidos FOR EACH ROW EXECUTE FUNCTION public.fn_pedidos_validar();


--
-- TOC entry 3414 (class 2620 OID 32985)
-- Name: lineas_pedido t3_lineas_audit; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER t3_lineas_audit AFTER INSERT OR DELETE OR UPDATE ON public.lineas_pedido FOR EACH ROW EXECUTE FUNCTION public.fn_auditar('id_linea');


--
-- TOC entry 3410 (class 2620 OID 32977)
-- Name: pedidos t3_pedidos_stock; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER t3_pedidos_stock AFTER UPDATE OF estado ON public.pedidos FOR EACH ROW WHEN ((old.estado IS DISTINCT FROM new.estado)) EXECUTE FUNCTION public.fn_pedidos_stock();


--
-- TOC entry 3409 (class 2620 OID 32979)
-- Name: pedidos t4_pedidos_audit_altabaja; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER t4_pedidos_audit_altabaja AFTER INSERT OR DELETE ON public.pedidos FOR EACH ROW EXECUTE FUNCTION public.fn_auditar('id_pedido');


--
-- TOC entry 3408 (class 2620 OID 32980)
-- Name: pedidos t4_pedidos_audit_cambios; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER t4_pedidos_audit_cambios AFTER UPDATE ON public.pedidos FOR EACH ROW WHEN (((old.estado IS DISTINCT FROM new.estado) OR (old.id_cliente IS DISTINCT FROM new.id_cliente) OR (old.fecha IS DISTINCT FROM new.fecha))) EXECUTE FUNCTION public.fn_auditar('id_pedido');


--
-- TOC entry 3407 (class 2606 OID 40995)
-- Name: colores_catalogo colores_catalogo_id_modelo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.colores_catalogo
    ADD CONSTRAINT colores_catalogo_id_modelo_fkey FOREIGN KEY (id_modelo) REFERENCES public.modelos(id_modelo);


--
-- TOC entry 3401 (class 2606 OID 41000)
-- Name: lineas_pedido lineas_pedido_id_color_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lineas_pedido
    ADD CONSTRAINT lineas_pedido_id_color_fkey FOREIGN KEY (id_color) REFERENCES public.colores_catalogo(id_color);


--
-- TOC entry 3402 (class 2606 OID 32929)
-- Name: lineas_pedido lineas_pedido_id_modelo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lineas_pedido
    ADD CONSTRAINT lineas_pedido_id_modelo_fkey FOREIGN KEY (id_modelo) REFERENCES public.modelos(id_modelo);


--
-- TOC entry 3403 (class 2606 OID 32924)
-- Name: lineas_pedido lineas_pedido_id_pedido_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.lineas_pedido
    ADD CONSTRAINT lineas_pedido_id_pedido_fkey FOREIGN KEY (id_pedido) REFERENCES public.pedidos(id_pedido);


--
-- TOC entry 3405 (class 2606 OID 32962)
-- Name: log_eventos log_eventos_id_usuario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.log_eventos
    ADD CONSTRAINT log_eventos_id_usuario_fkey FOREIGN KEY (id_usuario) REFERENCES public.usuarios(id_usuario);


--
-- TOC entry 3399 (class 2606 OID 32906)
-- Name: pedidos pedidos_creado_por_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pedidos
    ADD CONSTRAINT pedidos_creado_por_fkey FOREIGN KEY (creado_por) REFERENCES public.usuarios(id_usuario);


--
-- TOC entry 3400 (class 2606 OID 32901)
-- Name: pedidos pedidos_id_cliente_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pedidos
    ADD CONSTRAINT pedidos_id_cliente_fkey FOREIGN KEY (id_cliente) REFERENCES public.clientes(id_cliente);


--
-- TOC entry 3406 (class 2606 OID 40969)
-- Name: pedidos_odoo pedidos_odoo_id_pedido_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.pedidos_odoo
    ADD CONSTRAINT pedidos_odoo_id_pedido_fkey FOREIGN KEY (id_pedido) REFERENCES public.pedidos(id_pedido) ON DELETE CASCADE;


--
-- TOC entry 3397 (class 2606 OID 32831)
-- Name: permisos permisos_id_rol_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.permisos
    ADD CONSTRAINT permisos_id_rol_fkey FOREIGN KEY (id_rol) REFERENCES public.roles(id_rol);


--
-- TOC entry 3404 (class 2606 OID 32946)
-- Name: stock stock_id_modelo_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stock
    ADD CONSTRAINT stock_id_modelo_fkey FOREIGN KEY (id_modelo) REFERENCES public.modelos(id_modelo);


--
-- TOC entry 3398 (class 2606 OID 32850)
-- Name: usuarios usuarios_id_rol_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.usuarios
    ADD CONSTRAINT usuarios_id_rol_fkey FOREIGN KEY (id_rol) REFERENCES public.roles(id_rol);


-- Completed on 2026-11-10 13:32:12

--
-- PostgreSQL database dump complete
--

\unrestrict WRTbTxUPirbLz10tWh2fAihJVeWF6fbGfELyf4nZScrDAIyfxOkx1adhxv4L50h

