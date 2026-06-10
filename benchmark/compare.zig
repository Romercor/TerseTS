// Merge one or more benchmark result CSVs into a single unified table.
//
// Every input CSV is produced by a benchmark (bench.zig or Bench.java) and shares the schema
//   dataset,method,values,blocks,bits_per_value,compression_ratio,compress_ns_per_value,decompress_ns_per_value
// This tool tags each row with its implementation label and concatenates them, sorted by
// (dataset, method, implementation). Because it is a union, it stays correct when a contributor
// adds a new method to one or both benchmarks, or adds an entirely new implementation CSV:
// every declared method/implementation shows up in the unified output.
//
// Build/run:
//   zig build compare -- <out.csv> <label1>=<csv1> <label2>=<csv2> [<label3>=<csv3> ...]
// e.g.
//   zig build compare -- benchmark/comparison.csv \
//       tersets=benchmark/results_tersets.csv java=benchmark/results_java.csv

const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Row = struct {
    dataset: []const u8,
    method: []const u8,
    /// "implementation,<full original data line>"
    line: []const u8,

    fn lessThan(_: void, a: Row, b: Row) bool {
        return switch (std.mem.order(u8, a.dataset, b.dataset)) {
            .lt => true,
            .gt => false,
            .eq => std.mem.lessThan(u8, a.method, b.method),
        };
    }
};

fn field(line: []const u8, index: usize) []const u8 {
    var it = std.mem.splitScalar(u8, line, ',');
    var i: usize = 0;
    while (it.next()) |f| : (i += 1) {
        if (i == index) return f;
    }
    return "";
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    // Arena: result rows slice into the file bytes, so keep everything alive until exit.
    const allocator = init.arena.allocator();

    var args = try init.minimal.args.iterateAllocator(init.gpa);
    defer args.deinit();
    _ = args.next(); // skip program name
    const out_path = args.next() orelse {
        std.debug.print("usage: zig build compare -- <out.csv> <label>=<csv> [<label>=<csv> ...]\n", .{});
        return;
    };

    var rows = ArrayList(Row).empty;
    var header: ?[]const u8 = null;

    while (args.next()) |spec| {
        const eq = std.mem.indexOfScalar(u8, spec, '=') orelse {
            std.debug.print("ignoring '{s}' (expected label=path)\n", .{spec});
            continue;
        };
        const label = try allocator.dupe(u8, spec[0..eq]);
        const path = spec[eq + 1 ..];

        const bytes = try Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
        var lines = std.mem.splitScalar(u8, bytes, '\n');
        var first = true;
        while (lines.next()) |raw| {
            const line = if (raw.len > 0 and raw[raw.len - 1] == '\r') raw[0 .. raw.len - 1] else raw;
            if (line.len == 0) continue;
            if (first) {
                first = false;
                // Capture the column header once; prefix it with the implementation column.
                if (header == null) header = try std.fmt.allocPrint(allocator, "implementation,{s}", .{line});
                continue;
            }
            try rows.append(allocator, .{
                .dataset = field(line, 0),
                .method = field(line, 1),
                .line = try std.fmt.allocPrint(allocator, "{s},{s}", .{ label, line }),
            });
        }
    }

    std.mem.sort(Row, rows.items, {}, Row.lessThan);

    var out = ArrayList(u8).empty;
    if (header) |h| {
        try out.appendSlice(allocator, h);
        try out.append(allocator, '\n');
    }
    for (rows.items) |row| {
        try out.appendSlice(allocator, row.line);
        try out.append(allocator, '\n');
    }

    try Io.Dir.cwd().writeFile(io, .{ .sub_path = out_path, .data = out.items });
    std.debug.print("wrote {s} ({d} rows)\n", .{ out_path, rows.items.len });
}
