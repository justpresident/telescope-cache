-- tests/cache_plugin_spec.lua
-- Integration tests for the telescope-cache plugin

-- vusted does not auto-load tests/minimal_init.lua. Source it explicitly
-- so plenary/telescope are on the runtime path before any require() runs.
do
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    local dir = source:sub(2):match("(.*/)") or "./"
    dofile(dir .. 'minimal_init.lua')
  else
    dofile('./tests/minimal_init.lua')
  end
end

describe("Telescope Cache Plugin", function()
  local cache_plugin
  local test_cache_dir = "/tmp/telescope_cache_test"
  local test_files_dir = "/tmp/test_files"

  before_each(function()
    -- Clean up
    vim.fn.system("rm -rf " .. test_cache_dir)
    vim.fn.system("rm -rf " .. test_files_dir)

    -- Create test directory
    vim.fn.mkdir(test_files_dir, "p")

    -- Create some test files
    local test_file1 = test_files_dir .. "/test1.lua"
    local test_file2 = test_files_dir .. "/test2.py"
    local test_file3 = test_files_dir .. "/subdir/test3.lua"

    vim.fn.mkdir(test_files_dir .. "/subdir", "p")

    local f1 = io.open(test_file1, "w")
    f1:write("-- Test Lua file\nlocal function hello() print('hello') end")
    f1:close()

    local f2 = io.open(test_file2, "w")
    f2:write("# Test Python file\ndef hello():\n    print('hello')")
    f2:close()

    local f3 = io.open(test_file3, "w")
    f3:write("-- Nested Lua file\nlocal x = 42")
    f3:close()

    -- Reset module
    package.loaded['telescope-cache'] = nil
    cache_plugin = require('telescope-cache')

    -- Setup with test configuration
    cache_plugin.setup({
      cache_dir = test_cache_dir,
      directories = { test_files_dir },
      allow_patterns = { '%.lua$', '%.py$' },
      ignore_patterns = { '%.git' },
      password_prompt = false, -- Don't prompt in tests
    })
  end)

  after_each(function()
    -- Clean up
    vim.fn.system("rm -rf " .. test_cache_dir)
    vim.fn.system("rm -rf " .. test_files_dir)
  end)

  describe("configuration", function()
    it("should load plugin", function()
      assert.is_not_nil(cache_plugin)
    end)

    it("should have required functions", function()
      assert.is_function(cache_plugin.setup)
      assert.is_function(cache_plugin.refresh_cache)
      assert.is_function(cache_plugin.clear_cache)
      assert.is_function(cache_plugin.unlock_cache)
      assert.is_function(cache_plugin.lock_cache)
      assert.is_function(cache_plugin.get_cache_stats)
    end)

    it("should export print_config for debugging", function()
      assert.is_function(cache_plugin.print_config)
    end)
  end)

  describe("cache operations", function()
    it("should require unlock before operations", function()
      local locked = cache_plugin.is_cache_locked()
      assert.is_true(locked)
    end)

    it("should unlock cache", function()
      local success = cache_plugin.unlock_cache("test_password_123")
      assert.is_true(success)

      local locked = cache_plugin.is_cache_locked()
      assert.is_false(locked)
    end)

    it("should lock cache", function()
      cache_plugin.unlock_cache("test_password_123")
      cache_plugin.lock_cache()

      local locked = cache_plugin.is_cache_locked()
      assert.is_true(locked)
    end)
  end)

  describe("file caching", function()
    before_each(function()
      cache_plugin.unlock_cache("test_password_123")
    end)

    it("should refresh and cache files", function()
      cache_plugin.refresh_cache()

      local stats = cache_plugin.get_cache_stats()
      -- Should have cached 3 files (2 .lua + 1 .py)
      assert.is_true(stats.cached_files >= 2)
    end)

    it("should clear cache", function()
      cache_plugin.refresh_cache()

      local stats_before = cache_plugin.get_cache_stats()
      assert.is_true(stats_before.cached_files > 0)

      cache_plugin.clear_cache()

      local stats_after = cache_plugin.get_cache_stats()
      assert.equals(0, stats_after.cached_files)
    end)

    it("should track cache stats", function()
      cache_plugin.refresh_cache()

      local stats = cache_plugin.get_cache_stats()
      assert.is_number(stats.cached_files)
      assert.is_number(stats.total_size)
      assert.is_number(stats.last_refresh)
      assert.is_false(stats.locked)
      assert.is_table(stats.directories)
    end)
  end)

  describe("compute_common_prefix helper", function()
    it("should be exposed for testing", function()
      assert.is_not_nil(cache_plugin._internal)
      assert.is_function(cache_plugin._internal.compute_common_prefix)
    end)

    it("should return empty for empty input", function()
      assert.equals("", cache_plugin._internal.compute_common_prefix({}))
    end)

    it("should return directory of a single file", function()
      assert.equals("/foo/bar/",
        cache_plugin._internal.compute_common_prefix({ "/foo/bar/baz.lua" }))
    end)

    it("should find common directory prefix across files", function()
      local result = cache_plugin._internal.compute_common_prefix({
        "/foo/bar/a.lua",
        "/foo/bar/b.lua",
        "/foo/bar/c.lua",
      })
      assert.equals("/foo/bar/", result)
    end)

    it("should trim raw LCP back to a directory boundary", function()
      -- raw LCP is "/foo/ba", but the result must end at "/"
      local result = cache_plugin._internal.compute_common_prefix({
        "/foo/bar/a.lua",
        "/foo/baz/b.lua",
      })
      assert.equals("/foo/", result)
    end)

    it("should fall back to root when only '/' is shared", function()
      local result = cache_plugin._internal.compute_common_prefix({
        "/foo/a.lua",
        "/bar/b.lua",
      })
      assert.equals("/", result)
    end)

    it("should return empty when nothing is shared", function()
      local result = cache_plugin._internal.compute_common_prefix({
        "foo/a.lua",
        "bar/b.lua",
      })
      assert.equals("", result)
    end)

    it("should handle identical paths", function()
      local result = cache_plugin._internal.compute_common_prefix({
        "/foo/bar.lua",
        "/foo/bar.lua",
      })
      assert.equals("/foo/", result)
    end)
  end)

  describe("strip_trailing_slash helper", function()
    it("should strip a single trailing slash", function()
      assert.equals("/foo", cache_plugin._internal.strip_trailing_slash("/foo/"))
    end)

    it("should strip multiple trailing slashes", function()
      assert.equals("/foo", cache_plugin._internal.strip_trailing_slash("/foo///"))
    end)

    it("should preserve a path with no trailing slash", function()
      assert.equals("/foo", cache_plugin._internal.strip_trailing_slash("/foo"))
    end)

    it("should preserve the root path", function()
      assert.equals("/", cache_plugin._internal.strip_trailing_slash("/"))
    end)
  end)

  describe("file extraction", function()
    local test_extract_dir = "/tmp/test_extract_out"

    local function read_file(path)
      local f = io.open(path, "r")
      if not f then return nil end
      local content = f:read("*all")
      f:close()
      return content
    end

    before_each(function()
      vim.fn.system("rm -rf " .. test_extract_dir)
      cache_plugin.unlock_cache("test_password_123")
      cache_plugin.refresh_cache()
    end)

    after_each(function()
      vim.fn.system("rm -rf " .. test_extract_dir)
    end)

    it("should extract all cached files with path remapping", function()
      cache_plugin.extract(test_files_dir, test_extract_dir)

      assert.is_not_nil(read_file(test_extract_dir .. "/test1.lua"))
      assert.is_not_nil(read_file(test_extract_dir .. "/test2.py"))
      assert.is_not_nil(read_file(test_extract_dir .. "/subdir/test3.lua"))
    end)

    it("should preserve file content byte-for-byte", function()
      cache_plugin.extract(test_files_dir, test_extract_dir)

      assert.equals(
        read_file(test_files_dir .. "/test1.lua"),
        read_file(test_extract_dir .. "/test1.lua"))
      assert.equals(
        read_file(test_files_dir .. "/subdir/test3.lua"),
        read_file(test_extract_dir .. "/subdir/test3.lua"))
    end)

    it("should create missing parent directories", function()
      cache_plugin.extract(test_files_dir, test_extract_dir .. "/deeply/nested/output")

      assert.is_not_nil(read_file(test_extract_dir .. "/deeply/nested/output/test1.lua"))
      assert.is_not_nil(read_file(test_extract_dir .. "/deeply/nested/output/subdir/test3.lua"))
    end)

    it("should normalize trailing slashes on both prefixes", function()
      cache_plugin.extract(test_files_dir .. "/", test_extract_dir .. "/")

      assert.is_not_nil(read_file(test_extract_dir .. "/test1.lua"))
      assert.is_not_nil(read_file(test_extract_dir .. "/subdir/test3.lua"))
    end)

    it("should filter extracted files by SQL LIKE substring", function()
      cache_plugin.extract(test_files_dir, test_extract_dir, "test1")

      assert.is_not_nil(read_file(test_extract_dir .. "/test1.lua"))
      assert.is_nil(read_file(test_extract_dir .. "/test2.py"))
      assert.is_nil(read_file(test_extract_dir .. "/subdir/test3.lua"))
    end)

    it("should not match a sibling directory with similar prefix", function()
      -- Cache a file in a sibling that *string-prefix-matches* test_files_dir
      local sibling = test_files_dir .. "_extra"
      vim.fn.mkdir(sibling, "p")
      local f = io.open(sibling .. "/should_not_match.lua", "w")
      f:write("-- sibling")
      f:close()

      package.loaded['telescope-cache'] = nil
      cache_plugin = require('telescope-cache')
      cache_plugin.setup({
        cache_dir = test_cache_dir,
        directories = { test_files_dir, sibling },
        allow_patterns = { '%.lua$', '%.py$' },
        ignore_patterns = { '%.git' },
        password_prompt = false,
      })
      cache_plugin.unlock_cache("test_password_123")
      cache_plugin.refresh_cache()

      cache_plugin.extract(test_files_dir, test_extract_dir)

      assert.is_not_nil(read_file(test_extract_dir .. "/test1.lua"))
      assert.is_nil(read_file(test_extract_dir .. "/should_not_match.lua"))
      assert.is_nil(read_file(test_extract_dir .. "_extra/should_not_match.lua"))

      vim.fn.system("rm -rf " .. sibling)
    end)

    it("should extract nothing when from_prefix matches no cached file", function()
      cache_plugin.extract("/nonexistent/path", test_extract_dir)

      assert.is_nil(read_file(test_extract_dir .. "/test1.lua"))
    end)

    it("should refuse empty from_prefix", function()
      cache_plugin.extract("", test_extract_dir)
      assert.is_nil(read_file(test_extract_dir .. "/test1.lua"))
    end)

    it("should refuse empty to_prefix", function()
      -- Should not throw and should not create any extraction output
      cache_plugin.extract(test_files_dir, "")
      assert.is_nil(read_file(test_extract_dir .. "/test1.lua"))
    end)

    it("should overwrite an existing destination file", function()
      vim.fn.mkdir(test_extract_dir, "p")
      local existing = test_extract_dir .. "/test1.lua"
      local f = io.open(existing, "w")
      f:write("STALE CONTENT")
      f:close()

      cache_plugin.extract(test_files_dir, test_extract_dir)

      assert.equals(
        read_file(test_files_dir .. "/test1.lua"),
        read_file(existing))
    end)
  end)

  describe("query_cached_paths helper", function()
    before_each(function()
      cache_plugin.unlock_cache("test_password_123")
      cache_plugin.refresh_cache()
    end)

    it("should return all paths when filter is empty", function()
      local paths = cache_plugin._internal.query_cached_paths("")
      assert.equals(3, #paths)
    end)

    it("should return all paths when filter is nil", function()
      local paths = cache_plugin._internal.query_cached_paths(nil)
      assert.equals(3, #paths)
    end)

    it("should narrow results by LIKE substring", function()
      local paths = cache_plugin._internal.query_cached_paths("test1")
      assert.equals(1, #paths)
      assert.is_not_nil(paths[1]:match("test1%.lua$"))
    end)

    it("should return paths sorted", function()
      local paths = cache_plugin._internal.query_cached_paths("")
      for i = 2, #paths do
        assert.is_true(paths[i - 1] <= paths[i])
      end
    end)
  end)

  describe("pattern matching", function()
    before_each(function()
      cache_plugin.unlock_cache("test_password_123")
    end)

    it("should respect allow_patterns", function()
      -- Create a file that doesn't match patterns
      local non_matching = test_files_dir .. "/test.txt"
      local f = io.open(non_matching, "w")
      f:write("This should not be cached")
      f:close()

      cache_plugin.refresh_cache()

      -- Should only cache .lua and .py files
      local stats = cache_plugin.get_cache_stats()
      -- We created 3 matching files, should not include .txt
      assert.is_true(stats.cached_files == 3)
    end)

    it("should respect ignore_patterns", function()
      -- Create a .git directory
      vim.fn.mkdir(test_files_dir .. "/.git", "p")
      local git_file = test_files_dir .. "/.git/config.lua"
      local f = io.open(git_file, "w")
      f:write("-- This is in .git")
      f:close()

      -- Reset plugin with proper ignore pattern
      package.loaded['telescope-cache'] = nil
      cache_plugin = require('telescope-cache')
      cache_plugin.setup({
        cache_dir = test_cache_dir,
        directories = { test_files_dir },
        allow_patterns = { '%.lua$', '%.py$' },
        ignore_patterns = { '%.git' }, -- Properly escaped
        password_prompt = false,
      })

      cache_plugin.unlock_cache("test_password_123")
      cache_plugin.refresh_cache()

      -- Should not cache files in .git directory
      local stats = cache_plugin.get_cache_stats()
      assert.equals(3, stats.cached_files) -- Only the 3 original files
    end)
  end)
end)
