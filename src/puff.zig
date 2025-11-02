const std = @import("std");

const Puff = struct { files: []const *PuffFile };

const PuffFile = struct { relativePath: []const u8, puffedLength: i64, tempStartOffset: i64 };

pub fn ensureArchiveOutputExists(file_path: []const u8) !struct { dir_path: []const u8, archive_name: []const u8 } {
    const dir_path = std.fs.path.dirname(file_path) orelse return error.InvalidPath;
    const archive_name = std.fs.path.basename(file_path);

    try std.fs.cwd().makePath(dir_path);

    return .{
        .dir_path = dir_path,
        .archive_name = archive_name,
    };
}

pub fn puff(allocator: *std.mem.Allocator, paths: [][]const u8, output_file: []const u8) !void {
    for (paths) |path| {
        try std.fs.cwd().access(path, .{});
    }

    const path_info = try ensureArchiveOutputExists(output_file);
    var temp_file_paths = [2][]const u8{ path_info.archive_name, "temp.pff" };
    const temp_file_path = try std.fs.path.join(allocator, &temp_file_paths);
    defer allocator.free(temp_file_path);

    const file = try std.fs.cwd().createFile(temp_file_path, .{
        .truncate = true,
        .read = true,
    });
    file.close();
    //delete temp file after

}
