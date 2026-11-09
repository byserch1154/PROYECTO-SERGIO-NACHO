-- Comprueba qué hay ya cargado en la base de datos (solo lectura)
SELECT current_database() AS base,
       (SELECT string_agg(tablename, ', ' ORDER BY tablename) FROM pg_tables WHERE schemaname = 'public') AS tablas,
       (SELECT count(*) FROM pg_proc WHERE proname = 'fn_login')       AS tiene_01_esquema,
       (SELECT count(*) FROM pg_proc WHERE proname = 'fn_cliente_web') AS tiene_07_web,
       (SELECT string_agg(datname, ', ') FROM pg_database WHERE NOT datistemplate) AS bases_del_servidor;
