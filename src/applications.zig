//! Logic for window cycling + force focusing.

const std = @import("std");
const win = std.os.windows;
const win32 = @import("win32.zig");
const appmodel = @import("appmodel.zig");

const log = std.log.scoped(.rswap);

var cycle_windows: [64]win.HWND = undefined;
var cycle_len: usize = 0;
var cycle_index: usize = 0;
var cycle_active = false;
var cycle_target: ?appmodel.AppTarget = null;

const ScanCtx = struct {
    allocator: std.mem.Allocator,
    target: appmodel.AppTarget,
    windows: []win.HWND,
    len: usize = 0,
};

fn is_cloaked(hwnd: win.HWND) bool {
    var attr_val: win.DWORD = 0;
    const hresult = win32.DwmGetWindowAttribute(hwnd, win32.DWMWA_CLOAKED, &attr_val, @sizeOf(win.DWORD));
    if (hresult != 0) return true;
    return attr_val != 0;
}

fn scan_callback(hwnd: win.HWND, l_param: win.LPARAM) callconv(.winapi) bool {
    const ctx: *ScanCtx = @ptrFromInt(@as(usize, @intCast(l_param)));
    if (ctx.len >= ctx.windows.len) return false;
    if (!win32.IsWindowVisible(hwnd)) return true;
    if (is_cloaked(hwnd)) return true;
    if (!appmodel.window_matches(ctx.allocator, hwnd, ctx.target)) return true;
    ctx.windows[ctx.len] = hwnd;
    ctx.len += 1;
    return true;
}

// Create snapshot of windows matching target app.
fn start_scan() void {
    const target = cycle_target orelse return;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var ctx = ScanCtx{
        .allocator = arena.allocator(),
        .target = target,
        .windows = cycle_windows[0..],
    };
    const lp: win.LPARAM = @intCast(@intFromPtr(&ctx));
    _ = win32.EnumWindows(&scan_callback, lp);

    cycle_len = ctx.len;
    cycle_index = 0;
    cycle_active = true;
}

/// TODO opening a new window while the leader is still held down might not update snapshot
pub fn cycle_application(target: appmodel.AppTarget) bool {
    if (cycle_target == null or !std.mem.eql(u8, cycle_target.?.display_name, target.display_name)) {
        reset_cycle();
        cycle_target = target;
    }

    if (!cycle_active or cycle_len == 0) start_scan();

    // Check staleness (window closed mid cycle)
    if (cycle_len > 0 and !win32.IsWindow(cycle_windows[cycle_index]).toBool()) {
        start_scan();
    }

    if (cycle_len == 0) {
        log.warn("no window found for '{s}'", .{target.display_name});
        return false;
    }

    const hwnd = cycle_windows[cycle_index];
    cycle_index = (cycle_index + 1) % cycle_len;
    focus_window(hwnd);
    return true;
}

pub fn reset_cycle() void {
    cycle_active = false;
    cycle_len = 0;
    cycle_index = 0;
    cycle_target = null;
}

// Bring the window corresponding to `hwnd` to the foreground.
fn focus_window(hwnd: win.HWND) void {
    const cmd: c_int = if (win32.IsIconic(hwnd).toBool()) win32.SW_RESTORE else win32.SW_SHOW;
    _ = win32.ShowWindow(hwnd, cmd);

    // Temp merge window thread input queues of foreground & target
    // If we do this in a bg thread/attach our own thread, Windows will block and flash the app icon instead
    // Partially inspired by https://github.com/AutoHotkey/AutoHotkey/blob/alpha/source/window.cpp
    const foreground = win32.GetForegroundWindow();
    const foreground_thread = if (foreground) |fg| win32.GetWindowThreadProcessId(fg, null) else 0;
    const target_thread = win32.GetWindowThreadProcessId(hwnd, null);

    var attached = false;
    if (foreground_thread != 0 and target_thread != 0 and foreground_thread != target_thread) {
        // https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-attachthreadinput#remarks
        attached = win32.AttachThreadInput(foreground_thread, target_thread, true).toBool();
    }

    // https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setforegroundwindow#remarks
    _ = win32.SetForegroundWindow(hwnd);
    _ = win32.BringWindowToTop(hwnd);
    if (attached) {
        _ = win32.AttachThreadInput(foreground_thread, target_thread, false);
    }
}
