const std = @import("std");
const clap = @import("clap");

const commands = @import("commands.zig");

const SubCommands = enum {
    help,
    add_repo,
    remove_repo,
    validate,
};

const main_parsers = .{
    .command = clap.parsers.enumeration(SubCommands),
};

const main_params = clap.parseParamsComptime(
    \\-h, --help  Display this help and exit.
    \\-r, --root root of the data directory where the taxonomy is stored.
    \\<command>
    \\
);

const MainArgs = clap.ResultEx(clap.Help, &main_params, main_parsers);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try commands.cmdMain(allocator);
}

test {
    std.testing.refAllDecls(@This());
}
