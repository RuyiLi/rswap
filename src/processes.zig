const std = @import("std");
const win = std.os.windows;

extern "psapi" fn EnumProcesses(lpidProcess: [*]win.DWORD, cb: win.DWORD, lpcbNeeded: *win.DWORD) callconv(.winapi) bool;
extern "psapi" fn EnumProcessModules(hProcess: win.HANDLE, lphModule: *win.HMODULE, cb: win.DWORD, lpcbNeeded: *win.DWORD) callconv(.winapi) bool;
extern "kernel32" fn OpenProcess(dwDesiredAccess: win.DWORD, bInheritHandle: bool, dwProcessId: win.DWORD) callconv(.winapi) ?win.HANDLE;
extern "kernel32" fn CloseHandle(hObject: win.HANDLE) callconv(.winapi) bool;
extern "psapi" fn GetModuleBaseNameW(hProcess: win.HANDLE, hModule: ?win.HMODULE, lpBaseName: win.LPWSTR, nSize: win.DWORD) callconv(.winapi) win.DWORD;

const PROCESS_QUERY_INFORMATION = 0x0400;
const PROCESS_VM_READ = 0x0010;

fn get_process_name(allocator: std.mem.Allocator, pid: win.DWORD) !?[]u16 {
    const handle = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, false, pid);
    if (handle == null) {
        const err = win.GetLastError();
        if (err != win.Win32Error.ACCESS_DENIED) {
            std.debug.print("Failed to acquire handle for pid {}: {}\n", .{ pid, err });
        }
        return null;
    }
    defer _ = CloseHandle(handle.?);

    var module: win.HMODULE = undefined;
    var bytes_needed: win.DWORD = 0;
    if (!EnumProcessModules(handle.?, &module, @sizeOf(win.HMODULE), &bytes_needed)) {
        return null;
    }

    var buf: [1024:0]u16 = undefined;
    const len = GetModuleBaseNameW(handle.?, module, &buf, 1024);
    if (len == 0) {
        return null;
    }

    // std.debug.print("Length of string for pid {} was {}\n", .{ pid, len });

    const out = try allocator.alloc(u16, len);
    @memcpy(out, buf[0..len]);
    return out;
}

pub fn list_process_names(allocator: std.mem.Allocator) !std.ArrayList([]u16) {
    var process_names = try std.ArrayList([]u16).initCapacity(allocator, 1024);

    var process_ids: [1024]win.DWORD = undefined;
    var bytes_needed: win.DWORD = undefined;
    if (!EnumProcesses(&process_ids, process_ids.len, &bytes_needed)) {
        return process_names;
    }

    const num_processes = bytes_needed / @sizeOf(win.DWORD);
    std.debug.print("Found {} process\n", .{num_processes});

    for (process_ids[0..num_processes]) |pid| {
        const name = try get_process_name(allocator, pid) orelse continue;

        const utf8name = try std.unicode.utf16LeToUtf8Alloc(allocator, name);
        std.debug.print("Process name for pid {} is {s}\n", .{ pid, utf8name });
        try process_names.append(allocator, name);
    }

    return process_names;
}
