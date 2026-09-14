//! Resolve windows and Start Menu entries to a stable app identity (AUMID).

const std = @import("std");
const win = std.os.windows;
const win32 = @import("win32.zig");
const com = @import("com.zig");

/// Start Menu entry exposed by `shell:AppsFolder`.
pub const AppEntry = struct {
    display_name: []const u8,
    aumid: ?[]const u8,
};

/// Resolved target, friendly name + Start Menu AUMID.
pub const AppTarget = struct {
    display_name: []const u8,
    aumid: ?[]const u8,
};

/// Best-effort identity for a window.
pub const WindowIdentity = struct {
    aumid: ?[]const u8 = null,
    exe_path: ?[]const u8 = null,
    description: ?[]const u8 = null,
};

var com_ready = false;

pub fn init() void {
    const hr = com.CoInitializeEx(null, com.COINIT_APARTMENTTHREADED);
    com_ready = hr >= 0;
}

pub fn deinit() void {
    if (com_ready) com.CoUninitialize();
}

pub fn window_aumid(allocator: std.mem.Allocator, hwnd: win.HWND) !?[]u8 {
    var store_opaque: ?*anyopaque = null;
    if (com.SHGetPropertyStoreForWindow(hwnd, &com.IID_IPropertyStore, &store_opaque) < 0) return null;

    const store: *com.IPropertyStore = @ptrCast(@alignCast(store_opaque orelse return null));
    defer store.release();

    return try com.get_string_property(allocator, store, &com.PKEY_AppUserModel_ID);
}

/// Full path of the executable owning `hwnd`.
pub fn window_exe_path(allocator: std.mem.Allocator, hwnd: win.HWND) !?[]u8 {
    var pid: win.DWORD = 0;
    _ = win32.GetWindowThreadProcessId(hwnd, &pid);
    if (pid == 0) return null;

    const process = win32.OpenProcess(win32.PROCESS_QUERY_LIMITED_INFORMATION, false, pid) orelse return null;
    defer _ = win32.CloseHandle(process);

    var buf: [1024:0]u16 = undefined;
    var len: win.DWORD = buf.len;
    if (!win32.QueryFullProcessImageNameW(process, 0, &buf, &len).toBool()) return null;

    return try std.unicode.utf16LeToUtf8Alloc(allocator, buf[0..len]);
}

/// Package family name of the process owning `hwnd` or null for unpackaged apps.
pub fn window_package_family_name(allocator: std.mem.Allocator, hwnd: win.HWND) !?[]u8 {
    var pid: win.DWORD = 0;
    _ = win32.GetWindowThreadProcessId(hwnd, &pid);
    if (pid == 0) return null;

    const process = win32.OpenProcess(win32.PROCESS_QUERY_LIMITED_INFORMATION, false, pid) orelse return null;
    defer _ = win32.CloseHandle(process);

    var len: u32 = 0;
    _ = win32.GetPackageFamilyName(process, &len, null);
    if (len == 0) return null;

    const buf = try allocator.alloc(u16, len);
    defer allocator.free(buf);
    if (win32.GetPackageFamilyName(process, &len, buf.ptr) != 0) return null;

    return try std.unicode.utf16LeToUtf8Alloc(allocator, buf[0 .. len - 1]);
}

/// Common identity fields for a window.
pub fn window_identity(allocator: std.mem.Allocator, hwnd: win.HWND) !WindowIdentity {
    var identity = WindowIdentity{};
    identity.exe_path = try window_exe_path(allocator, hwnd);
    identity.aumid = try window_aumid(allocator, hwnd);
    if (identity.exe_path) |path| {
        identity.description = try file_description(allocator, path);
    }
    return identity;
}

/// Does hwnd belong to target?
pub fn window_matches(allocator: std.mem.Allocator, hwnd: win.HWND, target: AppTarget) bool {
    const exe = (window_exe_path(allocator, hwnd) catch return false) orelse return false;

    // exe basename vs target display name
    var stem = std.fs.path.basename(exe);
    if (stem.len > 4 and std.ascii.eqlIgnoreCase(stem[stem.len - 4 ..], ".exe")) {
        stem = stem[0 .. stem.len - 4];
    }
    if (std.ascii.eqlIgnoreCase(stem, target.display_name)) return true;

    if (target.aumid) |aumid| {
        // exe path vs AUMID path
        if (std.ascii.eqlIgnoreCase(exe, aumid)) return true;

        // Window AUMID vs target AUMID
        if (window_aumid(allocator, hwnd) catch null) |window_id| {
            if (std.ascii.eqlIgnoreCase(window_id, aumid)) return true;
        }

        // Package family name vs AUMID "<package family>!<app id>" prefix
        // https://learn.microsoft.com/en-us/windows/configuration/store/find-aumid?tabs=ps%2Cps-10&pivots=windows-11
        if (std.mem.indexOfScalar(u8, aumid, '!')) |bang| {
            if (window_package_family_name(allocator, hwnd) catch null) |family| {
                if (std.ascii.eqlIgnoreCase(family, aumid[0..bang])) return true;
            }
        }
    }

    // Version resource description vs target display name
    if (file_description(allocator, exe) catch null) |desc| {
        if (std.ascii.eqlIgnoreCase(desc, target.display_name)) return true;
    }
    return false;
}

