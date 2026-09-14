//! Map config entries to resolved app targets.

const std = @import("std");
const appmodel = @import("appmodel.zig");
const app_config = @import("config.zig");

pub const Binding = struct {
    key: u8,
    target: appmodel.AppTarget,
};

pub fn build(allocator: std.mem.Allocator, cfg: app_config.Config) ![]Binding {
    var list: std.ArrayList(Binding) = .empty;
    for (cfg.entries) |entry| {
        const target = (try appmodel.resolve_target(allocator, entry.app_name)) orelse {
            std.debug.print("config: no Start Menu app named '{s}'\n", .{entry.app_name});
            continue;
        };
        try list.append(allocator, .{ .key = entry.key, .target = target });
    }
    return try list.toOwnedSlice(allocator);
}
