const std = @import("std");

const magic_bytes = @embedFile("puffmagic.txt");

const Puff = struct { files: std.ArrayList(*PuffEntry) };
const PuffEntry = struct { relativePath: []const u8, puffedLength: i64, tempStartOffset: i64 };

pub fn ensureArchiveOutputExists(file_path: []const u8) !struct { dir_path: []const u8, archive_name: []const u8 } {
    const dir_path = std.fs.path.dirname(file_path) orelse return error.InvalidPath;
    const archive_name = std.fs.path.basename(file_path);

    try std.fs.cwd().makePath(dir_path);

    return .{
        .dir_path = dir_path,
        .archive_name = archive_name,
    };
}

fn write_to_toc(toc_buffer: []u8, value: i64, buffer_offset: *i64) !void {
    const offset = buffer_offset.*;
    const slice = toc_buffer[offset .. offset + @sizeOf(i64)];
    std.mem.writeInt(i64, slice, value, .little);

    buffer_offset.* += @sizeOf(i64);
}

fn puffFile(allocator: *std.mem.Allocator, file_path: []const u8, temp_file: *std.fs.File) !PuffEntry {
    const file = try std.fs.cwd().openFile(file_path, .{});

    var buffer = allocator.alloc(u8, 1024);
    try temp_file.seekFromEnd(0);
    const start_pos = try temp_file.getPos();
    var total_bytes = 0;
    try file.seekTo(0);
    var read_bytes = try file.readAll(buffer);
    while (read_bytes > 0) {
        try temp_file.writeAll(buffer[0..read_bytes]);
        total_bytes += read_bytes;
        read_bytes = try file.readAll(buffer);
    }
    return PuffEntry{ .puffedLength = total_bytes, .relativePath = file_path, .tempStartOffset = start_pos };
}

pub fn puff(allocator: *std.mem.Allocator, paths: [][]const u8, output_file: []const u8) !void {
    for (paths) |path| {
        try std.fs.cwd().access(path, .{});
    }

    const path_info = try ensureArchiveOutputExists(output_file);
    var temp_file_paths = [2][]const u8{ path_info.archive_name, "temp.pff" };
    const temp_file_path = try std.fs.path.join(allocator, &temp_file_paths);
    defer allocator.free(temp_file_path);

    const temp_file = try std.fs.cwd().createFile(temp_file_path, .{
        .truncate = true,
        .read = true,
    });
    defer temp_file.close();

    const puff_data = Puff{ .files = std.ArrayList(*PuffEntry).init(allocator) };

    for (paths) |path| {
        const newEntry = try puffFile(allocator, path, &temp_file);
        puff_data.files.addOne(&newEntry);
    }

    const final_file = try std.fs.cwd().createFile(output_file, .{
        .truncate = true,
        .read = true,
    });

    //Write magic bytes :D as start of file
    try final_file.writeAll(magic_bytes);

    //Write table of contents
    var total_toc_length = 0;
    for (puff_data.files.items) |pd| {
        total_toc_length += pd.relativePath.len;
        total_toc_length += @sizeOf(i64) * 2; //Size of offset and length in bytes
    }

    const toc_buffer = try allocator.alloc(u8, total_toc_length);
    defer allocator.free(toc_buffer);
    var current_toc_pointer = 0;

    const offset_after_header = try final_file.getPos() + total_toc_length;

    for (puff_data.files.items) |pd| {
        @memcpy(toc_buffer[0..pd.relativePath.len], pd.relativePath);
        current_toc_pointer += pd.relativePath.len;
        write_to_toc(toc_buffer, pd.tempStartOffset + offset_after_header, &current_toc_pointer);
        write_to_toc(toc_buffer, pd.puffedLength + offset_after_header, &current_toc_pointer);
    }

    try final_file.write(toc_buffer);

    const temp_file_buffer = try allocator.alloc(u8, 1024);
    var read = try temp_file.readAll(temp_file_buffer);
    while (read > 0) {
        final_file.writeAll(temp_file_buffer[0..read]);
        read = try temp_file.readAll(temp_file_buffer);
    }

    //delete temp file after
    std.fs.cwd().deleteFile(temp_file_path);
}
