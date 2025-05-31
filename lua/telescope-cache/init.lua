-- File structure:
-- lua/telescope-cache/init.lua (this file)
-- plugin/telescope-cache.lua (commands)

-- lua/telescope-cache/init.lua
local telescope = require('telescope')
local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local conf = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local previewers = require('telescope.previewers')
local utils = require('telescope.previewers.utils')

local uv = vim.loop
local Path = require('plenary.path')
local Job = require('plenary.job')

local M = {}

-- Default configuration
local default_config = {
  cache_dir = vim.fn.stdpath('cache') .. '/telescope-cache',
  db_name = 'cache.db',
  directories = {},
  filetypes = { '*.lua', '*.py', '*.js', '*.ts', '*.go', '*.rs', '*.c', '*.cpp', '*.h', '*.java', '*.md', '*.txt' },
  ignore_patterns = { '.git', 'node_modules', '__pycache__', '.pytest_cache', 'target', 'build' },
  max_file_size = 1024 * 1024, -- 1MB
  auto_refresh = true,
  refresh_interval = 300,      -- 5 minutes
  -- Encryption settings
  use_encryption = true,
  password_prompt = true, -- Prompt for password on first use
  session_timeout = 3600, -- 1 hour - auto-lock after inactivity
}

local config = vim.tbl_deep_extend('force', {}, default_config)
local db_connection = nil
local db_password = nil
local last_activity = 0
local is_unlocked = false

-- Password and encryption utilities
local function hash_password(password)
  -- Simple hash for key derivation - in production, use a proper KDF
  local hash = 0
  for i = 1, #password do
    hash = (hash * 31 + string.byte(password, i)) % 2147483647
  end
  return tostring(hash)
end

local function prompt_password(confirm)
  local password
  if confirm then
    password = vim.fn.inputsecret("Enter new cache password: ")
    if password == "" then
      return nil
    end
    local confirm_password = vim.fn.inputsecret("Confirm password: ")
    if password ~= confirm_password then
      print("Passwords don't match!")
      return nil
    end
  else
    password = vim.fn.inputsecret("Enter cache password: ")
    if password == "" then
      return nil
    end
  end
  return password
end

local function get_db_path()
  return config.cache_dir .. '/' .. config.db_name
end

local function ensure_cache_dir()
  local cache_path = Path:new(config.cache_dir)
  if not cache_path:exists() then
    cache_path:mkdir({ parents = true })
  end
end

local function check_session_timeout()
  if config.use_encryption and is_unlocked and config.session_timeout > 0 then
    if os.time() - last_activity > config.session_timeout then
      M.lock_cache()
      return false
    end
  end
  return true
end

local function update_activity()
  last_activity = os.time()
end

-- Database operations
local function init_database()
  if not config.use_encryption then
    -- Use regular SQLite without encryption
    local sqlite_available, sqlite = pcall(require, 'sqlite')
    if not sqlite_available then
      print("Error: lua-sqlite3 not available. Install with your package manager.")
      return false
    end

    local db_path = get_db_path()
    db_connection = sqlite.open(db_path)

    if not db_connection then
      print("Error: Could not open database")
      return false
    end
  else
    -- Try to use SQLCipher for encryption
    local sqlite_available, sqlite = pcall(require, 'lsqlite3')
    if not sqlite_available then
      print("Error: lsqlite3 not available. Install with: luarocks install --lua-version 5.1 lsqlite3:", sqlite)
      return false
    end

    local db_path = get_db_path()
    db_connection = sqlite.open(db_path)

    if not db_connection then
      print("Error: Could not open database")
      return false
    end

    -- Set encryption key if password is provided
    if db_password then
      local pragma_result = db_connection:exec("PRAGMA key = '" .. db_password .. "';")
      if pragma_result ~= sqlite.OK then
        print("Error: Could not set encryption key")
        db_connection:close()
        db_connection = nil
        return false
      end
    end
  end

  -- Create tables
  local create_files_table = [[
    CREATE TABLE IF NOT EXISTS cached_files (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      file_path TEXT UNIQUE NOT NULL,
      content TEXT NOT NULL,
      file_size INTEGER NOT NULL,
      mtime INTEGER NOT NULL,
      cached_at INTEGER NOT NULL
    );
  ]]

  local create_metadata_table = [[
    CREATE TABLE IF NOT EXISTS cache_metadata (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );
  ]]

  local create_index = [[
    CREATE INDEX IF NOT EXISTS idx_file_path ON cached_files(file_path);
  ]]

  local result1 = db_connection:exec(create_files_table)
  local result2 = db_connection:exec(create_metadata_table)
  local result3 = db_connection:exec(create_index)

  if result1 ~= 0 or result2 ~= 0 or result3 ~= 0 then
    print("Error creating database tables: " .. (db_connection:errmsg() or "unknown error"))
    return false
  end

  return true
