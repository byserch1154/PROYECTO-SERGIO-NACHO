-- =====================================================================
-- 09_actualizar_base_existente.sql
-- Para una base creada con una versión ANTERIOR de 01_esquema.sql.
-- No borra ni toca tablas ni datos: solo REEMPLAZA 2 funciones por su
-- versión actual (CREATE OR REPLACE). Los triggers siguen apuntando a ellas.
--   1. fn_pedidos_permisos: un pedido nuevo siempre nace 'pendiente'.
--   2. fn_indicadores: añade el indicador pares_solicitados.
-- =====================================================================

CREATE OR REPLACE FUNCTION fn_pedidos_permisos() RETURNS trigger
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

CREATE OR REPLACE FUNCTION fn_indicadores()
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
