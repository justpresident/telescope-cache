-- tests/cache_plugin_spec.lua
-- Integration tests for the telescope-cache plugin

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
      -- Mock password input
      _G.test_password = "test_password_123"
      vim.fn.inputsecret = function() return _G.test_password end

      local success = cache_plugin.unlock_cache()
      assert.is_true(success)

      local locked = cache_plugin.is_cache_locked()
      assert.is_false(locked)
    end)

    it("should lock cache", function()
      _G.test_password = "test_password_123"
      vim.fn.inputsecret = function() return _G.test_password end

      cache_plugin.unlock_cache()
      cache_plugin.lock_cache()

      local locked = cache_plugin.is_cache_locked()
      assert.is_true(locked)
    end)
  end)

  describe("file caching", function()
    before_each(function()
      -- Unlock cache for these tests
      _G.test_password = "test_password_123"
      vim.fn.inputsecret = function() return _G.test_password end
      cache_plugin.unlock_cache()
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

  describe("pattern matching", function()
    before_each(function()
      _G.test_password = "test_password_123"
      vim.fn.inputsecret = function() return _G.test_password end
      cache_plugin.unlock_cache()
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

      _G.test_password = "test_password_123"
      vim.fn.inputsecret = function() return _G.test_password end
      cache_plugin.unlock_cache()
      cache_plugin.refresh_cache()

      -- Should not cache files in .git directory
      local stats = cache_plugin.get_cache_stats()
      assert.equals(3, stats.cached_files) -- Only the 3 original files
    end)
  end)
end)
