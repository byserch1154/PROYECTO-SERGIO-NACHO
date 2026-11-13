import shutil
import sys
from pathlib import Path

import pandas as pd
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import analiticas as an  # noqa: E402
import config  # noqa: E402
import generador_datos as gen  # noqa: E402
import pipeline as pl  # noqa: E402


@pytest.fixture
def copia(tmp_path):
    destino = tmp_path / "acc"
    shutil.copytree(config.DIR_REAL, destino)
    return destino


def cambiar(carpeta, fichero, fila, columna, valor):
    df = pd.read_csv(carpeta / fichero, dtype=str)
    df.loc[fila, columna] = valor
    df.to_csv(carpeta / fichero, index=False)


def reglas(r):
    return set(r["incidencias"]["regla"])


def test_01_ruta_inexistente():
    with pytest.raises(pl.ErrorCarga, match="R01"):
        pl.ejecutar(Path("no_existe"))


def test_02_csv_vacio(copia):
    (copia / "stock.csv").write_text("", encoding="utf-8")
    with pytest.raises(pl.ErrorCarga, match="vacío"):
        pl.ejecutar(copia)


def test_03_columna_ausente(copia):
    df = pd.read_csv(copia / "pedidos.csv").drop(columns=["estado"])
    df.to_csv(copia / "pedidos.csv", index=False)
    with pytest.raises(pl.ErrorCarga, match="faltan columnas"):
        pl.ejecutar(copia)


def test_04_fecha_corrupta(copia):
    cambiar(copia, "pedidos.csv", 0, "fecha", "2026-02-31")
    r = pl.ejecutar(copia)
    assert "R04 · fecha nula o imposible" in reglas(r)
    assert r["valido"]


def test_05_id_huerfano_bloquea(copia):
    cambiar(copia, "lineas_pedido.csv", 0, "id_pedido", "999")
    r = pl.ejecutar(copia)
    assert "R03 · pedido inexistente" in reglas(r)
    assert not r["valido"]


def test_06_id_duplicado_bloquea(copia):
    cambiar(copia, "pedidos.csv", 1, "id_pedido", "1")
    r = pl.ejecutar(copia)
    assert "R02 · id_pedido duplicado" in reglas(r)
    assert not r["valido"]


def test_07_merge_no_multiplica_filas():
    r = pl.ejecutar()
    assert len(r["lineas"]) == len(r["tablas"]["lineas_pedido"])


def test_08_cantidad_negativa(copia):
    cambiar(copia, "lineas_pedido.csv", 2, "cantidad", "-3")
    r = pl.ejecutar(copia)
    assert "R05 · cantidad nula, cero o negativa" in reglas(r)
    assert len(r["lineas"]) == len(pd.read_csv(copia / "lineas_pedido.csv")) - 1


def test_09_csv_original_no_se_modifica(copia):
    antes = (copia / "pedidos.csv").read_bytes()
    cambiar(copia, "pedidos.csv", 0, "estado", "perdido")
    modificado = (copia / "pedidos.csv").read_bytes()
    pl.ejecutar(copia)
    assert (copia / "pedidos.csv").read_bytes() == modificado != antes


def test_10_cancelados_no_son_venta():
    res = an.calcular_todo(pl.ejecutar())
    p = res["df01_pedidos_unicos"]
    assert not p.loc[p["estado"] == "cancelado", "es_venta"].any()


def test_11_pedido_multilinea_cuenta_una_vez():
    r = pl.ejecutar()
    p = an.df01_pedidos_unicos(r["lineas"])
    assert len(p) == r["lineas"]["id_pedido"].nunique()
    assert p["n_lineas"].max() > 1


def test_12_importe_y_ticket_sin_duplicar():
    r = pl.ejecutar()
    res = an.calcular_todo(r)
    v = r["lineas"][r["lineas"]["es_venta"]]
    ingresos = round((v["cantidad"] * v["precio_unitario"]).sum(), 2)
    k = res["kpis"].set_index("indicador")["valor"]
    assert float(k["Ingresos (€)"]) == ingresos
    assert float(k["Ticket medio (€)"]) == round(ingresos / v["id_pedido"].nunique(), 2)


def test_13_misma_semilla_mismo_resultado():
    a, b = gen.generar(7), gen.generar(7)
    assert a["lineas_pedido"].equals(b["lineas_pedido"])
    assert a["lineas_pedido"]["cantidad"].sum() == b["lineas_pedido"]["cantidad"].sum()


def test_14_reconciliacion_sql_coincide():
    res = an.calcular_todo(pl.ejecutar())
    assert (res["df12_reconciliacion"]["coincide"] == "sí").all()


def test_15_rfm_cuenta_pedidos_no_lineas():
    res = an.calcular_todo(pl.ejecutar())
    rfm = res["df06_clientes_rfm"].set_index("cliente")
    assert rfm.loc["Club Halcones", "frequency"] == 1


def test_16_clustering_con_pocos_clientes_avisa():
    res = an.calcular_todo(pl.ejecutar())
    assert res["clustering_k"]["estado"].iloc[0] == "NO CALCULABLE"


def test_17_filtro_combinado():
    r = pl.ejecutar()
    f = an.filtrar(r["lineas"], tipos=["custom"], modelos=["SPEAKE Pulse"])
    assert set(f["tipo"]) == {"custom"} and set(f["modelo"]) == {"SPEAKE Pulse"}
    assert len(an.filtrar(r["lineas"])) == len(r["lineas"])
