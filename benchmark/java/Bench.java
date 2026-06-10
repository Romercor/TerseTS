package gr.aueb.delorean.chimp;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.function.Supplier;

import org.urbcomp.startdb.compress.elf.compressor.ElfCompressor;
import org.urbcomp.startdb.compress.elf.decompressor.ElfDecompressor;

/**
 * Benchmark for the reference Java Chimp / ChimpN codecs over a directory of
 * single-column CSV datasets. Mirrors TestDoublePrecision's methodology: each dataset is
 * split into fixed-size blocks, a fresh compressor encodes each block, and the reported
 * compression ratio is bits/value = total compressed bits / total values. Compress and
 * decompress throughput are reported as ns/value (best of several passes).
 *
 * Adding a codec is one line in the `codecs` list below.
 *
 * Usage: java -cp <classpath> gr.aueb.delorean.chimp.Bench <datasets_dir>
 */
public class Bench {

    private static final int BLOCK = 1000;
    private static final int TIME_REPS = 5;

    /** A pluggable codec: encodes one block to bits and decodes it back for verification. */
    interface Codec {
        String name();
        /** Returns the encoded byte[] and records the bit size in size[0]. */
        byte[] compress(double[] block, int[] size) throws IOException;
        double[] decompress(byte[] bytes, int count) throws IOException;
    }

    static final List<Codec> codecs = Arrays.asList(
            new Codec() {
                public String name() { return "chimp64"; }
                public byte[] compress(double[] block, int[] size) {
                    Chimp c = new Chimp();
                    for (double v : block) c.addValue(v);
                    c.close();
                    size[0] = c.getSize();
                    return c.getOut();
                }
                public double[] decompress(byte[] bytes, int count) {
                    // We want to time the decompression itself, not Java's data structures.
                    // The library's getValues() returns a List<Double>: every value gets wrapped
                    // in a Double object on the heap, which is slow and has nothing to do with the
                    // codec. So we call readValue() to pull one value at a time into a plain
                    // double[]. Now the timing reflects the codec, matching how TerseTS measures it.
                    ChimpDecompressor d = new ChimpDecompressor(bytes);
                    double[] out = new double[count];
                    for (int i = 0; i < count; i++) out[i] = d.readValue();
                    return out;
                }
            },
            new Codec() {
                public String name() { return "chimp128"; }
                public byte[] compress(double[] block, int[] size) {
                    ChimpN c = new ChimpN(128);
                    for (double v : block) c.addValue(v);
                    c.close();
                    size[0] = c.getSize();
                    return c.getOut();
                }
                public double[] decompress(byte[] bytes, int count) {
                    // Same as chimp64: read one value at a time into a plain double[] instead of
                    // the library's List<Double>, so we time the codec and not Java's boxing.
                    ChimpNDecompressor d = new ChimpNDecompressor(bytes, 128);
                    double[] out = new double[count];
                    for (int i = 0; i < count; i++) out[i] = d.readValue();
                    return out;
                }
            },
            new Codec() {
                public String name() { return "elf"; }
                public byte[] compress(double[] block, int[] size) {
                    // Reference Elf (paper-faithful vldb2023-release branch): Eraser + Elf XOR,
                    // no beta_star reuse - the same variant TerseTS's elf.zig implements.
                    ElfCompressor c = new ElfCompressor();
                    for (double v : block) c.addValue(v);
                    c.close();
                    size[0] = c.getSize();
                    return c.getBytes();
                }
                public double[] decompress(byte[] bytes, int count) {
                    // Elf's reference decoder boxes every value (Double). Use the primitive
                    // nextValuePrimitive() twin into a plain double[] so we time the codec, not
                    // Java's boxing - matching the chimp methodology above.
                    ElfDecompressor d = new ElfDecompressor(bytes);
                    double[] out = new double[count];
                    for (int i = 0; i < count; i++) out[i] = d.nextValuePrimitive();
                    return out;
                }
            }
    );

    static double[] readValues(File file) throws IOException {
        List<Double> values = new ArrayList<>();
        try (BufferedReader reader = new BufferedReader(new FileReader(file))) {
            String line;
            while ((line = reader.readLine()) != null) {
                String s = line.trim();
                if (s.isEmpty()) continue;
                int comma = s.lastIndexOf(',');
                if (comma >= 0) s = s.substring(comma + 1).trim();
                try {
                    values.add(Double.parseDouble(s));
                } catch (NumberFormatException e) {
                    // skip headers / unparseable lines
                }
            }
        }
        double[] out = new double[values.size()];
        for (int i = 0; i < out.length; i++) out[i] = values.get(i);
        return out;
    }