end

function M.unlock_cache()
  if not config.use_encryption then
    is_unlocked = true
    return init_database()
  end

  local db_path = get_db_path()
  local db_exists = Path:new(db_path):exists()

  if not db_exists and config.password_prompt then
    print("Creating new encrypted cache database...")
    db_password = prompt_password(true)  -- Confirm password for new database
  elseif config.password_prompt then
    db_password = prompt_password(false) -- Enter existing password
  end

  if not db_password then
    print("Password required for encrypted cache")
    return false
  end

  local success = init_database()
  if success then
    is_unlocked = true
    update_activity()
    print("Cache unlocked successfully")
  else
    db_password = nil
    print("Failed to unlock cache - incorrect password?")
  end

  return success
end

function M.lock_cache()
  if db_connection then
    db_connection:close()
    db_connection = nil
  end
  db_password = nil
  is_unlocked = false
  print("Cache locked")
end

function M.is_cache_locked()
  return config.use_encryption and not is_unlocked
end

local function ensure_unlocked()
  if M.is_cache_locked() then
    return M.unlock_cache()
  end
  if not check_session_timeout() then
    return M.unlock_cache()
  end
  update_activity()
  return true
end

-- File operations with database
local function should_cache_file(file_path)
  -- Check file size
  local stat = uv.fs_stat(file_path)
  if not stat or stat.size > config.max_file_size then
    return false
  end

  -- Check if file matches any of the configured filetypes
  for _, pattern in ipairs(config.filetypes) do
    if file_path:match(pattern:gsub('%*', '.*')) then
      return true
    end
  end

  return false
end

local function should_ignore_path(path)
  for _, pattern in ipairs(config.ignore_patterns) do
    if path:match(pattern) then
      return true
    end
  end
  return false
end

local function scan_directory(directory)
  local files = {}

  local function scan_recursive(dir)
    local handle = uv.fs_scandir(dir)
    if not handle then return end

    while true do
      local name, type = uv.fs_scandir_next(handle)
      if not name then break end

      local full_path = dir .. '/' .. name

      if should_ignore_path(full_path) then
        goto continue
      end

      if type == 'directory' then
        scan_recursive(full_path)
      elseif type == 'file' and should_cache_file(full_path) then
        table.insert(files, full_path)
      end

      ::continue::
    end
  end

  scan_recursive(directory)
  return files
end

local function read_file_content(file_path)
  local file = io.open(file_path, 'r')
  if not file then
    return nil
  end

  local content = file:read('*all')
  file:close()
  return content
end

local function get_cached_file(file_path)
  if not db_connection then return nil end

  local stmt = db_connection:prepare("SELECT content, mtime FROM cached_files WHERE file_path = ?")
  if not stmt then return nil end

  stmt:bind(1, file_path)
  local result = stmt:step()

  if result == 100 then -- SQLITE_ROW
    local content = stmt:get_value(0)
    local mtime = stmt:get_value(1)
    stmt:finalize()
    return content, mtime
  end

  stmt:finalize()
  return nil
end

local function save_cached_file(file_path, content, file_size, mtime)
  if not db_connection then return false end

  local stmt = db_connection:prepare([[
    INSERT OR REPLACE INTO cached_files (file_path, content, file_size, mtime, cached_at)
    VALUES (?, ?, ?, ?, ?)
  ]])

  if not stmt then return false end

  stmt:bind(1, file_path)
  stmt:bind(2, content)
  stmt:bind(3, file_size)
  stmt:bind(4, mtime)
  stmt:bind(5, os.time())

  local result = stmt:step()
  stmt:finalize()

  return result == 101 -- SQLITE_DONE
end

local function get_all_cached_files()
  if not db_connection then return {} end

  local files = {}
  local stmt = db_connection:prepare("SELECT file_path, mtime, file_size FROM cached_files ORDER BY file_path")
  if not stmt then return files end

  while stmt:step() == 100 do -- SQLITE_ROW
    local file_path = stmt:get_value(0)
    local mtime = stmt:get_value(1)
    local file_size = stmt:get_value(2)

    files[file_path] = {
      mtime = mtime,
      size = file_size,
    }
  end

  stmt:finalize()
  return files
end

