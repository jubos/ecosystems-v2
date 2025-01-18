const std = @import("std");
const clap = @import("clap");
const db = @import("taxonomy.zig");

const SubCommands = enum {
    @"export",
    help,
    validate,
};

const main_parsers = .{ .command = clap.parsers.enumeration(SubCommands), .str = clap.parsers.string };

const main_params = clap.parseParamsComptime(
    \\-h, --help       Display this help and exit.
    \\-r, --root <str> root of the data directory where the taxonomy is stored.
    \\<command>        Main command
    \\
);

const MainArgs = clap.ResultEx(clap.Help, &main_params, main_parsers);

pub fn cmdMain(allocator: std.mem.Allocator) !void {
    var iter = try std.process.ArgIterator.initWithAllocator(allocator);
    defer iter.deinit();

    _ = iter.next();

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &main_params, main_parsers, &iter, .{
        .diagnostic = &diag,
        .allocator = allocator,

        // Terminate the parsing of arguments after parsing the first positional (0 is passed
        // here because parsed positionals are, like slices and arrays, indexed starting at 0).
        //
        // This will terminate the parsing after parsing the subcommand enum and leave `iter`
        // not fully consumed. It can then be reused to parse the arguments for subcommands
        .terminating_positional = 0,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &main_params, .{});

    const command = res.positionals[0] orelse return error.MissingCommand;
    switch (command) {
        .@"export" => try cmdExport(allocator, &iter, res),
        .help => std.debug.print("--help\n", .{}),
        .validate => try cmdValidate(allocator, &iter, res),
    }
}

pub fn cmdValidate(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help Validate the taxonomy database stored in <root>
        \\
    );

    // Here we pass the partially parsed argument iterator
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});

    if (main_args.args.root) |root| {
        std.debug.print("main args root: {s}\n", .{root});
        std.debug.print("cmd validate\n", .{});
        var taxonomy = db.Taxonomy.init(gpa);
        defer taxonomy.deinit();
        const load_result = try taxonomy.load(root);
        _ = load_result;
    } else {
        std.debug.print("Please specify the --root parameter", .{});
    }
}

pub fn cmdExport(gpa: std.mem.Allocator, iter: *std.process.ArgIterator, main_args: MainArgs) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help export the taxonomy database stored in <root>
        \\-e, --ecosystem only output a single ecosystem
        \\<str> output file
        \\
    );

    // Here we pass the partially parsed argument iterator
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});

    if (main_args.args.root) |root| {
        if (res.positionals.len > 0) {
            if (res.positionals[0]) |output_file| {
                std.debug.print("main args root: {s}\n", .{root});
                std.debug.print("cmd export to {s}\n", .{output_file});
                var taxonomy = db.Taxonomy.init(gpa);
                defer taxonomy.deinit();
                const load_result = try taxonomy.load(root);
                _ = load_result;
                try taxonomy.exportJson(output_file);
            }
        }
    } else {
        std.debug.print("Please specify the --root parameter", .{});
    }
}
