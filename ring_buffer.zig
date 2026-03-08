const std = @import("std");

pub fn RingBuffer(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        items: []T,
        start: usize,
        len: usize,

        pub fn init(allocator: std.mem.Allocator, cap: usize) !Self {
            if (cap == 0) return error.InvalidRange;
            return .{
                .allocator = allocator,
                .items = try allocator.alloc(T, cap),
                .start = 0,
                .len = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.items);
            self.* = undefined;
        }

        pub fn push(self: *Self, value: T) void {
            if (self.len < self.items.len) {
                const idx = (self.start + self.len) % self.items.len;
                self.items[idx] = value;
                self.len += 1;
                return;
            }

            self.items[self.start] = value;
            self.start = (self.start + 1) % self.items.len;
        }

        pub fn at(self: Self, index: usize) ?T {
            if (index >= self.len) return null;
            const idx = (self.start + index) % self.items.len;
            return self.items[idx];
        }
    };
}

test "ring buffer overwrites oldest values" {
    var ring = try RingBuffer(u32).init(std.testing.allocator, 3);
    defer ring.deinit();

    ring.push(1);
    ring.push(2);
    ring.push(3);
    ring.push(4);

    try std.testing.expectEqual(@as(usize, 3), ring.len);
    try std.testing.expectEqual(@as(u32, 2), ring.at(0).?);
    try std.testing.expectEqual(@as(u32, 3), ring.at(1).?);
    try std.testing.expectEqual(@as(u32, 4), ring.at(2).?);
}
