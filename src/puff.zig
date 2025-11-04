const std = @import("std");
const com = @import("compressor.zig");

const magic_bytes = @embedFile("puffmagic.txt");

const Puff = struct { files: std.ArrayList(PuffEntry) };
const PuffEntry = struct { relativePath: []const u8, puffedLength: u64, tempStartOffset: u64 };

pub fn ensureArchiveOutputExists(file_path: []const u8) !struct { dir_path: []const u8, archive_name: []const u8 } {
    const dir_path = std.fs.path.dirname(file_path) orelse return error.InvalidPath;
    const archive_name = std.fs.path.basename(file_path);

    try std.fs.cwd().makePath(dir_path);

    return .{
        .dir_path = dir_path,
        .archive_name = archive_name,
    };
}

fn write_to_toc(toc_buffer: []u8, value: u64, buffer_offset: *usize) !void {
    const offset = buffer_offset.*;
    var slice = toc_buffer[offset .. offset + @sizeOf(@TypeOf(value))];
    std.mem.writeInt(@TypeOf(value), slice[0..@sizeOf(@TypeOf(value))], value, .little);

    buffer_offset.* += @sizeOf(@TypeOf(value));
}

fn puffFile(allocator: *std.mem.Allocator, file_path: []const u8, temp_file: *std.fs.File, compressor: com.Compressor) !PuffEntry {
    const file = try std.fs.cwd().openFile(file_path, .{});
    var buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(buffer);
    try temp_file.seekFromEnd(0);
    const start_pos = try temp_file.getPos();
    var total_bytes: usize = 0;
    try file.seekTo(0);
    var read_bytes = try file.readAll(buffer);
    while (read_bytes > 0) {
        try temp_file.writeAll(buffer[0..read_bytes]);
        total_bytes += read_bytes;
        read_bytes = try file.readAll(buffer);
    }
    try temp_file.sync();
    const reader = file.reader();
    const writer = temp_file.writer();
    try compressor.compress(reader.any(), writer.any());
    return PuffEntry{ .puffedLength = @intCast(total_bytes), .relativePath = file_path, .tempStartOffset = start_pos };
}

pub fn puff(allocator: *std.mem.Allocator, paths: [][]const u8, output_file: []const u8, compressor: com.Compressor) !void {
    for (paths) |path| {
        try std.fs.cwd().access(path, .{});
    }

    const path_info = try ensureArchiveOutputExists(output_file);
    var temp_file_paths = [2][]const u8{ path_info.dir_path, "temp.pff" };
    const temp_file_path = try std.fs.path.join(allocator.*, &temp_file_paths);
    defer allocator.free(temp_file_path);

    std.debug.print("Creating temp file {s}", .{temp_file_path});
    var temp_file = try std.fs.cwd().createFile(temp_file_path, .{
        .truncate = true,
        .read = true,
    });
    defer temp_file.close();

    var puff_data = Puff{ .files = std.ArrayList(PuffEntry).init(allocator.*) };

    for (paths) |path| {
        const newEntry = try puffFile(allocator, path, &temp_file, compressor);
        try puff_data.files.append(newEntry);
    }

    const final_file = try std.fs.cwd().createFile(output_file, .{
        .truncate = true,
        .read = true,
    });
    defer final_file.close();

    //Write magic bytes :D as start of file
    try final_file.writeAll(magic_bytes);

    //Write table of contents
    var total_toc_length: usize = 0;
    for (puff_data.files.items) |pd| {
        total_toc_length += pd.relativePath.len;
        total_toc_length += @sizeOf(i64) * 2; //Size of offset and length in bytes
    }

    const toc_buffer = try allocator.alloc(u8, total_toc_length);
    defer allocator.free(toc_buffer);

    const offset_after_header = try final_file.getPos() + total_toc_length;

    var current_toc_pointer: usize = 0;
    for (puff_data.files.items) |pd| {
        @memcpy(toc_buffer[current_toc_pointer .. current_toc_pointer + pd.relativePath.len], pd.relativePath);
        current_toc_pointer += @intCast(pd.relativePath.len);
        try write_to_toc(toc_buffer, pd.tempStartOffset + offset_after_header, &current_toc_pointer);
        try write_to_toc(toc_buffer, pd.puffedLength + offset_after_header, &current_toc_pointer);
    }

    _ = try final_file.write(toc_buffer);

    const temp_file_buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(temp_file_buffer);
    try temp_file.seekTo(0);
    var read = try temp_file.readAll(temp_file_buffer);
    while (read > 0) {
        std.debug.print("Reading from temp file into main archive", .{});
        try final_file.writeAll(temp_file_buffer[0..read]);
        read = try temp_file.readAll(temp_file_buffer);
    }

    //delete temp file after
    try std.fs.cwd().deleteFile(temp_file_path);
}
