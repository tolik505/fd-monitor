const std = @import("std");
const config_mod = @import("config.zig");
const ring_mod = @import("ring_buffer.zig");
const sampler_mod = @import("sampler.zig");

const Config = config_mod.Config;
const RingBuffer = ring_mod.RingBuffer;
const Snapshot = sampler_mod.Snapshot;
const ProcessFdCount = sampler_mod.ProcessFdCount;

pub fn render(
    writer: anytype,
    config: Config,
    history: RingBuffer(usize),
    snapshot: Snapshot,
) !void {
    if (!config.no_color) {
        try writer.writeAll("\x1b[2J\x1b[H\x1b[0m");
    } else {
        try writer.writeAll("\x1b[2J\x1b[H");
    }

    const now_ms = std.time.milliTimestamp();
    try writer.print("fd-monitor  |  ts={d}  total_fds={d}  inaccessible_pids={d}\n", .{
        now_ms,
        snapshot.total_fds,
        snapshot.inaccessible_pids,
    });

    try renderGraph(writer, history);
    try writer.writeAll("\n");
    try renderTable(writer, snapshot.processes, snapshot.total_fds, config.top);
}

fn renderGraph(writer: anytype, history: RingBuffer(usize)) !void {
    const height: usize = 10;
    var min_value: usize = std.math.maxInt(usize);
    var max_value: usize = 0;
    var i: usize = 0;
    while (i < history.len) : (i += 1) {
        const value = history.at(i) orelse 0;
        min_value = @min(min_value, value);
        max_value = @max(max_value, value);
    }

    if (history.len == 0) {
        min_value = 0;
    } else if (min_value == std.math.maxInt(usize)) {
        min_value = 0;
    }

    const current_value = history.at(history.len - 1) orelse 0;
    try writer.print("Graph ({d} points, min={d}, max={d}, current={d})\n", .{
        history.len,
        min_value,
        max_value,
        current_value,
    });

    var row: usize = height;
    while (row > 0) {
        row -= 1;
        const axis_value = graphAxisValue(row, height, min_value, max_value);
        try writer.print("{d: >8} |", .{axis_value});

        i = 0;
        while (i < history.len) : (i += 1) {
            const value = history.at(i) orelse 0;
            const level = graphLevel(value, min_value, max_value, height);
            const ch: u8 = if (level == row) '#' else ' ';
            try writer.writeByte(ch);
        }
        try writer.writeByte('\n');
    }
    try writer.writeAll("         +");
    i = 0;
    while (i < history.len) : (i += 1) {
        try writer.writeByte('-');
    }
    try writer.writeByte('\n');
}

fn graphLevel(value: usize, min_value: usize, max_value: usize, height: usize) usize {
    if (height == 0) return 0;
    if (max_value <= min_value) return height / 2;

    const range = max_value - min_value;
    const normalized = value - min_value;
    return (normalized * (height - 1)) / range;
}

fn graphAxisValue(row: usize, height: usize, min_value: usize, max_value: usize) usize {
    if (height <= 1) return max_value;
    if (max_value <= min_value) return max_value;

    const range = max_value - min_value;
    return min_value + (row * range) / (height - 1);
}

fn renderTable(
    writer: anytype,
    processes: []const ProcessFdCount,
    total_fds: usize,
    top: usize,
) !void {
    const rows = @min(top, processes.len);
    try writer.writeAll("Top processes by open file descriptors\n");
    try writer.writeAll("PID      FD_COUNT   PCT     NAME\n");
    try writer.writeAll("-------------------------------------------\n");

    var shown_total: usize = 0;
    var idx: usize = 0;
    while (idx < rows) : (idx += 1) {
        const p = &processes[idx];
        shown_total += p.fd_count;
        const pid_display: u32 = @intCast(p.pid);

        const pct_times_100 = if (total_fds == 0) 0 else (p.fd_count * 10_000) / total_fds;
        try writer.print("{d: <8} {d: <10} {d}.{d:0>2}%  {s}\n", .{
            pid_display,
            p.fd_count,
            pct_times_100 / 100,
            pct_times_100 % 100,
            p.displayName(),
        });
    }

    if (processes.len > rows) {
        const other_count = total_fds - shown_total;
        const pct_times_100 = if (total_fds == 0) 0 else (other_count * 10_000) / total_fds;
        try writer.print("others   {d: <10} {d}.{d:0>2}%  ({d} processes)\n", .{
            other_count,
            pct_times_100 / 100,
            pct_times_100 % 100,
            processes.len - rows,
        });
    }
}

test "graph level uses center row for flat data" {
    try std.testing.expectEqual(@as(usize, 5), graphLevel(100, 100, 100, 10));
}

test "graph axis shows max at top and min at bottom" {
    try std.testing.expectEqual(@as(usize, 100), graphAxisValue(9, 10, 0, 100));
    try std.testing.expectEqual(@as(usize, 0), graphAxisValue(0, 10, 0, 100));
}
