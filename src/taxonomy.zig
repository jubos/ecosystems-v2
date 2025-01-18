const std = @import("std");
const shlex = @import("./shlex.zig");
const timestamp = @import("./timestamp.zig");
const print = std.debug.print;

const ArrayList = std.ArrayList;
const HashMap = std.hash_map.HashMap;
const AutoHashMap = std.hash_map.AutoHashMap;

const SliceIdMap = HashMap([]const u8, u32, std.hash_map.StringContext, std.hash_map.default_max_load_percentage);
const IdSliceMap = AutoHashMap(u32, []const u8);

const IdSet = AutoHashMap(u32, void);
const RepoToTagMap = AutoHashMap(u32, ?IdSet);
const EcoToRepoMap = AutoHashMap(u32, RepoToTagMap);
const RepoToEcoMap = AutoHashMap(u32, u32);
const ParentToChildMap = AutoHashMap(u32, IdSet);

pub const TaxonomyStats = struct {
    migration_count: u32,
    eco_count: u32,
    repo_count: u32,
    eco_connections_count: u32,
    tag_count: u32,
};

pub const TaxonomyError = struct {
    message: []const u8,
    line_num: u32,
    path: []const u8,
};

pub const TaxonomyLoadResult = struct { errors: ArrayList(TaxonomyError) };

pub const Ecosystem = struct {
    id: u32,
    name: []const u8,
    //sub_ecosystems: [][]const u8,
    repos: []const []const u8,

    pub fn deinit(self: *Ecosystem, allocator: std.mem.Allocator) void {
        allocator.free(self.repos);
    }
};

pub const EcosystemJson = struct {
    name: []const u8,
    //sub_ecosystems: [][]const u8,
    repos: []const []const u8,

    pub fn deinit(self: *Ecosystem, allocator: std.mem.Allocator) void {
        allocator.free(self.repos);
    }
};

