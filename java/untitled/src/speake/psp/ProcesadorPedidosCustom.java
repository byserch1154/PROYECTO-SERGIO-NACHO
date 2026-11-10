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

/**
 * PROCESO PADRE · ProcesadorPedidosCustom
 * Lee la exportación ficha_fabricacion.csv, la separa por pedido y, para cada uno,
 * encadena tres procesos hijos lanzados con ProcessBuilder:
 *   CSV del pedido -> ValidadorPedidoCustom -> AnalizadorTallas -> GeneradorFichaTaller
 * Si un hijo termina con código distinto de 0, no se lanza el siguiente.
 * Uso: ProcesadorPedidosCustom [fichero.csv]   (por defecto datos/ficha_fabricacion.csv)
 * Código de salida: 0 = todo OK, 1 = algún pedido con error, 2 = fichero incorrecto.
 */
public final class ProcesadorPedidosCustom {

    private static final Path SALIDA = Paths.get("salida");
    private static PrintStream out;

    /** Lo que devuelve un proceso hijo. */
    record Resultado(String proceso, int codigo, String stdout, String stderr) {
        boolean ok() {
            return codigo == 0;
        }
    }

    private ProcesadorPedidosCustom() { }

    public static void main(String[] args) throws Exception {
        out = Csv.salida();
        Path entrada = Paths.get(args.length > 0 ? args[0] : "datos/ficha_fabricacion.csv");

        // TODO (JSON): aceptar también un .json como datos/pedido_SO003.json y convertirlo
        //   a las mismas filas que el CSV antes de seguir.
        if (!Files.isRegularFile(entrada)) {
            out.println("ERROR: no existe el fichero " + entrada.toAbsolutePath());
            System.exit(2);
        }

        List<String> lineas = Files.readAllLines(entrada, StandardCharsets.UTF_8);
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
            String estado = procesarPedido(p.getKey(), csv);
            out.println(p.getKey() + " -> " + estado);
            if (!estado.equals("OK")) {
                fallidos++;
            }
        }
        out.println("Evidencias en " + SALIDA.toAbsolutePath());
        System.exit(fallidos == 0 ? 0 : 1);
    }

    /** Encadena los tres hijos. Devuelve "OK" o el paso que falló. */
    static String procesarPedido(String ref, String csv) throws IOException, InterruptedException {
        Resultado val = ejecutarHijo("ValidadorPedidoCustom", csv);
        log(ref, val);
        if (!val.ok()) {
            return "ERROR_VALIDACION";
        }
        Resultado ana = ejecutarHijo("AnalizadorTallas", val.stdout());
        log(ref, ana);
        if (!ana.ok()) {
            return "ERROR_ANALISIS";
        }
        Resultado gen = ejecutarHijo("GeneradorFichaTaller", ana.stdout());
        log(ref, gen);
        if (!gen.ok()) {
            return "ERROR_FICHA";
        }
        Files.writeString(SALIDA.resolve("ficha_taller_" + ref + ".txt"), gen.stdout(),
            StandardCharsets.UTF_8);
        return "OK";
    }

    /** Lanza un hijo con ProcessBuilder, le pasa la entrada por stdin y recoge stdout y stderr. */
    static Resultado ejecutarHijo(String clase, String entrada)
            throws IOException, InterruptedException {
        String java = Paths.get(System.getProperty("java.home"), "bin", "java").toString();
        ProcessBuilder pb = new ProcessBuilder(java, "-Dfile.encoding=UTF-8",
            "-cp", System.getProperty("java.class.path"), "speake.psp." + clase);
        pb.redirectErrorStream(false);   // stderr separado de stdout
        Process p = pb.start();

        // stdout y stderr se leen en hilos distintos para que el hijo no se bloquee
        CompletableFuture<String> salida = CompletableFuture.supplyAsync(() -> leer(p.getInputStream()));
        CompletableFuture<String> errores = CompletableFuture.supplyAsync(() -> leer(p.getErrorStream()));
        try (OutputStream os = p.getOutputStream()) {
            os.write(entrada.getBytes(StandardCharsets.UTF_8));
        }

        // TODO (timeout): esperar como máximo N segundos con p.waitFor(N, TimeUnit.SECONDS);
        //   si no termina, p.destroy() y, si sigue vivo, p.destroyForcibly(). Marcar el pedido
        //   como TIMEOUT. Probarlo con AnalizadorTallas --retardo-ms 8000.
        int codigo = p.waitFor();
        return new Resultado(clase, codigo, salida.join(), errores.join());
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
            + " salida=" + r.codigo();
        if (!r.stderr().isBlank()) {
            linea += " | " + r.stderr().trim().replace("\n", " / ");
        }
        out.println(linea);
        Files.writeString(SALIDA.resolve("procesamiento.log"), linea + System.lineSeparator(),
            StandardCharsets.UTF_8, StandardOpenOption.CREATE, StandardOpenOption.APPEND);
    }
}
