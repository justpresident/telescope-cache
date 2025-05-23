# telescope-cache.nvim

A Neovim plugin that provides persistent caching for Telescope.nvim search results. The main use case is caching files from slow filesystems and for offline work on files from remote filesystems.

## Configuration

First, add 'justpresident/telescope-cache' to dependencies list of nvim-telescope/telescope.nvim plugin

Second, configured through Telescope's setup function:

```lua
require('telescope').setup({
  extensions = {
    cache = {
      -- Cache directory (defaults to vim.fn.stdpath('cache') .. '/telescope-cache')
      cache_dir = vim.fn.stdpath('cache') .. '/telescope-cache',
      directories = {
        '/path/to/dir_to_cache',
        '/another/path/to/cache',
      }
      filetypes = {
        '*.lua', '*.py', '*.rs', '*.c', "*.h", "*.cpp",
        "Makefile", "Dockerfile"
      },
      ignore_patterns = { '.git', '__pycache__', '.pytest_cache', 'target', 'build', 'buck-out'},
      max_file_size = 1024 * 1024,
      auto_refresh = true,
      refresh_interval = 3600,
    }
  }
})
require('telescope').load_extension('cache')

-- Optional: Set up keymaps
vim.keymap.set('n', '<leader>scf', '<cmd>TelescopeCacheFiles<cr>', { desc = '[S]earch [C]ached [F]iles' })
vim.keymap.set('n', '<leader>scg', '<cmd>TelescopeCacheGrep<cr>', { desc = '[S]earch [C]ached by [G]rep' })
vim.keymap.set('n', '<leader>scr', '<cmd>TelescopeCacheRefresh<cr>', { desc = '[S]earch [C]ache [R]efresh' })
```

## Usage

Following commands are available:

**TelescopeCacheRefresh**: Refresh the cache. It will be initialized if it doesn't exist. And the password will be asked if encryption is enabled

**TelescopeCacheClear**: Clears all the cache

**TelescopeCacheStats**: Print cache stats

**TelescopeCacheFiles**: Find files in cache

**TelescopeCacheGrep**: Find by grep

**TelescopeCacheUnlock**: Unlock cache. It will ask the password if encryption is enabled

**TelescopeCacheLock**: Lock the cache if it is unlocked. It will require entering a password again to access it

**TelescopeCacheStatus**: Prints cache status: Locked or Unlocked

## Contributing

Contributions are welcome! Please feel free to submit issues, feature requests, or pull requests.


## Acknowledgments

- [Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) - The amazing fuzzy finder that this plugin extends
- Neovim community for the excellent plugin ecosystem

