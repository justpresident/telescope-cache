-- Create user commands
vim.api.nvim_create_user_command('TelescopeCacheRefresh', function()
  require('telescope').extensions.cache.refresh_cache()
end, { desc = 'Refresh telescope cache' })

vim.api.nvim_create_user_command('TelescopeCacheClear', function()
  require('telescope').extensions.cache.clear_cache()
end, { desc = 'Clear telescope cache' })

vim.api.nvim_create_user_command('TelescopeCacheStats', function()
  local stats = require('telescope').extensions.cache.cache_stats()
  print("Telescope Cache Stats:")
  print("  Cached files: " .. stats.cached_files)
  print("  Total size: " .. string.format("%.2f MB", stats.total_size / 1024 / 1024))
  print("  Last refresh: " .. (stats.last_refresh > 0 and os.date("%Y-%m-%d %H:%M:%S", stats.last_refresh) or "Never"))
  print("  Cache directory: " .. stats.cache_dir)
end, { desc = 'Show telescope cache statistics' })

vim.api.nvim_create_user_command('TelescopeCacheFiles', function()
  require('telescope').extensions.cache.find_files()
end, { desc = 'Find files in cache' })

vim.api.nvim_create_user_command('TelescopeCacheGrep', function()
  require('telescope').extensions.cache.live_grep()
end, { desc = 'Live grep in cached files' })
