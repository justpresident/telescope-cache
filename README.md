![CI](https://github.com/justpresident/telescope-cache/actions/workflows/tests.yml/badge.svg)
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
      -- list of patterns for full file path. All files that match at least one of these will be cached
      allow_patterns = {
        '%.lua$', '%.py$', '%.rs$', '%.c$', "%.h$", "%.cpp$",
        "Makefile$", "Dockerfile$", "BUCK$", "TARGETS$", "%.bzl$"
      },
      -- list of patterns for full file path. All the files or directories that match at least one of these will be skipped
      ignore_patterns = { '.git', '__pycache__', '.pytest_cache', 'target', 'build', 'buck-out'},
      max_file_size = 1024 * 1024,
      auto_refresh = true,
      refresh_interval = 3600,
      -- Encryption settings (database is always encrypted)
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

The plugin requires SQLCipher (SQLite with encryption) to be installed.

#### On Ubuntu/Debian:
```bash
sudo apt install libsqlcipher0
```

#### On Fedora:
```bash
sudo dnf install sqlcipher-libs
```

#### On Arch Linux:
```bash
sudo pacman -S sqlcipher
```

**Note:** libsqlcipher must be discoverable by the dynamic loader. You can verify with: `ldconfig -p | grep sqlcipher`

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

## Security & Threat Model

### What's Protected
- ✅ Database file content (page-level AES-256 encryption via SQLCipher)
- ✅ WAL and journal files (also encrypted)
- ✅ Schema, indices, and all data
- ✅ Protection against disk theft, backups, unauthorized file access

### What's NOT Protected
- ❌ Database file size (visible on disk)
- ❌ Password in process memory (accessible to other plugins with FFI access)
- ❌ Timing attacks or access pattern analysis
- ❌ Attackers with root/debugger access to the running process

### Verification

To verify encryption is working:

```bash
# This should show random bytes, NOT "SQLite format 3"
hexdump -C ~/.cache/nvim/telescope-cache/cache.db | head

# This should fail with "file is not a database" or "file is encrypted"
sqlite3 ~/.cache/nvim/telescope-cache/cache.db "SELECT * FROM cached_files;"
```

If you see "SQLite format 3" in the hexdump or if sqlite3 can read the database, encryption is not working properly.

## Troubleshooting

### libsqlcipher not found

If you see "SQLCipher FFI module failed to load":
- Ensure libsqlcipher is installed (see Dependencies section above)
- Verify library is in loader path: `ldconfig -p | grep sqlcipher`
- Check library name: you might need to create a symlink if the version differs from expected names

Example symlink if needed:
```bash
sudo ln -s /usr/lib/x86_64-linux-gnu/libsqlcipher.so.1 /usr/lib/x86_64-linux-gnu/libsqlcipher.so.0
```

### Wrong password

The database will fail to open with "file is not a database" error if:
- The password is incorrect
- The database is corrupted
- You're trying to open a plaintext SQLite database with SQLCipher (delete the old database and refresh)

### Performance

SQLCipher adds minimal overhead (~5-10% typically). The database is always encrypted to ensure security of cached data.

## Testing

This plugin includes automated tests to ensure encryption and caching functionality work correctly.

### Running Tests Locally

1. **Install test dependencies:**
   ```bash
   make install-deps
   ```

2. **Run all tests:**
   ```bash
   make test
   ```

3. **Run specific test file:**
   ```bash
   make test-file FILE=sqlcipher_ffi_spec.lua
   ```

4. **Verify SQLCipher installation:**
   ```bash
   make check-sqlcipher
   ```

5. **Quick smoke test:**
   ```bash
   make smoke
   ```

### Test Structure

```
tests/
├── minimal_init.lua           # Minimal Neovim config for tests
├── sqlcipher_ffi_spec.lua     # Tests for SQLCipher FFI module
└── cache_plugin_spec.lua      # Integration tests for caching
```

### GitHub Actions

Tests run automatically on push and pull requests via GitHub Actions. The workflow:
- Tests on both Neovim stable and nightly
- Installs libsqlcipher0
- Runs the full test suite
- Verifies encryption is working

See `.github/workflows/test.yml` for details.

## Contributing

Contributions are welcome! Please feel free to submit issues, feature requests, or pull requests.

When contributing:
- Add tests for new features
- Ensure existing tests pass: `make test`
- Follow the existing code style
- Update documentation as needed


## Acknowledgments

- [Telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) - The amazing fuzzy finder that this plugin extends
- Neovim community for the excellent plugin ecosystem

