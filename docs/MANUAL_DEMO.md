# Manual de demostración (guion de 10-15 minutos)

Preparación (antes de entrar):
- Base de datos SPEAKE cargada: `01_esquema.sql`, `02_datos.sql` y, desde `backend-express/sql/`,
  `07_web_backend.sql`, `10_integracion_odoo.sql` y `11_colores_catalogo.sql`.
- `npm start` en `backend-express` · VM de Odoo encendida · pgAdmin abierto.
- `java\untitled` abierto en IntelliJ · una consola en `python\sneaker-data-lab`.

| # | Paso | Dónde | Qué enseñar |
|---|---|---|---|
| 1 | Presentar SPEAKE y el problema | Diapositiva | Fábrica con catálogo estándar + línea Custom para clubes |
| 2 | Catálogo y ficha de producto con sus colores | `http://localhost:3000` | Web responsive (F12 → modo móvil) |
| 3 | Personaliza: colores, texto y tallas → *Enviar* | `personaliza.html` / `contacto.html` | Mensaje con la **referencia SO0xx** |
| 4 | Tabla `pedidos`: el SO0xx aparece **pendiente** | pgAdmin | Triggers de stock, importes y colores |
| 5 | Ejecutar `04_pruebas.sql` y `12_pruebas_web_odoo.sql` | pgAdmin | Todas las pruebas superadas (terminan en ROLLBACK) |
| 6 | Login `comercial1` → abrir el SO0xx → **Confirmar** | `/gestion/` | Descuento de stock, auditoría y columna Odoo «enviado» |
| 7 | Login `almacen1` e intentar confirmar | `/gestion/` | Rechazado: los permisos están en PostgreSQL |
| 8 | Ventas → pedido S000xx (Referencia del cliente = SO0xx) | Odoo | El importe incluye el 21 % de IVA |
| 9 | Fabricación → órdenes con origen S000xx | Odoo | Ruta MTO de los productos Custom |
| 10 | *Exportar CSV PSP/Python* y copiar los CSV a Java y Python | panel | `backend-express\data\export\` |
| 11 | Run sobre `Main` → `salida\ficha_taller_SO0xx.txt` y `procesamiento.log` | IntelliJ | Padre + 3 hijos, stdin/stdout, códigos de salida |
| 12 | Run con `datos/pedido_erroneo.csv` | IntelliJ | El validador sale con 3 y no se lanzan más hijos |
| 13 | `streamlit run app_dashboard.py` | consola | KPIs con el pedido nuevo; se actualiza cada 60 s |
| 14 | Cierre: el mismo SO0xx en web, BD, panel, Odoo, Java y Python | Diapositiva | Trazabilidad completa |

Comandos de pruebas para enseñar si lo piden:
```bat
cd backend-express && npm test           :: pruebas de la API
cd backend-express && npm run test:odoo  :: pruebas de la integración con Odoo
cd python\sneaker-data-lab && python -m pytest -q
```

Plan B si algo falla en directo:
- Sin Odoo: enseñar `odoo/ESTADO_ODOO.md` y usar `java\untitled\datos\ficha_fabricacion.csv`.
- Sin backend: la web se ve abriendo los HTML y Python lee los CSV de `entrada_acc/`.
