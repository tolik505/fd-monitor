const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.fd_monitor);

const config_mod = @import("config.zig");
const ring_mod = @import("ring_buffer.zig");
const sampler_mod = @import("sampler.zig");
const render_mod = @import("render.zig");

const RingBuffer = ring_mod.RingBuffer;

pub fn main() !void {
    if (builtin.os.tag != .macos) {
        @compileError("fd-monitor currently supports macOS only.");
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const config = config_mod.parseConfig(allocator) catch |err| switch (err) {
        error.InvalidArgument => {
            config_mod.printUsage();
            return;
        },
        error.InvalidNumber, error.InvalidRange => return err,
        else => return err,
    };

    var sampler = sampler_mod.Sampler.init(allocator);
    defer sampler.deinit();

    var history = try RingBuffer(usize).init(allocator, config.history_points);
    defer history.deinit();

    const stdout = std.fs.File.stdout().deprecatedWriter();
    while (true) {
        const snapshot = sampler.collect() catch |err| switch (err) {
            error.ListPidsFailed => {
                log.err("failed to enumerate process ids", .{});
                return err;
            },
            error.OutOfMemory => return err,
        };
        history.push(snapshot.total_fds);

        try render_mod.render(stdout, config, history, snapshot);
        try stdout.writeAll("\nPress Ctrl-C to exit.\n");
        std.Thread.sleep(config.interval_ms * std.time.ns_per_ms);
    }
}
