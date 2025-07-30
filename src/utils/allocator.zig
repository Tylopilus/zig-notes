const std = @import("std");

pub var gpa = std.heap.GeneralPurposeAllocator(.{}){};
pub const allocator = gpa.allocator();

pub fn deinit() void {
    _ = gpa.deinit();
}
