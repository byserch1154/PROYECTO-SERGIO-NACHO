-- Paso 2: cierra las conexiones abiertas a sneaker_factory para poder renombrarla
SELECT pg_terminate_backend(pid) FROM pg_stat_activity
 WHERE datname = 'sneaker_factory' AND pid <> pg_backend_pid();