pub const Taxonomy = struct {
    allocator: std.mem.Allocator,
    eco_auto_id: u32,
    repo_auto_id: u32,
    tag_auto_id: u32,
    migration_count: u32,

    buffers: ArrayList([]const u8),

    eco_ids: SliceIdMap,
    repo_ids: SliceIdMap,
    tag_ids: SliceIdMap,
    repo_id_to_url_map: IdSliceMap,
    eco_to_repo_map: EcoToRepoMap,
    repo_to_eco_map: RepoToEcoMap,
    parent_to_child_map: ParentToChildMap,

    pub fn init(allocator: std.mem.Allocator) Taxonomy {
        return .{
            .allocator = allocator,
            .eco_auto_id = 0,
            .repo_auto_id = 0,
            .tag_auto_id = 0,
            .migration_count = 0,
            .buffers = ArrayList([]const u8).init(allocator),
            .eco_ids = SliceIdMap.init(allocator),
            .repo_ids = SliceIdMap.init(allocator),
            .tag_ids = SliceIdMap.init(allocator),
            .parent_to_child_map = ParentToChildMap.init(allocator),
            .eco_to_repo_map = EcoToRepoMap.init(allocator),
            .repo_to_eco_map = RepoToEcoMap.init(allocator),
            .repo_id_to_url_map = IdSliceMap.init(allocator),
        };
    }

    pub fn deinit(self: *Taxonomy) void {
        var iterator = self.eco_to_repo_map.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }

        var p2c_iterator = self.parent_to_child_map.iterator();
        while (p2c_iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }

        self.parent_to_child_map.deinit();
        self.eco_to_repo_map.deinit();
        self.tag_ids.deinit();
        self.eco_ids.deinit();
        self.repo_ids.deinit();
        self.repo_id_to_url_map.deinit();
        self.repo_to_eco_map.deinit();

        for (self.buffers.items) |buf| {
            self.allocator.free(buf);
        }
        self.buffers.deinit();
    }

    pub fn load(self: *Taxonomy, root: []const u8) !void {
        std.debug.print("validate: {s}\n", .{root});
        var dir = try std.fs.cwd().openDir(root, .{ .iterate = true });
        defer dir.close();

        // Create directory iterator
        var iter = dir.iterate();

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;

        var migration_files = std.ArrayList([]const u8).init(self.allocator);
        defer {
            for (migration_files.items) |filename| {
                self.allocator.free(filename);
            }
            migration_files.deinit();
        }

        while (try iter.next()) |entry| {
            if (entry.kind == std.fs.File.Kind.file) {
                const name = try self.allocator.dupe(u8, entry.name);
                if (timestamp.hasValidTimestamp(name)) {
                    try migration_files.append(name);
                }
            }
        }

        std.mem.sort([]const u8, migration_files.items, {}, struct {
            pub fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                return std.mem.lessThan(u8, a[0..19], b[0..19]);
            }
        }.lessThan);

        var fba = std.heap.FixedBufferAllocator.init(&path_buf);
        const fba_allocator = fba.allocator();
        for (migration_files.items) |filename| {
            std.debug.print("{s}\n", .{filename});
            fba.reset();
            const full_path = try std.fs.path.join(fba_allocator, &[_][]const u8{ root, filename });
            try self.loadFile(full_path);
            self.migration_count += 1;
        }
    }

    fn loadFile(self: *Taxonomy, path: []const u8) !void {
        std.debug.print("Parsing {s}\n", .{path});
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const size = try file.getEndPos();
        const buffer = try self.allocator.alloc(u8, size);

        // One big read
        _ = try file.readAll(buffer);
        try self.buffers.append(buffer);

        var iter = std.mem.splitScalar(u8, buffer, '\n');
        while (iter.next()) |line| {
            if (isComment(line)) {
                continue;
            }
            // Note: line might end in \r for CRLF files
            //std.debug.print("{s}\n", .{line});
            if (line.len < 6) {
                continue;
            }

            const keyword = line[0..6];
            const remainder = line[6..];

            if (keyword[0] == 'r' and std.mem.eql(u8, keyword, "repadd")) {
                try repAdd(remainder, self);
            } else if (std.mem.eql(u8, keyword, "ecocon")) {
                try ecoCon(remainder, self);
            } else if (std.mem.eql(u8, keyword, "ecoadd")) {
                try ecoAdd(remainder, self);
            }
        }
    }

    pub fn stats(self: *Taxonomy) TaxonomyStats {
        return .{
            .migration_count = self.migration_count,
            .eco_count = self.eco_ids.count(),
            .repo_count = self.repo_ids.count(),
            .eco_connections_count = 0,
            .tag_count = 0,
        };
    }

    pub fn exportJson(self: *Taxonomy, output_file: []const u8) !void {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const allocator = arena.allocator();

        const file = try std.fs.cwd().createFile(output_file, .{ .read = false, .truncate = true });
        defer file.close();

        var buffered_writer = std.io.bufferedWriter(file.writer());
        const writer = buffered_writer.writer();

        var iterator = self.eco_ids.iterator();
        while (iterator.next()) |entry| {
            const repo_ids = self.eco_to_repo_map.get(entry.value_ptr.*);
            const repo_urls = if (repo_ids) |ids| ok: {
                const repo_urls = try allocator.alloc([]const u8, ids.count());
                var repo_id_it = ids.keyIterator();
                var i: u32 = 0;
                while (repo_id_it.next()) |repo_id| {
                    repo_urls[i] = self.repo_id_to_url_map.get(repo_id.*).?;
                    i += 1;
                }
                std.mem.sort([]const u8, repo_urls, {}, lessThanLowercase);
                break :ok repo_urls;
            } else ko: {
                break :ko &[_][]const u8{};
            };

            const ecosystem = EcosystemJson{
                .name = entry.key_ptr.*,
                .repos = repo_urls,
            };
            var json_string = std.ArrayList(u8).init(allocator);
            const json_writer = json_string.writer();
            try std.json.stringify(ecosystem, .{}, json_writer);

            try writer.print("{s}\n", .{json_string.items});
        }

        try buffered_writer.flush();
    }

    pub fn eco(self: *Taxonomy, name: []const u8) !?Ecosystem {
        const eco_id_entry = self.eco_ids.getEntry(name) orelse return null;
        const repo_ids = self.eco_to_repo_map.get(eco_id_entry.value_ptr.*);
        const repo_urls = if (repo_ids) |ids| ok: {
            const repo_urls = try self.allocator.alloc([]const u8, ids.count());
            var iterator = ids.keyIterator();
            var i: u32 = 0;
            while (iterator.next()) |repo_id| {
                repo_urls[i] = self.repo_id_to_url_map.get(repo_id.*).?;
                i += 1;
            }
            std.mem.sort([]const u8, repo_urls, {}, lessThanLowercase);
            break :ok repo_urls;
        } else ko: {
            break :ko &[_][]const u8{};
        };
        return .{
            .id = eco_id_entry.value_ptr.*,
            .name = eco_id_entry.key_ptr.*,
            .repos = repo_urls,
        };
    }

    fn addEco(self: *Taxonomy, name: []const u8) !void {
        const eco_id_entry = try self.eco_ids.getOrPut(name);
        if (!eco_id_entry.found_existing) {
            self.eco_auto_id += 1;
            eco_id_entry.value_ptr.* = self.eco_auto_id;
            //std.debug.print("Creating {s} with id: {d}\n", .{ name, self.eco_auto_id });
        } else {
            //const eco_id = eco_id_entry.value_ptr;
            //std.debug.print("Found {s} with existing_id: {}\n", .{ name, eco_id });
        }
    }

    fn connectEco(self: *Taxonomy, parent: []const u8, child: []const u8) !void {
        const parent_id = self.eco_ids.get(parent) orelse return error.InvalidParentEcosystem;
        const child_id = self.eco_ids.get(child) orelse return error.InvalidChildEcosystem;
        const child_entry = try self.parent_to_child_map.getOrPut(parent_id);
        if (!child_entry.found_existing) {
            child_entry.value_ptr.* = IdSet.init(self.allocator);
        }
        try child_entry.value_ptr.put(child_id, {});
    }

    //tags: ?[][]const u8) {
    fn addRepo(self: *Taxonomy, eco_name: []const u8, repo_url: []const u8) !void {
        const eco_id = self.eco_ids.get(eco_name) orelse return error.InvalidEcosystem;
        const repo_id_entry = try self.repo_ids.getOrPut(repo_url);
        if (!repo_id_entry.found_existing) {
            self.repo_auto_id += 1;
            repo_id_entry.value_ptr.* = self.repo_auto_id;
            try self.repo_id_to_url_map.putNoClobber(self.repo_auto_id, repo_url);
        } else {}
        const repo_id = repo_id_entry.value_ptr.*;

        //_ = repo_id;
        const repos_for_eco_entry = try self.eco_to_repo_map.getOrPut(eco_id);
        if (!repos_for_eco_entry.found_existing) {
            repos_for_eco_entry.value_ptr.* = RepoToTagMap.init(self.allocator);
        }
        var repo_to_tag_map = repos_for_eco_entry.value_ptr;
        try repo_to_tag_map.putNoClobber(repo_id, IdSet.init(self.allocator));
    }
};

