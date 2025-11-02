const std = @import("std");
/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("puff_lib");
// const txt = @embedFile("puffmagic.txt");
const puff = @import("puff.zig");

const ArgParseMode = enum { default, input, output };

pub fn main() !void {
    var alloc = std.heap.page_allocator;

    const outw = std.io.getStdOut().writer();

    var strings = try alloc.alloc([]const u8, 8);
    var total_files: usize = 0;
    defer alloc.free(strings);

    var outFile: ?[]const u8 = null;

    var mode: ArgParseMode = ArgParseMode.default;

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    for (args[1..]) |arg| {
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
            strings[total_files] = arg;
            total_files += 1;
            continue;
        }

        if (mode == .output) {
            outFile = arg;
        }
    }

    if (total_files == 0) {
        try outw.print("Must specify at least one input file with -i (--input)\n", .{});
        std.process.exit(1);
    }

    const sure_out_file = outFile orelse {
        try outw.print("Must specify output file with -o (--output)\n", .{});
        std.process.exit(1);
    };

    try puff.puff(&alloc, strings[0..total_files], sure_out_file);
}
