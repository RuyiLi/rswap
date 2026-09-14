//! Diagnostic CLI commands.

const std = @import("std");
const appmodel = @import("appmodel.zig");
const app_config = @import("config.zig");
const app_bindings = @import("bindings.zig");
const win32 = @import("win32.zig");
const win = std.os.windows;

// Runs a CLI command from `args` (args[0] is the program name). COM is
// initialized for the duration of the command.
pub fn run(io: std.Io, allocator: std.mem.Allocator, args: []const [:0]const u8) !void {
    appmodel.init();
    defer appmodel.deinit();

    if (std.mem.eql(u8, args[1], "--list-apps")) return run_list_apps(allocator);
    if (std.mem.eql(u8, args[1], "--list-windows")) return run_list_windows(allocator);
    if (std.mem.eql(u8, args[1], "--list-bindings")) return run_list_bindings(io, allocator);
    if (std.mem.eql(u8, args[1], "--find") and args.len > 2) return run_find(allocator, args[2]);
    std.debug.print("unknown argument: {s}\n", .{args[1]});
}

const ListWindowsCtx = struct { allocator: std.mem.Allocator };

fn list_windows_callback(hwnd: win.HWND, l_param: win.LPARAM) callconv(.winapi) bool {
    const ctx: *ListWindowsCtx = @ptrFromInt(@as(usize, @intCast(l_param)));
    const allocator = ctx.allocator;

    if (!win32.IsWindowVisible(hwnd)) return true;

    const identity = appmodel.window_identity(allocator, hwnd) catch return true;
    if (identity.exe_path == null and identity.aumid == null) return true;

    std.debug.print("{s}\n    aumid: {s}\n    description: {s}\n", .{
        identity.exe_path orelse "(unknown exe)",
        identity.aumid orelse "(none)",
        identity.description orelse "(none)",
    });
    return true;
}

fn run_list_windows(allocator: std.mem.Allocator) !void {
    var ctx = ListWindowsCtx{ .allocator = allocator };
    const lp: win.LPARAM = @intCast(@intFromPtr(&ctx));
    _ = win32.EnumWindows(&list_windows_callback, lp);
}

fn run_list_apps(allocator: std.mem.Allocator) !void {
    var apps = try appmodel.list_start_menu_apps(allocator);
    defer apps.deinit(allocator);

    std.debug.print("shell:AppsFolder entries: {}\n", .{apps.items.len});
    for (apps.items) |app| {
        std.debug.print("  {s}\n      aumid: {s}\n", .{ app.display_name, app.aumid orelse "(none)" });
    }
}

fn run_list_bindings(io: std.Io, allocator: std.mem.Allocator) !void {
    const loaded_cfg = try app_config.load(io, allocator);
    const loaded = try app_bindings.build(allocator, loaded_cfg.config);
    for (loaded) |binding| {
        std.debug.print("{c} -> {s} (aumid: {s})\n", .{
            binding.key,
            binding.target.display_name,
            binding.target.aumid orelse "(none)",
        });
    }
}

const FindCtx = struct {
    allocator: std.mem.Allocator,
    target: appmodel.AppTarget,
    count: usize = 0,
};

fn find_callback(hwnd: win.HWND, l_param: win.LPARAM) callconv(.winapi) bool {
    const ctx: *FindCtx = @ptrFromInt(@as(usize, @intCast(l_param)));
    if (!win32.IsWindowVisible(hwnd)) return true;
    if (!appmodel.window_matches(ctx.allocator, hwnd, ctx.target)) return true;
    const exe = appmodel.window_exe_path(ctx.allocator, hwnd) catch null;
    std.debug.print("  {s}\n", .{exe orelse "(unknown exe)"});
    ctx.count += 1;
    return true;
}

fn run_find(allocator: std.mem.Allocator, name: []const u8) !void {
    const target = (try appmodel.resolve_target(allocator, name)) orelse {
        std.debug.print("no Start Menu app named '{s}'\n", .{name});
        return;
    };

    var ctx = FindCtx{ .allocator = allocator, .target = target };
    const lp: win.LPARAM = @intCast(@intFromPtr(&ctx));
    _ = win32.EnumWindows(&find_callback, lp);
    std.debug.print("{} window(s) for {s}\n", .{ ctx.count, target.display_name });
}
