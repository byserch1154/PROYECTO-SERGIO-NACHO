-- Paso 1: borra la base SPEAKE antigua (esquema viejo). WITH (FORCE) cierra sus conexiones.
DROP DATABASE IF EXISTS "SPEAKE" WITH (FORCE);
