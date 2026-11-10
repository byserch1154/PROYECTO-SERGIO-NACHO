import shutil
import sys
from pathlib import Path

import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import analiticas as an  # noqa: E402
import config  # noqa: E402
import pipeline as pl  # noqa: E402


@pytest.fixture
def copia(tmp_path):
    """Copia de los CSV reales para poder estropearlos sin tocar los originales."""
    destino = tmp_path / "acc"
    shutil.copytree(config.DIR_ENTRADA, destino)
    return destino


def test_carga_real_correcta():
    t, lineas = pl.ejecutar()
    assert len(t["pedidos"]) == 12
    assert len(lineas) == len(t["lineas_pedido"])  # el merge no multiplica filas


def test_carpeta_inexistente():
    with pytest.raises(pl.ErrorCarga):
        pl.ejecutar(Path("no_existe"))


def test_columna_ausente(copia):
    df = pd.read_csv(copia / "pedidos.csv").drop(columns=["estado"])
    df.to_csv(copia / "pedidos.csv", index=False)
    with pytest.raises(pl.ErrorCarga, match="faltan columnas"):
        pl.ejecutar(copia)


def test_linea_huerfana(copia):
    df = pd.read_csv(copia / "lineas_pedido.csv")
    df.loc[0, "id_pedido"] = 999
    df.to_csv(copia / "lineas_pedido.csv", index=False)
    with pytest.raises(pl.ErrorCarga, match="no existen"):
        pl.ejecutar(copia)


def test_cancelados_no_son_venta():
    t, lineas = pl.ejecutar()
    pedidos = an.pedidos_unicos(lineas)
    assert not pedidos.loc[pedidos["estado"] == "cancelado", "es_venta"].any()


# TODO: pruebas de fecha corrupta, id duplicado, cantidad negativa y de los KPIs
#   (por ejemplo, que un pedido con varias líneas cuente una sola vez).
