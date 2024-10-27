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
pub const ServerError = error{
    ServerGone,
    ServerLost,
};
pub const DatabaseError = error{
    ConnectionLost,
    DatabaseNotFound,
    BadHost,

    CommandsOutofSync,
    UnknownError,
};
pub const MemoryError = error{
    OutOfMemory,
    OutOfResources,
};
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
            return DatabaseError.DatabaseNotFound;
        }
        return .{
            .conn = db,
            .allocator = allocator,
        };
    }
    pub fn StatementInit(self: Self) MemoryError!Statement {
        const statement: *c.MYSQL_STMT = c.mysql_stmt_init(self.conn);
        if (statement == null) {
            return MemoryError.OutOfMemory;
        }
        return .{
            .statement = statement,
        };
    }
    pub fn deinit(self: Self) void {
        c.mysql_close(self.conn);
    }

    pub fn autoCommit(self: Self, mode: bool) void {
        c.autoCommit(self.conn, mode);
    }
    pub fn commit(self: Self) bool {
        return c.mysql_commit(self.conn);
    }
};

const Statement = struct {
    statement: *c.MYSQL_STMT,
    query: [:0]const u8 = "",

    const Self = @This();

    pub fn setQuery(self: Self, query: [:0]const u8) void {
        self.query = query;
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
    pub fn deinit(self: Self) (ServerError || DatabaseError) {
        const case: c_uint = c.mysql_stmt_close(self.statement);
        return switch (case) {
            0 => return,

            c.CR_SERVER_GONE_ERROR => ServerError.ServerGone,

            c.CR_UNKNOWN_ERROR => DatabaseError.UnknownError,

            else => unreachable,
        };
    }
    pub fn execute(self: Self) (DatabaseError || ServerError)!void {
        const case: c_uint = c.mysql_real_query(self.conn, self.query.ptr, self.query.len);
        return switch (case) {
            //Success case
            0 => return,

            //Commands were executed in an improper order.
            c.CR_COMMANDS_OUT_OF_SYNC => DatabaseError.CommandsOutofSync,

            //The MySQL server has gone away.
            c.CR_SERVER_GONE_ERROR => ServerError.ServerGone,

            //The connection to the server was lost during the query.
            c.CR_SERVER_LOST => ServerError.ServerLost,

            //An unknown error occurred.
            c.CR_UNKNOWN_ERROR => DatabaseError.UnknownError,

            else => unreachable,
        };
    }
};
pub const types = enum(c_int) {
    TYNY = c.MYSQL_TYPE_TINY,
    SHORT = c.MYSQL_TYPE_SHORT,
    LONG = c.MYSQL_TYPE_LONG,
    INT24 = c.MYSQL_TYPE_INT24,
    LONGLONG = c.MYSQL_TYPE_LONGLONG,
    DECIMAL = c.MYSQL_TYPE_DECIMAL,
    NEWDECIMAL = c.MYSQL_TYPE_NEWDECIMAL,
    FLOAT = c.MYSQL_TYPE_FLOAT,
    DOUBLE = c.MYSQL_TYPE_DOUBLE,
    BIT = c.MYSQL_TYPE_BIT,
    TIMESTAMP = c.MYSQL_TYPE_TIMESTAMP,
    DATE = c.MYSQL_TYPE_DATE,
    TIME = c.MYSQL_TYPE_TIME,
    DATETIME = c.MYSQL_TYPE_DATETIME,
    YEAR = c.MYSQL_TYPE_YEAR,
    STRING = c.MYSQL_TYPE_STRING,
    VAR_STRING = c.MYSQL_TYPE_VAR_STRING,
    BLOB = c.MYSQL_TYPE_BLOB,
    SET = c.MYSQL_TYPE_SET,
    ENUM = c.MYSQL_TYPE_ENUM,
    GEOMETRY = c.MYSQL_TYPE_GEOMETRY,
    NULL = c.MYSQL_TYPE_NULL,
};
