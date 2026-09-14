//! Win32 bindings

const std = @import("std");
const win = std.os.windows;

pub const HRESULT = i32;
pub const WPARAM = usize;
pub const LRESULT = isize;

pub const HHOOK = *opaque {};
pub const HOOKPROC = *const fn (nCode: c_int, wParam: WPARAM, lParam: win.LPARAM) callconv(.winapi) LRESULT;
pub const WNDENUMPROC = *const fn (hwnd: win.HWND, lParam: win.LPARAM) callconv(.winapi) bool;

pub const POINT = extern struct { x: i32, y: i32 };

pub const KBDLLHOOKSTRUCT = extern struct {
    vkCode: u32,
    scanCode: u32,
    flags: u32,
    time: u32,
    dwExtraInfo: u32,
};

pub const MSLLHOOKSTRUCT = extern struct {
    pt: POINT,
    mouseData: win.DWORD,
    flags: win.DWORD,
    time: win.DWORD,
    dwExtraInfo: win.ULONG_PTR,
};

pub const MSG = extern struct {
    hwnd: win.HWND,
    message: u32,
    wParam: WPARAM,
    lParam: win.LPARAM,
    time: win.DWORD,
    pt: POINT,
    lPrivate: win.DWORD,
};

pub const OVERLAPPED = extern struct {
    Internal: win.ULONG_PTR,
    InternalHigh: win.ULONG_PTR,
    offset: u64,
    hEvent: ?win.HANDLE,
};

/// https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-file_notify_information
pub const FILE_NOTIFY_INFORMATION = extern struct {
    NextEntryOffset: u32,
    Action: u32,
    FileNameLength: u32,
};

/// Hook types
pub const WH_KEYBOARD_LL = 13;
pub const WH_MOUSE_LL = 14;

/// Window messages
pub const WM_APP: u32 = 0x8000;
pub const WM_KEYDOWN = 0x0100;
pub const WM_SYSKEYDOWN = 0x0104;
pub const WM_XBUTTONDOWN = 0x020B;
pub const WM_XBUTTONUP = 0x020C;

/// Virtual keys
pub const VK_XBUTTON1 = 0x05;
pub const VK_XBUTTON2 = 0x06;
pub const VK_RMENU = 0xA5;

/// Low-level hook flags
pub const LLKHF_INJECTED = 0x10;
pub const LLMHF_INJECTED = 0x01;

/// Process access rights
pub const PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;

/// DwmGetWindowAttribute
pub const DWMWA_CLOAKED: win.DWORD = 14;

/// ShowWindow commands
pub const SW_SHOW = 5;
pub const SW_RESTORE = 9;

/// CreateFileW
pub const FILE_LIST_DIRECTORY: win.DWORD = 0x0001;
pub const FILE_SHARE_READ: win.DWORD = 0x00000001;
pub const FILE_SHARE_WRITE: win.DWORD = 0x00000002;
pub const FILE_SHARE_DELETE: win.DWORD = 0x00000004;
pub const OPEN_EXISTING: win.DWORD = 3;
pub const FILE_FLAG_BACKUP_SEMANTICS: win.DWORD = 0x02000000;
pub const FILE_FLAG_OVERLAPPED: win.DWORD = 0x40000000;

// ReadDirectoryChangesW
pub const FILE_NOTIFY_CHANGE_FILE_NAME: win.DWORD = 0x00000001;
pub const FILE_NOTIFY_CHANGE_SIZE: win.DWORD = 0x00000008;
pub const FILE_NOTIFY_CHANGE_LAST_WRITE: win.DWORD = 0x00000010;

/// WaitForSingleObject
pub const INFINITE: win.DWORD = 0xFFFFFFFF;
pub const WAIT_OBJECT_0: win.DWORD = 0;

// ---------------------------------------------------------------------------
// DLL entry points
// ---------------------------------------------------------------------------

pub extern "user32" fn SetWindowsHookExW(idHook: c_int, lpfn: HOOKPROC, hMod: ?win.HINSTANCE, dwThreadId: win.DWORD) callconv(.winapi) ?HHOOK;
pub extern "user32" fn CallNextHookEx(hhk: ?HHOOK, nCode: c_int, wParam: WPARAM, lParam: win.LPARAM) callconv(.winapi) LRESULT;
pub extern "user32" fn UnhookWindowsHookEx(hhk: ?HHOOK) callconv(.winapi) bool;
pub extern "user32" fn GetMessageW(lpMsg: *MSG, hwnd: ?win.HWND, wMsgFilterMin: u32, wMsgFilterMax: u32) callconv(.winapi) bool;
pub extern "user32" fn PostThreadMessageW(idThread: win.DWORD, Msg: win.UINT, wParam: WPARAM, lParam: win.LPARAM) callconv(.winapi) win.BOOL;

