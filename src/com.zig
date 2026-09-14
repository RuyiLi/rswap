//! COM bindings for reading application identity.

const std = @import("std");
const win = std.os.windows;

pub const HRESULT = i32;
pub const GUID = win.GUID;

pub const COINIT_APARTMENTTHREADED: win.DWORD = 0x2;
pub const VT_LPWSTR: u16 = 31;
pub const SIGDN_NORMALDISPLAY: c_int = 0x0;

// ---------------------------------------------------------------------------
// DLL entry points
// ---------------------------------------------------------------------------

/// https://learn.microsoft.com/en-us/windows/win32/api/combaseapi/nf-combaseapi-coinitializeex
pub extern "ole32" fn CoInitializeEx(pvReserved: ?*anyopaque, dwCoInit: win.DWORD) callconv(.winapi) HRESULT;
pub extern "ole32" fn CoUninitialize() callconv(.winapi) void;
pub extern "ole32" fn CoTaskMemFree(pv: ?*anyopaque) callconv(.winapi) void;

/// https://learn.microsoft.com/en-us/windows/win32/api/propidl/nf-propidl-propvariantclear
pub extern "ole32" fn PropVariantClear(pvar: *PROPVARIANT) callconv(.winapi) HRESULT;

/// https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shgetpropertystoreforwindow
pub extern "shell32" fn SHGetPropertyStoreForWindow(hwnd: win.HWND, riid: *const GUID, ppv: *?*anyopaque) callconv(.winapi) HRESULT;

/// https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-shcreateitemfromparsingname
pub extern "shell32" fn SHCreateItemFromParsingName(pszPath: win.LPCWSTR, pbc: ?*anyopaque, riid: *const GUID, ppv: *?*anyopaque) callconv(.winapi) HRESULT;

// ---------------------------------------------------------------------------
// Windows Property System
// ---------------------------------------------------------------------------

/// https://learn.microsoft.com/en-us/windows/win32/api/wtypes/ns-wtypes-propertykey
pub const PROPERTYKEY = extern struct {
    fmtid: GUID,
    pid: win.DWORD,
};

/// https://learn.microsoft.com/en-us/windows/win32/api/propidl/ns-propidl-propvariant
pub const PROPVARIANT = extern struct {
    vt: u16,
    wReserved1: u16,
    wReserved2: u16,
    wReserved3: u16,
    data: extern union {
        // We only care about this prop, pad for alignment
        pwszVal: ?[*:0]u16,
        _pad: [2]u64,
    },
};

/// https://learn.microsoft.com/en-us/windows/win32/properties/props-system-appusermodel-id
pub const PKEY_AppUserModel_ID = PROPERTYKEY{
    .fmtid = .{
        .Data1 = 0x9f4c2855,
        .Data2 = 0x9f79,
        .Data3 = 0x4b39,
        .Data4 = .{ 0xa8, 0xd0, 0xe1, 0xd4, 0x2d, 0xe1, 0xd5, 0xf3 },
    },
    .pid = 5,
};

// ---------------------------------------------------------------------------
// IIDs / BHIDs
// https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-ishellitem-bindtohandler
// ---------------------------------------------------------------------------

pub const IID_IPropertyStore = GUID{
    .Data1 = 0x886d8eeb,
    .Data2 = 0x8cf2,
    .Data3 = 0x4446,
    .Data4 = .{ 0x8d, 0x02, 0xcd, 0xba, 0x1d, 0xbd, 0xcf, 0x99 },
};

pub const IID_IShellItem = GUID{
    .Data1 = 0x43826d1e,
    .Data2 = 0xe718,
    .Data3 = 0x42ee,
    .Data4 = .{ 0xbc, 0x55, 0xa1, 0xe2, 0x61, 0xc3, 0x7b, 0xfe },
};

pub const IID_IEnumShellItems = GUID{
    .Data1 = 0x70629033,
    .Data2 = 0xe363,
    .Data3 = 0x4a28,
    .Data4 = .{ 0xa5, 0x67, 0x0d, 0xb7, 0x80, 0x06, 0xe6, 0xd7 },
};

pub const BHID_EnumItems = GUID{
    .Data1 = 0x94f60519,
    .Data2 = 0x2850,
    .Data3 = 0x4924,
    .Data4 = .{ 0xaa, 0x5a, 0xd1, 0x5e, 0x84, 0x86, 0x80, 0x39 },
};

