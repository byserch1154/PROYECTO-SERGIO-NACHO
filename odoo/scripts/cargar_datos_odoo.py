"""Carga en Odoo los datos de SPEAKE mediante la API XML-RPC (solo librería estándar).

Crea (si no existen): atributo Talla 38-46, los 6 modelos SPEAKE con variantes de talla,
componentes, listas de materiales, rutas Fabricar + MTO para los productos Custom,
los clientes ficticios, la oportunidad CRM y el pedido de venta SO003 del caso común
(Club Halcones · SPEAKE Pulse Custom · 40 pares · tallas 38-46).

Uso (la contraseña NUNCA va en el código ni en el repositorio):
    set ODOO_PASSWORD=la_de_tu_admin
    python cargar_datos_odoo.py --url http://IP_DE_LA_VM:8069 --db speake --user admin
    python cargar_datos_odoo.py ... --confirmar       # además confirma SO003 (genera la OF por MTO)

Compatible con Odoo 17, 18 y 19 (detecta la versión para el tipo de producto almacenable).
El pedido se crea con la numeración propia de Odoo (S000xx) y Referencia del cliente = SO003.
Es idempotente: si se ejecuta dos veces no duplica registros (busca por nombre/referencia).
"""
from __future__ import annotations

import argparse
import csv
import os
import sys
import xmlrpc.client
from pathlib import Path

RAIZ = Path(__file__).resolve().parents[2]
FICHA = RAIZ / "java" / "untitled" / "datos" / "ficha_fabricacion.csv"

MODELOS = [  # nombre, categoría, precio base (iguales a PostgreSQL y a la web)
    ("SPEAKE Court", "Urbano", 89), ("SPEAKE Pulse", "Deportivo", 109), ("SPEAKE High", "Baloncesto", 99),
    ("SPEAKE Retro", "Retro", 95), ("SPEAKE Street", "Street", 92), ("SPEAKE Aero", "Running", 105),
]
COMPONENTES = [("Corte (upper) SPEAKE", 18), ("Suela SPEAKE", 9), ("Cordones SPEAKE", 1.5),
               ("Plantilla SPEAKE", 2.5), ("Kit de personalización (tintes + serigrafía)", 6)]
CLIENTES = [("Ana García", "ana.garcia@example.com", False), ("Club Halcones", "info@halcones.example.com", True),
            ("Pedro Ruiz", "pedro.ruiz@example.com", False), ("Peña Los Linces", "linces@example.com", True),
            ("Marta Sánchez", "marta.s@example.com", False), ("Escuela Deportiva Norte", "escuela@norte.example.com", True)]
TALLAS = [str(t) for t in range(38, 47)]
EXTRA_CUSTOM, EXTRA_TEXTO = 15, 5


class Odoo:
    def __init__(self, url, db, user, password):
        self.db, self.password = db, password
        comun = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/common", allow_none=True)
        self.version = int(str(comun.version()["server_version_info"][0]))
        self.uid = comun.authenticate(db, user, password, {})
        if not self.uid:
            sys.exit("ERROR: usuario o contraseña de Odoo incorrectos")
        self.m = xmlrpc.client.ServerProxy(f"{url}/xmlrpc/2/object", allow_none=True)

    def call(self, modelo, metodo, *args, **kw):
        return self.m.execute_kw(self.db, self.uid, self.password, modelo, metodo, list(args), kw)

    def buscar(self, modelo, dominio, **kw):
        return self.call(modelo, "search", dominio, **kw)

    def obtener_o_crear(self, modelo, dominio, valores):
        ids = self.buscar(modelo, dominio, limit=1)
        if ids:
            return ids[0], False
        return self.call(modelo, "create", valores), True


def tipo_almacenable(o: Odoo) -> dict:
    # Odoo 17: type='product'; Odoo 18: type='consu' + is_storable=True
    return {"type": "consu", "is_storable": True} if o.version >= 18 else {"type": "product"}


