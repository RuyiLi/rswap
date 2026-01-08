const std = @import("std");
const win = std.os.windows;

const WNDENUMPROC = *const fn (hwnd: win.HWND, lParam: win.LPARAM) callconv(.winapi) bool;

extern "user32" fn EnumWindows(lpEnumFunc: WNDENUMPROC, lParam: win.LPARAM) callconv(.winapi) bool;
extern "user32" fn IsWindowVisible(hwnd: win.HWND) callconv(.winapi) bool;
extern "user32" fn GetWindowTextW(hwnd: win.HWND, lpString: win.LPWSTR, nMaxCount: c_int) callconv(.winapi) c_int;
extern "dwmapi" fn DwmGetWindowAttribute(hwnd: win.HWND, dwAttribute: win.DWORD, pvAttribute: win.PVOID, cbAttribute: win.DWORD) callconv(.winapi) win.HRESULT;
extern "user32" fn GetWindowThreadProcessId(hwnd: win.HWND, lpdwProcessId: *win.DWORD) callconv(.winapi) win.DWORD;
extern "kernel32" fn OpenProcess(dwDesiredAccess: win.DWORD, bInheritHandle: bool, dwProcessId: win.DWORD) callconv(.winapi) ?win.HANDLE;
extern "user32" fn QueryFullProcessImageNameW(hProcess: win.HANDLE, dwFlags: win.DWORD, lpExeName: win.LPWSTR, lpDwSize: *win.DWORD) callconv(.winapi) win.BOOL;
extern "user32" fn GetFileVersionInfoSizeW(lpstrFilename: *const win.WCHAR, lpdwHandle: ?*win.DWORD) callconv(.winapi) win.DWORD;
extern "user32" fn GetFileVersionInfoW(lptstrFilename: *const win.WCHAR, dwHandle: win.DWORD, dwLen: win.DWORD, lpData: win.PVOID) callconv(.winapi) bool;
extern "user32" fn VerQueryValueA(pBlock: *win.LPCVOID, lpSubBlock: win.LPCSTR, lplpBuffer: *win.LPVOID, puLen: *win.UINT) callconv(.winapi) bool;
extern "user32" fn ShowWindow(hwnd: win.HWND, nCmdShow: c_int) callconv(.winapi) win.BOOL;
extern "user32" fn SetForegroundWindow(hwnd: win.HWND) callconv(.winapi) win.BOOL;

const PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
const DWMWA_CLOAKED: win.DWORD = 14;

const CollectActiveWindowsParams = struct { names: std.ArrayList([]u16), allocator: std.mem.Allocator };

// assume error => cloaked
fn is_cloaked(hwnd: win.HWND) bool {
    var attr_val: win.DWORD = 0;
    const hresult = DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &attr_val, @sizeOf(win.DWORD));
    if (hresult != 0) {
        return true;
    }
    return attr_val != 0;
}

fn collect_active_windows(hwnd: win.HWND, l_param: win.LPARAM) callconv(.winapi) bool {
    const params_ptr: usize = @intCast(l_param);
    const params: *CollectActiveWindowsParams = @ptrFromInt(params_ptr);
    var names: std.ArrayList([]u16) = params.names;
    const allocator: std.mem.Allocator = params.allocator;

    if (IsWindowVisible(hwnd) and !is_cloaked(hwnd)) {
        var pid: u32 = 0;
        _ = GetWindowThreadProcessId(hwnd, &pid);

        const h_process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) orelse return true;
        defer _ = win.CloseHandle(h_process);

        var buf: [1024:0]u16 = undefined;
        var len: u32 = 1024;

        if (QueryFullProcessImageNameW(h_process, 0, &buf, &len) == 0) {
            const err = win.GetLastError();
            std.debug.print("Failed to get window name: {}\n", .{err});
            return true;
        }

        // Short window name test
        // const filename = buf[0..len];
        // const bytes = GetFileVersionInfoSizeW(&filename, null);

        // var data = allocator.alloc(u8, bytes) catch return true;
        // errdefer allocator.free(data);

        // if (GetFileVersionInfoW(filename, 0, version_size, out.ptr) == 0) {
        //     const err = win.GetLastError();
        //     std.debug.print("Failed to get version info: {}\n", .{err});
        //     return true;
        // }

        // var trans_ptr: ?*anyopaque = null;
        // var trans_len: u32 = 0;
        // if (VerQueryValueA(out.ptr, "\\VarFileInfo\\Translation", &trans_ptr, &trans_len) == 0) {}

        const name = allocator.alloc(u16, len) catch return true;
        @memcpy(name, buf[0..len]);
        const s = std.unicode.utf16LeToUtf8AllocZ(allocator, name) catch "idk";
        std.debug.print("Found: {s}\n", .{s});

        names.append(allocator, name) catch return true;

        // Window switching test
        // if (std.mem.count(u8, s, "edge") > 0) {
        //     std.Thread.sleep(2000000000);
        //     _ = ShowWindow(hwnd, 5);
        //     _ = SetForegroundWindow(hwnd);
        //     return false;
        // }

        // var buf: [1024:0]u16 = undefined;
        // const len = GetWindowTextW(hwnd, &buf, 1024);
        // if (len == 0) {
        //     const err = win.GetLastError();
        //     std.debug.print("Failed to get window name: {}\n", .{err});
        //     return true;
        // }

        // std.debug.print("Found app with len: {}\n", .{len});
        // const ulen: usize = @intCast(len);
        // const name = allocator.alloc(u16, ulen) catch return true;
        // @memcpy(name, buf[0..ulen]);

        // const utf8string = std.unicode.utf16LeToUtf8Alloc(allocator, name) catch "";
        // std.debug.print("as: {s}\n", .{utf8string});

        // names.append(allocator, name) catch return true;
    }

    return true;
}

pub fn list_applications(allocator: std.mem.Allocator) !std.ArrayList([]u16) {
    const names = try std.ArrayList([]u16).initCapacity(allocator, 1024);
    const params = CollectActiveWindowsParams{
        .names = names,
        .allocator = allocator,
    };

    const lp: win.LPARAM = @intCast(@intFromPtr(&params));
    _ = EnumWindows(&collect_active_windows, lp);
    return names;
}

fn find_and_activate_window(hwnd: win.HWND, l_param: win.LPARAM) callconv(.winapi) bool {
    const name_ptr: usize = @intCast(l_param);
    const name: *[]u16 = @ptrFromInt(name_ptr);
    _ = name;

    if (IsWindowVisible(hwnd) and !is_cloaked(hwnd)) {
        var pid: u32 = 0;
        _ = GetWindowThreadProcessId(hwnd, &pid);

        const h_process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) orelse return true;
        defer _ = win.CloseHandle(h_process);

        var buf: [1024:0]u16 = undefined;
        var len: u32 = 1024;

        if (QueryFullProcessImageNameW(h_process, 0, &buf, &len) == 0) {
            const err = win.GetLastError();
            std.debug.print("Failed to get window name: {}\n", .{err});
            return true;
        }

        const edge: []const u16 = &[_]u16{ 'e', 'd', 'g', 'e' };
        const res = std.mem.count(u16, buf[0..len], edge);
        // std.debug.print("FN {}\n", .{res});
        if (res > 0) {
            // std.Thread.sleep(2000000000);
            _ = ShowWindow(hwnd, 5);
            _ = SetForegroundWindow(hwnd);
            return false;
        }
    }
    return true;
}

pub fn activate_application(name: []const u16) void {
    const l_param: win.LPARAM = @intCast(@intFromPtr(&name));
    _ = EnumWindows(&find_and_activate_window, l_param);
}
