"""Genera las fotos de los colores de catálogo a partir de la foto original de cada modelo.

Las fotos originales tienen los detalles en azul. Para cada combinación se cambia ese azul por el
color nuevo (también la luz azul del fondo, para que parezca una foto de estudio con otra luz).
Uso (desde lenguaje-de-marcas):  python herramientas/recolorear_fotos.py
Requiere: pip install pillow numpy
"""
from pathlib import Path

import numpy as np
from PIL import Image

IMG = Path(__file__).resolve().parents[1] / "img"

# Tono en la escala de Pillow (0-255) y ajuste de brillo para cada color
TONOS = {
    "rojo": (253, 1.0, 1.05),
    "naranja": (13, 1.0, 1.15),
    "amarillo": (33, 0.95, 1.4),
    "verde": (92, 0.85, 1.0),
}

# código del color de catálogo -> (foto original, color nuevo o None si es la original)
COLORES = {
    "court-blanco-azul": ("court", None),
    "court-blanco-rojo": ("court", "rojo"),
    "court-blanco-verde": ("court", "verde"),
    "pulse-negro-azul": ("pulse", None),
    "pulse-negro-naranja": ("pulse", "naranja"),
    "pulse-negro-verde": ("pulse", "verde"),
    "high-blanco-azul": ("high", None),
    "high-blanco-rojo": ("high", "rojo"),
    "high-blanco-amarillo": ("high", "amarillo"),
    "retro-gris-azul": ("retro", None),
    "retro-gris-naranja": ("retro", "naranja"),
    "retro-gris-verde": ("retro", "verde"),
    "street-negro-azul": ("street", None),
    "street-negro-rojo": ("street", "rojo"),
    "street-negro-verde": ("street", "verde"),
    "aero-negro-azul": ("aero", None),
    "aero-negro-amarillo": ("aero", "amarillo"),
    "aero-negro-rojo": ("aero", "rojo"),
}


def recolorear(foto: Image.Image, tono: int, sat: float, brillo: float) -> Image.Image:
    rgb = foto.convert("RGB")
    hsv = np.array(rgb.convert("HSV")).astype(np.float32)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]

    # Cuánto "azul" tiene cada píxel (0 a 1), sin cortes bruscos
    peso = np.clip(1 - np.abs(h - 160) / 30, 0, 1) ** 0.5 * np.clip((s - 30) / 60, 0, 1)

    nueva = np.stack([np.full_like(h, tono), np.clip(s * sat, 0, 255), np.clip(v * brillo, 0, 255)], -1)
    nueva = np.array(Image.fromarray(nueva.astype(np.uint8), "HSV").convert("RGB")).astype(np.float32)

    # Mezcla en RGB: así los bordes no pasan por colores intermedios raros
    p = peso[..., None]
    mezcla = np.array(rgb).astype(np.float32) * (1 - p) + nueva * p
    return Image.fromarray(mezcla.astype(np.uint8))


def main():
    destino = IMG / "colores"
    destino.mkdir(exist_ok=True)
    for codigo, (modelo, color) in COLORES.items():
        foto = Image.open(IMG / f"{modelo}.jpg")
        if color:
            foto = recolorear(foto, *TONOS[color])
        foto.convert("RGB").save(destino / f"{codigo}.jpg", quality=88, optimize=True)
        print("ok", codigo)


if __name__ == "__main__":
    main()