def ruta(o: Odoo, nombre_parcial: str) -> int | None:
    ids = o.call("stock.route", "search", [("name", "ilike", nombre_parcial)], context={"active_test": False}, limit=1)
    if ids:
        o.call("stock.route", "write", ids, {"active": True})   # la ruta MTO viene archivada por defecto
        return ids[0]
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://localhost:8069")
    ap.add_argument("--db", default="speake")
    ap.add_argument("--user", default="admin")
    ap.add_argument("--confirmar", action="store_true", help="confirmar SO003 tras crearlo")
    a = ap.parse_args()
    password = os.environ.get("ODOO_PASSWORD")
    if not password:
        sys.exit("Define la variable de entorno ODOO_PASSWORD (no se guardan contraseñas en el código)")
    o = Odoo(a.url, a.db, a.user, password)
    print(f"Conectado a Odoo {o.version} · uid={o.uid}")

    # ---------------------------------------------------------- atributo Talla
    attr, _ = o.obtener_o_crear("product.attribute", [("name", "=", "Talla")],
                                {"name": "Talla", "create_variant": "always", "display_type": "select"})
    valores = {}
    for t in TALLAS:
        valores[t], _ = o.obtener_o_crear("product.attribute.value", [("attribute_id", "=", attr), ("name", "=", t)],
                                          {"attribute_id": attr, "name": t})

    # ---------------------------------------------------------- categorías y componentes
    cat_prod, _ = o.obtener_o_crear("product.category", [("name", "=", "SPEAKE · Zapatillas")], {"name": "SPEAKE · Zapatillas"})
    cat_comp, _ = o.obtener_o_crear("product.category", [("name", "=", "SPEAKE · Componentes")], {"name": "SPEAKE · Componentes"})
    componentes = {}
    for nombre, coste in COMPONENTES:
        tmpl, _ = o.obtener_o_crear("product.template", [("name", "=", nombre)],
                                    {"name": nombre, "categ_id": cat_comp, "standard_price": coste, "sale_ok": False,
                                     "purchase_ok": True, **tipo_almacenable(o)})
        componentes[nombre] = o.buscar("product.product", [("product_tmpl_id", "=", tmpl)], limit=1)[0]

    r_fabricar = ruta(o, "Fabricar") or ruta(o, "Manufacture")
    r_mto = ruta(o, "MTO") or ruta(o, "Make To Order") or ruta(o, "sobre pedido")
    if not r_fabricar:
        print("AVISO: no se encontró la ruta Fabricar (¿está instalada la app Fabricación?)")

    # ---------------------------------------------------------- productos (estándar y Custom)
    plantillas = {}
    for nombre, categoria, precio in MODELOS:
        for custom in (False, True):
            nom = f"{nombre} Custom" if custom else nombre
            rutas = [r for r in ([r_fabricar, r_mto] if custom else [r_fabricar]) if r]
            tmpl, nuevo = o.obtener_o_crear("product.template", [("name", "=", nom)], {
                "name": nom, "categ_id": cat_prod, "list_price": precio + (EXTRA_CUSTOM if custom else 0),
                "sale_ok": True, "purchase_ok": False, "description_sale": f"Modelo {categoria}" + (" personalizado" if custom else ""),
                "route_ids": [(6, 0, rutas)], **tipo_almacenable(o),
                "attribute_line_ids": [(0, 0, {"attribute_id": attr, "value_ids": [(6, 0, list(valores.values()))]})],
            })
            plantillas[nom] = tmpl
            if nuevo:  # lista de materiales para la plantilla (vale para todas las tallas)
                lineas = [(0, 0, {"product_id": componentes[c], "product_qty": 1}) for c, _ in COMPONENTES[:4]]
                if custom:
                    lineas.append((0, 0, {"product_id": componentes[COMPONENTES[4][0]], "product_qty": 1}))
                o.call("mrp.bom", "create", {"product_tmpl_id": tmpl, "product_qty": 1, "type": "normal", "bom_line_ids": lineas})
                print("  + producto", nom)

    # ---------------------------------------------------------- clientes
    clientes = {}
    for nombre, email, empresa in CLIENTES:
        clientes[nombre], _ = o.obtener_o_crear("res.partner", [("email", "=", email)],
                                                {"name": nombre, "email": email, "is_company": empresa, "customer_rank": 1})

    # ---------------------------------------------------------- caso común: SO003
    if not FICHA.exists():
        sys.exit(f"No se encuentra {FICHA}")
    with open(FICHA, encoding="utf-8") as f:
        filas = [r for r in csv.DictReader(f) if r["referencia"] == "SO003"]
    if o.buscar("sale.order", [("client_order_ref", "=", "SO003")]):
        print("SO003 ya existe en Odoo: no se duplica")
    else:
        tmpl = plantillas[f"{filas[0]['modelo']} Custom"]
        variantes = o.call("product.product", "search_read", [("product_tmpl_id", "=", tmpl)],
                           fields=["id", "product_template_attribute_value_ids"])
        ptav = o.call("product.template.attribute.value", "search_read", [("product_tmpl_id", "=", tmpl)], fields=["id", "name"])
        talla_de = {p["id"]: p["name"] for p in ptav}
        variante_por_talla = {talla_de[v["product_template_attribute_value_ids"][0]]: v["id"] for v in variantes}
        precio = next(p for n, _, p in MODELOS if n == filas[0]["modelo"]) + EXTRA_CUSTOM + (EXTRA_TEXTO if filas[0]["texto_suela"] else 0)
        colores = "/".join(filas[0][c] for c in ["color_cuerpo", "color_franja", "color_puntera", "color_talon", "color_suela", "color_cordones"])
        total = sum(int(r["cantidad"]) for r in filas)
        cliente = clientes[filas[0]["cliente"]]
        crm_instalado = o.call("ir.module.module", "search_count", [("name", "=", "crm"), ("state", "=", "installed")])
        lead = False
        if crm_instalado:
            lead, _ = o.obtener_o_crear("crm.lead", [("name", "=", "Club Halcones · 40 pares Pulse Custom")], {
            "name": "Club Halcones · 40 pares Pulse Custom", "type": "opportunity", "partner_id": cliente,
                "expected_revenue": precio * total, "description": "Solicitud recibida desde la web (pedido BD SO003)"})
        else:
            print("AVISO: la app CRM no está instalada; el pedido se crea sin oportunidad")
        so = o.call("sale.order", "create", {
            "partner_id": cliente, "client_order_ref": "SO003", **({"opportunity_id": lead} if lead else {}),
            "order_line": [(0, 0, {"product_id": variante_por_talla[r["talla"]], "product_uom_qty": int(r["cantidad"]),
                                   "price_unit": precio,
                                   "name": f"{r['modelo']} Custom · Talla {r['talla']} · Personalización: {colores} | Texto: {r['texto_suela']}"})
                           for r in filas]})
        print(f"  + pedido de venta SO003 (id {so}) · {total} pares · {len(filas)} líneas")
        if a.confirmar:
            o.call("sale.order", "action_confirm", [so])
            nombre_so = o.call("sale.order", "read", [so], fields=["name"])[0]["name"]
            ofs = o.call("mrp.production", "search_read", [("origin", "ilike", nombre_so)], fields=["name", "product_qty", "state"])
            print(f"  ✓ SO003 confirmado · órdenes de fabricación generadas por MTO: {len(ofs)}")
            for of in ofs:
                print("     ", of["name"], of["product_qty"], of["state"])
    print("Carga terminada.")


if __name__ == "__main__":
    main()
