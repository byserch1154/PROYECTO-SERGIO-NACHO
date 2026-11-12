from pathlib import Path

BASE = Path(__file__).resolve().parent
DIR_ENTRADA = BASE / "entrada_acc"
DIR_SALIDA = BASE / "outputs"
LOG = BASE / "logs" / "ejecuciones.log"

ESQUEMA = {
    "clientes": ["id_cliente", "nombre", "tipo"],
    "modelos": ["id_modelo", "modelo", "categoria"],
    "pedidos": ["id_pedido", "fecha", "id_cliente", "estado", "tipo"],
    "lineas_pedido": ["id_linea", "id_pedido", "id_modelo", "talla", "cantidad", "precio_unitario"],
    "stock": ["id_modelo", "talla", "stock_disponible", "fecha_corte"],
}

ESTADOS = ["pendiente", "confirmado", "entregado", "cancelado"]
ESTADOS_VENTA = ["confirmado", "entregado"]
TALLAS = list(range(38, 47))
STOCK_MINIMO = 10
REFRESCO_SEGUNDOS = 60
SEMILLA = 42
