//! Loads hotkeys from rswap.conf. TODO move to appdata or something
//! key = app name

const std = @import("std");
const Io = std.Io;

const config_limit = Io.Limit.limited(1 << 20);

pub const Entry = struct {
    key: u8,
    app_name: []const u8,
};

pub const Config = struct {
    entries: []const Entry,
};

pub const Loaded = struct {
    config: Config,
    /// Absolute path of the config file (may not exist)
    path: []const u8,
};

/// Reads `rswap.conf` next to the executable, else from the working directory.
pub fn load(io: Io, allocator: std.mem.Allocator) !Loaded {
    if (exe_dir(io, allocator)) |dir| {
        const path = try std.fs.path.join(allocator, &.{ dir, "rswap.conf" });
        if (try read_file(io, allocator, path)) |text| {
            return .{ .config = try parse(allocator, text), .path = path };
        }
    }

    const base: []const u8 = std.process.currentPathAlloc(io, allocator) catch ".";
    const path = try std.fs.path.join(allocator, &.{ base, "rswap.conf" });
    if (try read_file(io, allocator, path)) |text| {
        return .{ .config = try parse(allocator, text), .path = path };
    }
    return .{ .config = .{ .entries = &.{} }, .path = path };
}

fn exe_dir(io: Io, allocator: std.mem.Allocator) ?[]const u8 {
    const exe = std.process.executablePathAlloc(io, allocator) catch return null;
    return std.fs.path.dirname(exe);
}

fn read_file(io: Io, allocator: std.mem.Allocator, path: []const u8) !?[]u8 {
    const dir_path = std.fs.path.dirname(path) orelse ".";
    const name = std.fs.path.basename(path);

    var dir = Io.Dir.openDirAbsolute(io, dir_path, .{}) catch return null;
    defer dir.close(io);

    return dir.readFileAlloc(io, name, allocator, config_limit) catch null;
}

pub fn parse(allocator: std.mem.Allocator, text: []const u8) !Config {
    var entries: std.ArrayList(Entry) = .empty;

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t");
        const value = std.mem.trim(u8, line[eq + 1 ..], " \t");
        if (key.len != 1 or value.len == 0) continue;

        try entries.append(allocator, .{ .key = std.ascii.toLower(key[0]), .app_name = value });
    }

    return .{ .entries = try entries.toOwnedSlice(allocator) };
}
