"""Exporta un pedido de venta de Odoo al formato ficha_fabricacion.csv que procesa PSP (Java).

    set ODOO_PASSWORD=...
    python exportar_pedido_odoo.py --url http://IP_VM:8069 --db speake --user admin --pedido SO003
    -> odoo/exportaciones/ficha_SO003_odoo.csv
    -> java\\psp\\ejecutar.bat ..\\..\\odoo\\exportaciones\\ficha_SO003_odoo.csv

Lee las líneas del pedido (variante de talla, cantidad y la descripción con la personalización)
y escribe las mismas columnas que la vista v_ficha_fabricacion de PostgreSQL. Así el
subsistema PSP puede procesar una copia del pedido sin tocar el ERP (solo lectura).
"""
from __future__ import annotations

import argparse
import csv
import os
import re
import sys
import xmlrpc.client
from pathlib import Path

COLUMNAS = ["referencia", "cliente", "modelo", "color_cuerpo", "color_franja", "color_puntera", "color_talon",
            "color_suela", "color_cordones", "texto_suela", "talla", "cantidad"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://localhost:8069")
    ap.add_argument("--db", default="speake")
    ap.add_argument("--user", default="admin")
    ap.add_argument("--pedido", default="SO003")
    ap.add_argument("--salida", type=Path, default=Path(__file__).resolve().parents[1] / "exportaciones")
    a = ap.parse_args()
    pw = os.environ.get("ODOO_PASSWORD") or sys.exit("Define ODOO_PASSWORD")
    comun = xmlrpc.client.ServerProxy(f"{a.url}/xmlrpc/2/common")
    uid = comun.authenticate(a.db, a.user, pw, {}) or sys.exit("Credenciales incorrectas")
    m = xmlrpc.client.ServerProxy(f"{a.url}/xmlrpc/2/object")

    def leer(modelo, dominio, campos):
        return m.execute_kw(a.db, uid, pw, modelo, "search_read", [dominio], {"fields": campos})

    # Se busca por la referencia común (SO003) o por el número propio de Odoo (S00007)
    so = leer("sale.order", ["|", ("client_order_ref", "=", a.pedido), ("name", "=", a.pedido)], ["id", "name", "partner_id", "state"])
    if not so:
        sys.exit(f"No existe el pedido {a.pedido} en Odoo")
    lineas = leer("sale.order.line", [("order_id", "=", so[0]["id"]), ("display_type", "=", False)],
                  ["product_id", "product_template_id", "product_uom_qty", "name"])
    a.salida.mkdir(parents=True, exist_ok=True)
    destino = a.salida / f"ficha_{a.pedido}_odoo.csv"
    with open(destino, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(COLUMNAS)
        for l in lineas:
            talla = re.search(r"Talla (\d{2})", l["name"]) or re.search(r"\((\d{2})\)", l["product_id"][1])
            pers = re.search(r"Personalización: ([^|]+)", l["name"])
            texto = re.search(r"Texto: (\S*)", l["name"])
            colores = [c.strip() for c in pers.group(1).split("/")] if pers else [""] * 6
            # "SPEAKE PULSE CUSTOM" (Odoo) -> "SPEAKE Pulse" (mismo nombre que en PostgreSQL)
            base = re.sub(r"\s+custom$", "", l["product_template_id"][1].strip(), flags=re.I).split()
            modelo = " ".join([base[0].upper()] + [w.capitalize() for w in base[1:]])
            w.writerow([a.pedido, so[0]["partner_id"][1], modelo, *colores[:6],
                        texto.group(1) if texto else "", talla.group(1) if talla else "", int(l["product_uom_qty"])])
    print(f"Exportado {destino} · pedido Odoo {so[0]['name']} · {len(lineas)} líneas · estado: {so[0]['state']}")


if __name__ == "__main__":
    main()
