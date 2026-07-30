// Copyright 2024 TerseTS Contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

const std = @import("std");
const LinkMode = std.builtin.LinkMode;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    // Define build options.
    const linking = b.option(
        LinkMode,
        "linking",
        "Build a static or dynamic (default) library",
    ) orelse LinkMode.dynamic;

    const pic = b.option(
        bool,
        "pic",
        "Use Position Independent Code (PIC)",
    ) orelse null;

    const optimize = b.standardOptimizeOption(.{});

    // Create root module.
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/capi.zig"),
        .target = target,
        .optimize = optimize,
        .pic = pic,
    });

    // Paths to external libraries. Include the PocketFFT source file directly in the build,
    // as it's a single C file with no dependencies.
    const pocketfft_path = b.path("lib/pocketfft");
    const pocketfft_c_path = b.path("lib/pocketfft/pocketfft.c");

    root_module.addIncludePath(pocketfft_path);
    root_module.addCSourceFile(.{ .file = pocketfft_c_path });
    root_module.link_libc = true;

    // Task for compilation.
    const library = b.addLibrary(.{
        .name = "tersets",
        .root_module = root_module,
        .linkage = linking,
        .version = .{ .major = 0, .minor = 0, .patch = 1 },
    });

    if (linking == LinkMode.static) {
        library.bundle_compiler_rt = true;
    }

    b.installArtifact(library);

    // Task for running tests.
    const tests = b.addTest(.{
        .root_module = root_module,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests.step);

    // Task for running the benchmark harness. The Zig API (`src/tersets.zig`) is exposed to the
    // benchmark as the `tersets` module so it can call the public compress/decompress.
    const tersets_module = b.createModule(.{
        .root_source_file = b.path("src/tersets.zig"),
        .target = target,
        .optimize = optimize,
    });
    // DiscreteFourierTransform depends on the PocketFFT C library, same as root_module above.
    tersets_module.addIncludePath(pocketfft_path);
    tersets_module.addCSourceFile(.{ .file = pocketfft_c_path });
    tersets_module.link_libc = true;
    const bench_module = b.createModule(.{
        .root_source_file = b.path("benchmark/bench.zig"),
        .target = target,
        .optimize = optimize,
    });
    bench_module.addImport("tersets", tersets_module);
    const bench = b.addExecutable(.{
        .name = "bench",
        .root_module = bench_module,
    });
    const run_bench = b.addRunArtifact(bench);
    if (b.args) |args| run_bench.addArgs(args);
    const bench_step = b.step("bench", "Run the benchmark (zig build bench -Doptimize=ReleaseFast -- <datasets_dir>)");
    bench_step.dependOn(&run_bench.step);

    // Task for merging benchmark result CSVs (any number of implementations) into one unified
    // table. Pure CSV plumbing, so it needs no library module.
    const compare_module = b.createModule(.{
        .root_source_file = b.path("benchmark/compare.zig"),
        .target = target,
        .optimize = optimize,
    });
    const compare = b.addExecutable(.{
        .name = "compare",
        .root_module = compare_module,
    });
    const run_compare = b.addRunArtifact(compare);
    if (b.args) |args| run_compare.addArgs(args);
    const compare_step = b.step("compare", "Merge result CSVs (zig build compare -- <out.csv> <label>=<csv> ...)");
    compare_step.dependOn(&run_compare.step);
}
