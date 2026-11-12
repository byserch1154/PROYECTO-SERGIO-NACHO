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
    destino = tmp_path / "acc"
    shutil.copytree(config.DIR_ENTRADA, destino)
    return destino


def test_carga_real_correcta():
    t, lineas, incidencias = pl.ejecutar()
    assert len(t["pedidos"]) > 0
    assert len(lineas) == len(t["lineas_pedido"])


def test_carpeta_inexistente():
    with pytest.raises(pl.ErrorCarga):
        pl.ejecutar(Path("no_existe"))


def test_columna_ausente(copia):
    df = pd.read_csv(copia / "pedidos.csv").drop(columns=["estado"])
    df.to_csv(copia / "pedidos.csv", index=False)
    with pytest.raises(pl.ErrorCarga, match="faltan columnas"):
        pl.ejecutar(copia)


def test_linea_huerfana_se_marca(copia):
    df = pd.read_csv(copia / "lineas_pedido.csv")
    df.loc[0, "id_pedido"] = 999
    df.to_csv(copia / "lineas_pedido.csv", index=False)
    _, lineas, incidencias = pl.ejecutar(copia)
    assert "pedido inexistente" in incidencias["regla"].tolist()
    assert 999 not in lineas["id_pedido"].tolist()


def test_fecha_y_cantidad_erroneas(copia):
    p = pd.read_csv(copia / "pedidos.csv")
    p.loc[0, "fecha"] = "no-es-fecha"
    p.to_csv(copia / "pedidos.csv", index=False)
    lin = pd.read_csv(copia / "lineas_pedido.csv")
    lin.loc[1, "cantidad"] = -3
    lin.to_csv(copia / "lineas_pedido.csv", index=False)
    _, _, incidencias = pl.ejecutar(copia)
    assert {"fecha no válida", "cantidad no positiva"} <= set(incidencias["regla"])


def test_cancelados_no_son_venta():
    _, lineas, _ = pl.ejecutar()
    pedidos = an.pedidos_unicos(lineas)
    assert not pedidos.loc[pedidos["estado"] == "cancelado", "es_venta"].any()


def test_pedido_con_varias_lineas_cuenta_una_vez():
    _, lineas, _ = pl.ejecutar()
    assert len(an.pedidos_unicos(lineas)) == lineas["id_pedido"].nunique()


def test_filtro_por_modelo():
    _, lineas, _ = pl.ejecutar()
    modelo = lineas["modelo"].iloc[0]
    assert set(an.filtrar(lineas, modelos=[modelo])["modelo"]) == {modelo}
