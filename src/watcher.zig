//! Watch config file for changes for hot reloading.

const std = @import("std");
const win = std.os.windows;
const win32 = @import("win32.zig");

/// Posted to the main thread when the config file changes.
pub const WM_RELOAD = win32.WM_APP + 2;

const debounce_ms: win.DWORD = 250;
const buffer_len = 4096;

pub const Watcher = struct {
    dir: win.HANDLE,
    event: win.HANDLE,
    overlapped: win32.OVERLAPPED,
    buffer: [buffer_len]u8 = undefined,
    filename: []const u16,
    main_thread_id: win.DWORD,

    pub fn start(allocator: std.mem.Allocator, config_path: []const u8, main_thread_id: win.DWORD) !*Watcher {
        const dir_path = std.fs.path.dirname(config_path) orelse ".";
        const filename = std.fs.path.basename(config_path);

        const dir_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, dir_path);
        const filename_w = try std.unicode.utf8ToUtf16LeAllocZ(allocator, filename);

        const dir = win32.CreateFileW(
            dir_w.ptr,
            win32.FILE_LIST_DIRECTORY,
            win32.FILE_SHARE_READ | win32.FILE_SHARE_WRITE | win32.FILE_SHARE_DELETE,
            null,
            win32.OPEN_EXISTING,
            win32.FILE_FLAG_BACKUP_SEMANTICS | win32.FILE_FLAG_OVERLAPPED,
            null,
        );
        if (dir == win.INVALID_HANDLE_VALUE) return error.OpenConfigDirFailed;

        const event = win32.CreateEventW(null, false, false, null) orelse {
            _ = win32.CloseHandle(dir);
            return error.CreateEventFailed;
        };

        const self = allocator.create(Watcher) catch |err| {
            _ = win32.CloseHandle(event);
            _ = win32.CloseHandle(dir);
            return err;
        };
        self.* = .{
            .dir = dir,
            .event = event,
            .overlapped = .{ .Internal = 0, .InternalHigh = 0, .offset = 0, .hEvent = event },
            .filename = filename_w,
            .main_thread_id = main_thread_id,
        };

        const thread = std.Thread.spawn(.{}, run, .{self}) catch |err| {
            _ = win32.CloseHandle(event);
            _ = win32.CloseHandle(dir);
            return err;
        };
        thread.detach();
        return self;
    }

    fn run(self: *Watcher) void {
        if (!issue_read(self)) return;

        while (true) {
            if (win32.WaitForSingleObject(self.event, win32.INFINITE) != win32.WAIT_OBJECT_0) return;

            var changed = self.consume();
            if (!issue_read(self)) return;

            // Coalesce further writes until the directory stays quiet.
            while (win32.WaitForSingleObject(self.event, debounce_ms) == win32.WAIT_OBJECT_0) {
                changed = self.consume() or changed;
                if (!issue_read(self)) return;
            }

            if (changed) _ = win32.PostThreadMessageW(self.main_thread_id, WM_RELOAD, 0, 0);
        }
    }

    /// Prepare watcher for read
    fn issue_read(self: *Watcher) bool {
        var bytes: win.DWORD = 0;
        const ok = win32.ReadDirectoryChangesW(
            self.dir,
            &self.buffer,
            self.buffer.len,
            false,
            win32.FILE_NOTIFY_CHANGE_FILE_NAME | win32.FILE_NOTIFY_CHANGE_SIZE | win32.FILE_NOTIFY_CHANGE_LAST_WRITE,
            &bytes,
            &self.overlapped,
            null,
        );
        if (ok.toBool()) return true;
        return win.GetLastError() == win.Win32Error.IO_PENDING;
    }

    /// Read completed notification buffer and report whether it mentions the config file.
    fn consume(self: *Watcher) bool {
        var bytes: win.DWORD = 0;
        if (!win32.GetOverlappedResult(self.dir, &self.overlapped, &bytes, false).toBool()) return false;

        const data = self.buffer[0..bytes];
        var offset: usize = 0;
        while (offset + @sizeOf(win32.FILE_NOTIFY_INFORMATION) <= data.len) {
            const next = std.mem.readInt(u32, data[offset..][0..4], .little);
            const name_len = std.mem.readInt(u32, data[offset + 8 ..][0..4], .little);
            const name_offset = offset + @sizeOf(win32.FILE_NOTIFY_INFORMATION);
            if (name_offset + name_len <= data.len and name_matches(data[name_offset .. name_offset + name_len], self.filename)) {
                return true;
            }
            if (next == 0) break;
            offset += next;
        }
        return false;
    }
};

fn name_matches(name_bytes: []const u8, filename: []const u16) bool {
    if (name_bytes.len / 2 != filename.len) return false;
    for (filename, 0..) |expected, i| {
        const actual = std.mem.readInt(u16, name_bytes[i * 2 ..][0..2], .little);
        if (!ascii_ci_eq(actual, expected)) return false;
    }
    return true;
}

// Case-insensitive u16 char comparison
fn ascii_ci_eq(a: u16, b: u16) bool {
    if (a > 0x7f or b > 0x7f) return a == b;
    return std.ascii.toLower(@intCast(a)) == std.ascii.toLower(@intCast(b));
}
