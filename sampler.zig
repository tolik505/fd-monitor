const std = @import("std");
const c = @cImport({
    @cInclude("libproc.h");
    @cInclude("sys/proc_info.h");
});

pub const SamplingError = error{
    ListPidsFailed,
    OutOfMemory,
};

pub const ProcessFdCount = struct {
    pid: c_int,
    fd_count: usize,
    name_len: u8,
    name: [64]u8,

    pub fn init(pid: c_int, fd_count: usize, raw_name: []const u8) ProcessFdCount {
        var entry: ProcessFdCount = .{
            .pid = pid,
            .fd_count = fd_count,
            .name_len = 0,
            .name = [_]u8{0} ** 64,
        };
        const copy_len = copyProcessNameForDisplay(raw_name, entry.name[0..]);
        entry.name_len = @intCast(copy_len);
        return entry;
    }

    pub fn displayName(self: *const ProcessFdCount) []const u8 {
        return self.name[0..self.name_len];
    }
};

pub const Snapshot = struct {
    total_fds: usize,
    inaccessible_pids: usize,
    processes: []const ProcessFdCount,
};

pub const Sampler = struct {
    allocator: std.mem.Allocator,
    pid_buffer: std.ArrayList(c_int),
    fd_buffer: std.ArrayList(c.struct_proc_fdinfo),
    process_buffer: std.ArrayList(ProcessFdCount),

    pub fn init(allocator: std.mem.Allocator) Sampler {
        return .{
            .allocator = allocator,
            .pid_buffer = .empty,
            .fd_buffer = .empty,
            .process_buffer = .empty,
        };
    }

    pub fn deinit(self: *Sampler) void {
        self.pid_buffer.deinit(self.allocator);
        self.fd_buffer.deinit(self.allocator);
        self.process_buffer.deinit(self.allocator);
    }

    pub fn collect(self: *Sampler) SamplingError!Snapshot {
        try self.refreshPids();
        self.process_buffer.clearRetainingCapacity();

        var total_fds: usize = 0;
        var inaccessible: usize = 0;

        for (self.pid_buffer.items) |pid| {
            if (pid <= 0) continue;

            const fd_count = self.countPidFds(pid) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.Inaccessible => {
                    inaccessible += 1;
                    continue;
                },
            };
            total_fds += fd_count;

            var name: [64]u8 = [_]u8{0} ** 64;
            const name_len = readProcessName(pid, &name);
            try self.process_buffer.append(self.allocator, ProcessFdCount.init(pid, fd_count, name[0..name_len]));
        }

        sortProcessesByFdDesc(self.process_buffer.items);
        return .{
            .total_fds = total_fds,
            .inaccessible_pids = inaccessible,
            .processes = self.process_buffer.items,
        };
    }

    fn refreshPids(self: *Sampler) SamplingError!void {
        var capacity: usize = 1024;
        while (true) {
            try self.pid_buffer.resize(self.allocator, capacity);

            const buf_size: c_int = @intCast(capacity * @sizeOf(c_int));
            const bytes_written = c.proc_listpids(
                c.PROC_ALL_PIDS,
                0,
                self.pid_buffer.items.ptr,
                buf_size,
            );
            if (bytes_written <= 0) {
                return error.ListPidsFailed;
            }

            const count = @as(usize, @intCast(bytes_written)) / @sizeOf(c_int);
            self.pid_buffer.items.len = count;
            if (count < capacity) return;
            capacity *= 2;
            if (capacity > 1_000_000) return;
        }
    }

    const CountError = error{ OutOfMemory, Inaccessible };

    fn countPidFds(self: *Sampler, pid: c_int) CountError!usize {
        var capacity: usize = 64;
        while (true) {
            try self.fd_buffer.resize(self.allocator, capacity);

            const buf_size: c_int = @intCast(capacity * @sizeOf(c.struct_proc_fdinfo));
            const bytes = c.proc_pidinfo(
                pid,
                c.PROC_PIDLISTFDS,
                0,
                self.fd_buffer.items.ptr,
                buf_size,
            );
            if (bytes <= 0) return error.Inaccessible;

            const count = @as(usize, @intCast(bytes)) / @sizeOf(c.struct_proc_fdinfo);
            if (count < capacity) return count;

            capacity *= 2;
            if (capacity > 1_000_000) return count;
        }
    }

    fn readProcessName(pid: c_int, out: *[64]u8) usize {
        var bsd_info: c.struct_proc_bsdinfo = undefined;
        const bytes = c.proc_pidinfo(
            pid,
            c.PROC_PIDTBSDINFO,
            0,
            &bsd_info,
            @sizeOf(c.struct_proc_bsdinfo),
        );
        if (bytes == @as(c_int, @intCast(@sizeOf(c.struct_proc_bsdinfo)))) {
            const name_len = copyCNameForDisplay(bsd_info.pbi_name[0..], out[0..]);
            if (name_len > 0) return name_len;

            const comm_len = copyCNameForDisplay(bsd_info.pbi_comm[0..], out[0..]);
            if (comm_len > 0) return comm_len;
        }

        const written = c.proc_name(pid, out, @as(c_uint, @intCast(out.len)));
        if (written > 0) {
            const raw_len = @min(@as(usize, @intCast(written)), out.len);
            return copyProcessNameForDisplay(out[0..raw_len], out[0..]);
        }

        const fallback = "(unknown)";
        @memcpy(out[0..fallback.len], fallback);
        return fallback.len;
    }
};

