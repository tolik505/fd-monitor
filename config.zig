const std = @import("std");

pub const ConfigError = error{
    InvalidArgument,
    InvalidNumber,
    InvalidRange,
};

pub const Config = struct {
    interval_ms: u64 = 500,
    history_points: usize = 120,
    top: usize = 20,
    no_color: bool = false,
};

pub fn parseConfig(allocator: std.mem.Allocator) !Config {
    var config = Config{};
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            printUsage();
            std.process.exit(0);
        } else if (std.mem.startsWith(u8, arg, "--interval-ms=")) {
            config.interval_ms = try parseU64(arg["--interval-ms=".len..]);
        } else if (std.mem.startsWith(u8, arg, "--history-points=")) {
            config.history_points = try parseUsize(arg["--history-points=".len..]);
        } else if (std.mem.startsWith(u8, arg, "--top=")) {
            config.top = try parseUsize(arg["--top=".len..]);
        } else if (std.mem.eql(u8, arg, "--no-color")) {
            config.no_color = true;
        } else {
            return error.InvalidArgument;
        }
    }

    if (config.interval_ms == 0 or config.history_points == 0 or config.top == 0) {
        return error.InvalidRange;
    }
    return config;
}

fn parseU64(input: []const u8) ConfigError!u64 {
    return std.fmt.parseInt(u64, input, 10) catch error.InvalidNumber;
}

fn parseUsize(input: []const u8) ConfigError!usize {
    return std.fmt.parseInt(usize, input, 10) catch error.InvalidNumber;
}

pub fn printUsage() void {
    std.debug.print(
        \\fd-monitor (macOS)
        \\
        \\Flags:
        \\  --interval-ms=<N>     Refresh interval in milliseconds (default: 500)
        \\  --history-points=<N>  Number of points to keep in graph (default: 120)
        \\  --top=<N>             Number of processes in table (default: 20)
        \\  --no-color            Disable ANSI color
        \\  --help                Show this help
        \\
    , .{});
}
