import argparse
import sys
from datetime import datetime

import analiticas as an
import config
import graficos
import pipeline as pl


def log(mensaje):
    config.LOG.parent.mkdir(exist_ok=True)
    with open(config.LOG, "a", encoding="utf-8") as f:
        f.write(f"{datetime.now():%Y-%m-%d %H:%M:%S} | {mensaje}\n")


def main(argv=None):
    parser = argparse.ArgumentParser(description="SPEAKE · análisis de datos")
    parser.add_argument("--entrada", default=config.DIR_ENTRADA)
    args = parser.parse_args(argv)

    try:
        t, lineas, incidencias = pl.ejecutar(args.entrada)
    except pl.ErrorCarga as e:
        print(f"ERROR en los datos: {e}")
        log(f"ERROR {e}")
        return 2

    res = an.calcular_todo(t, lineas, incidencias)
    print(res["kpis"].to_string(index=False))
    print(f"\nIncidencias de calidad: {len(incidencias)}")

    config.DIR_SALIDA.mkdir(exist_ok=True)
    for nombre, df in res.items():
        df.to_csv(config.DIR_SALIDA / f"{nombre}.csv", index=False, encoding="utf-8")
    graficos.generar(res, lineas, config.DIR_SALIDA / "graficos")

    log(f"OK pedidos={len(res['pedidos'])} incidencias={len(incidencias)}")
    print(f"Resultados y gráficos en {config.DIR_SALIDA}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