pub extern "user32" fn EnumWindows(lpEnumFunc: WNDENUMPROC, lParam: win.LPARAM) callconv(.winapi) bool;
pub extern "user32" fn IsWindow(hwnd: win.HWND) callconv(.winapi) win.BOOL;
pub extern "user32" fn IsWindowVisible(hwnd: win.HWND) callconv(.winapi) bool;
pub extern "user32" fn IsIconic(hwnd: win.HWND) callconv(.winapi) win.BOOL;
pub extern "user32" fn GetWindowThreadProcessId(hwnd: win.HWND, lpdwProcessId: ?*win.DWORD) callconv(.winapi) win.DWORD;
pub extern "user32" fn QueryFullProcessImageNameW(hProcess: win.HANDLE, dwFlags: win.DWORD, lpExeName: win.LPWSTR, lpDwSize: *win.DWORD) callconv(.winapi) win.BOOL;
pub extern "user32" fn ShowWindow(hwnd: win.HWND, nCmdShow: c_int) callconv(.winapi) win.BOOL;
pub extern "user32" fn SetForegroundWindow(hwnd: win.HWND) callconv(.winapi) win.BOOL;
pub extern "user32" fn GetForegroundWindow() callconv(.winapi) ?win.HWND;
pub extern "user32" fn BringWindowToTop(hwnd: win.HWND) callconv(.winapi) win.BOOL;
pub extern "user32" fn AttachThreadInput(idAttach: win.DWORD, idAttachTo: win.DWORD, fAttach: bool) callconv(.winapi) win.BOOL;
pub extern "user32" fn GetAsyncKeyState(vKey: c_int) callconv(.winapi) i16;

pub extern "version" fn GetFileVersionInfoSizeW(lpstrFilename: win.LPCWSTR, lpdwHandle: ?*win.DWORD) callconv(.winapi) win.DWORD;
pub extern "version" fn GetFileVersionInfoW(lptstrFilename: win.LPCWSTR, dwHandle: win.DWORD, dwLen: win.DWORD, lpData: win.LPVOID) callconv(.winapi) win.BOOL;
pub extern "version" fn VerQueryValueW(pBlock: win.LPCVOID, lpSubBlock: win.LPCWSTR, lplpBuffer: *win.LPVOID, puLen: *win.UINT) callconv(.winapi) win.BOOL;

pub extern "dwmapi" fn DwmGetWindowAttribute(hwnd: win.HWND, dwAttribute: win.DWORD, pvAttribute: win.PVOID, cbAttribute: win.DWORD) callconv(.winapi) HRESULT;

pub extern "kernel32" fn OpenProcess(dwDesiredAccess: win.DWORD, bInheritHandle: bool, dwProcessId: win.DWORD) callconv(.winapi) ?win.HANDLE;
pub extern "kernel32" fn CloseHandle(hObject: win.HANDLE) callconv(.winapi) bool;
pub extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) win.DWORD;
pub extern "kernel32" fn GetPackageFamilyName(hProcess: win.HANDLE, packageFamilyNameLength: *u32, packageFamilyName: ?[*]u16) callconv(.winapi) i32;
pub extern "kernel32" fn WaitForSingleObject(hHandle: win.HANDLE, dwMilliseconds: win.DWORD) callconv(.winapi) win.DWORD;
pub extern "kernel32" fn CreateFileW(lpFileName: win.LPCWSTR, dwDesiredAccess: win.DWORD, dwShareMode: win.DWORD, lpSecurityAttributes: ?*anyopaque, dwCreationDisposition: win.DWORD, dwFlagsAndAttributes: win.DWORD, hTemplateFile: ?win.HANDLE) callconv(.winapi) win.HANDLE;
pub extern "kernel32" fn CreateEventW(lpEventAttributes: ?*anyopaque, bManualReset: bool, bInitialState: bool, lpName: ?win.LPCWSTR) callconv(.winapi) ?win.HANDLE;
pub extern "kernel32" fn ReadDirectoryChangesW(hDirectory: win.HANDLE, lpBuffer: *anyopaque, nBufferLength: win.DWORD, bWatchSubtree: bool, dwNotifyFilter: win.DWORD, lpBytesReturned: ?*win.DWORD, lpOverlapped: ?*OVERLAPPED, lpCompletionRoutine: ?*anyopaque) callconv(.winapi) win.BOOL;
pub extern "kernel32" fn GetOverlappedResult(hFile: win.HANDLE, lpOverlapped: *OVERLAPPED, lpNumberOfBytesTransferred: *win.DWORD, bWait: bool) callconv(.winapi) win.BOOL;