/// Start Menu applications as `(display name, AUMID)` pairs.
pub fn list_start_menu_apps(allocator: std.mem.Allocator) !std.ArrayList(AppEntry) {
    var apps: std.ArrayList(AppEntry) = .empty;

    var folder_opaque: ?*anyopaque = null;
    const apps_folder = std.unicode.utf8ToUtf16LeStringLiteral("shell:AppsFolder");
    if (com.SHCreateItemFromParsingName(apps_folder, null, &com.IID_IShellItem, &folder_opaque) < 0) return apps;

    const folder: *com.IShellItem = @ptrCast(@alignCast(folder_opaque orelse return apps));
    defer folder.release();

    var enum_opaque: ?*anyopaque = null;
    if (folder.bind_to_handler(&com.BHID_EnumItems, &com.IID_IEnumShellItems, &enum_opaque) < 0) return apps;

    const enumerator: *com.IEnumShellItems = @ptrCast(@alignCast(enum_opaque orelse return apps));
    defer enumerator.release();

    while (true) {
        var child_opaque: ?*com.IShellItem = null;
        var fetched: u32 = 0;
        if (enumerator.vtbl.Next(enumerator, 1, &child_opaque, &fetched) < 0) break;
        if (fetched == 0) break;
        const child = child_opaque orelse break;
        defer child.release();

        const display_name = try item_display_name(allocator, child) orelse continue;
        const aumid = try item_aumid(allocator, child);
        try apps.append(allocator, .{ .display_name = display_name, .aumid = aumid });
    }

    return apps;
}

/// Resolve a friendly name from the Start Menu to a target.
pub fn resolve_target(allocator: std.mem.Allocator, display_name: []const u8) !?AppTarget {
    var apps = try list_start_menu_apps(allocator);
    defer apps.deinit(allocator);

    for (apps.items) |app| {
        if (std.ascii.eqlIgnoreCase(app.display_name, display_name)) {
            return .{ .display_name = app.display_name, .aumid = app.aumid };
        }
    }
    return null;
}

fn item_display_name(allocator: std.mem.Allocator, child: *com.IShellItem) !?[]u8 {
    var name_ptr: ?[*:0]u16 = null;
    if (child.display_name(com.SIGDN_NORMALDISPLAY, &name_ptr) < 0) return null;

    const wide = name_ptr orelse return null;
    const utf8 = try std.unicode.utf16LeToUtf8Alloc(allocator, std.mem.span(wide));
    com.CoTaskMemFree(@ptrCast(wide));
    return utf8;
}

fn item_aumid(allocator: std.mem.Allocator, child: *com.IShellItem) !?[]u8 {
    var store_opaque: ?*anyopaque = null;
    if (child.bind_to_handler(&com.BHID_PropertyStore, &com.IID_IPropertyStore, &store_opaque) < 0) return null;

    const store: *com.IPropertyStore = @ptrCast(@alignCast(store_opaque orelse return null));
    defer store.release();

    return try com.get_string_property(allocator, store, &com.PKEY_AppUserModel_ID);
}

pub fn file_description(allocator: std.mem.Allocator, exe_path: []const u8) !?[]u8 {
    const path_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, exe_path);
    defer allocator.free(path_w);

    const size = win32.GetFileVersionInfoSizeW(path_w.ptr, null);
    if (size == 0) return null;

    const data = try allocator.alloc(u8, size);
    defer allocator.free(data);

    if (!win32.GetFileVersionInfoW(path_w.ptr, 0, size, data.ptr).toBool()) return null;

    // First (language, codepage) pair selects the StringFileInfo table.
    const translation_block = std.unicode.utf8ToUtf16LeStringLiteral("\\VarFileInfo\\Translation");
    var trans_ptr: *anyopaque = undefined;
    var trans_len: win.UINT = 0;
    if (!win32.VerQueryValueW(data.ptr, translation_block, &trans_ptr, &trans_len).toBool()) return null;
    if (trans_len < 4) return null;

    const words: [*]u16 = @ptrCast(@alignCast(trans_ptr));
    const lang = words[0];
    const codepage = words[1];

    const subblock = try std.fmt.allocPrint(allocator, "\\StringFileInfo\\{x:0>4}{x:0>4}\\FileDescription", .{ lang, codepage });
    defer allocator.free(subblock);
    const subblock_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, subblock);
    defer allocator.free(subblock_w);

    var desc_ptr: *anyopaque = undefined;
    var desc_len: win.UINT = 0;
    if (!win32.VerQueryValueW(data.ptr, subblock_w.ptr, &desc_ptr, &desc_len).toBool()) return null;
    if (desc_len == 0) return null;

    const wide: [*:0]const u16 = @ptrCast(@alignCast(desc_ptr));
    return try std.unicode.utf16LeToUtf8Alloc(allocator, std.mem.span(wide));
}
