/* Siluetas SVG de los 6 modelos SPEAKE (vista lateral, puntera a la izquierda
   como en las fotos del catálogo; viewBox 620x290).

   Cada modelo tiene una lista de capas que se dibujan en orden:
     { p: "cuerpo" | "franja" | "puntera" | "talon" | "suela" | "acento", d }
         -> se rellena con el color elegido para esa parte
     { p: "cordones" }          -> momento en que se dibujan los cordones (lazos)
     { p: "fijo", d, fill }     -> detalle de color fijo (forro, agujeros de la suela...)
     { p: "linea", d }          -> costuras y trazos decorativos

   lazos: cada tramo de cordón es una línea desde (x + a) hasta (x + b),
   repetida n veces avanzando dx, dy.
   textoY: altura del texto grabado en la suela. */
(function () {
  // Rectángulo con extremos redondos (cámaras de aire)
  const pastilla = (x, y, w, h) => {
    const r = h / 2;
    return `M${x + r} ${y} h${w - h} a${r} ${r} 0 0 1 0 ${h} h${h - w} a${r} ${r} 0 0 1 0 ${-h} Z`;
  };

  // Elipse (huecos de la mediasuela)
  const elipse = (cx, cy, rx, ry) =>
    `M${cx - rx} ${cy} a${rx} ${ry} 0 1 0 ${2 * rx} 0 a${rx} ${ry} 0 1 0 ${-2 * rx} 0 Z`;

  const FORRO = "#0b0e14";

  /* ---------- Formas comunes ---------- */

  // Zapatilla baja (court, street): puntera redonda, lengüeta y cuello bajo
  const BAJA =
    "M36 212 C22 192 40 172 86 168 C140 162 190 150 228 140 L316 98 " +
    "C324 86 340 82 350 88 C378 108 418 118 456 116 C492 114 512 98 536 94 " +
    "C566 90 580 104 584 130 C590 160 590 190 588 212 Z";
  const BAJA_FORRO =
    "M350 88 C378 108 418 118 456 116 C492 114 512 98 536 94 " +
    "C512 106 490 108 456 108 C420 108 388 102 350 88 Z";
  const BAJA_TALON =
    "M494 212 C486 168 494 126 516 98 C524 96 530 94 536 94 " +
    "C566 90 580 104 584 130 C590 160 590 190 588 212 Z";

  // Running (pulse, retro, aero): puntera más afilada y talón algo más alto
  const RUNNING =
    "M36 214 C20 196 36 176 80 172 C140 166 196 154 236 136 L322 90 " +
    "C330 78 346 74 356 80 C384 102 424 110 458 106 C494 102 516 82 540 78 " +
    "C568 74 584 90 586 120 C588 160 588 190 586 214 Z";
  const RUNNING_FORRO =
    "M356 80 C384 102 424 110 458 106 C494 102 516 82 540 78 " +
    "C516 92 492 98 458 98 C424 100 390 94 356 80 Z";
  const RUNNING_TALON =
    "M500 214 C494 168 500 118 522 82 C528 80 534 78 540 78 " +
    "C568 74 584 90 586 120 C588 160 588 190 586 214 Z";
  const RUNNING_PESTANA =
    "M546 76 C566 72 580 80 582 96 L584 128 C576 128 572 122 570 114 L564 88 C560 82 554 80 546 80 Z";

  const lazos = (x0, y0, n, dx, dy) => [{ x0, y0, n, dx, dy, a: [-8, -8], b: [10, 6] }];

  window.SPEAKE_FORMAS = {
    /* COURT · baloncesto clásico bajo, piel blanca, suela de copa y pestaña azul */
    court: {
      textoY: 246,
      lazos: lazos(240, 150, 5, 18, -10),
      capas: [
        { p: "cuerpo", d: BAJA },
        { p: "fijo", d: BAJA_FORRO, fill: FORRO },
        {
          p: "puntera",
          d: "M36 212 C22 192 40 172 86 168 C114 165 140 162 162 160 C176 180 174 198 168 212 Z",
        },
        { p: "talon", d: BAJA_TALON },
        {
          p: "franja",
          d: "M228 140 L316 98 C320 94 326 92 332 94 L338 102 L244 154 C238 156 232 154 228 150 Z",
        },
        {
          p: "acento",
          d: "M548 92 C570 92 584 106 586 128 L588 160 C578 160 574 152 572 144 L566 112 C562 102 556 98 548 98 Z",
        },
        { p: "acento", d: "M522 150 L542 142 L532 156 L548 152 L524 168 L531 157 L518 161 Z" },
        {
          p: "linea",
          d: "M164 170 C174 186 172 200 168 210 M496 210 C488 168 496 128 516 100 M180 196 C300 176 400 172 494 176",
        },
        {
          p: "linea",
          d: "M66 198 h1 M80 194 h1 M94 191 h1 M108 188 h1 M74 206 h1 M88 202 h1 M102 199 h1",
        },
        { p: "cordones" },
        {
          p: "suela",
          d: "M30 210 H580 Q594 210 594 226 V244 Q594 258 578 258 H60 Q34 258 26 238 Q22 222 30 210 Z",
        },
        { p: "linea", d: "M40 222 H584 M34 250 H588" },
      ],
    },

    /* PULSE · running con cámaras de aire visibles y refuerzos en forma de ola */
    pulse: {
      textoY: 252,
      lazos: lazos(248, 144, 5, 18, -11),
      capas: [
        { p: "cuerpo", d: RUNNING },
        { p: "fijo", d: RUNNING_FORRO, fill: FORRO },
        {
          p: "puntera",
          d: "M36 214 C20 196 36 176 80 172 C102 170 120 169 136 168 C126 188 128 204 132 214 Z",
        },
        { p: "talon", d: RUNNING_TALON },
        {
          p: "franja",
          d:
            "M110 206 C130 186 170 172 214 166 C180 180 150 192 124 208 Z " +
            "M180 206 C210 176 250 152 300 136 C262 160 228 182 196 208 Z " +
            "M260 206 C292 168 334 136 384 116 C342 146 306 176 278 208 Z " +
            "M344 206 C374 164 418 128 466 104 C428 136 392 170 362 208 Z " +
            "M428 206 C452 164 492 124 536 98 C504 130 474 168 448 208 Z " +
            "M60 196 C96 186 136 182 176 182 C140 188 100 194 72 202 Z",
        },
        { p: "acento", d: RUNNING_PESTANA },
        { p: "cordones" },
        {
          p: "suela",
          d: "M26 212 C40 200 70 200 100 202 L540 196 C580 194 594 206 594 224 L592 240 C590 254 580 258 566 258 H64 C40 258 26 246 24 232 C22 222 22 216 26 212 Z",
        },
        {
          p: "fijo",
          d: "M26 246 C30 254 44 258 64 258 H566 C580 258 588 254 591 246 Z",
          fill: FORRO,
        },
        { p: "acento", d: pastilla(64, 212, 54, 16) },
        { p: "acento", d: pastilla(126, 212, 54, 16) },
        { p: "acento", d: pastilla(188, 211, 54, 16) },
        { p: "acento", d: pastilla(400, 208, 64, 18) },
        { p: "acento", d: pastilla(474, 204, 96, 24) },
      ],
    },

    /* HIGH · bota de baloncesto con cuello alto, guardabarros y talón negros */
    high: {
      textoY: 246,
      lazos: lazos(236, 140, 7, 12, -14),
      capas: [
        {
          p: "cuerpo",
          d:
            "M36 212 C22 192 40 172 86 168 C140 162 190 150 228 140 L302 56 " +
            "C306 42 310 32 318 28 C334 20 352 24 362 34 C400 38 468 28 516 20 " +
            "C550 16 572 26 578 52 C588 100 590 160 588 212 Z",
        },
        { p: "fijo", d: "M318 28 C334 20 352 24 362 34 C346 32 330 34 318 38 Z", fill: FORRO },
        {
          p: "puntera",
          d: "M36 212 C22 192 40 172 86 168 C114 165 138 164 158 164 C192 164 230 172 252 186 C266 196 276 204 282 212 Z",
        },
        {
          p: "talon",
          d:
            "M462 212 C454 170 466 132 496 112 C522 96 540 72 546 44 C550 30 552 22 550 18 " +
            "C566 20 574 30 578 52 C588 100 590 160 588 212 Z " +
            "M362 34 C400 38 468 28 516 20 C540 16 552 18 550 22 C544 56 526 82 500 98 C470 84 436 76 404 62 C386 54 372 44 362 34 Z",
        },
        {
          p: "franja",
          d: "M228 140 L302 56 C306 50 312 48 318 50 L322 58 L248 154 C240 158 232 156 228 150 Z",
        },
        {
          p: "acento",
          d: "M408 70 L430 60 C434 58 438 62 436 66 L428 76 L404 84 C400 86 396 82 400 78 Z",
        },
        { p: "linea", d: "M282 210 C276 200 262 190 248 186 M464 210 C456 170 468 134 498 114" },
        { p: "cordones" },
        {
          p: "suela",
          d: "M30 212 H580 Q592 212 592 228 V244 Q592 258 576 258 H58 Q34 258 26 240 Q22 224 30 212 Z",
        },
        { p: "acento", d: pastilla(508, 228, 64, 12) },
        { p: "linea", d: "M38 224 H496" },
      ],
    },

    /* RETRO · running de los 90 con capas de ante y malla y mediasuela robusta */
    retro: {
      textoY: 236,
      lazos: lazos(248, 144, 5, 18, -11),
      capas: [
        { p: "cuerpo", d: RUNNING },
        { p: "fijo", d: RUNNING_FORRO, fill: FORRO },
        {
          p: "puntera",
          d: "M36 214 C20 196 36 176 80 172 C112 169 140 166 162 165 C172 186 170 204 166 214 Z",
        },
        { p: "talon", d: RUNNING_TALON },
        {
          p: "franja",
          d:
            "M166 214 C182 184 226 166 282 160 L330 156 C290 176 270 194 262 214 Z " +
            "M280 214 C300 176 352 150 414 140 L462 136 C412 162 384 188 376 214 Z " +
            "M236 136 L322 90 C326 86 332 84 338 86 L342 94 L252 154 C244 156 238 154 236 150 Z",
        },
        { p: "acento", d: RUNNING_PESTANA },
        { p: "linea", d: "M166 176 C172 190 170 204 166 212 M502 212 C496 168 502 120 524 84" },
        { p: "cordones" },
        {
          p: "suela",
          d: "M26 212 C40 198 70 198 110 200 L548 194 C584 192 594 206 594 222 L592 240 C590 254 580 258 566 258 H64 C40 258 26 246 24 232 C22 222 22 216 26 212 Z",
        },
        {
          p: "fijo",
          d: "M25 244 C28 254 42 258 64 258 H566 C580 258 588 254 592 244 Z",
          fill: "#2a2f38",
        },
        { p: "acento", d: "M410 226 C470 210 530 204 580 206 C540 214 490 226 446 240 Z" },
        { p: "acento", d: "M150 232 C190 222 236 218 272 218 C238 224 200 232 168 240 Z" },
      ],
    },

    /* STREET · skate de ante con suela vulcanizada plana y gruesa */
    street: {
      textoY: 244,
      lazos: lazos(240, 150, 5, 18, -10),
      capas: [
        { p: "cuerpo", d: BAJA },
        { p: "fijo", d: BAJA_FORRO, fill: FORRO },
        {
          p: "puntera",
          d: "M36 212 C22 192 40 172 86 168 C110 165 132 163 150 162 C164 182 162 200 156 212 Z",
        },
        { p: "talon", d: BAJA_TALON },
        { p: "franja", d: "M180 212 C200 180 250 166 312 160 L392 154 C346 172 326 192 318 212 Z" },
        {
          p: "acento",
          d: "M546 92 C568 92 582 106 584 128 L586 160 C576 160 572 152 570 144 L564 112 C560 102 554 98 546 98 Z",
        },
        { p: "acento", d: elipse(360, 112, 6, 6) },
        {
          p: "linea",
          d: "M152 174 C162 188 160 202 156 210 M58 194 C90 186 120 180 148 176 M496 210 C488 168 496 128 516 100",
        },
        { p: "cordones" },
        {
          p: "suela",
          d: "M28 210 H584 Q596 210 596 224 V246 Q596 258 582 258 H42 Q26 258 26 244 V224 Q26 210 40 210 Z",
        },
        { p: "linea", d: "M30 222 H592" },
      ],
    },

    /* AERO · running de punto con mediasuela esculpida y huecos laterales */
    aero: {
      textoY: 252,
      lazos: lazos(248, 144, 5, 18, -11),
      capas: [
        { p: "cuerpo", d: RUNNING },
        { p: "fijo", d: RUNNING_FORRO, fill: FORRO },
        {
          p: "puntera",
          d: "M36 214 C20 196 36 176 80 172 C102 170 120 169 136 168 C126 188 128 204 132 214 Z",
        },
        { p: "talon", d: RUNNING_TALON },
        {
          p: "franja",
          d:
            "M96 200 C200 186 320 156 430 112 L470 98 C404 140 300 178 160 202 Z " +
            "M300 208 C400 182 480 150 548 116 L566 118 C496 164 410 196 350 212 Z",
        },
        { p: "acento", d: RUNNING_PESTANA },
        { p: "cordones" },
        {
          p: "suela",
          d: "M26 214 C34 198 70 198 110 200 L540 190 C584 188 596 204 596 222 L594 236 C590 254 576 258 556 258 H62 C38 258 24 246 22 232 C22 224 22 218 26 214 Z",
        },
        { p: "fijo", d: elipse(132, 222, 22, 6), fill: FORRO },
        { p: "fijo", d: elipse(202, 221, 26, 7), fill: FORRO },
        { p: "fijo", d: elipse(278, 220, 28, 7), fill: FORRO },
        { p: "fijo", d: elipse(358, 218, 28, 7), fill: FORRO },
        { p: "fijo", d: elipse(438, 215, 28, 8), fill: FORRO },
        { p: "fijo", d: elipse(516, 211, 26, 8), fill: FORRO },
      ],
    },
  };
})();