/// Returns whether  a line is a comment
fn isComment(line: []const u8) bool {
    var i: usize = 0;
    while (i < line.len) {
        // Skip whitespace
        while (i < line.len and std.ascii.isWhitespace(line[i])) i += 1;
        if (i >= line.len) break;
        if (line[i] == '#') {
            return true;
        } else {
            return false;
        }
    }
    return false;
}

fn ecoAdd(sub_line: []const u8, db: *Taxonomy) !void {
    var tokens: [10]?[]const u8 = undefined;
    const token_count = try shlex.split(sub_line, &tokens);
    if (token_count != 1) {
        return error.EcoAddRequiresOneParameter;
    }

    if (tokens[0]) |token| {
        try db.addEco(token);
    }
}

/// Connect an ecosystem to another ecosystem
fn ecoCon(sub_line: []const u8, db: *Taxonomy) !void {
    var tokens: [10]?[]const u8 = undefined;
    const token_count = try shlex.split(sub_line, &tokens);
    if (token_count != 2) {
        return error.EcoConRequiresExactlyTwoParameters;
    }

    if (tokens[0] != null and tokens[1] != null) {
        const parent = tokens[0].?;
        const child = tokens[1].?;
        //std.debug.print("Connecting {s} to {s}\n", .{ parent, child });
        try db.connectEco(parent, child);
    }
}

