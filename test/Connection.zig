const std = @import("std");
const Conn = @import("mysql");
const testing = std.testing;
const Errors = Conn.All;
const DB = Conn.DB;
test "Database err connection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(Errors.DatabaseNotFound, DB.init(allocator, .{
        .database = "testdb",
        .host = "127.0.0.1",
        .user = "root",
        .password = "1234",
    }));
}

test "Database connection deinit" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    defer DB.init(allocator, .{
        .database = "testdb",
        .host = "127.0.0.1",
        .user = "root",
        .password = "1234",
    });

    try testing.expect(
        Errors.DatabaseNotFound,
    );
}
