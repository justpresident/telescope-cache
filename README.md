# telescope-cache.nvim

An extension for Neovim Telescope plugin that provides persistent caching for specified directories. The main use case is caching files from slow filesystems and for offline work on files from remote filesystems.

For example, if your code is on the remote filesystem and is not accessible offline, you can run :TelescopeCacheRefresh which will cache folders specified in the config in an sqlite3 database. Then, when you are offline you can interact with the files using Telescope find and grep tools as if the filesystem was still mounted.

## Configuration

First, add 'justpresident/telescope-cache' to dependencies list of nvim-telescope/telescope.nvim plugin

Second, configure through Telescope's setup function:

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
      -- Encryption settings
      use_encryption = true,
      password_prompt = true, -- Prompt for password on first use
      session_timeout = 3600, -- 1 hour - auto-lock after inactivity
    }
  }
})
require('telescope').load_extension('cache')

-- Optional: Set up keymaps
vim.keymap.set('n', '<leader>scf', '<cmd>TelescopeCacheFiles<cr>', { desc = '[S]earch [C]ached [F]iles' })
vim.keymap.set('n', '<leader>scg', '<cmd>TelescopeCacheGrep<cr>', { desc = '[S]earch [C]ached by [G]rep' })
vim.keymap.set('n', '<leader>scr', '<cmd>TelescopeCacheRefresh<cr>', { desc = '[S]earch [C]ache [R]efresh' })
```

## Dependencies

The plugin requires lua sqlite library to be installed. 

#### On Ubuntu:
```
sudo apt install libsqlite3-dev luarocks
sudo luarocks install lsqlite3
```
#### On Fedora:
```
sudo dnf install luarocks sqlite-devel
sudo luarocks install lsqlite3
```

## Usage

Following commands are available:

- **TelescopeCacheRefresh**: Refresh the cache. It will be initialized if it doesn't exist. And the password will be asked if encryption is enabled
- **TelescopeCacheClear**: Clears all the cache
- **TelescopeCacheStats**: Print cache stats
- **TelescopeCacheFiles**: Find files in cache
- **TelescopeCacheGrep**: Find by grep
- **TelescopeCacheUnlock**: Unlock cache. It will ask the password if encryption is enabled
- **TelescopeCacheLock**: Lock the cache if it is unlocked. It will require entering a password again to access it
- **TelescopeCacheStatus**: Prints cache status: Locked or Unlocked

## Troubleshooting

If `require sqlite` command fails, it might be that sqlite is installed either for wrong version of lua that Neovim uses or into a folder that neovim doesn't know about.

- You can specify lua version in the install command: `sudo luarocks install --lua-version 5.1 lsqlite3`

- You might need to link installed library to the place that Neovim knows about, like: `sudo ln -s /usr/lib64/lua/5.1/lsqlite3.so /usr/local/lib/lua/5.1/`

## Contributing

Contributions are welcome! Please feel free to submit issues, feature requests, or pull requests.


## Acknowledgments

- [Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) - The amazing fuzzy finder that this plugin extends
- Neovim community for the excellent plugin ecosystem