fn repAdd(remainder: []const u8, db: *Taxonomy) !void {
    var tokens: [10]?[]const u8 = undefined;
    const token_count = try shlex.split(remainder, &tokens);
    if (token_count < 2) {
        return error.RepAddRequiresAtLeastTwoParameters;
    }

    if (tokens[0] != null and tokens[1] != null) {
        const eco = tokens[0].?;
        const repo = tokens[1].?;
        try db.addRepo(eco, repo);
    }
}

fn lessThanLowercase(_: void, a: []const u8, b: []const u8) bool {
    var i: usize = 0;
    while (i < @min(a.len, b.len)) : (i += 1) {
        const a_lower = std.ascii.toLower(a[i]);
        const b_lower = std.ascii.toLower(b[i]);
        if (a_lower != b_lower) {
            return a_lower < b_lower;
        }
    }
    return a.len < b.len;
}

/// This function finds the root of the project so that unit tests can find the test fixtures directory.
fn findBuildZigDirAlloc(allocator: std.mem.Allocator) ![]const u8 {
    const self_path = try std.fs.selfExePathAlloc(allocator);
    defer allocator.free(self_path);

    var current_path = std.fs.path.dirname(self_path) orelse "/";

    while (true) {
        const build_path = try std.fs.path.join(allocator, &.{ current_path, "build.zig" });
        defer allocator.free(build_path);

        std.fs.accessAbsolute(build_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                if (current_path.len == 0 or std.mem.eql(u8, current_path, "/")) {
                    return error.BuildZigNotFound;
                }
                current_path = std.fs.path.dirname(current_path) orelse "/";
                continue;
            }
            return err;
        };

        return allocator.dupe(u8, current_path);
    }
}

// Unit tests of the taxonomy loader.
test "load of single ecosystem" {
    const testing = std.testing;
    const a = testing.allocator;
    const build_dir = try findBuildZigDirAlloc(a);
    defer testing.allocator.free(build_dir);

    // Navigate up to project root and then to tests directory
    const tests_path = try std.fs.path.join(a, &[_][]const u8{ build_dir, "tests", "simple_ecosystems" });
    defer a.free(tests_path);

    var db = Taxonomy.init(testing.allocator);
    defer db.deinit();
    try db.load(tests_path);
    const stats = db.stats();

    try testing.expectEqual(stats.migration_count, 1);
    try testing.expectEqual(stats.eco_count, 1);
    try testing.expectEqual(stats.repo_count, 3);
    try testing.expectEqual(stats.tag_count, 0);
    var btc = (try db.eco("Bitcoin")).?;
    defer btc.deinit(a);

    try testing.expectEqualStrings("Bitcoin", btc.name);
    try testing.expectEqual(btc.id, 1);
    try testing.expectEqual(btc.repos.len, 3);
    try testing.expectEqualStrings("https://github.com/bitcoin/bips", btc.repos[0]);
}

test "time ordering" {
    const testing = std.testing;
    const a = testing.allocator;
    const build_dir = try findBuildZigDirAlloc(a);
    defer testing.allocator.free(build_dir);

    // Navigate up to project root and then to tests directory
    const tests_path = try std.fs.path.join(a, &[_][]const u8{ build_dir, "tests", "time_ordering" });
    defer a.free(tests_path);

    var db = Taxonomy.init(testing.allocator);
    defer db.deinit();
    try db.load(tests_path);
    const stats = db.stats();

    try testing.expectEqual(stats.migration_count, 3);
    try testing.expectEqual(stats.eco_count, 1);
    try testing.expectEqual(stats.repo_count, 2);

    var eth = (try db.eco("Ethereum")).?;
    defer eth.deinit(a);
}