fn copyProcessNameForDisplay(raw: []const u8, out: []u8) usize {
    var src_i: usize = 0;
    var out_i: usize = 0;

    while (src_i < raw.len and out_i < out.len) {
        const first = raw[src_i];

        if (first == 0) break;
        if (first < 0x20 or first > 0x7E) {
            out[out_i] = '?';
            out_i += 1;
            src_i += 1;
            continue;
        }
        out[out_i] = first;
        out_i += 1;
        src_i += 1;
    }
    return out_i;
}

fn copyCNameForDisplay(raw: []const u8, out: []u8) usize {
    var out_i: usize = 0;
    var src_i: usize = 0;
    while (src_i < raw.len and out_i < out.len) : (src_i += 1) {
        const b = raw[src_i];
        if (b == 0) break;
        out[out_i] = if (b >= 0x20 and b <= 0x7E) b else '?';
        out_i += 1;
    }
    return out_i;
}

fn sortProcessesByFdDesc(items: []ProcessFdCount) void {
    var i: usize = 1;
    while (i < items.len) : (i += 1) {
        const key = items[i];
        var j = i;
        while (j > 0 and items[j - 1].fd_count < key.fd_count) : (j -= 1) {
            items[j] = items[j - 1];
        }
        items[j] = key;
    }
}

test "process sorting is descending by fd count" {
    var values = [_]ProcessFdCount{
        ProcessFdCount.init(1, 3, "one"),
        ProcessFdCount.init(2, 8, "two"),
        ProcessFdCount.init(3, 5, "three"),
    };
    sortProcessesByFdDesc(values[0..]);
    try std.testing.expectEqual(@as(usize, 8), values[0].fd_count);
    try std.testing.expectEqual(@as(usize, 5), values[1].fd_count);
    try std.testing.expectEqual(@as(usize, 3), values[2].fd_count);
}

test "process display name is normalized to printable ascii" {
    const src = "a\x00b\x7f\x80z";
    var out: [6]u8 = [_]u8{0} ** 6;
    const len = copyProcessNameForDisplay(src, out[0..]);
    try std.testing.expectEqualStrings("a", out[0..len]);
}

test "process display name slice points to struct storage" {
    var p = ProcessFdCount.init(1, 2, "abc");
    const s = p.displayName();
    try std.testing.expectEqual(@intFromPtr(&p.name[0]), @intFromPtr(s.ptr));
    try std.testing.expectEqualStrings("abc", s);
}
