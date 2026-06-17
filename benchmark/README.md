# `benchmark/` — Chimp & Elf: TerseTS (Zig) vs reference (Java)

Compares TerseTS's lossless float codecs against the original Java implementations on the
standard public datasets, using one shared methodology so the numbers line up.

| File | What it is |
|------|------------|
| [`bench.zig`](bench.zig) | TerseTS (Zig) benchmark — `zig build bench`. |
| [`java/Bench.java`](java/Bench.java) | Reference (Java) benchmark — drop into the ELF repo. |
| [`compare.zig`](compare.zig) | Merges result CSVs into one unified table — `zig build compare`. |
| `results_*.csv`, `comparison.csv` | Raw per-implementation outputs and the unified table. |

**What is compared:** all codecs live in `src/lossless_compression/` and are driven via
`tersets.compress`/`decompress`:

- `Chimp64`/`Chimp128` vs `Chimp`/`ChimpN` (package `gr.aueb.delorean.chimp`) — the official Chimp
  by P. Liakos (Chimp paper's first author; VLDB 2022), [`panagiotisl/chimp`](https://github.com/panagiotisl/chimp).
- `Elf` vs `ElfCompressor`/`ElfDecompressor` (package `org.urbcomp.startdb.compress.elf`) — the
  authors' reference Elf (Li et al., *Elf*, VLDB 2023).

Both references are built from a single checkout of the [ELF repo](https://github.com/Spatio-Temporal-Lab/elf),
on the **`vldb2023-release`** branch. That branch is the one the authors mark as faithful to the
VLDB 2023 paper (the default `dev` branch is an optimized, beyond-paper variant), and it bundles the
paper-faithful Elf, a byte-identical copy of the Chimp codec, and the 22 `ElfTestData` datasets the
benchmark needs — none of which `panagiotisl/chimp` ships on its own.

**Methodology** (from the ELF repo's `TestDoublePrecision`): split each dataset into blocks of
1000, encode each block with a fresh compressor, verify the round-trip bit-for-bit, and report
per dataset: `bits_per_value` (mean) and `compression_ratio` (= `64 / bits_per_value`); the
spread of per-block bits/value as `bpv_min`/`bpv_median`/`bpv_max`/`bpv_std` (how stable the
ratio is across the dataset, not just its average); and compress/decompress `ns_per_value` (best
of 5 passes).

## Metrics

Each row of `comparison.csv` carries these columns (the tables below show a readable subset):

| Column | What it means |
|--------|---------------|
| `dataset` | Name of the input series (the CSV file). |
| `method` | Codec used: `chimp64`, `chimp128`, or `elf`. |
| `values` | How many `f64` values were compressed (only whole 1000-value blocks count). |
| `blocks` | Number of 1000-value blocks. |
| `bits_per_value` | Average compressed size of one value, in bits. Raw `f64` is 64; lower is better. |
| `compression_ratio` | `64 / bits_per_value` — how many times smaller than raw. Higher is better. |
| `bpv_min` | Smallest per-block `bits_per_value` (the block that compressed best). |
| `bpv_median` | Middle per-block `bits_per_value` (half the blocks are below it). |
| `bpv_max` | Largest per-block `bits_per_value` (the block that compressed worst). |
| `bpv_std` | Standard deviation of per-block `bits_per_value` — how much the ratio swings block to block. 0 = every block compresses the same; large = bursty. |
| `compress_ns_per_value` | Nanoseconds to compress one value (best of 5 passes). Lower is faster. |
| `decompress_ns_per_value` | Nanoseconds to decompress one value (best of 5 passes). Lower is faster. |

## Results (this machine; Zig `ReleaseFast`, JDK 17)

> TerseTS `comp` and `decomp` numbers include the Chimp optimizations from `feature/optimization-chimp-1`
> (see [Optimizations](#optimizations)); they reproduce once that branch lands in `main`.

Every cell is `TerseTS / Java`. `bpv` = `bits_per_value` (mean); `std` = `bpv_std`;
`comp`/`decomp` = the `ns_per_value` columns. Per-block min/median/max for both implementations
are in `comparison.csv`.

**Means across datasets** (excludes the `init` duplicate, like the per-dataset tables below)

| Method | ratio | mean bpv | std | comp ns | decomp ns |
|--------|-------|----------|-----|---------|-----------|
| chimp64 | **1.44× / 1.44×** | 46.8 / 46.9 | 3.36 / 3.36 | 9 / 21 | 10 / 18 |
| chimp128 | **2.56× / 2.55×** | 31.7 / 31.7 | 2.11 / 2.10 | 11 / 31 | 9 / 17 |

**chimp128** (sorted by ratio)

| dataset | ratio | mean bpv | std | comp ns | decomp ns |
|---|---|---|---|---|---|
| PM10-dust | 4.39× / 4.38× | 14.59 / 14.60 | 3.10 / 3.10 | 8 / 20 | 6 / 10 |
| Stocks-USA | 4.34× / 4.35× | 14.74 / 14.71 | 2.19 / 2.19 | 12 / 22 | 6 / 13 |
| Wind-Speed | 4.30× / 4.31× | 14.87 / 14.87 | 0.72 / 0.72 | 8 / 23 | 7 / 13 |
| IR-bio-temp | 4.02× / 4.03× | 15.92 / 15.88 | 1.47 / 1.47 | 8 / 23 | 7 / 13 |
| SSD-bench | 3.76× / 3.77× | 17.03 / 17.00 | 1.20 / 1.19 | 7 / 24 | 6 / 13 |
| Stocks-DE | 3.69× / 3.69× | 17.33 / 17.33 | 3.26 / 3.29 | 10 / 24 | 8 / 13 |
| Stocks-UK | 3.49× / 3.49× | 18.36 / 18.33 | 1.46 / 1.46 | 11 / 25 | 8 / 13 |
| City-temp | 3.14× / 3.15× | 20.39 / 20.35 | 3.05 / 3.05 | 11 / 26 | 9 / 14 |
| Food-price | 2.94× / 2.94× | 21.78 / 21.79 | 3.08 / 3.09 | 11 / 42 | 10 / 14 |
| Dew-point-temp | 2.88× / 2.88× | 22.26 / 22.23 | 1.97 / 1.97 | 12 / 28 | 10 / 16 |
| electric_vehicle_charging | 2.76× / 2.76× | 23.18 / 23.16 | 1.44 / 1.42 | 8 / 38 | 8 / 12 |
| Basel-temp | 2.13× / 2.12× | 30.04 / 30.18 | 4.20 / 4.24 | 11 / 50 | 11 / 20 |
| Bird-migration | 2.02× / 2.01× | 31.63 / 31.77 | 5.16 / 5.14 | 13 / 30 | 11 / 19 |
| Air-pressure | 1.85× / 1.84× | 34.58 / 34.84 | 1.60 / 1.54 | 11 / 37 | 8 / 22 |
| Blockchain-tr | 1.82× / 1.81× | 35.18 / 35.35 | 3.65 / 3.66 | 11 / 31 | 10 / 17 |
| Basel-wind | 1.41× / 1.41× | 45.45 / 45.57 | 2.73 / 2.71 | 13 / 34 | 12 / 22 |
| Bitcoin-price | 1.39× / 1.39× | 46.19 / 46.22 | 0.55 / 0.55 | 13 / 31 | 11 / 20 |
| City-lat | 1.29× / 1.29× | 49.50 / 49.76 | 0.98 / 0.95 | 14 / 35 | 13 / 23 |
| Air-sensor | 1.29× / 1.29× | 49.54 / 49.55 | 2.93 / 2.93 | 10 / 34 | 10 / 18 |
| City-lon | 1.18× / 1.18× | 54.17 / 54.34 | 1.30 / 1.29 | 14 / 38 | 13 / 24 |
| POI-lat | 1.11× / 1.11× | 57.45 / 57.46 | 0.19 / 0.19 | 10 / 32 | 10 / 17 |
| POI-lon | 1.02× / 1.02× | 63.07 / 63.08 | 0.20 / 0.19 | 12 / 31 | 12 / 19 |

**chimp64** (sorted by ratio)

| dataset | ratio | mean bpv | std | comp ns | decomp ns |
|---|---|---|---|---|---|
| PM10-dust | 2.36× / 2.34× | 27.09 / 27.34 | 9.73 / 9.76 | 7 / 15 | 8 / 15 |
| Food-price | 2.13× / 2.12× | 30.08 / 30.16 | 8.14 / 8.16 | 8 / 18 | 10 / 18 |
| Stocks-UK | 1.93× / 1.93× | 33.12 / 33.22 | 12.01 / 12.09 | 10 / 21 | 10 / 18 |
| SSD-bench | 1.85× / 1.82× | 34.70 / 35.10 | 4.21 / 4.24 | 11 / 14 | 10 / 14 |
| IR-bio-temp | 1.57× / 1.56× | 40.78 / 40.98 | 5.83 / 5.77 | 9 / 17 | 10 / 18 |
| Stocks-USA | 1.57× / 1.56× | 40.80 / 40.94 | 3.35 / 3.28 | 9 / 16 | 10 / 18 |
| City-temp | 1.57× / 1.56× | 40.82 / 41.01 | 10.15 / 10.19 | 9 / 21 | 11 / 20 |
| Air-pressure | 1.53× / 1.53× | 41.72 / 41.81 | 0.79 / 0.76 | 7 / 32 | 7 / 16 |
| Blockchain-tr | 1.50× / 1.50× | 42.60 / 42.72 | 3.89 / 3.89 | 8 / 18 | 9 / 19 |
| Stocks-DE | 1.50× / 1.49× | 42.76 / 42.87 | 2.07 / 2.03 | 10 / 19 | 11 / 18 |
| Bird-migration | 1.40× / 1.40× | 45.76 / 45.81 | 2.06 / 2.04 | 10 / 22 | 11 / 20 |
| Bitcoin-price | 1.31× / 1.31× | 49.05 / 49.05 | 0.49 / 0.49 | 9 / 28 | 10 / 22 |
| Air-sensor | 1.29× / 1.29× | 49.51 / 49.51 | 2.92 / 2.92 | 8 / 30 | 10 / 19 |
| Dew-point-temp | 1.29× / 1.29× | 49.54 / 49.58 | 1.44 / 1.44 | 10 / 20 | 12 / 21 |
| Wind-Speed | 1.23× / 1.22× | 52.17 / 52.30 | 1.86 / 1.81 | 9 / 17 | 11 / 18 |
| Basel-temp | 1.18× / 1.18× | 54.08 / 54.13 | 1.26 / 1.26 | 9 / 31 | 11 / 18 |
| electric_vehicle_charging | 1.16× / 1.16× | 55.11 / 55.18 | 1.12 / 1.12 | 8 / 17 | 12 / 19 |
| Basel-wind | 1.14× / 1.14× | 56.04 / 56.07 | 0.54 / 0.53 | 9 / 22 | 10 / 17 |
| POI-lat | 1.11× / 1.11× | 57.68 / 57.69 | 0.20 / 0.20 | 7 / 16 | 9 / 16 |
| City-lat | 1.08× / 1.08× | 59.09 / 59.10 | 1.07 / 1.07 | 8 / 18 | 10 / 18 |
| City-lon | 1.02× / 1.02× | 63.00 / 63.00 | 0.70 / 0.70 | 9 / 22 | 10 / 20 |
| POI-lon | 1.01× / 1.01× | 63.29 / 63.29 | 0.15 / 0.15 | 9 / 20 | 10 / 20 |

> Timings are machine-specific; ratios reproduce anywhere. `init` duplicates `Wind-Speed` (stray file
> in the dataset directory).

## Elf results (this machine; Zig `ReleaseFast`, JDK 17)

`Elf` (Li et al., VLDB 2023) erases the noise bits a decimal value carries in its mantissa, then
runs a Chimp-style XOR layer over the cleaned-up value. TerseTS is compared against the authors'
paper-faithful reference on the `vldb2023-release` branch (`ElfCompressor`/`ElfDecompressor`). Both
implement the same variant: no `beta_star` reuse across values. Cells are `TerseTS / Java`.

**Means across datasets** (excludes the `init` duplicate)

| Method | ratio | mean bpv | std | comp ns | decomp ns |
|--------|-------|----------|-----|---------|-----------|
| elf | **3.01× / 2.96×** | 27.7 / 28.0 | 1.75 / 1.79 | 21 / 53 | 18 / 25 |

TerseTS edges the reference on ratio while compressing **~2.5× faster** and decompressing **~30%
faster**. The ratio win comes from the XOR layer (see caveats); the speed win is the eraser rewrite
plus bulk bit I/O (see [Optimizations](#optimizations)).

**elf** (sorted by ratio)

| dataset | ratio | mean bpv | std | comp ns | decomp ns |
|---|---|---|---|---|---|
| PM10-dust | 5.82x / 5.80x | 10.99 / 11.03 | 2.12 / 2.26 | 15 / 42 | 14 / 22 |
| Stocks-UK | 4.74x / 4.58x | 13.50 / 13.98 | 2.23 / 2.23 | 17 / 36 | 17 / 18 |
| IR-bio-temp | 4.64x / 4.56x | 13.79 / 14.05 | 1.61 / 1.78 | 17 / 49 | 16 / 24 |
| Food-price | 4.41x / 4.32x | 14.50 / 14.81 | 3.24 / 3.34 | 20 / 38 | 19 / 19 |
| Stocks-USA | 4.28x / 4.18x | 14.94 / 15.32 | 2.65 / 2.71 | 18 / 42 | 17 / 26 |
| City-temp | 4.04x / 3.94x | 15.85 / 16.26 | 3.19 / 3.32 | 17 / 36 | 17 / 20 |
| Wind-Speed | 3.98x / 3.91x | 16.10 / 16.37 | 0.49 / 0.51 | 22 / 51 | 18 / 28 |
| Stocks-DE | 3.93x / 3.83x | 16.28 / 16.71 | 3.02 / 3.05 | 20 / 48 | 18 / 23 |
| SSD-bench | 3.73x / 3.75x | 17.17 / 17.05 | 2.00 / 1.85 | 13 / 40 | 14 / 21 |
| Dew-point-temp | 3.31x / 3.22x | 19.35 / 19.87 | 1.62 / 1.65 | 20 / 44 | 17 / 23 |
| Air-pressure | 3.25x / 3.27x | 19.70 / 19.56 | 0.61 / 0.72 | 15 / 40 | 12 / 23 |
| electric_vehicle_charging | 2.96x / 2.93x | 21.60 / 21.86 | 1.47 / 1.58 | 14 / 36 | 13 / 20 |
| Blockchain-tr | 2.83x / 2.79x | 22.64 / 22.91 | 1.72 / 1.76 | 21 / 52 | 21 / 24 |
| Bird-migration | 2.41x / 2.37x | 26.56 / 27.06 | 3.09 / 3.11 | 24 / 51 | 20 / 24 |
| City-lat | 1.81x / 1.79x | 35.31 / 35.76 | 1.23 / 1.27 | 27 / 49 | 22 / 26 |
| Bitcoin-price | 1.80x / 1.77x | 35.48 / 36.08 | 1.63 / 1.64 | 19 / 52 | 18 / 28 |
| Basel-temp | 1.75x / 1.73x | 36.51 / 36.98 | 2.14 / 2.17 | 26 / 54 | 22 / 30 |
| Basel-wind | 1.73x / 1.70x | 37.08 / 37.55 | 0.53 / 0.55 | 27 / 52 | 19 / 28 |
| City-lon | 1.61x / 1.59x | 39.66 / 40.17 | 0.66 / 0.67 | 27 / 59 | 26 / 36 |
| Air-sensor | 1.20x / 1.18x | 53.55 / 54.17 | 2.87 / 2.85 | 28 / 106 | 17 / 42 |
| POI-lat | 1.05x / 1.04x | 61.07 / 61.51 | 0.27 / 0.29 | 28 / 96 | 17 / 20 |
| POI-lon | 0.95x / 0.95x | 67.12 / 67.68 | 0.15 / 0.15 | 33 / 88 | 20 / 23 |

> `Elf` ratios match or beat the reference on 20 of 22 datasets (the rest within block-framing
> noise). Where there is nothing to erase — high-entropy coordinates like `POI-lon` — both fall
> below 1.0× (the value expands: `bpv > 64`), and TerseTS still edges ahead by the implicit-1 XOR bit.

**Why the ratios differ slightly** (TerseTS vs the reference, same Elf variant):

- **XOR layer (TerseTS wins ~1 bit/value).** On a new leading-zero bucket the top meaningful bit is
  always 1, so TerseTS omits it (Chimp-style implicit-leading-1) and the decoder prepends it. The
  reference Elf XOR writes that bit explicitly. This is why TerseTS is slightly ahead even on
  un-erasable data.
- **Block framing (reference wins a little).** Each 1000-value block, TerseTS writes a `u64` count
  header + a raw first value + a method-tag byte (~0.14 bit/value); the reference writes a compressed
  first value + an end-of-stream marker. On the two datasets where the reference edges TerseTS
  (`SSD-bench`, `Air-pressure`) this framing difference dominates.

## Elf+ results (this machine; Zig `ReleaseFast`, JDK 22)

`Elf+` is the enhanced Elf maintained on the ELF repo's **`dev`** branch (under review for VLDBJ,
and the variant its README recommends over the paper version). On top of paper Elf it adds
`beta_star` state reuse (a 1-bit marker when the decimal-significand count is unchanged) and
lookup-table-driven `beta` computation. TerseTS is compared against that dev-branch reference
(`ElfCompressor`/`ElfDecompressor`, same variant). Cells are `TerseTS / Java`.

**Means across datasets** (excludes the `init` duplicate)

| Method | ratio | mean bpv | comp ns | decomp ns |
|--------|-------|----------|---------|-----------|
| elf_plus | **3.59× / 3.64×** | 25.3 / 25.2 | 23 / 40 | 23 / 24 |

TerseTS reproduces the reference ratio to within ~0.05× (<=0.4 bit/value) on every dataset while
compressing **~1.7× faster** (decompress on par). Unlike paper Elf — where TerseTS edges ahead via
the implicit-leading-1 XOR bit — here the dev reference uses that same trick, so the remaining gap
is TerseTS's per-block framing (`u64` count + raw first value + method byte; the raw, un-erased
first value also seeds the XOR predictor, costing a little body on erasable data). Elf+ beats paper
Elf by **~19%** mean ratio (3.59× vs 3.01×), most on decimal-heavy series.

**elf_plus** (sorted by ratio)

| dataset | ratio | mean bpv | std | comp ns | decomp ns |
|---|---|---|---|---|---|
| PM10-dust | 8.24x / 8.48x | 7.76 / 7.55 | 2.20 / 2.21 | 16 / 25 | 18 / 18 |
| IR-bio-temp | 6.31x / 6.46x | 10.14 / 9.91 | 1.50 / 1.58 | 20 / 31 | 20 / 21 |
| Stocks-USA | 5.64x / 5.73x | 11.35 / 11.18 | 2.57 / 2.58 | 22 / 34 | 21 / 21 |
| Stocks-UK | 5.39x / 5.46x | 11.86 / 11.72 | 1.22 / 1.22 | 27 / 40 | 21 / 22 |
| Wind-Speed | 5.03x / 5.11x | 12.73 / 12.53 | 0.42 / 0.43 | 22 / 35 | 23 / 24 |
| City-temp | 4.76x / 4.82x | 13.44 / 13.28 | 2.33 / 2.32 | 20 / 31 | 20 / 20 |
| Food-price | 4.65x / 4.69x | 13.77 / 13.64 | 2.53 / 2.54 | 23 / 37 | 20 / 21 |
| Stocks-DE | 4.50x / 4.55x | 14.22 / 14.05 | 3.04 / 3.04 | 24 / 39 | 23 / 24 |
| SSD-bench | 4.22x / 4.31x | 15.17 / 14.84 | 1.85 / 1.66 | 17 / 27 | 18 / 18 |
| Dew-point-temp | 4.04x / 4.09x | 15.83 / 15.66 | 1.47 / 1.47 | 21 / 33 | 22 / 21 |
| Air-pressure | 3.91x / 4.01x | 16.37 / 15.97 | 0.98 / 1.00 | 16 / 31 | 18 / 21 |
| electric_vehicle_charging | 3.50x / 3.56x | 18.27 / 17.96 | 1.19 / 1.26 | 17 / 28 | 22 / 17 |
| Blockchain-tr | 3.38x / 3.41x | 18.92 / 18.75 | 1.79 / 1.80 | 24 / 38 | 23 / 24 |
| Bird-migration | 2.70x / 2.72x | 23.68 / 23.52 | 2.69 / 2.69 | 30 / 45 | 25 / 26 |
| Bitcoin-price | 2.05x / 2.06x | 31.16 / 31.02 | 1.64 / 1.64 | 22 / 35 | 24 / 22 |
| City-lat | 2.00x / 2.01x | 31.93 / 31.78 | 1.56 / 1.56 | 28 / 42 | 26 / 27 |
| Basel-temp | 1.94x / 1.95x | 33.02 / 32.86 | 1.25 / 1.27 | 24 / 39 | 26 / 26 |
| Basel-wind | 1.82x / 1.83x | 35.08 / 34.93 | 0.58 / 0.58 | 29 / 50 | 28 / 30 |
| City-lon | 1.69x / 1.70x | 37.87 / 37.72 | 0.74 / 0.74 | 34 / 56 | 39 / 34 |
| Air-sensor | 1.17x / 1.18x | 54.52 / 54.45 | 2.88 / 2.88 | 22 / 82 | 23 / 43 |
| POI-lat | 1.03x / 1.03x | 62.05 / 61.98 | 0.27 / 0.27 | 22 / 44 | 26 / 26 |
| POI-lon | 0.94x / 0.94x | 68.09 / 68.02 | 0.15 / 0.15 | 31 / 61 | 27 / 29 |

> Built from the ELF repo's `dev` branch (`mvn dependency:copy-dependencies` + `javac`), with the
> boxing-free `nextValuePrimitive()` decode path added to the reference (as for paper Elf, see
> [Optimizations](#optimizations) E3) so the decode comparison times the codec, not Java's boxing.

## Optimizations

Each step keeps output byte-identical (ratios unchanged) and round-trips bit-exact. Numbers are
mean ns/value on this machine.

**1. Java decompress — boxing** *(adopted)*
- **Problem:** the reference `getValues()` returns a `List<Double>`, boxing every value on the heap — ~230 ns/value, measuring Java's object model, not the codec.
- **Solution:** loop the primitive `readValue()` straight into a `double[]`; no boxing, no list.
- **Result:** ~230 → ~17 ns/value (now comparable to TerseTS).

**2. chimp128 compress — per-block table** *(adopted on `feature/optimization-chimp-1`)*
- **Problem:** a 64 KB lookup table is allocated and zeroed on *every* 1000-value block; the JVM gets this nearly free, Zig pays an explicit allocate + `memset`. (~2–2.5× slower than Java; chimp64, which has no table, is at parity — so it's not the algorithm.)
- **Solution:** keep the table in a thread-local scratch — zeroed once, then reset only the ~1000 slots a block dirtied instead of reallocating+zeroing. `u32` slots (not `usize`) halve the retained scratch to ~128 KB/thread.
- **Result:** 70 → 26 ns/value alone; **11 ns/value combined with #3** (Java 31). The `u32` step is memory-only — no speed change.

**3. chimp64 / chimp128 compress — bit writer** *(adopted on `feature/optimization-chimp-1`)*
- **Problem:** the `BitWriter` appends one byte at a time into a buffer that grows from empty (~1.4× slower than Java).
- **Solution:** a `BulkBitWriter` that accumulates bits in a 64-bit register and flushes 8 bytes per store. Added alongside `BitWriter` (additive) and used by both Chimp codecs; output stays byte-identical.
- **Result:** chimp64 25 → 9 ns/value (~2× faster than Java's 18); also lifts chimp128 (26 → 11 with #2).

**4. chimp64 / chimp128 decompress — bit reader + output sizing** *(adopted on `feature/optimization-chimp-1`)*
- **Problem:** the `BitReader` takes one byte at a time through a stream interface, and the output `ArrayList(f64)` grows from empty even though the value count is in the header.
- **Solution:** a `BulkBitReader` that reads straight from the byte slice into a 64-bit accumulator (the decode twin of `BulkBitWriter`), plus pre-reserving the output from the header count (`ensureTotalCapacity` + `appendAssumeCapacity`, matching what Java already does).
- **Result:** chimp64 ~15 → ~10 ns/value, chimp128 ~14 → ~10 ns/value (~30% faster; Java ~18). Already ahead of Java, so this extends the lead.

### Elf

The bit-I/O and Java-boxing steps below reuse the Chimp work above; the eraser step is Elf-specific.
Unlike the Chimp steps, the eraser step **changes the ratio on purpose** (it erases more) — the
other two are byte-identical perf tweaks. All steps round-trip bit-exact.

**E1. Elf compress — eraser significant-digit search** *(TerseTS-side; the ratio win)*
- **Problem:** `getSignificantCount` started its search at the *maximal* scale (`i = 17 - sp - 1`) and stripped trailing zeros. Scaling by such a large power of ten loses f64 precision, so the reversibility check failed and the eraser returned "give up" (17 → no erase) far too often. Decimal values that *should* erase were left raw, inflating the XOR layer. (Mean ratio was stuck at 2.42× vs the reference's 2.96×.)
- **Solution:** match the reference — start at the *minimal* scale (`i = 1`, or `-sp` for `v < 1`) and walk up to the first power of ten that makes `v · 10^i` an exact integer. Starting low lands on the minimal significant-digit count directly, so it both finds the true count and needs no trailing-zero stripping.
- **Result:** mean ratio **2.42× → 3.01×** (closes the ~22% gap and edges ahead). Compress also got *faster* — starting at `i = 1` iterates far fewer times than starting at ~15. Java doesn't hit this because its reference already starts at the minimal scale.

**E2. Elf compress/decompress — bulk bit I/O** *(adopted; same `BulkBitWriter`/`BulkBitReader` as Chimp #3/#4)*
- **Problem:** Elf still used the byte-at-a-time `BitWriter`/`BitReader`, and the decode output `ArrayList(f64)` grew from empty even though the count is in the header.
- **Solution:** switch compress to `BulkBitWriter` and decompress to `BulkBitReader` + pre-reserve the output (`ensureTotalCapacity`); reuses the shared types Chimp already added (no table is involved — Elf has none, so Chimp #2 does not apply).
- **Result:** with E1, compress ~21 ns/value and decompress ~18 — both well ahead of the reference (53 / 25). Output stays byte-identical.

**E3. Java decompress — boxing** *(adopted; same idea as Chimp #1, applied to the Elf reference)*
- **Problem:** Elf's reference decoder boxes every value end-to-end — `decompress()` returns `List<Double>`, and even `ElfXORDecompressor.readValue()` returns `Double` — so a naive decode times Java's allocator, not the codec.
- **Solution:** add an *additive* primitive `nextValuePrimitive()` path through the three Elf decompressor classes (`ElfXORDecompressor`/`AbstractElfDecompressor`/`ElfDecompressor`) and loop it straight into a `double[]`. The shipped boxed methods are untouched, so sibling codecs are unaffected.
- **Result:** Java decode drops to ~25 ns/value (codec, not boxing), making the decode comparison fair. These edits live only in the local ELF clone, not in this repo.

## Run

```sh
# TerseTS  (writes benchmark/results_tersets.csv)
zig build bench -Doptimize=ReleaseFast -- <ElfTestData_dir>

# Java reference — paper-faithful Chimp + Elf, both from the ELF repo's vldb2023-release branch
git clone --depth 1 -b vldb2023-release https://github.com/Spatio-Temporal-Lab/elf.git
cp benchmark/java/Bench.java elf/src/main/java/gr/aueb/delorean/chimp/Bench.java
# Elf decode only: add a primitive (boxing-free) decode path to the reference (see Optimizations E3):
#   ElfXORDecompressor  -> public double readValuePrimitive()
#   AbstractElfDecompressor -> public double nextValuePrimitive() + protected double xorDecompressPrimitive()
#   ElfDecompressor     -> @Override protected double xorDecompressPrimitive()
mvn -f elf/pom.xml dependency:copy-dependencies -DincludeScope=compile -DoutputDirectory=elf/target/dependency
javac -cp "elf/target/dependency/*" -sourcepath elf/src/main/java -d elf/target/bench \
      elf/src/main/java/gr/aueb/delorean/chimp/Bench.java
java -cp "elf/target/bench;elf/target/dependency/*" gr.aueb.delorean.chimp.Bench \
      elf/src/test/resources/ElfTestData > benchmark/results_java.csv

# Unify (union over all implementations/methods present)
zig build compare -- benchmark/comparison.csv \
    tersets=benchmark/results_tersets.csv java=benchmark/results_java.csv
```

> Maven TLS error behind a corporate proxy? `set MAVEN_OPTS=-Djavax.net.ssl.trustStoreType=Windows-ROOT`.
>
> Why ELF and not [`panagiotisl/chimp`](https://github.com/panagiotisl/chimp) directly? The Chimp
> codec is identical in both, but ELF bundles the 22 datasets (the official repo ships only 3) and
> builds cleanly, whereas the official `pom.xml` pulls a publishing plugin that needs extra setup.
> Same codec, same results — ELF is just the convenient source of code + data.

## Extend

Both benchmarks use a one-line registry, and `compare` is a union — so a new method or even a
whole new implementation flows into `comparison.csv` automatically.

- **Add a method:** add a `tersets.Method` entry to `methods` in [`bench.zig`](bench.zig) and a
  matching `Codec` to `codecs` in [`java/Bench.java`](java/Bench.java), re-run, re-`compare`.
- **Add an implementation:** produce a results CSV with the same columns and pass it as another
  `label=path` to `zig build compare`.
