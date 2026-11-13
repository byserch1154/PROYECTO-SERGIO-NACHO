from pathlib import Path

BASE = Path(__file__).resolve().parent
DIR_REAL = BASE / "entrada_acc"
DIR_SINTETICO = BASE / "datos_sinteticos"
DIR_SALIDA = BASE / "outputs"
DIR_LOGS = BASE / "logs"

ESQUEMA = {
    "clientes": ["id_cliente", "nombre", "tipo"],
    "modelos": ["id_modelo", "modelo", "categoria"],
    "pedidos": ["id_pedido", "fecha", "id_cliente", "estado", "tipo"],
    "lineas_pedido": ["id_linea", "id_pedido", "id_modelo", "talla", "cantidad", "precio_unitario"],
    "stock": ["id_modelo", "talla", "stock_disponible", "fecha_corte"],
}
FICHERO_SQL = "reconciliacion_sql.csv"

ESTADOS = ["pendiente", "confirmado", "entregado", "cancelado"]
ESTADOS_VENTA = ["confirmado", "entregado"]
TIPOS = ["estandar", "custom"]
TALLAS = list(range(38, 47))

STOCK_MINIMO = 10
DIAS_DEMANDA = 28
ABC_A = 0.80
ABC_B = 0.95
RFM_DIAS_ACTIVO = 60
MIN_CLIENTES_CLUSTER = 8
MIN_FILAS_IQR = 5

REFRESCO_SEGUNDOS = 60
SEMILLA = 42
