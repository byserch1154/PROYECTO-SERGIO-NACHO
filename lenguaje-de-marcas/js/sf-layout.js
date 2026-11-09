/* =============================================================
   SPEAKE · HEADER Y FOOTER COMPARTIDOS  (sf-layout.js)
   -------------------------------------------------------------
   Inserta el mismo header y footer en todas las páginas sin
   fetch ni servidor: funciona abriendo el HTML con doble clic.
   Se copia IDÉNTICO a todas las asignaturas. Lo propio de cada
   módulo va en sf-config.js (window.SF_CONFIG).

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
============================================================= */
(function () {
  "use strict";

  if (window.__sfLayoutCargado) return; // evita duplicar header/footer
  window.__sfLayoutCargado = true;

  var DEFAULTS = {
    marca: "SPEAKE",
    simbolo: "S",
    lema: "Tu estilo. Tus reglas.",
    modulo: "",
    legal: "Proyecto académico",
    inicioHref: "index.html",
    cta: { texto: "Explorar modelos", href: "catalogo.html" }, // null = sin botón
    menu: [
      { texto: "Inicio", href: "index.html" },
      { texto: "Catálogo", href: "catalogo.html" },
      { texto: "Personaliza", href: "personaliza.html" },
      { texto: "Contacto", href: "contacto.html" }
    ],
    fuentes: "" // URL opcional de Google Fonts
  };

  var cfg = Object.assign({}, DEFAULTS, window.SF_CONFIG || {});
  var BP = 860; // mismo punto de corte que sf-layout.css

  function el(tag, attrs, hijos) {
    var nodo = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) {
      if (k === "class") nodo.className = attrs[k];
      else if (k === "text") nodo.textContent = attrs[k];
      else nodo.setAttribute(k, attrs[k]);
    });
    (hijos || []).forEach(function (h) { if (h) nodo.appendChild(h); });
    return nodo;
  }

  function nombreFichero(href) {
    return String(href).split("#")[0].split("?")[0].split("/").pop().toLowerCase();
  }

  // Fichero actual; si la ruta termina en "/" se considera la página de inicio
  function paginaActual() {
    var ruta = "";
    try { ruta = decodeURIComponent(window.location.pathname || ""); }
    catch (e) { ruta = window.location.pathname || ""; }
    return ruta.split("/").pop().toLowerCase() || nombreFichero(cfg.inicioHref);
  }

  function cargarFuentes() {
    if (!cfg.fuentes || document.querySelector("link[data-sf-fuentes]")) return;
    document.head.appendChild(el("link", { rel: "stylesheet", href: cfg.fuentes, "data-sf-fuentes": "1" }));
  }

  function crearLogo() {
    return el("a", { class: "sf-logo", href: cfg.inicioHref, "aria-label": cfg.marca + ", inicio" }, [
      el("span", { class: "sf-logo__symbol", text: cfg.simbolo }),
      el("span", {}, [
        document.createTextNode(cfg.marca),
        el("span", { class: "sf-logo__dot", text: "." })
      ])
    ]);
  }

  function crearHeader() {
    var actual = paginaActual();
    var nav = el("nav", { class: "sf-nav", id: "sf-nav", "aria-label": "Navegación principal" });

    cfg.menu.forEach(function (item) {
      var a = el("a", { class: "sf-nav__link", href: item.href, text: item.texto });
      if (nombreFichero(item.href) === actual) a.setAttribute("aria-current", "page");
      nav.appendChild(a);
    });
    if (cfg.cta) {
      nav.appendChild(el("a", { class: "sf-nav__link sf-nav__cta-mobile", href: cfg.cta.href, text: cfg.cta.texto + " ↗" }));
    }

    var boton = el("button", {
      class: "sf-menu-btn", type: "button",
      "aria-label": "Abrir menú", "aria-expanded": "false", "aria-controls": "sf-nav"
    }, [
      el("span", { class: "sf-menu-btn__bar" }),
      el("span", { class: "sf-menu-btn__bar" }),
      el("span", { class: "sf-menu-btn__bar" })
    ]);

    function cerrar() {
      nav.classList.remove("sf-nav--open");
      boton.setAttribute("aria-expanded", "false");
      boton.setAttribute("aria-label", "Abrir menú");
    }
    boton.addEventListener("click", function () {
      var abierto = nav.classList.toggle("sf-nav--open");
      boton.setAttribute("aria-expanded", abierto ? "true" : "false");
      boton.setAttribute("aria-label", abierto ? "Cerrar menú" : "Abrir menú");
    });
    nav.addEventListener("click", function (e) {
      if (e.target.closest && e.target.closest("a")) cerrar();
    });
    document.addEventListener("keydown", function (e) { if (e.key === "Escape") cerrar(); });
    window.addEventListener("resize", function () { if (window.innerWidth > BP) cerrar(); });

    var cta = cfg.cta
      ? el("a", { class: "sf-cta", href: cfg.cta.href }, [
          document.createTextNode(cfg.cta.texto + " "),
          el("span", { "aria-hidden": "true", text: "↗" })
        ])
      : null;

    return el("header", { class: "sf-header" }, [
      el("div", { class: "sf-header__inner" }, [crearLogo(), nav, cta, boton])
    ]);
  }

  function crearFooter() {
    var nav = el("nav", { class: "sf-footer__nav", "aria-label": "Enlaces del pie" });
    cfg.menu.forEach(function (item) {
      nav.appendChild(el("a", { href: item.href, text: item.texto }));
    });
    nav.appendChild(el("a", { href: "#", "data-sf-top": "1", text: "Volver arriba ↑" }));
    nav.addEventListener("click", function (e) {
      var a = e.target.closest && e.target.closest("[data-sf-top]");
      if (!a) return;
      e.preventDefault();
      window.scrollTo({ top: 0, behavior: "smooth" });
    });

    var partes = ["© " + new Date().getFullYear() + " " + cfg.marca];
    if (cfg.legal) partes.push(cfg.legal);
    if (cfg.modulo) partes.push("Módulo: " + cfg.modulo);

    return el("footer", { class: "sf-footer" }, [
      crearLogo(),
      el("p", { class: "sf-footer__tagline", text: cfg.lema }),
      nav,
      el("small", { class: "sf-footer__legal" }, [
        el("span", { text: partes[0] }),
        el("span", { text: partes.slice(1).join(" · ") })
      ])
    ]);
  }

  function montar() {
    cargarFuentes();
    document.body.classList.add("sf-body");

    var main = document.querySelector("main");
    if (main) {
      if (!main.id) main.id = "contenido";
      main.setAttribute("tabindex", "-1");
      if (!document.querySelector(".sf-skip")) {
        document.body.insertBefore(
          el("a", { class: "sf-skip", href: "#" + main.id, text: "Saltar al contenido" }),
          document.body.firstChild
        );
      }
    }

    var ph = document.getElementById("sf-header");
    var header = crearHeader();
    if (ph) ph.replaceWith(header);
    else document.body.insertBefore(header, main || document.body.firstChild);

    var pf = document.getElementById("sf-footer");
    var footer = crearFooter();
    if (pf) pf.replaceWith(footer);
    else document.body.appendChild(footer);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", montar);
  else montar();
})();
