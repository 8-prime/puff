const std = @import("std");
const com = @import("compression/compressor.zig");
const archive = @import("types/archive.zig");
const plain = @import("compression/plain.zig");

const magic_bytes = @embedFile("puffmagic.txt");

pub fn ensureArchiveOutputExists(file_path: []const u8) !struct { dir_path: []const u8, archive_name: []const u8 } {
    const dir_path = std.fs.path.dirname(file_path) orelse return error.InvalidPath;
    const archive_name = std.fs.path.basename(file_path);

    try std.fs.cwd().makePath(dir_path);

    return .{
        .dir_path = dir_path,
        .archive_name = archive_name,
    };
}

fn write_to_toc(comptime T: type, toc_buffer: []u8, value: T, buffer_offset: *usize) !void {
    const offset = buffer_offset.*;
    var slice = toc_buffer[offset .. offset + @sizeOf(@TypeOf(value))];
    std.mem.writeInt(@TypeOf(value), slice[0..@sizeOf(@TypeOf(value))], value, .little);

    buffer_offset.* += @sizeOf(@TypeOf(value));
}

fn puffFile(allocator: std.mem.Allocator, file_path: []const u8, temp_file: *std.fs.File, compressor: com.Compressor) !archive.PuffEntry {
    const file = try std.fs.cwd().openFile(file_path, .{});
    try file.seekTo(0);
    try temp_file.seekFromEnd(0);
    const start_pos = try temp_file.getPos();
    const total_bytes = try compressor.compress(file.reader().any(), temp_file.writer().any(), allocator);
    return archive.PuffEntry{ .puffedLength = @intCast(total_bytes), .relativePath = file_path, .tempStartOffset = start_pos };
}

pub fn puff(allocator: std.mem.Allocator, paths: [][]const u8, output_file: []const u8, compressor: com.Compressor) !void {
    for (paths) |path| {
        try std.fs.cwd().access(path, .{});
    }

    const path_info = try ensureArchiveOutputExists(output_file);
    var temp_file_paths = [2][]const u8{ path_info.dir_path, "temp.pff" };
    const temp_file_path = try std.fs.path.join(allocator, &temp_file_paths);
    defer allocator.free(temp_file_path);

    std.debug.print("Creating temp file {s}", .{temp_file_path});
    var temp_file = try std.fs.cwd().createFile(temp_file_path, .{
        .truncate = true,
        .read = true,
    });
    defer temp_file.close();

    var puff_data = archive.Puff{ .files = std.ArrayList(archive.PuffEntry).init(allocator), .type = compressor.archiveType };

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
    var archive_info_length: usize = 0;

    //info bytes for archive info length
    archive_info_length += @sizeOf(i64);
    //info bytes for archive type
    archive_info_length += @sizeOf(i64);

    for (puff_data.files.items) |pd| {
        archive_info_length += @sizeOf(i64); //Size of relative path in bytes
        archive_info_length += pd.relativePath.len;
        archive_info_length += @sizeOf(i64) * 2; //Size of offset and length of compressed file in bytes
    }

    const archive_info_buffer = try allocator.alloc(u8, archive_info_length);
    defer allocator.free(archive_info_buffer);

    const offset_after_header: u64 = try final_file.getPos() + archive_info_length;

    var current_toc_pointer: usize = 0;

    try write_to_toc(i64, archive_info_buffer, @intCast(archive_info_length), &current_toc_pointer);
    try write_to_toc(i64, archive_info_buffer, compressor.archiveType, &current_toc_pointer);

    for (puff_data.files.items) |pd| {
        try write_to_toc(i64, archive_info_buffer, @intCast(pd.relativePath.len), &current_toc_pointer);
        @memcpy(archive_info_buffer[current_toc_pointer .. current_toc_pointer + pd.relativePath.len], pd.relativePath);
        current_toc_pointer += @intCast(pd.relativePath.len);
        try write_to_toc(u64, archive_info_buffer, pd.tempStartOffset + offset_after_header, &current_toc_pointer);
        try write_to_toc(u64, archive_info_buffer, pd.puffedLength + offset_after_header, &current_toc_pointer);
    }

    _ = try final_file.write(archive_info_buffer);

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

pub fn unPuff(allocator: std.mem.Allocator, archive_path: []const u8, output_path: []const u8) !void {
    //check if archive path exists
    try std.fs.cwd().access(archive_path, .{});
    //open archive file
    const file = try std.fs.cwd().openFile(archive_path, .{});
    try file.seekTo(0);
    //check for header
    const magic_bytes_buffer = try allocator.alloc(u8, magic_bytes.len);
    const read_bytes = try file.readAll(magic_bytes_buffer);
    if (read_bytes < magic_bytes.len) {
        return archive.UnPuffError.InvalidArchiveHeader;
    }
    allocator.free(magic_bytes_buffer);

    const intBuffer = try allocator.alloc(u8, @sizeOf(i64));
    defer allocator.free(intBuffer);
    //read header size
    try file.readAll(intBuffer);
    const header_size = std.mem.readInt(i64, intBuffer, .little);
    //read archive type
    try file.readAll(intBuffer);
    const archive_type: archive.ArchiveType = @enumFromInt(std.mem.readInt(i64, intBuffer, .little));
    //create decompressor based on archive type

    const header_bytes = try allocator.alloc(u8, header_size);

    const decompressor = switch (archive_type) {
        .plain => plain.PlainDecompressor.init().decompressor(),
    };

    _ = header_bytes;

    var read_toc_bytes: i64 = 0;

    try std.fs.cwd().makePath(output_path);
    while (read_toc_bytes < header_size) {
        const relative_path_length = std.mem.readInt(i64, intBuffer, .little);
        const relative_path = try allocator.alloc(u8, relative_path_length);
        const start_offset = std.mem.readInt(i64, intBuffer, .little);
        const length = std.mem.readInt(i64, intBuffer, .little);
        const full_path = try std.fs.path.join(allocator, &.{ output_path, relative_path });
        defer allocator.free(full_path);

        // Create the file
        const out_file = try std.fs.cwd().createFile(full_path, .{});
        defer out_file.close();
        //create reader from file and seek to
        file.seekTo(start_offset);
        try decompressor.decompress(file.reader().any(), start_offset, start_offset + length, out_file.writer().any(), allocator);
        read_toc_bytes += intBuffer.len * 3;
        read_toc_bytes += relative_path_length;
    }

    //for each entry
    //read length of relative file path
    //read relative file path based on length
    //read start offset of file
    //read length of file

    //open file for output_path + relative path

    //pass reader and lengths to decompressor as well as writer for file

}
