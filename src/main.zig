const std = @import("std");
const processes = @import("processes.zig");
const applications = @import("applications.zig");
const win = std.os.windows;

const HHOOK = *opaque {};
const HOOKPROC = *const fn (nCode: c_int, wParam: win.WPARAM, lParam: win.LPARAM) callconv(.winapi) win.LRESULT;
const KBDLLHOOKSTRUCT = extern struct {
    vkCode: u32,
    scanCode: u32,
    flags: u32,
    time: u32,
    dwExtraInfo: u32,
};
const MSLLHOOKSTRUCT = extern struct {
    pt: win.POINT,
    mouseData: win.DWORD,
    flags: win.DWORD,
    time: win.DWORD,
    dwExtraInfo: win.ULONG_PTR,
};
const MSG = extern struct {
    hwnd: win.HWND,
    message: u32,
    wParam: win.WPARAM,
    lParam: win.LPARAM,
    time: win.DWORD,
    pt: win.POINT,
    lPrivate: win.DWORD,
};

extern "user32" fn SetWindowsHookExW(idHook: c_int, lpfn: HOOKPROC, hMod: ?win.HINSTANCE, dwThreadId: win.DWORD) callconv(.winapi) ?HHOOK;
extern "user32" fn CallNextHookEx(hhk: ?HHOOK, nCode: c_int, wParam: win.WPARAM, lParam: win.LPARAM) callconv(.winapi) win.LRESULT;
extern "user32" fn UnhookWindowsHookEx(hhk: ?HHOOK) callconv(.winapi) bool;
extern "user32" fn GetMessageW(lpMsg: *MSG, hwnd: ?win.HWND, wMsgFilterMin: u32, wMsgFilterMax: u32) callconv(.winapi) bool;

const WH_KEYBOARD_LL = 13;
const WH_MOUSE_LL = 14;
const WM_KEYDOWN = 0x0100;
const WM_SYSKEYDOWN = 0x0104;
const WM_SYSKEYUP = 0x0105;
const VK_RMENU = 0xA5;
const WM_XBUTTONDOWN = 0x020B;
const WM_XBUTTONUP = 0x020C;

const ActionHookHandler = struct {
    allocator: std.mem.Allocator,
    seq_action: std.StringHashMap([]const u8),
    mod_held: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return ActionHookHandler{
            .allocator = allocator,
            .seq_action = std.StringHashMap([]const u8).init(allocator),
            .mod_held = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.seq_action.deinit();
    }

    pub fn keydown(self: *Self, kb: *const KBDLLHOOKSTRUCT) void {
        std.debug.print("keydown: {}\n", .{kb});
        std.debug.print("mod_held: {}\n", .{self.mod_held});
        // _ = self;
        // _ = kb;
        if (!self.mod_held) {
            return;
        }

        const name = "edge";
        const cast = @as([*]const u16, @ptrCast(@alignCast(name)))[0..2];
        applications.activate_application(cast);
    }

    pub fn syskeydown(self: *Self, kb: *const KBDLLHOOKSTRUCT) void {
        std.debug.print("syskeydown: {}\n", .{kb});
        if (kb.vkCode == VK_RMENU) {
            self.mod_held = true;
        }
    }

    pub fn syskeyup(self: *Self, kb: *const KBDLLHOOKSTRUCT) void {
        std.debug.print("syskeyup: {}\n", .{kb});
        self.mod_held = false;
    }

    pub fn mousedown(self: *Self, ms: *const MSLLHOOKSTRUCT) void {
        const btn = ms.mouseData >> 16;
        std.debug.print("mousebtn: {}\n", .{btn});
        self.mod_held = true;
    }

    pub fn mouseup(self: *Self, ms: *const MSLLHOOKSTRUCT) void {
        const btn = ms.mouseData >> 16;
        std.debug.print("mouseup: {}\n", .{btn});
        self.mod_held = false;
    }
};

var handler_g: ?*ActionHookHandler = null;

// LowLevelKeyboardProc
fn key_hookproc(n_code: c_int, w_param: win.WPARAM, l_param: win.LPARAM) callconv(.winapi) win.LRESULT {
    if (n_code >= 0) {
        const kb = @as(*KBDLLHOOKSTRUCT, @ptrFromInt(@as(usize, @intCast(l_param))));
        switch (w_param) {
            WM_KEYDOWN => handler_g.?.keydown(kb),
            WM_SYSKEYDOWN => handler_g.?.syskeydown(kb),
            WM_SYSKEYUP => handler_g.?.syskeyup(kb),
            else => {},
        }
    }
    return CallNextHookEx(null, n_code, w_param, l_param);
}

// LowLevelMouseProc
fn mouse_hookproc(n_code: c_int, w_param: win.WPARAM, l_param: win.LPARAM) callconv(.winapi) win.LRESULT {
    if (n_code >= 0) {
        const ms = @as(*MSLLHOOKSTRUCT, @ptrFromInt(@as(usize, @intCast(l_param))));
        switch (w_param) {
            WM_XBUTTONDOWN => handler_g.?.mousedown(ms),
            WM_XBUTTONUP => handler_g.?.mouseup(ms),
            else => {},
        }
    }
    return CallNextHookEx(null, n_code, w_param, l_param);
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // var process_names = try processes.list_process_names(allocator);
    // defer process_names.deinit(allocator);

    // var process_names = try applications.list_applications(allocator);
    // defer process_names.deinit(allocator);

    // for (process_names.items) |name| {
    //     const utf8string = try std.unicode.utf16LeToUtf8Alloc(allocator, name);
    //     std.debug.print("App: {s}\n", .{utf8string});
    // }

    var handler = ActionHookHandler.init(allocator);
    defer handler.deinit();

    // handler.seq_action.put("a", "..");
    handler_g = &handler;

    const kb_hook = SetWindowsHookExW(WH_KEYBOARD_LL, key_hookproc, null, 0);
    if (kb_hook == null) {
        std.debug.print("Failed to install keyboard hook\n", .{});
        return;
    }
    defer _ = UnhookWindowsHookEx(kb_hook);

    const ms_hook = SetWindowsHookExW(WH_MOUSE_LL, mouse_hookproc, null, 0);
    if (ms_hook == null) {
        std.debug.print("Failed to install mouse hook\n", .{});
        return;
    }

    std.debug.print("Hooks mounted, waiting for sigterm\n", .{});

    var msg: MSG = undefined;
    while (GetMessageW(&msg, null, 0, 0)) {}
}
