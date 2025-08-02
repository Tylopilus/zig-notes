const std = @import("std");
const allocator = @import("../utils/allocator.zig").allocator;

pub const FuzzyMatch = struct {
    text: []const u8,
    score: f32,
    
    pub fn lessThan(context: void, a: FuzzyMatch, b: FuzzyMatch) bool {
        _ = context;
        return a.score > b.score; // Higher scores first
    }
};

// Check if fzf is available on the system
fn isFzfAvailable() bool {
    var child = std.process.Child.init(&[_][]const u8{ "which", "fzf" }, allocator);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    
    const term = child.spawnAndWait() catch return false;
    
    return switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };
}

// Use fzf for fuzzy matching (if available)
fn fuzzyMatchWithFzf(query: []const u8, candidates: []const []const u8, max_results: usize) ![]FuzzyMatch {
    var matches = std.ArrayList(FuzzyMatch).init(allocator);
    defer matches.deinit();
    
    // Create input for fzf
    var input = std.ArrayList(u8).init(allocator);
    defer input.deinit();
    
    for (candidates) |candidate| {
        try input.appendSlice(candidate);
        try input.append('\n');
    }
    
    // Run fzf with the query
    var child = std.process.Child.init(&[_][]const u8{
        "fzf", "--filter", query, "--no-sort"
    }, allocator);
    
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    
    try child.spawn();
    
    // Send input to fzf
    try child.stdin.?.writeAll(input.items);
    child.stdin.?.close();
    child.stdin = null;
    
    // Read output
    const output = try child.stdout.?.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(output);
    
    _ = try child.wait();
    
    // Parse fzf output
    var lines = std.mem.splitScalar(u8, output, '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (count >= max_results) break;
        
        try matches.append(FuzzyMatch{
            .text = try allocator.dupe(u8, line),
            .score = @as(f32, @floatFromInt(max_results - count)), // Higher for earlier results
        });
        count += 1;
    }
    
    return try allocator.dupe(FuzzyMatch, matches.items);
}

// Simple fallback fuzzy matching algorithm
fn fuzzyMatchFallback(query: []const u8, candidates: []const []const u8, max_results: usize) ![]FuzzyMatch {
    var matches = std.ArrayList(FuzzyMatch).init(allocator);
    defer matches.deinit();
    
    const query_lower = try std.ascii.allocLowerString(allocator, query);
    defer allocator.free(query_lower);
    
    for (candidates) |candidate| {
        const candidate_lower = try std.ascii.allocLowerString(allocator, candidate);
        defer allocator.free(candidate_lower);
        
        const score = calculateFuzzyScore(query_lower, candidate_lower);
        if (score > 0) {
            try matches.append(FuzzyMatch{
                .text = try allocator.dupe(u8, candidate),
                .score = score,
            });
        }
    }
    
    // Sort by score (highest first)
    std.sort.insertion(FuzzyMatch, matches.items, {}, FuzzyMatch.lessThan);
    
    // Limit results
    const result_count = @min(matches.items.len, max_results);
    return try allocator.dupe(FuzzyMatch, matches.items[0..result_count]);
}

// Calculate fuzzy score for fallback algorithm
fn calculateFuzzyScore(query: []const u8, candidate: []const u8) f32 {
    if (query.len == 0) return 1.0;
    if (candidate.len == 0) return 0.0;
    
    // Exact match gets highest score
    if (std.mem.eql(u8, query, candidate)) {
        return 100.0;
    }
    
    // Prefix match gets high score
    if (std.mem.startsWith(u8, candidate, query)) {
        return 50.0 + (10.0 * @as(f32, @floatFromInt(query.len)) / @as(f32, @floatFromInt(candidate.len)));
    }
    
    // Substring match gets medium score
    if (std.mem.indexOf(u8, candidate, query) != null) {
        return 25.0 + (5.0 * @as(f32, @floatFromInt(query.len)) / @as(f32, @floatFromInt(candidate.len)));
    }
    
    // Character sequence match gets lower score
    var query_idx: usize = 0;
    var score: f32 = 0;
    var consecutive: usize = 0;
    
    for (candidate) |c| {
        if (query_idx < query.len and c == query[query_idx]) {
            query_idx += 1;
            consecutive += 1;
            score += @as(f32, @floatFromInt(consecutive)); // Bonus for consecutive matches
        } else {
            consecutive = 0;
        }
    }
    
    if (query_idx == query.len) {
        return score + 1.0; // Found all characters
    }
    
    return 0.0; // No match
}

// Main fuzzy matching function
pub fn fuzzyMatch(query: []const u8, candidates: []const []const u8, max_results: usize) ![]FuzzyMatch {
    // If query is empty, return all candidates
    if (query.len == 0) {
        var matches = std.ArrayList(FuzzyMatch).init(allocator);
        defer matches.deinit();
        
        const result_count = @min(candidates.len, max_results);
        for (candidates[0..result_count]) |candidate| {
            try matches.append(FuzzyMatch{
                .text = try allocator.dupe(u8, candidate),
                .score = 1.0,
            });
        }
        
        return try allocator.dupe(FuzzyMatch, matches.items);
    }
    
    // Try fzf first, fall back to simple algorithm
    if (isFzfAvailable()) {
        std.log.debug("Using fzf for fuzzy matching", .{});
        return fuzzyMatchWithFzf(query, candidates, max_results) catch |err| {
            std.log.warn("fzf failed: {}, falling back to simple matching", .{err});
            return fuzzyMatchFallback(query, candidates, max_results);
        };
    } else {
        std.log.debug("fzf not available, using fallback fuzzy matching", .{});
        return fuzzyMatchFallback(query, candidates, max_results);
    }
}

// Free fuzzy match results
pub fn freeFuzzyMatches(matches: []FuzzyMatch) void {
    for (matches) |match| {
        allocator.free(match.text);
    }
    allocator.free(matches);
}

test "fuzzy match fallback" {
    const candidates = [_][]const u8{ "file1.md", "file2.md", "subfile.md", "another.md" };
    
    const matches = try fuzzyMatchFallback("sub", &candidates, 10);
    defer freeFuzzyMatches(matches);
    
    try std.testing.expect(matches.len >= 1);
    try std.testing.expectEqualStrings("subfile.md", matches[0].text);
}

test "fuzzy score calculation" {
    // Exact match
    try std.testing.expect(calculateFuzzyScore("test", "test") == 100.0);
    
    // Prefix match
    try std.testing.expect(calculateFuzzyScore("te", "test") > 50.0);
    
    // Substring match
    try std.testing.expect(calculateFuzzyScore("es", "test") > 20.0);
    
    // No match
    try std.testing.expect(calculateFuzzyScore("xyz", "test") == 0.0);
}