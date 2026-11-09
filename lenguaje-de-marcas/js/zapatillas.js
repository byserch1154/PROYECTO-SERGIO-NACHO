/* Siluetas SVG de los 6 modelos SPEAKE (vista lateral, viewBox 620x290).
   Cada modelo es una lista de "capas" que se dibujan en orden:
     { p: "cuerpo" | "franja" | "puntera" | "talon" | "suela" | "acento", d: "..." }  -> se rellena con el color elegido para esa parte
     { p: "cordones" }                                                              -> punto donde se dibujan los cordones
     { p: "fijo", d, fill }                                                         -> detalle de color fijo (no editable)
     { p: "linea", d }                                                              -> costura / trazo decorativo
   Las partes editables son las mismas en todos los modelos, pero cada modelo las
   usa en zonas distintas para parecerse a su foto del catálogo. */
(function () {
  const pill = (x, y, w, h) => {
    const r = h / 2;
    return "M" + (x + r) + " " + y + " h" + (w - h) + " a" + r + " " + r + " 0 0 1 0 " + h +
           " h" + (-(w - h)) + " a" + r + " " + r + " 0 0 1 0 " + (-h) + " Z";
  };
  const ell = (cx, cy, rx, ry) =>
    "M" + (cx - rx) + " " + cy + " a" + rx + " " + ry + " 0 1 0 " + (2 * rx) + " 0 a" + rx + " " + ry + " 0 1 0 " + (-2 * rx) + " 0 Z";

  /* Cuerpo base con cuello y lengüeta: sy = y de la suela, hy = y del talón, ty = y de la lengüeta */
  const base = (sy, hy, ty) => [
    { p: "fijo",  d: "M86 " + (hy - 4) + " Q124 " + (hy - 14) + " 190 " + (ty + 4) + " L192 " + (ty + 8) + " Q140 " + (hy + 22) + " 110 " + hy + " Z", fill: "#0b0e14" },
    { p: "cuerpo", d: "M64 " + sy + " L58 " + (hy + 26) + " Q58 " + hy + " 84 " + (hy - 2) + " L110 " + hy + " Q140 " + (hy + 22) + " 176 " + (hy + 16) +
                    " L192 " + (ty + 8) + " Q204 " + ty + " 216 " + (ty + 12) + " L234 154 L330 162 Q440 166 508 " + (sy - 18) + " Q544 " + (sy - 6) + " 556 " + sy + " Z" },
    { p: "talon",  d: "M64 " + sy + " L58 " + (hy + 26) + " Q58 " + hy + " 84 " + (hy - 2) + " L110 " + hy + " Q124 " + (hy + 12) + " 132 " + (hy + 34) + " L126 " + sy + " Z" }
  ];

  window.SPEAKE_FORMAS = {

    /* COURT · cancha clásica, suela plana y gruesa */
    court: {
      textoY: 244,
      lazos: [{ x0: 226, y0: 152, n: 5, dx: 26, dy: 2, a: [0, -16], b: [9, 5] }],
      capas: [
        ...base(212, 100, 82),
        { p: "puntera", d: "M436 170 Q508 182 548 202 L556 212 L414 212 Z" },
        { p: "franja",  d: "M240 158 L336 164 Q352 188 356 212 L250 212 Q238 190 240 158 Z" },
        { p: "linea",   d: "M470 190 l7 3 M486 197 l7 3 M456 197 l7 3 M472 204 l7 3 M126 150 L64 152" },
        { p: "acento",  d: "M60 122 Q60 102 84 100 L104 100 L108 134 L62 142 Z" },
        { p: "acento",  d: ell(208, 128, 8, 8) },
        { p: "cordones" },
        { p: "suela",   d: "M46 212 L556 212 Q578 216 575 238 Q572 262 546 262 L74 262 Q46 262 46 238 Z" },
        { p: "linea",   d: "M70 236 L548 236" }
      ]
    },

    /* PULSE · malla negra con bandas onduladas y cámaras de aire */
    pulse: {
      textoY: 254,
      lazos: [{ x0: 226, y0: 148, n: 5, dx: 24, dy: 1.5, a: [0, -16], b: [9, 5] }],
      capas: [
        ...base(228, 90, 74),
        { p: "puntera", d: "M444 164 Q514 178 550 204 L552 224 L424 224 Z" },
        { p: "franja",  d: "M150 218 C186 160 232 160 254 190 C266 208 292 192 304 170 C320 142 362 150 374 178 C386 204 422 194 446 176 L452 192 C424 214 380 222 360 196 C350 176 332 172 322 192 C300 220 250 226 236 204 C224 184 202 186 172 222 Z" },
        { p: "acento",  d: "M470 188 Q510 198 536 216 L530 218 Q504 204 466 194 Z" },
        { p: "acento",  d: "M330 170 q24 -12 44 4 q-24 -2 -44 -4 Z" },
        { p: "cordones" },
        { p: "suela",   d: "M46 228 L550 222 Q574 226 572 242 Q568 262 540 264 L84 264 Q46 264 46 244 Z" },
        { p: "acento",  d: pill(118, 238, 54, 20) },
        { p: "acento",  d: pill(190, 240, 54, 20) },
        { p: "acento",  d: pill(262, 240, 54, 20) },
        { p: "acento",  d: pill(334, 238, 54, 20) },
        { p: "acento",  d: pill(406, 234, 52, 20) }
      ]
    },

    /* HIGH · caña alta, paneles contrastados y ventana de aire en el talón */
    high: {
      textoY: 244,
      lazos: [
        { x0: 228, y0: 156, n: 5, dx: 26, dy: 2, a: [0, -16], b: [9, 5] },
        { x0: 199, y0: 72, n: 5, dx: 3.5, dy: 17.5, a: [-14, -4], b: [6, 6] }
      ],
      capas: [
        ...base(214, 22, 6),
        { p: "puntera", d: "M432 170 Q504 182 546 204 L552 214 L408 214 Z" },
        { p: "franja",  d: "M128 170 C190 182 260 172 330 168 C390 170 430 184 470 206 L470 214 L128 214 Z" },
        { p: "linea",   d: "M130 110 L196 70" },
        { p: "acento",  d: "M166 82 l18 -14 l5 22 l-16 7 Z" },
        { p: "cordones" },
        { p: "suela",   d: "M46 214 L552 214 Q576 218 574 240 Q570 262 544 262 L74 262 Q46 262 46 240 Z" },
        { p: "acento",  d: pill(62, 230, 70, 22) },
        { p: "linea",   d: "M150 238 L540 238" }
      ]
    },

    /* RETRO · capas de ante y malla, suela robusta */
    retro: {
      textoY: 254,
      lazos: [{ x0: 222, y0: 152, n: 5, dx: 24, dy: 1.5, a: [0, -16], b: [9, 5] }],
      capas: [
        ...base(214, 98, 84),
        { p: "puntera", d: "M436 168 Q506 180 546 202 L552 214 L412 214 Z" },
        { p: "franja",  d: "M200 132 L330 158 Q384 164 424 178 L384 212 L214 212 Q188 180 200 132 Z" },
        { p: "linea",   d: "M246 178 q20 -10 40 2 M262 194 q20 -10 40 2 M300 170 q18 -8 34 2" },
        { p: "acento",  d: "M62 104 L60 72 Q60 62 74 64 L86 100 Z" },
        { p: "acento",  d: "M62 192 L122 186 L124 214 L62 214 Z" },
        { p: "cordones" },
        { p: "suela",   d: "M44 214 L552 206 Q580 212 576 238 Q570 262 540 264 L80 264 Q42 262 44 238 Z" },
        { p: "acento",  d: "M168 216 Q230 178 264 198 Q284 208 268 216 Z" },
        { p: "acento",  d: "M470 216 Q522 214 548 198 L552 216 Z" },
        { p: "linea",   d: "M110 242 q40 -10 90 2 t110 0 t120 -4" }
      ]
    },

    /* STREET · skate de ante, suela vulcanizada y lengüeta alta */
    street: {
      textoY: 252,
      lazos: [{ x0: 228, y0: 154, n: 5, dx: 26, dy: 2, a: [0, -16], b: [9, 5] }],
      capas: [
        ...base(220, 90, 64),
        { p: "puntera", d: "M440 172 Q510 184 548 208 L554 220 L416 220 Z" },
        { p: "franja",  d: "M248 160 L332 162 Q346 190 350 220 L256 220 Q244 190 248 160 Z" },
        { p: "linea",   d: "M232 160 L338 166 M250 178 L342 184" },
        { p: "fijo",    d: "M160 70 L196 64 L200 84 L164 90 Z", fill: "#f5f7fa" },
        { p: "acento",  d: "M62 100 Q62 90 80 88 L108 87 L110 122 L62 126 Z" },
        { p: "acento",  d: ell(208, 124, 8, 8) },
        { p: "cordones" },
        { p: "suela",   d: "M44 220 L554 220 Q576 222 574 242 Q572 262 548 262 L74 262 Q44 262 44 242 Z" },
        { p: "linea",   d: "M60 238 L558 238" }
      ]
    },

    /* AERO · malla ligera, gran trazo lateral y suela con huecos */
    aero: {
      textoY: 256,
      lazos: [{ x0: 224, y0: 146, n: 5, dx: 24, dy: 1.5, a: [0, -16], b: [9, 5] }],
      capas: [
        ...base(230, 90, 76),
        { p: "puntera", d: "M440 164 Q510 176 548 198 L556 214 L430 222 Z" },
        { p: "franja",  d: "M110 222 C190 186 300 150 440 156 C400 170 330 184 260 214 C220 230 160 236 110 222 Z" },
        { p: "acento",  d: "M456 170 Q498 178 530 198 L526 202 Q496 186 452 176 Z" },
        { p: "acento",  d: "M66 98 Q54 64 80 58 Q98 62 92 92 Z" },
        { p: "cordones" },
        { p: "suela",   d: "M44 232 Q60 226 120 232 L330 238 Q450 236 520 206 Q560 190 576 214 Q580 250 540 262 L120 264 Q44 264 44 240 Z" },
        { p: "fijo",    d: ell(190, 250, 26, 9), fill: "#0d1118" },
        { p: "fijo",    d: ell(262, 252, 26, 9), fill: "#0d1118" },
        { p: "fijo",    d: ell(334, 250, 26, 9), fill: "#0d1118" },
        { p: "fijo",    d: ell(406, 242, 24, 9), fill: "#0d1118" }
      ]
    }
  };
})();
