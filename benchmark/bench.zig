// Benchmark for TerseTS lossless float codecs against CSV datasets.
//
// Methodology mirrors the reference Java benchmark (gr.aueb.delorean.chimp
// TestDoublePrecision): each dataset is split into fixed-size blocks, a fresh
// compressor encodes each block, and the reported compression ratio is
// bits/value = total compressed bits / total values. Compress and decompress
// throughput are reported as ns/value (best of several passes).
//
// Codecs go through the public TerseTS API (tersets.compress/decompress with a
// Method). Adding a codec is one line in `methods` below.
//
// Build/run: zig build bench -Doptimize=ReleaseFast -- <datasets_dir> [out_csv]

const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const tersets = @import("tersets");

const Codec = struct {
    name: []const u8,
    method: tersets.Method,
};

// Registry of codecs to benchmark. Add a line to extend.
const methods = [_]Codec{
    .{ .name = "chimp64", .method = .Chimp64 },
    .{ .name = "chimp128", .method = .Chimp128 },
    .{ .name = "elf", .method = .Elf },
};

const BLOCK: usize = 1000;
const TIME_REPS: usize = 5;

const Result = struct {
    values: usize,
    blocks: usize,
    // Mean bits/value over all values (equals the mean of per-block bits/value, since blocks are
    // equal-sized). The min/median/max/std fields describe the per-block bits/value distribution,
    // exposing how stable the ratio is across the dataset rather than just its average.
    bits_per_value: f64,
    bpv_min: f64,
    bpv_median: f64,
    bpv_max: f64,
    bpv_std: f64,
    // Raw f64 is 64 bits, so the compression ratio is 64 / bits_per_value (higher is better).
    compression_ratio: f64,
    compress_ns_per_value: f64,
    decompress_ns_per_value: f64,
};

fn parseLineValue(raw: []const u8) ?f64 {
    var s = std.mem.trim(u8, raw, " \t\r\n");
    if (s.len == 0) return null;
    // Single-column datasets parse whole; tolerate a trailing comma-separated value column.
    if (std.mem.lastIndexOfScalar(u8, s, ',')) |idx| s = std.mem.trim(u8, s[idx + 1 ..], " \t\r\n");
    return std.fmt.parseFloat(f64, s) catch null;
}

fn readValues(io: Io, allocator: Allocator, dir: Io.Dir, sub_path: []const u8) !ArrayList(f64) {
    const bytes = try dir.readFileAlloc(io, sub_path, allocator, .unlimited);
    defer allocator.free(bytes);

    var values = ArrayList(f64).empty;
    errdefer values.deinit(allocator);
    var it = std.mem.splitScalar(u8, bytes, '\n');
    while (it.next()) |line| {
        if (parseLineValue(line)) |v| try values.append(allocator, v);
    }
    return values;
}

fn benchMethod(io: Io, allocator: Allocator, values: []const f64, method: tersets.Method) !Result {
    const num_blocks = values.len / BLOCK;
    const total_values = num_blocks * BLOCK;

    // Compress every block once: collect sizes (ratio) and keep the bytes for decode timing.
    var blobs = ArrayList([]u8).empty;
    defer {
        for (blobs.items) |b| allocator.free(b);
        blobs.deinit(allocator);
    }

    // Per-block bits/value, used for the distribution stats (min/median/max/std).
    var per_block_bpv = ArrayList(f64).empty;
    defer per_block_bpv.deinit(allocator);

    var total_bytes: usize = 0;
    var b: usize = 0;
    while (b < num_blocks) : (b += 1) {
        const block = values[b * BLOCK .. b * BLOCK + BLOCK];

        var compressed = try tersets.compress(allocator, block, method, "{}");
        defer compressed.deinit(allocator);
        total_bytes += compressed.items.len;
        try per_block_bpv.append(allocator, @as(f64, @floatFromInt(compressed.items.len * 8)) / @as(f64, BLOCK));
        try blobs.append(allocator, try allocator.dupe(u8, compressed.items));

        // Correctness: round-trip must be bit-exact.
        var dec = try tersets.decompress(allocator, compressed.items);
        defer dec.deinit(allocator);
        if (dec.items.len != block.len) return error.RoundTripLengthMismatch;
        for (block, dec.items) |expected, actual| {
            if (@as(u64, @bitCast(expected)) != @as(u64, @bitCast(actual))) return error.RoundTripValueMismatch;
        }
    }

    // Compress timing: best wall time over TIME_REPS passes across all blocks.
    var best_compress: u64 = std.math.maxInt(u64);
    var r: usize = 0;
    while (r < TIME_REPS) : (r += 1) {
        const start = Io.Clock.Timestamp.now(io, .awake);
        b = 0;
        while (b < num_blocks) : (b += 1) {
            const block = values[b * BLOCK .. b * BLOCK + BLOCK];
            var compressed = try tersets.compress(allocator, block, method, "{}");
            compressed.deinit(allocator);
        }
        best_compress = @min(best_compress, @as(u64, @intCast(start.untilNow(io).raw.nanoseconds)));
    }

    // Decompress timing: best wall time over TIME_REPS passes across all stored blobs.
    var best_decompress: u64 = std.math.maxInt(u64);
    r = 0;
    while (r < TIME_REPS) : (r += 1) {
        const start = Io.Clock.Timestamp.now(io, .awake);
        for (blobs.items) |blob| {
            var dec = try tersets.decompress(allocator, blob);
            dec.deinit(allocator);
        }
        best_decompress = @min(best_decompress, @as(u64, @intCast(start.untilNow(io).raw.nanoseconds)));
    }

    const fv: f64 = @floatFromInt(total_values);
    const bits_per_value = @as(f64, @floatFromInt(total_bytes * 8)) / fv;
    const dist = bpvDistribution(allocator, per_block_bpv.items, bits_per_value) catch
        Distribution{ .min = bits_per_value, .median = bits_per_value, .max = bits_per_value, .std = 0 };
    return .{
        .values = total_values,
        .blocks = num_blocks,
        .bits_per_value = bits_per_value,
        .bpv_min = dist.min,
        .bpv_median = dist.median,
        .bpv_max = dist.max,
        .bpv_std = dist.std,
        .compression_ratio = 64.0 / bits_per_value,
        .compress_ns_per_value = @as(f64, @floatFromInt(best_compress)) / fv,
        .decompress_ns_per_value = @as(f64, @floatFromInt(best_decompress)) / fv,
    };
}

