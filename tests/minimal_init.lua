-- tests/minimal_init.lua
-- Minimal Neovim configuration for running tests

-- Add plugin to runtimepath
vim.opt.runtimepath:append('.')

local data_dir = vim.fn.stdpath('data')
local pack_dir = data_dir .. '/site/pack/deps/start'

-- Add plenary for testing framework and as Telescope dependency
local plenary_path = pack_dir .. '/plenary.nvim'
vim.opt.runtimepath:append(plenary_path)

-- Add telescope
local telescope_path = pack_dir .. '/telescope.nvim'
vim.opt.runtimepath:append(telescope_path)

-- Disable swap files and other stuff that might interfere with tests
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false

-- Set up test environment
vim.g.telescope_cache_test_mode = true
