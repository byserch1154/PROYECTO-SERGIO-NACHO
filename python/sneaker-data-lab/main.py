"""Ejecución por consola: valida los datos y guarda los resultados en outputs/.

Uso:  python main.py  [--entrada carpeta]
"""

import argparse
import sys

import analiticas as an
import config
import pipeline as pl


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="SPEAKE · laboratorio de datos")
    parser.add_argument("--entrada", default=config.DIR_ENTRADA)
    args = parser.parse_args(argv)

    try:
        t, lineas = pl.ejecutar(args.entrada)
    except pl.ErrorCarga as e:
        print(f"ERROR en los datos: {e}")
        return 2

    res = an.calcular_todo(t, lineas)
    print(res["kpis"].to_string(index=False))

    config.DIR_SALIDA.mkdir(exist_ok=True)
    for nombre, df in res.items():
        df.to_csv(config.DIR_SALIDA / f"{nombre}.csv", index=False, encoding="utf-8")
    # TODO: guardar también los gráficos en PNG (matplotlib) y un informe en Markdown.
    print(f"Resultados guardados en {config.DIR_SALIDA}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
