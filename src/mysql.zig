const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;
const Database = struct {
    host: [:0]const u8,
    user: [:0]const u8,
    password: [:0]const u8,
    database: [:0]const u8,
    port: u32 = 3306,
};

const DatabaseError = error{
    ConnectionLost,
    DatabaseNotFound,
    BadHost,

    CommandsOutofSync,
    ServerGone,
    ServerLost,
    UnknownError,
};
const MemoryError = error{
    OutOfMemory,
    OutOfResources,
};
pub const All = DatabaseError || MemoryError;
const c = @cImport({
    @cInclude("mysql.h");
});

pub const DB = struct {
    conn: *c.MYSQL,
    allocator: Allocator,

    const Self = @This();
    pub fn init(
        allocator: Allocator,
        db_info: Database,
    ) (DatabaseError || MemoryError)!Self {
        const db = c.mysql_init(null);

        if (db == null) {
            return MemoryError.OutOfMemory;
        }

        if (c.mysql_real_connect(
            db,
            db_info.host,
            db_info.user,
            db_info.password,
            db_info.database,
            db_info.port,
            null,
            c.CLIENT_MULTI_STATEMENTS,
        ) == null) {
            print("Connect to database failed: {s}\n", .{c.mysql_error(db)});
            return Database.DatabaseNotFound;
        }
        const self = Self{
            .conn = db,
            .allocator = allocator,
        };
        return self;
    }

    pub fn deinit(self: Self) void {
        c.mysql_close(self.conn);
    }
    pub fn execute(self: DB, query: []const u8) DatabaseError!void {
        const success: c_uint = c.mysql_real_query(self.conn, query.ptr, query.len);
        return switch (success) {
            //Success case
            0 => return,

            //Commands were executed in an improper order.
            c.CR_COMMANDS_OUT_OF_SYNC => DatabaseError.CommandsOutofSync,

            //The MySQL server has gone away.
            c.CR_SERVER_GONE_ERROR => DatabaseError.ServerGone,

            //The connection to the server was lost during the query.
            c.CR_SERVER_LOST => DatabaseError.ServerLost,

            //An unknown error occurred.
            c.CR_UNKNOWN_ERROR => DatabaseError.UnknownError,

            else => unreachable,
        };
    }
    pub fn autoCommit(self: Self, mode: bool) void {
        c.autoCommit(self.conn, mode);
    }
    pub fn queryTable(self: DB) !void {
        const query =
            \\ SELECT
            \\     c.name,
            \\     cc.name
            \\ FROM
            \\     cats c
            \\     INNER JOIN cat_colors cc ON cc.id = c.color_id;
            \\
        ;

        try self.execute(query);
        const result = c.mysql_store_result(self.conn);
        if (result == null) {
            print("Store result failed: {s}\n", .{c.mysql_error(self.conn)});
            return error.storeResultError;
        }
        defer c.mysql_free_result(result);

        while (c.mysql_fetch_row(result)) |row| {
            const cat_name = row[0];
            const color_name = row[1];
            print("Cat: {s}, Color: {s}\n", .{ cat_name, color_name });
        }
    }

    pub fn insertTable(self: DB) !void {
        const cat_colors = .{
            .{
                "Blue",
                .{ "Tigger", "Sammy" },
            },
            .{
                "Black",
                .{ "Oreo", "Biscuit" },
            },
        };

        const insert_color_stmt: *c.MYSQL_STMT = blk: {
            const stmt = c.mysql_stmt_init(self.conn);
            if (stmt == null) {
                return error.initStmt;
            }
            errdefer _ = c.mysql_stmt_close(stmt);

            const insert_color_query = "INSERT INTO cat_colors (name) values (?)";
            if (c.mysql_stmt_prepare(stmt, insert_color_query, insert_color_query.len) != 0) {
                print("Prepare color stmt failed, msg:{s}\n", .{c.mysql_error(self.conn)});
                return error.prepareStmt;
            }

            break :blk stmt.?;
        };
        defer _ = c.mysql_stmt_close(insert_color_stmt);

        const insert_cat_stmt = blk: {
            const stmt = c.mysql_stmt_init(self.conn);
            if (stmt == null) {
                return error.initStmt;
            }
            errdefer _ = c.mysql_stmt_close(stmt);

            const insert_cat_query = "INSERT INTO cats (name, color_id) values (?, ?)";
            if (c.mysql_stmt_prepare(stmt, insert_cat_query, insert_cat_query.len) != 0) {
                print("Prepare cat stmt failed: {s}\n", .{c.mysql_error(self.conn)});
                return error.prepareStmt;
            }

            break :blk stmt.?;
        };
        defer _ = c.mysql_stmt_close(insert_cat_stmt);

        inline for (cat_colors) |row| {
            const color = row.@"0";
            const cat_names = row.@"1";

            var color_binds = [_]c.MYSQL_BIND{std.mem.zeroes(c.MYSQL_BIND)};
            color_binds[0].buffer_type = c.MYSQL_TYPE_STRING;
            color_binds[0].buffer_length = color.len;
            color_binds[0].is_null = 0;
            color_binds[0].buffer = @constCast(@ptrCast(color.ptr));

            if (c.mysql_stmt_bind_param(insert_color_stmt, &color_binds)) {
                print("Bind color param failed: {s}\n", .{c.mysql_error(self.conn)});
                return error.bindParamError;
            }
            if (c.mysql_stmt_execute(insert_color_stmt) != 0) {
                print("Exec color stmt failed: {s}\n", .{c.mysql_error(self.conn)});
                return error.execStmtError;
            }
            const last_id = c.mysql_stmt_insert_id(insert_color_stmt);
            _ = c.mysql_stmt_reset(insert_color_stmt);

            inline for (cat_names) |cat_name| {
                var cat_binds = [_]c.MYSQL_BIND{ std.mem.zeroes(c.MYSQL_BIND), std.mem.zeroes(c.MYSQL_BIND) };
                cat_binds[0].buffer_type = c.MYSQL_TYPE_STRING;
                cat_binds[0].buffer_length = cat_name.len;
                cat_binds[0].buffer = @constCast(@ptrCast(cat_name.ptr));

                cat_binds[1].buffer_type = c.MYSQL_TYPE_LONG;
                cat_binds[1].length = (@as(c_ulong, 1));
                cat_binds[1].buffer = @constCast(@ptrCast(&last_id));

                if (c.mysql_stmt_bind_param(insert_cat_stmt, &cat_binds)) {
                    print("Bind cat param failed: {s}\n", .{c.mysql_error(self.conn)});
                    return error.bindParamError;
                }
                if (c.mysql_stmt_execute(insert_cat_stmt) != 0) {
                    print("Exec cat stmt failed: {s}\n", .{c.mysql_error(self.conn)});
                    return error.execStmtError;
                }

                _ = c.mysql_stmt_reset(insert_cat_stmt);
            }
        }
    }
};
