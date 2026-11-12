package speake.psp;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;

/**
 * PROCESO PADRE · ProcesadorPedidosCustom
 * Lee la exportación ficha_fabricacion.csv o pedido_SO003.json, la separa por pedido y, para cada uno,
 * encadena tres procesos hijos lanzados con ProcessBuilder:
 *   pedido -> ValidadorPedidoCustom -> AnalizadorTallas -> GeneradorFichaTaller
 * Si un hijo termina con código distinto de 0 o agota el timeout, no se lanza el siguiente.
 * Uso: ProcesadorPedidosCustom [fichero] [--timeout-ms N] [--retardo-ms N]
 * Código de salida: 0 = todo OK, 1 = algún pedido con error, 2 = fichero incorrecto.
 */
public final class ProcesadorPedidosCustom {

    private static final Path SALIDA = Paths.get("salida");
    private static final long TIMEOUT_POR_DEFECTO_MS = 3_000;
    private static PrintStream out;

    /** Lo que devuelve un proceso hijo. */
    record Resultado(String proceso, int codigo, String stdout, String stderr, boolean timeout) {
        boolean ok() {
            return !timeout && codigo == 0;
        }
    }

    private ProcesadorPedidosCustom() { }

    public static void main(String[] args) throws Exception {
        out = Csv.salida();
        Path entrada = Paths.get("datos/ficha_fabricacion.csv");
        long timeoutMs = TIMEOUT_POR_DEFECTO_MS;
        long retardoMs = 0;
        try {
            for (int i = 0; i < args.length; i++) {
                switch (args[i]) {
                    case "--timeout-ms" -> timeoutMs = numeroPositivo(args, ++i, "--timeout-ms");
                    case "--retardo-ms" -> retardoMs = numeroPositivo(args, ++i, "--retardo-ms");
                    default -> entrada = Paths.get(args[i]);
                }
            }
        } catch (IllegalArgumentException e) {
            out.println("ERROR: " + e.getMessage());
            System.exit(2);
            return;
        }

        if (!Files.isRegularFile(entrada)) {
            out.println("ERROR: no existe el fichero " + entrada.toAbsolutePath());
            System.exit(2);
        }

        List<String> lineas;
        if (entrada.toString().toLowerCase().endsWith(".json")) {
            try {
                lineas = JsonPedido.aLineas(entrada);
            } catch (IllegalArgumentException e) {
                out.println("ERROR: " + e.getMessage());
                System.exit(2);
                return;
            }
        } else {
            lineas = Files.readAllLines(entrada, StandardCharsets.UTF_8);
        }
        lineas.removeIf(String::isBlank);
        if (lineas.size() < 2) {
            out.println("ERROR: el fichero no tiene pedidos");
            System.exit(2);
        }

        // Agrupar las filas por la columna «referencia» (SO003, SO005...)
        String cabecera = lineas.get(0).replace("﻿", "");
        int colRef = Csv.separar(cabecera).indexOf("referencia");
        Map<String, List<String>> pedidos = new LinkedHashMap<>();
        for (String l : lineas.subList(1, lineas.size())) {
            String ref = colRef >= 0 ? Csv.separar(l).get(colRef) : "SIN_REF";
            pedidos.computeIfAbsent(ref, k -> new ArrayList<>()).add(l);
        }

        Files.createDirectories(SALIDA);
        // TODO (concurrencia): opción --paralelo que procese varios pedidos a la vez con un
        //   ExecutorService. El log pasaría a ser un recurso compartido: log() synchronized.
        int fallidos = 0;
        for (Map.Entry<String, List<String>> p : pedidos.entrySet()) {
            String csv = cabecera + "\n" + String.join("\n", p.getValue()) + "\n";
            String estado = procesarPedido(p.getKey(), csv, timeoutMs, retardoMs);
            out.println(p.getKey() + " -> " + estado);
            if (!estado.equals("OK")) {
                fallidos++;
            }
        }
        out.println("Evidencias en " + SALIDA.toAbsolutePath());
        System.exit(fallidos == 0 ? 0 : 1);
    }

