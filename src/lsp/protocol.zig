const std = @import("std");
const types = @import("types.zig");
const allocator = @import("../utils/allocator.zig").allocator;

pub const ProtocolError = error{
    InvalidMessage,
    ParseError,
    InvalidRequest,
    MethodNotFound,
    InvalidParams,
    InternalError,
};

pub const Message = union(enum) {
    request: types.JsonRpcRequest,
    response: types.JsonRpcResponse,
    notification: types.JsonRpcNotification,
};
// Global storage for parsed JSON to keep it alive
var global_parsed_json: ?std.json.Parsed(std.json.Value) = null;

pub fn readMessage(reader: anytype) !?Message {
    // Clean up previous JSON if any
    if (global_parsed_json) |*prev| {
        prev.deinit();
        global_parsed_json = null;
    }

    // Read headers
    var content_length: ?usize = null;

    while (true) {
        var line_buf: [1024]u8 = undefined;
        if (try reader.readUntilDelimiterOrEof(line_buf[0..], '\n')) |line| {
            const trimmed = std.mem.trim(u8, line, " \r\n");
            if (trimmed.len == 0) break; // Empty line indicates end of headers

            if (std.mem.startsWith(u8, trimmed, "Content-Length:")) {
                const value_start = std.mem.indexOf(u8, trimmed, ":").? + 1;
                const value = std.mem.trim(u8, trimmed[value_start..], " ");
                content_length = std.fmt.parseInt(usize, value, 10) catch return ProtocolError.InvalidMessage;
            }
        } else {
            return null; // EOF reached
        }
    }

    const len = content_length orelse return ProtocolError.InvalidMessage;

    // Read content
    const content = try allocator.alloc(u8, len);
    defer allocator.free(content);

    const bytes_read = try reader.readAll(content);
    if (bytes_read != len) return ProtocolError.InvalidMessage;

    std.log.debug("Received JSON: {s}", .{content});

    // Parse JSON and keep it alive globally
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch |err| {
        std.log.err("JSON parse error: {} for content: {s}", .{ err, content });
        return ProtocolError.ParseError;
    };
    global_parsed_json = parsed;

    const json_obj = switch (parsed.value) {
        .object => |obj| obj,
        else => return ProtocolError.ParseError,
    };

    // Check if it's a request, response, or notification
    if (json_obj.get("method")) |method_value| {
        const method = switch (method_value) {
            .string => |str| str,
            else => return ProtocolError.ParseError,
        };

        const owned_method = try allocator.dupe(u8, method);

        if (json_obj.get("id")) |id_value| {
            // It's a request
            return Message{ .request = types.JsonRpcRequest{
                .jsonrpc = "2.0",
                .id = id_value,
                .method = owned_method,
                .params = json_obj.get("params"),
            } };
        } else {
            // It's a notification
            return Message{ .notification = types.JsonRpcNotification{
                .jsonrpc = "2.0",
                .method = owned_method,
                .params = json_obj.get("params"),
            } };
        }
    }

    return ProtocolError.InvalidRequest;
}

pub fn writeMessage(writer: anytype, message: anytype) !void {
    var json_string = std.ArrayList(u8).init(allocator);
    defer json_string.deinit();

    try std.json.stringify(message, .{}, json_string.writer());

    try writer.print("Content-Length: {d}\r\n\r\n{s}", .{ json_string.items.len, json_string.items });
}

pub fn writeResponse(writer: anytype, id: ?std.json.Value, result: anytype) !void {
    var json_string = std.ArrayList(u8).init(allocator);
    defer json_string.deinit();

    try std.json.stringify(.{
        .jsonrpc = "2.0",
        .id = id,
        .result = result,
    }, .{}, json_string.writer());

    try writer.print("Content-Length: {d}\r\n\r\n{s}", .{ json_string.items.len, json_string.items });
}

pub fn writeError(writer: anytype, id: ?std.json.Value, code: i32, message: []const u8) !void {
    var json_string = std.ArrayList(u8).init(allocator);
    defer json_string.deinit();

    try std.json.stringify(.{
        .jsonrpc = "2.0",
        .id = id,
        .@"error" = .{
            .code = code,
            .message = message,
        },
    }, .{}, json_string.writer());

    try writer.print("Content-Length: {d}\r\n\r\n{s}", .{ json_string.items.len, json_string.items });
}

pub fn writeNotification(writer: anytype, method: []const u8, params: anytype) !void {
    var json_string = std.ArrayList(u8).init(allocator);
    defer json_string.deinit();

    try std.json.stringify(.{
        .jsonrpc = "2.0",
        .method = method,
        .params = params,
    }, .{}, json_string.writer());

    try writer.print("Content-Length: {d}\r\n\r\n{s}", .{ json_string.items.len, json_string.items });
}