    static void benchOne(String dataset, double[] values, Codec codec) throws IOException {
        int numBlocks = values.length / BLOCK;
        int totalValues = numBlocks * BLOCK;
        if (numBlocks == 0) return;

        long totalBits = 0;
        byte[][] blobs = new byte[numBlocks][];
        // Per-block bits/value, used for the distribution stats (min/median/max/std).
        double[] perBlockBpv = new double[numBlocks];

        // Compress every block once: collect sizes (ratio) and keep the bytes for decode timing.
        for (int b = 0; b < numBlocks; b++) {
            double[] block = Arrays.copyOfRange(values, b * BLOCK, b * BLOCK + BLOCK);
            int[] size = new int[1];
            byte[] bytes = codec.compress(block, size);
            totalBits += size[0];
            perBlockBpv[b] = (double) size[0] / BLOCK;
            blobs[b] = bytes;

            // Correctness: round-trip must be bit-exact.
            double[] dec = codec.decompress(bytes, BLOCK);
            for (int i = 0; i < BLOCK; i++) {
                if (Double.doubleToRawLongBits(block[i]) != Double.doubleToRawLongBits(dec[i])) {
                    throw new RuntimeException("round-trip mismatch in " + dataset + "/" + codec.name());
                }
            }
        }

        // Compress timing: best wall time over TIME_REPS passes across all blocks.
        long bestCompress = Long.MAX_VALUE;
        for (int r = 0; r < TIME_REPS; r++) {
            long start = System.nanoTime();
            for (int b = 0; b < numBlocks; b++) {
                double[] block = Arrays.copyOfRange(values, b * BLOCK, b * BLOCK + BLOCK);
                int[] size = new int[1];
                codec.compress(block, size);
            }
            bestCompress = Math.min(bestCompress, System.nanoTime() - start);
        }

        // Decompress timing: best wall time over TIME_REPS passes across all stored blobs.
        long bestDecompress = Long.MAX_VALUE;
        for (int r = 0; r < TIME_REPS; r++) {
            long start = System.nanoTime();
            for (int b = 0; b < numBlocks; b++) {
                codec.decompress(blobs[b], BLOCK);
            }
            bestDecompress = Math.min(bestDecompress, System.nanoTime() - start);
        }

        double bitsPerValue = (double) totalBits / totalValues;
        // Raw f64 is 64 bits, so the compression ratio is 64 / bits_per_value (higher is better).
        double compressionRatio = 64.0 / bitsPerValue;
        double compressNs = (double) bestCompress / totalValues;
        double decompressNs = (double) bestDecompress / totalValues;

        // Per-block bits/value distribution: how stable the ratio is across the dataset.
        double bpvMin = Double.MAX_VALUE, bpvMax = -Double.MAX_VALUE, sqSum = 0;
        for (double x : perBlockBpv) {
            bpvMin = Math.min(bpvMin, x);
            bpvMax = Math.max(bpvMax, x);
            double d = x - bitsPerValue;
            sqSum += d * d;
        }
        double bpvStd = Math.sqrt(sqSum / numBlocks);
        double[] sorted = perBlockBpv.clone();
        Arrays.sort(sorted);
        double bpvMedian = (numBlocks % 2 == 1)
                ? sorted[numBlocks / 2]
                : (sorted[numBlocks / 2 - 1] + sorted[numBlocks / 2]) / 2.0;

        System.out.printf("%s,%s,%d,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.1f,%.1f%n",
                dataset, codec.name(), totalValues, numBlocks, bitsPerValue, compressionRatio,
                bpvMin, bpvMedian, bpvMax, bpvStd, compressNs, decompressNs);
    }

    public static void main(String[] args) throws IOException {
        if (args.length < 1) {
            System.err.println("usage: java gr.aueb.delorean.chimp.Bench <datasets_dir>");
            return;
        }
        File dir = new File(args[0]);
        File[] files = dir.listFiles((d, n) -> n.endsWith(".csv"));
        if (files == null) {
            System.err.println("no CSV files in " + dir);
            return;
        }
        Arrays.sort(files);

        System.out.println("dataset,method,values,blocks,bits_per_value,compression_ratio,bpv_min,bpv_median,bpv_max,bpv_std,compress_ns_per_value,decompress_ns_per_value");
        for (File file : files) {
            double[] values = readValues(file);
            if (values.length < BLOCK) continue;
            String dataset = file.getName().substring(0, file.getName().length() - 4);
            for (Codec codec : codecs) {
                benchOne(dataset, values, codec);
            }
        }
    }
}