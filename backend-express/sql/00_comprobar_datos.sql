-- Comprueba qué hay cargado en la base de datos (solo lectura)
SELECT current_database()                                               AS base,
       (SELECT count(*) FROM pg_proc WHERE proname = 'fn_login')        AS esquema_01,
       (SELECT count(*) FROM pg_proc WHERE proname = 'fn_cliente_web')  AS script_07,
       (SELECT string_agg(username || ':' || r.nombre, ', ' ORDER BY id_usuario)
          FROM usuarios u JOIN roles r USING (id_rol))                  AS usuarios,
       (SELECT count(*) FROM modelos)                                   AS modelos,
       (SELECT count(*) FROM clientes)                                  AS clientes,
       (SELECT count(*) FROM pedidos)                                   AS pedidos,
       (SELECT count(*) FROM lineas_pedido)                             AS lineas,
       (SELECT count(*) FROM stock)                                     AS stock,
       (SELECT string_agg(indicador || '=' || valor, ' · ') FROM v_reconciliacion) AS cifras;