const Distribution = struct { min: f64, median: f64, max: f64, std: f64 };

// min/median/max and population standard deviation of `samples` (per-block bits/value).
// `mean` is passed in since the caller already computed it as the value-weighted average.
fn bpvDistribution(allocator: Allocator, samples: []const f64, mean: f64) !Distribution {
    var min: f64 = samples[0];
    var max: f64 = samples[0];
    var sq_sum: f64 = 0;
    for (samples) |x| {
        min = @min(min, x);
        max = @max(max, x);
        const d = x - mean;
        sq_sum += d * d;
    }
    const std_dev = @sqrt(sq_sum / @as(f64, @floatFromInt(samples.len)));

    // Median needs a sorted copy so the caller's slice order is preserved.
    const sorted = try allocator.dupe(f64, samples);
    defer allocator.free(sorted);
    std.mem.sort(f64, sorted, {}, std.sort.asc(f64));
    const n = sorted.len;
    const median = if (n % 2 == 1) sorted[n / 2] else (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0;

    return .{ .min = min, .median = median, .max = max, .std = std_dev };
}

fn appendLine(sb: *ArrayList(u8), allocator: Allocator, comptime fmt: []const u8, args: anytype) !void {
    const line = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(line);
    try sb.appendSlice(allocator, line);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var args_it = try init.minimal.args.iterateAllocator(allocator);
    defer args_it.deinit();
    _ = args_it.next(); // skip program name
    const dir_path = args_it.next() orelse {
        std.debug.print("usage: zig build bench -- <datasets_dir> [out_csv]\n", .{});
        return;
    };
    const out_path: []const u8 = args_it.next() orelse "benchmark/results_tersets.csv";

    var data_dir = try Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true });
    defer data_dir.close(io);

    // Collect + sort file names for stable output.
    var names = ArrayList([]u8).empty;
    defer {
        for (names.items) |n| allocator.free(n);
        names.deinit(allocator);
    }
    var dir_it = data_dir.iterate();
    while (try dir_it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".csv")) continue;
        try names.append(allocator, try allocator.dupe(u8, entry.name));
    }
    std.mem.sort([]u8, names.items, {}, struct {
        fn lt(_: void, a: []u8, b: []u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lt);

    var sb = ArrayList(u8).empty;
    defer sb.deinit(allocator);
    try appendLine(&sb, allocator, "dataset,method,values,blocks,bits_per_value,compression_ratio,bpv_min,bpv_median,bpv_max,bpv_std,compress_ns_per_value,decompress_ns_per_value\n", .{});

    for (names.items) |name| {
        var values = try readValues(io, allocator, data_dir, name);
        defer values.deinit(allocator);
        if (values.items.len < BLOCK) continue;

        const dataset = name[0 .. name.len - 4];
        for (methods) |codec| {
            const result = try benchMethod(io, allocator, values.items, codec.method);
            try appendLine(&sb, allocator, "{s},{s},{d},{d},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.1},{d:.1}\n", .{
                dataset,
                codec.name,
                result.values,
                result.blocks,
                result.bits_per_value,
                result.compression_ratio,
                result.bpv_min,
                result.bpv_median,
                result.bpv_max,
                result.bpv_std,
                result.compress_ns_per_value,
                result.decompress_ns_per_value,
            });
        }
    }

    try Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = sb.items });
    std.debug.print("{s}", .{sb.items});
}
