-- tests/minimal_init.lua
-- Minimal Neovim configuration for running tests.
--
-- vusted can redirect XDG paths to a sandboxed temp dir, which makes
-- stdpath('data') unreliable for locating manually-installed plugins.
-- Probe several candidate locations and explicitly extend package.path
-- so require() works even if rtp->package.path sync has not run.

vim.opt.runtimepath:append('.')

local function dir_exists(path)
  return vim.fn.isdirectory(path) == 1
end

local function find_plugin(name)
  local home = vim.env.HOME or os.getenv('HOME') or ''
  local candidates = {
    vim.fn.stdpath('data') .. '/site/pack/deps/start/' .. name,
    home .. '/.local/share/nvim/site/pack/deps/start/' .. name,
    '/opt/nvim-plugins/' .. name,
  }
  for _, path in ipairs(candidates) do
    if dir_exists(path) then
      return path
    end
  end
  return nil
end

local function add_plugin(name)
  local path = find_plugin(name)
  if not path then
    return
  end
  vim.opt.runtimepath:append(path)
  package.path = package.path
    .. ';' .. path .. '/lua/?.lua'
    .. ';' .. path .. '/lua/?/init.lua'
end

add_plugin('plenary.nvim')
add_plugin('telescope.nvim')

-- Disable swap files and other stuff that might interfere with tests
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false

-- Set up test environment
vim.g.telescope_cache_test_mode = true
