# Header y footer unificados (SPEAKE)

Compartidos entre asignaturas (copiar IDÉNTICOS, no editar por módulo):
- css/sf-layout.css
- js/sf-layout.js

Propio de cada asignatura:
- js/sf-config.js  -> `modulo`, y si hace falta `menu`, `cta`, `inicioHref`.

Uso en cada página:
<head>
  <link rel="stylesheet" href="css/sf-layout.css">
  <script src="js/sf-config.js"></script>
  <script src="js/sf-layout.js" defer></script>
</head>
<body class="sf-body">
  <div id="sf-header"></div>
  <main> ... </main>
  <div id="sf-footer"></div>
</body>

Funciona abriendo el HTML con doble clic (sin servidor).
