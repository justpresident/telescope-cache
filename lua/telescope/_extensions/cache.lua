local telescope = require('telescope')
local cache_plugin = require('telescope-cache')

return telescope.register_extension {
  setup = function(ext_config, config)
    -- Pass extension config to the main plugin
    -- This allows configuration via telescope setup
    if ext_config then
      cache_plugin.setup(ext_config)
    end
  end,
  exports = {
    find_files = cache_plugin.find_files,
    live_grep = cache_plugin.live_grep,
    refresh_cache = cache_plugin.refresh_cache,
    clear_cache = cache_plugin.clear_cache,
    cache_stats = cache_plugin.get_cache_stats,
  }
}
