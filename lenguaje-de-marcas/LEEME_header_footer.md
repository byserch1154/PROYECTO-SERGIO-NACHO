# Estructura común de las páginas (SPEAKE)

Todas las páginas usan los mismos tres ficheros:
- `css/estilos.css` → la única hoja de estilos de la web (general + header/footer + reglas de cada página)
- `js/sf-config.js` → menú, botón de la cabecera y nombre del módulo
- `js/sf-layout.js` → crea el header y el footer en todas las páginas

Plantilla de una página:
```html
<head>
  <link rel="stylesheet" href="css/estilos.css">
  <script src="js/sf-config.js"></script>
  <script src="js/sf-layout.js" defer></script>
</head>
<body class="sf-body pagina-nombre">
  <div id="sf-header"></div>
  <main> ... </main>
  <div id="sf-footer"></div>
</body>
```

Los estilos propios de una página van en `css/estilos.css`, dentro de su sección y empezando por
`.pagina-nombre` (por ejemplo `.pagina-contacto .formulario`), para que no afecten a las demás.
No se usan `<style>` ni atributos `style=""` en el HTML.