local function update_cache_entry(file_path)
  local stat = uv.fs_stat(file_path)
  if not stat then
    -- File no longer exists, remove from cache
    if db_connection then
      local stmt = db_connection:prepare("DELETE FROM cached_files WHERE file_path = ?")
      if stmt then
        stmt:bind(1, file_path)
        stmt:step()
        stmt:finalize()
      end
    end
    return false
  end

  local cached_content, cached_mtime = get_cached_file(file_path)
  local needs_update = not cached_content or cached_mtime < stat.mtime.sec

  if needs_update then
    local content = read_file_content(file_path)
    if content then
      local success = save_cached_file(file_path, content, stat.size, stat.mtime.sec)
      return success
    end
  end

  return false
end

-- Main cache functions
function M.refresh_cache()
  if not ensure_unlocked() then
    print("Cache is locked. Use :TelescopeCacheUnlock to unlock.")
    return
  end

  ensure_cache_dir()

  print("Refreshing cache...")
  local total_files = 0
  local updated_files = 0

  for _, directory in ipairs(config.directories) do
    local files = scan_directory(directory)
    total_files = total_files + #files

    for _, file_path in ipairs(files) do
      if update_cache_entry(file_path) then
        updated_files = updated_files + 1
      end
    end
  end

  -- Update metadata
  if db_connection then
    local stmt = db_connection:prepare("INSERT OR REPLACE INTO cache_metadata (key, value) VALUES (?, ?)")
    if stmt then
      stmt:bind(1, "last_refresh")
      stmt:bind(2, tostring(os.time()))
      stmt:step()
      stmt:finalize()
    end
  end

  print(string.format("Cache refresh complete: %d/%d files updated", updated_files, total_files))
end

function M.clear_cache()
  if not ensure_unlocked() then
    print("Cache is locked. Use :TelescopeCacheUnlock to unlock.")
    return
  end

  if db_connection then
    db_connection:exec("DELETE FROM cached_files")
    db_connection:exec("DELETE FROM cache_metadata")
  end

  print("Cache cleared")
end

function M.get_cache_stats()
  if not ensure_unlocked() then
    return {
      cached_files = 0,
      total_size = 0,
      last_refresh = 0,
      cache_dir = config.cache_dir,
      locked = true
    }
  end

  local cached_files = 0
  local total_size = 0
  local last_refresh = 0

  if db_connection then
    -- Get file count and total size
    local stmt = db_connection:prepare("SELECT COUNT(*), SUM(file_size) FROM cached_files")
    if stmt and stmt:step() == 100 then
      cached_files = stmt:get_value(0) or 0
      total_size = stmt:get_value(1) or 0
      stmt:finalize()
    end

    -- Get last refresh time
    local stmt2 = db_connection:prepare("SELECT value FROM cache_metadata WHERE key = 'last_refresh'")
    if stmt2 and stmt2:step() == 100 then
      last_refresh = tonumber(stmt2:get_value(0)) or 0
      stmt2:finalize()
    end
  end

  return {
    cached_files = cached_files,
    total_size = total_size,
    last_refresh = last_refresh,
    cache_dir = config.cache_dir,
    locked = false
  }
end

-- Telescope picker functions
local function create_finder()
  if not ensure_unlocked() then
    return finders.new_table { results = {} }
  end

  local entries = {}
  local cached_files = get_all_cached_files()

  for file_path, _ in pairs(cached_files) do
    local relative_path = file_path
    -- Try to make path relative to first configured directory
    if #config.directories > 0 then
      relative_path = file_path:gsub('^' .. vim.pesc(config.directories[1]) .. '/', '')
    end

    table.insert(entries, {
      value = file_path,
      display = relative_path,
      ordinal = relative_path,
    })
  end

  return finders.new_table {
    results = entries,
    entry_maker = function(entry)
      return entry
    end
  }
end

local function create_previewer()
  return previewers.new_buffer_previewer {
    title = "File Preview (Cached)",
    get_buffer_by_name = function(_, entry)
      return entry.value
    end,
    define_preview = function(self, entry)
      if not ensure_unlocked() then
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "Cache is locked" })
        return
      end

      local content = get_cached_file(entry.value)
      if content then
        local lines = vim.split(content, '\n')
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)

        -- Set filetype for syntax highlighting
        local ft = vim.filetype.match({ filename = entry.value })
        if ft then
          vim.api.nvim_buf_set_option(self.state.bufnr, 'filetype', ft)
        end
      else
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "File not found in cache" })
      end
    end
  }
end

