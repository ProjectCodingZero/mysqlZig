const std = @import("std");
const Conn = @import("mysql");
const testing = std.testing;
const Errors = Conn.All;
const DB = Conn.DB;
const Database = Conn.Database;
test "Database connection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try testing.expectError(Errors.DatabaseNotFound, DB.init(allocator, .{
        .database = "testdb",
        .host = "127.0.0.12",
        .user = "root",
        .password = "1234",
    }));
}
