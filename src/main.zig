const std = @import("std");
const applications = @import("applications.zig");
const appmodel = @import("appmodel.zig");
const app_bindings = @import("bindings.zig");
const app_config = @import("config.zig");
const cli = @import("cli.zig");
const watcher = @import("watcher.zig");
const win32 = @import("win32.zig");
const win = std.os.windows;

var bindings: []const app_bindings.Binding = &.{};

// Set while an X1/X2 leader is held. We consume those events, so we track the
// state from the down/up pair instead of polling the async key state.
var mouse_leader_down = false;

// Holds the current config text and bindings. Swapped on reload.
var config_arena: ?*std.heap.ArenaAllocator = null;

// Whether a leader (RightAlt, or a held X1/X2) is currently down.
fn activated() bool {
    return mouse_leader_down or win32.GetAsyncKeyState(win32.VK_RMENU) < 0;
}

// Returns true if the event was consumed and must not reach the app.
fn handle_key_down(kb: *const win32.KBDLLHOOKSTRUCT) bool {
    if (!activated()) return false;
    return dispatch(kb.vkCode);
}

fn handle_sys_key_down(kb: *const win32.KBDLLHOOKSTRUCT) bool {
    if (kb.vkCode == win32.VK_RMENU) {
        applications.reset_cycle();
        return false;
    }
    if (!activated()) return false;
    return dispatch(kb.vkCode);
}

// Handle mouse-based activation. Always swallow so shit like back/forward nav in browsers won't trigger.
fn handle_mouse_down(_: *const win32.MSLLHOOKSTRUCT) bool {
    mouse_leader_down = true;
    applications.reset_cycle();
    return true;
}

fn handle_mouse_up(_: *const win32.MSLLHOOKSTRUCT) bool {
    mouse_leader_down = false;
    return true;
}

// Nust run in same thread as input handler. Returns if input should be swallowed.
fn dispatch(vk_code: u32) bool {
    if (vk_code > 0x7f) return false;
    const key = std.ascii.toLower(@intCast(vk_code));
    for (bindings) |binding| {
        if (binding.key == key) {
            _ = applications.cycle_application(binding.target);
            return true;
        }
    }
    return false;
}

// LowLevelKeyboardProc
fn key_hookproc(n_code: c_int, w_param: win32.WPARAM, l_param: win.LPARAM) callconv(.winapi) win32.LRESULT {
    if (n_code >= 0) {
        const kb = @as(*win32.KBDLLHOOKSTRUCT, @ptrFromInt(@as(usize, @intCast(l_param))));
        if ((kb.flags & win32.LLKHF_INJECTED) == 0) {
            const consumed = switch (w_param) {
                win32.WM_KEYDOWN => handle_key_down(kb),
                win32.WM_SYSKEYDOWN => handle_sys_key_down(kb),
                else => false,
            };
            if (consumed) return 1;
        }
    }
    return win32.CallNextHookEx(null, n_code, w_param, l_param);
}

// LowLevelMouseProc
fn mouse_hookproc(n_code: c_int, w_param: win32.WPARAM, l_param: win.LPARAM) callconv(.winapi) win32.LRESULT {
    if (n_code >= 0) {
        const ms = @as(*win32.MSLLHOOKSTRUCT, @ptrFromInt(@as(usize, @intCast(l_param))));
        if ((ms.flags & win32.LLMHF_INJECTED) == 0) {
            const consumed = switch (w_param) {
                win32.WM_XBUTTONDOWN => handle_mouse_down(ms),
                win32.WM_XBUTTONUP => handle_mouse_up(ms),
                else => false,
            };
            if (consumed) return 1;
        }
    }
    return win32.CallNextHookEx(null, n_code, w_param, l_param);
}

// (Re)build `bindings` from the config file into a fresh arena. The old arena
// is freed only after the new bindings exist, so a hook can never observe
// freed bindings. Returns the config path (for watching).
fn apply_config(io: std.Io, backing: std.mem.Allocator) ![]const u8 {
    const arena = try backing.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    errdefer {
        arena.deinit();
        backing.destroy(arena);
    }

    const loaded = try app_config.load(io, arena.allocator());
    const new_bindings = try app_bindings.build(arena.allocator(), loaded.config);

    // Swap in the new bindings and drop every reference into the old arena
    // (the cached cycle target points at a `display_name` inside it) before
    // freeing it.
    const old_arena = config_arena;
    config_arena = arena;
    bindings = new_bindings;
    applications.reset_cycle();

    if (old_arena) |old| {
        old.deinit();
        backing.destroy(old);
    }
    return loaded.path;
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    const args = try std.process.Args.toSlice(init.minimal.args, allocator);
    if (args.len > 1) return cli.run(init.io, allocator, args);

    appmodel.init();
    defer appmodel.deinit();

    const config_path = try apply_config(init.io, allocator);
    std.debug.print("rswap: loaded {} binding(s)\n", .{bindings.len});

    if (watcher.Watcher.start(allocator, config_path, win32.GetCurrentThreadId())) |_| {} else |err| {
        std.debug.print("config watch unavailable: {t}\n", .{err});
    }

    const kb_hook = win32.SetWindowsHookExW(win32.WH_KEYBOARD_LL, key_hookproc, null, 0);
    if (kb_hook == null) {
        std.debug.print("Failed to install keyboard hook\n", .{});
        return;
    }
    defer _ = win32.UnhookWindowsHookEx(kb_hook);

    const ms_hook = win32.SetWindowsHookExW(win32.WH_MOUSE_LL, mouse_hookproc, null, 0);
    if (ms_hook == null) {
        std.debug.print("Failed to install mouse hook\n", .{});
        return;
    }

    std.debug.print("Hooks mounted, waiting for sigterm\n", .{});

    var msg: win32.MSG = undefined;
    while (win32.GetMessageW(&msg, null, 0, 0)) {
        if (msg.message == watcher.WM_RELOAD) {
            _ = apply_config(init.io, allocator) catch |err| {
                std.debug.print("config reload failed: {t}\n", .{err});
                continue;
            };
            std.debug.print("rswap: loaded {} binding(s)\n", .{bindings.len});
        }
    }
}
