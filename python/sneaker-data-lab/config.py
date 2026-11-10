"""Configuración común del laboratorio de datos de SPEAKE."""

from pathlib import Path

BASE = Path(__file__).resolve().parent
DIR_ENTRADA = BASE / "entrada_acc"  # CSV exportados desde la base de datos SPEAKE
DIR_SALIDA = BASE / "outputs"

# Columnas obligatorias de cada CSV
ESQUEMA = {
    "clientes": ["id_cliente", "nombre", "tipo"],
    "modelos": ["id_modelo", "modelo", "categoria"],
    "pedidos": ["id_pedido", "fecha", "id_cliente", "estado", "tipo"],
    "lineas_pedido": ["id_linea", "id_pedido", "id_modelo", "talla", "cantidad", "precio_unitario"],
    "stock": ["id_modelo", "talla", "stock_disponible", "fecha_corte"],
}

ESTADOS = ["pendiente", "confirmado", "entregado", "cancelado"]
ESTADOS_VENTA = ["confirmado", "entregado"]  # lo que cuenta como venta
TALLAS = list(range(38, 47))
STOCK_MINIMO = 10
REFRESCO_SEGUNDOS = 60
