# SPEAKE · Fábrica de zapatillas

Proyecto Intermodular de 2º DAM. SPEAKE fabrica y vende zapatillas: 6 modelos de catálogo y una línea Custom en la que
el cliente elige los colores y un texto para la suela.

**Equipo:** Sergio Sierra y Nacho García.

**Memoria técnica:** `SERGIO-SIERRA-NACHO-MEMORIA_TECNICA_SANTI.docx`, en esta misma carpeta.

## Qué mirar en cada asignatura

| Asignatura | Dónde está |
|---|---|
| Desarrollo de Interfaces | `lenguaje-de-marcas/`: las 5 páginas HTML, `css/estilos.css` y `js/zapatillas.js` |
| Sistemas de Gestión Empresarial | Odoo está en una máquina virtual y no se sube. La conexión con la web está en `backend-express/src/odoo.js`, `backend-express/src/routes/gestion.js` y `backend-express/sql/10_integracion_odoo.sql`. Las capturas de Odoo están en el apartado 6 de la memoria |
| Programación de Servicios y Procesos | `java/untitled/`: se abre en IntelliJ y se pulsa Run sobre `Main` |

## Cómo se arranca

**Web y conexión con Odoo**
```bat
cd backend-express
copy .env.example .env
npm install
npm start
```
En el `.env` van la contraseña de PostgreSQL y los datos de Odoo (no se sube a GitHub). La web queda en
`http://localhost:3000` y el panel de gestión en `http://localhost:3000/gestion/`. Al confirmar un pedido en el panel,
se crea solo en Odoo con la referencia del cliente SO0xx.

**Java (PSP)**

Abrir `java/untitled` en IntelliJ y Run sobre `Main`. Lee `datos/ficha_fabricacion.csv` y deja la ficha del taller y
el log en `salida/`. Los demás casos se prueban cambiando los argumentos en Run → Edit Configurations:

| Argumentos | Qué pasa |
|---|---|
| (ninguno) | Procesa 3 pedidos y genera sus fichas. Salida 0 |
| `datos/pedido_erroneo.csv` | El validador encuentra los errores y se para. Salida 1 |
| `datos/pedido_sin_columnas.csv` | Faltan columnas. Salida 1 |
| `datos/no_existe.csv` | El fichero no existe. Salida 2 |
| `--retardo-ms 8000 --timeout 3` | El analizador tarda demasiado y el padre lo corta. TIMEOUT, salida 1 |
| `--paralelo` | Procesa los pedidos a la vez con 3 hilos |
| `datos/pedido_SO003.json` | Lee el pedido en JSON. Misma ficha que con el CSV |
| `datos/pedido_roto.json` | JSON incompleto. Salida 2 |