pub const BHID_PropertyStore = GUID{
    .Data1 = 0x0384e1a4,
    .Data2 = 0x1523,
    .Data3 = 0x439c,
    .Data4 = .{ 0xa4, 0xc8, 0xab, 0x91, 0x10, 0x52, 0xf5, 0x86 },
};

// ---------------------------------------------------------------------------
// Interfaces
// ---------------------------------------------------------------------------

/// https://learn.microsoft.com/en-us/windows/win32/api/propsys/nn-propsys-ipropertystore
pub const IPropertyStore = extern struct {
    vtbl: *const Vtbl,

    pub const Vtbl = extern struct {
        QueryInterface: *const fn (*IPropertyStore, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*IPropertyStore) callconv(.winapi) u32,
        Release: *const fn (*IPropertyStore) callconv(.winapi) u32,
        GetCount: *const fn (*IPropertyStore, *win.DWORD) callconv(.winapi) HRESULT,
        GetAt: *const fn (*IPropertyStore, win.DWORD, *PROPERTYKEY) callconv(.winapi) HRESULT,
        GetValue: *const fn (*IPropertyStore, *const PROPERTYKEY, *PROPVARIANT) callconv(.winapi) HRESULT,
        SetValue: *const fn (*IPropertyStore, *const PROPERTYKEY, *const PROPVARIANT) callconv(.winapi) HRESULT,
        Commit: *const fn (*IPropertyStore) callconv(.winapi) HRESULT,
    };

    pub fn release(self: *IPropertyStore) void {
        _ = self.vtbl.Release(self);
    }
};

/// https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-ishellitem
pub const IShellItem = extern struct {
    vtbl: *const Vtbl,

    pub const Vtbl = extern struct {
        QueryInterface: *const fn (*IShellItem, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*IShellItem) callconv(.winapi) u32,
        Release: *const fn (*IShellItem) callconv(.winapi) u32,
        BindToHandler: *const fn (*IShellItem, ?*anyopaque, *const GUID, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        GetParent: *const fn (*IShellItem, *?*IShellItem) callconv(.winapi) HRESULT,
        GetDisplayName: *const fn (*IShellItem, c_int, *?[*:0]u16) callconv(.winapi) HRESULT,
        GetAttributes: *const fn (*IShellItem, u32, *u32) callconv(.winapi) HRESULT,
        Compare: *const fn (*IShellItem, *IShellItem, u32, *c_int) callconv(.winapi) HRESULT,
    };

    pub fn release(self: *IShellItem) void {
        _ = self.vtbl.Release(self);
    }

    pub fn bind_to_handler(self: *IShellItem, bhid: *const GUID, riid: *const GUID, ppv: *?*anyopaque) HRESULT {
        return self.vtbl.BindToHandler(self, null, bhid, riid, ppv);
    }

    pub fn display_name(self: *IShellItem, sigdn: c_int, out: *?[*:0]u16) HRESULT {
        return self.vtbl.GetDisplayName(self, sigdn, out);
    }
};

/// https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-ienumshellitems
pub const IEnumShellItems = extern struct {
    vtbl: *const Vtbl,

    pub const Vtbl = extern struct {
        QueryInterface: *const fn (*IEnumShellItems, *const GUID, *?*anyopaque) callconv(.winapi) HRESULT,
        AddRef: *const fn (*IEnumShellItems) callconv(.winapi) u32,
        Release: *const fn (*IEnumShellItems) callconv(.winapi) u32,
        Next: *const fn (*IEnumShellItems, u32, *?*IShellItem, ?*u32) callconv(.winapi) HRESULT,
        Skip: *const fn (*IEnumShellItems, u32) callconv(.winapi) HRESULT,
        Reset: *const fn (*IEnumShellItems) callconv(.winapi) HRESULT,
        Clone: *const fn (*IEnumShellItems, *?*IEnumShellItems) callconv(.winapi) HRESULT,
    };

    pub fn release(self: *IEnumShellItems) void {
        _ = self.vtbl.Release(self);
    }
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Reads a string property as a UTF-8 copy owned by `allocator`.
pub fn get_string_property(allocator: std.mem.Allocator, store: *IPropertyStore, key: *const PROPERTYKEY) !?[]u8 {
    var pv: PROPVARIANT = std.mem.zeroes(PROPVARIANT);
    if (store.vtbl.GetValue(store, key, &pv) < 0) return null;
    defer _ = PropVariantClear(&pv);

    if (pv.vt != VT_LPWSTR) return null;
    const wide = pv.data.pwszVal orelse return null;
    return try std.unicode.utf16LeToUtf8Alloc(allocator, std.mem.span(wide));
}