    /** Encadena los tres hijos. Devuelve "OK", "TIMEOUT" o el paso que falló. */
    static String procesarPedido(String ref, String csv, long timeoutMs, long retardoMs)
            throws IOException, InterruptedException {
        Resultado val = ejecutarHijo("ValidadorPedidoCustom", csv, timeoutMs);
        log(ref, val);
        if (val.timeout()) {
            return "TIMEOUT";
        }
        if (!val.ok()) {
            return "ERROR_VALIDACION";
        }

        Resultado ana = retardoMs > 0
            ? ejecutarHijo("AnalizadorTallas", val.stdout(), timeoutMs,
                "--retardo-ms", Long.toString(retardoMs))
            : ejecutarHijo("AnalizadorTallas", val.stdout(), timeoutMs);
        log(ref, ana);
        if (ana.timeout()) {
            return "TIMEOUT";
        }
        if (!ana.ok()) {
            return "ERROR_ANALISIS";
        }

        Resultado gen = ejecutarHijo("GeneradorFichaTaller", ana.stdout(), timeoutMs);
        log(ref, gen);
        if (gen.timeout()) {
            return "TIMEOUT";
        }
        if (!gen.ok()) {
            return "ERROR_FICHA";
        }
        Files.writeString(SALIDA.resolve("ficha_taller_" + ref + ".txt"), gen.stdout(),
            StandardCharsets.UTF_8);
        return "OK";
    }

    /** Lanza un hijo con ProcessBuilder, le pasa la entrada por stdin y recoge stdout y stderr. */
    static Resultado ejecutarHijo(String clase, String entrada, long timeoutMs, String... argsHijo)
            throws IOException, InterruptedException {
        String java = Paths.get(System.getProperty("java.home"), "bin", "java").toString();
        List<String> comando = new ArrayList<>(List.of(
            java, "-Dfile.encoding=UTF-8",
            "-cp", System.getProperty("java.class.path"),
            "speake.psp." + clase));
        comando.addAll(List.of(argsHijo));

        ProcessBuilder pb = new ProcessBuilder(comando);
        pb.redirectErrorStream(false);   // stderr separado de stdout
        Process p = pb.start();

        // stdout y stderr se leen en hilos distintos para que el hijo no se bloquee
        CompletableFuture<String> salida = CompletableFuture.supplyAsync(() -> leer(p.getInputStream()));
        CompletableFuture<String> errores = CompletableFuture.supplyAsync(() -> leer(p.getErrorStream()));
        try (OutputStream os = p.getOutputStream()) {
            os.write(entrada.getBytes(StandardCharsets.UTF_8));
        }

        boolean termino = p.waitFor(timeoutMs, TimeUnit.MILLISECONDS);
        if (!termino) {
            p.destroy();
            if (!p.waitFor(1, TimeUnit.SECONDS)) {
                p.destroyForcibly();
                p.waitFor();
            }
            return new Resultado(clase, -1, salida.join(), errores.join(), true);
        }
        return new Resultado(clase, p.exitValue(), salida.join(), errores.join(), false);
    }

    private static long numeroPositivo(String[] args, int i, String opcion) {
        if (i >= args.length) {
            throw new IllegalArgumentException("falta el valor de " + opcion);
        }
        try {
            long valor = Long.parseLong(args[i]);
            if (valor <= 0) {
                throw new NumberFormatException();
            }
            return valor;
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException("valor no válido para " + opcion + ": " + args[i]);
        }
    }

    private static String leer(InputStream is) {
        try (InputStream in = is) {
            return new String(in.readAllBytes(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            return "";
        }
    }

    /** Escribe en pantalla y en salida/procesamiento.log. */
    private static void log(String ref, Resultado r) throws IOException {
        String linea = LocalDateTime.now() + " | " + ref + " | " + r.proceso()
            + (r.timeout() ? " TIMEOUT" : " salida=" + r.codigo());
        if (!r.stderr().isBlank()) {
            linea += " | " + r.stderr().trim().replace("\n", " / ");
        }
        out.println(linea);
        Files.writeString(SALIDA.resolve("procesamiento.log"), linea + System.lineSeparator(),
            StandardCharsets.UTF_8, StandardOpenOption.CREATE, StandardOpenOption.APPEND);
    }
}