function M.find_files()
  if not ensure_unlocked() then
    print("Cache is locked. Use :TelescopeCacheUnlock to unlock.")
    return
  end

  -- Auto-refresh if needed
  if config.auto_refresh then
    local stats = M.get_cache_stats()
    if (os.time() - stats.last_refresh) > config.refresh_interval then
      M.refresh_cache()
    end
  end

  pickers.new({}, {
    prompt_title = "Cached Files",
    finder = create_finder(),
    sorter = conf.generic_sorter({}),
    previewer = create_previewer(),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        vim.cmd('edit ' .. selection.value)
      end)

      -- Add custom mapping to refresh cache
      map('i', '<C-r>', function()
        actions.close(prompt_bufnr)
        M.refresh_cache()
        M.find_files()
      end)

      return true
    end,
  }):find()
end

local function grep_cached_files(prompt)
  local results = {}

  if not prompt or prompt == "" then
    return results
  end

  if not ensure_unlocked() then
    return results
  end

  local cached_files = get_all_cached_files()

  for file_path, _ in pairs(cached_files) do
    local content = get_cached_file(file_path)
    if content then
      local lines = vim.split(content, '\n')
      for line_num, line in ipairs(lines) do
        if line:lower():find(prompt:lower(), 1, true) then
          local relative_path = file_path
          if #config.directories > 0 then
            relative_path = file_path:gsub('^' .. vim.pesc(config.directories[1]) .. '/', '')
          end

          table.insert(results, {
            filename = file_path,
            lnum = line_num,
            col = 1,
            text = line,
            display = string.format("%s:%d:%s", relative_path, line_num, line),
          })
        end
      end
    end
  end

  return results
end

function M.live_grep()
  if not ensure_unlocked() then
    print("Cache is locked. Use :TelescopeCacheUnlock to unlock.")
    return
  end

  -- Auto-refresh if needed
  if config.auto_refresh then
    local stats = M.get_cache_stats()
    if (os.time() - stats.last_refresh) > config.refresh_interval then
      M.refresh_cache()
    end
  end

  pickers.new({}, {
    prompt_title = "Live Grep (Cached)",
    finder = finders.new_dynamic {
      fn = function(prompt)
        return grep_cached_files(prompt)
      end,
      entry_maker = function(entry)
        return {
          value = entry,
          display = entry.display,
          ordinal = entry.display,
          filename = entry.filename,
          lnum = entry.lnum,
          col = entry.col,
          text = entry.text,
        }
      end,
    },
    sorter = conf.generic_sorter({}),
    previewer = previewers.new_buffer_previewer {
      title = "File Preview (Cached)",
      get_buffer_by_name = function(_, entry)
        return entry.filename
      end,
      define_preview = function(self, entry)
        if not ensure_unlocked() then
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "Cache is locked" })
          return
        end

        local content = get_cached_file(entry.filename)
        if content then
          local lines = vim.split(content, '\n')
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)

          -- Set filetype for syntax highlighting
          local ft = vim.filetype.match({ filename = entry.filename })
          if ft then
            vim.api.nvim_buf_set_option(self.state.bufnr, 'filetype', ft)
          end

          -- Highlight the search result line
          if entry.lnum then
            vim.api.nvim_buf_add_highlight(self.state.bufnr, 0, 'TelescopePreviewLine', entry.lnum - 1, 0, -1)
            -- Try to center the line in preview
            pcall(vim.api.nvim_win_set_cursor, self.state.winid, { entry.lnum, 0 })
          end
        else
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "File not found in cache" })
        end
      end
    },
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection and selection.filename then
          vim.cmd('edit ' .. selection.filename)
          if selection.lnum then
            vim.api.nvim_win_set_cursor(0, { selection.lnum, selection.col or 0 })
          end
        end
      end)

      return true
    end,
  }):find()
end

-- Setup and configuration
function M.setup(opts)
  config = vim.tbl_deep_extend('force', config, opts or {})

  -- Validate directories
  for i, dir in ipairs(config.directories) do
    local path = Path:new(dir)
    if not path:exists() then
      print("Warning: Directory does not exist: " .. dir)
    else
      config.directories[i] = path:absolute()
    end
  end

  ensure_cache_dir()

  -- Auto-unlock on startup if not using encryption
  if not config.use_encryption then
    M.unlock_cache()
  end
end

-- Telescope extension registration
local function register_extension()
  return telescope.register_extension {
    setup = function(ext_config)
      -- This allows telescope configuration to override plugin config
      config = vim.tbl_deep_extend('force', config, ext_config or {})
    end,
    exports = {
      find_files = M.find_files,
      live_grep = M.live_grep,
      refresh_cache = M.refresh_cache,
      clear_cache = M.clear_cache,
      cache_stats = M.get_cache_stats,
      unlock_cache = M.unlock_cache,
      lock_cache = M.lock_cache,
      is_cache_locked = M.is_cache_locked,
    }
  }
end

-- Register the extension automatically when telescope is available
M.register = register_extension

return M
