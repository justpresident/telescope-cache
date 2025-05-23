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
  directories = {},
  filetypes = { '*.lua', '*.py', '*.js', '*.ts', '*.go', '*.rs', '*.c', '*.cpp', '*.h', '*.java', '*.md', '*.txt' },
  ignore_patterns = { '.git', 'node_modules', '__pycache__', '.pytest_cache', 'target', 'build' },
  max_file_size = 1024 * 1024, -- 1MB
  auto_refresh = true,
  refresh_interval = 300, -- 5 minutes
}

local config = vim.tbl_deep_extend('force', {}, default_config)
local cache_db = {}
local last_refresh = 0

-- Utility functions
local function get_cache_file_path(file_path)
  local cache_path = config.cache_dir .. '/' .. file_path:gsub('/', '_SLASH_')
  return cache_path
end

local function get_metadata_path()
  return config.cache_dir .. '/metadata.json'
end

local function ensure_cache_dir()
  local cache_path = Path:new(config.cache_dir)
  if not cache_path:exists() then
    cache_path:mkdir({ parents = true })
  end
end

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

local function write_cache_file(file_path, content)
  local cache_path = get_cache_file_path(file_path)
  local cache_file = io.open(cache_path, 'w')
  if cache_file then
    cache_file:write(content)
    cache_file:close()
    return true
  end
  return false
end

local function read_cache_file(file_path)
  local cache_path = get_cache_file_path(file_path)
  local cache_file = io.open(cache_path, 'r')
  if cache_file then
    local content = cache_file:read('*all')
    cache_file:close()
    return content
  end
  return nil
end

local function save_metadata()
  local metadata = {
    cache_db = cache_db,
    last_refresh = last_refresh,
    config = config
  }

  local metadata_file = io.open(get_metadata_path(), 'w')
  if metadata_file then
    metadata_file:write(vim.fn.json_encode(metadata))
    metadata_file:close()
  end
end

local function load_metadata()
  local metadata_file = io.open(get_metadata_path(), 'r')
  if metadata_file then
    local content = metadata_file:read('*all')
    metadata_file:close()

    local ok, metadata = pcall(vim.fn.json_decode, content)
    if ok and metadata then
      cache_db = metadata.cache_db or {}
      last_refresh = metadata.last_refresh or 0
      return true
    end
  end
  return false
end

local function update_cache_entry(file_path)
  local stat = uv.fs_stat(file_path)
  if not stat then
    cache_db[file_path] = nil
    return false
  end

  local cached_entry = cache_db[file_path]
  local needs_update = not cached_entry or cached_entry.mtime < stat.mtime.sec

  if needs_update then
    local content = read_file_content(file_path)
    if content then
      write_cache_file(file_path, content)
      cache_db[file_path] = {
        mtime = stat.mtime.sec,
        size = stat.size,
        cached_at = os.time()
      }
      return true
    end
  end

  return false
end

-- Main cache functions
function M.refresh_cache()
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

  last_refresh = os.time()
  save_metadata()

  print(string.format("Cache refresh complete: %d/%d files updated", updated_files, total_files))
end

function M.clear_cache()
  -- Remove cache files
  local cache_path = Path:new(config.cache_dir)
  if cache_path:exists() then
    cache_path:rm({ recursive = true })
  end

  cache_db = {}
  last_refresh = 0

  print("Cache cleared")
end

function M.get_cache_stats()
  local cached_files = 0
  local total_size = 0

  for file_path, entry in pairs(cache_db) do
    cached_files = cached_files + 1
    total_size = total_size + (entry.size or 0)
  end

  return {
    cached_files = cached_files,
    total_size = total_size,
    last_refresh = last_refresh,
    cache_dir = config.cache_dir
  }
end

-- Telescope picker functions
local function create_finder()
  local entries = {}

  for file_path, _ in pairs(cache_db) do
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
      local content = read_cache_file(entry.value)
      if content then
        local lines = vim.split(content, '\n')
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)

        -- Set filetype for syntax highlighting
        local ft = vim.filetype.match({ filename = entry.value })
        if ft then
          vim.api.nvim_buf_set_option(self.state.bufnr, 'filetype', ft)
        end
      else
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {"File not found in cache"})
      end
    end
  }
end

function M.find_files()
  -- Auto-refresh if needed
  if config.auto_refresh and (os.time() - last_refresh) > config.refresh_interval then
    M.refresh_cache()
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

function M.live_grep()
  -- Auto-refresh if needed
  if config.auto_refresh and (os.time() - last_refresh) > config.refresh_interval then
    M.refresh_cache()
  end

  pickers.new({}, {
    prompt_title = "Live Grep (Cached)",
    finder = finders.new_async_job {
      command_generator = function(prompt)
        if not prompt or prompt == "" then
          return nil
        end

        local results = {}
        for file_path, _ in pairs(cache_db) do
          local content = read_cache_file(file_path)
          if content then
            local lines = vim.split(content, '\n')
            for line_num, line in ipairs(lines) do
              if line:lower():find(prompt:lower()) then
                local relative_path = file_path
                if #config.directories > 0 then
                  relative_path = file_path:gsub('^' .. vim.pesc(config.directories[1]) .. '/', '')
                end
                table.insert(results, string.format("%s:%d:%s", relative_path, line_num, line))
              end
            end
          end
        end

        return { command = "echo", args = results }
      end,
      entry_maker = function(entry)
        local parts = vim.split(entry, ":", { plain = true })
        if #parts >= 3 then
          local file = parts[1]
          local line_num = tonumber(parts[2]) or 1
          local text = table.concat(parts, ":", 3)

          return {
            value = entry,
            display = entry,
            ordinal = entry,
            filename = file,
            lnum = line_num,
            text = text,
          }
        end
        return nil
      end,
    },
    sorter = conf.generic_sorter({}),
    previewer = conf.grep_previewer({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection and selection.filename then
          local full_path = selection.filename
          -- Convert relative path back to full path
          if not full_path:match('^/') and #config.directories > 0 then
            full_path = config.directories[1] .. '/' .. full_path
          end

          vim.cmd('edit ' .. full_path)
          if selection.lnum then
            vim.api.nvim_win_set_cursor(0, {selection.lnum, 0})
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
  load_metadata()
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
    }
  }
end

-- Register the extension automatically when telescope is available
M.register = register_extension

return M
