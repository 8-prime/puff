const std = @import("std");
const plain = @import("compression/plain.zig");
const lib = @import("puff_lib");
const puff = @import("puff.zig");

const ArgParseMode = enum { default, input, output };

fn runPuff(args: [][:0]u8, alloc: std.mem.Allocator, output: std.io.AnyWriter) !void {
    if (args.len < 3) {
        try output.print("Must specify at least one input file with -i (--input)\n", .{});
        std.process.exit(1);
    }
    var files = std.ArrayList([]const u8).init(alloc);
    var total_files: usize = 0;

    defer files.deinit();

    var outFile: ?[]const u8 = null;

    var mode: ArgParseMode = ArgParseMode.default;

    for (args[2..]) |arg| {
        const a: []const u8 = arg;

        if (std.mem.eql(u8, a, @as([]const u8, "-i")) or
            std.mem.eql(u8, a, @as([]const u8, "--input")))
        {
            mode = .input;
            continue;
        }

        if (std.mem.eql(u8, a, @as([]const u8, "-o")) or
            std.mem.eql(u8, a, @as([]const u8, "--output")))
        {
            mode = .output;
            continue;
        }

        if (mode == .input) {
            try files.append(arg);
            total_files += 1;
            continue;
        }

        if (mode == .output) {
            outFile = arg;
        }
    }

    if (total_files == 0) {
        try output.print("Must specify at least one input file with -i (--input)\n", .{});
        std.process.exit(1);
    }

    const sure_out_file = outFile orelse {
        try output.print("Must specify output file with -o (--output)\n", .{});
        std.process.exit(1);
    };
    var empty_compressor = plain.PlainCompressor{};
    try puff.puff(alloc, files.items, sure_out_file, empty_compressor.compressor());
}

fn runUnPuff() !void {}

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    const outw = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    if (args.len < 2) {
        try outw.print("Must specify operation [puff, unpuff]", .{});
        std.process.exit(1);
    }

    if (std.mem.eql(u8, args[1], "puff")) {
        try runPuff(args, alloc, outw.any());
    } else if (std.mem.eql(u8, args[1], "unpuff")) {
        try runUnPuff();
    }
}
