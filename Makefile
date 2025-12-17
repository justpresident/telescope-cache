.PHONY: test test-watch install-deps clean

# Run all tests (SQLCipher FFI only - integration tests need telescope setup)
test:
	@echo "Running SQLCipher encryption tests..."
	vusted --verbose ./tests/sqlcipher_ffi_spec.lua

# Run all tests including integration (requires telescope installed)
test-all:
	@echo "Running all tests (including integration)..."
	vusted --verbose ./tests

# Run tests in watch mode (re-run on file changes)
test-watch:
	@echo "Running tests in watch mode..."
	vusted --watch ./tests

# Run specific test file
test-file:
	@echo "Running specific test file: $(FILE)"
	vusted --verbose ./tests/$(FILE)

# Install test dependencies
install-deps:
	@echo "Installing test dependencies..."
	@command -v luarocks >/dev/null 2>&1 || { echo "luarocks is required but not installed. Aborting." >&2; exit 1; }
	@command -v nvim >/dev/null 2>&1 || { echo "neovim is required but not installed. Aborting." >&2; exit 1; }
	@mkdir -p ~/.local/share/nvim/site/pack/deps/start/
	@echo "Installing plenary.nvim..."
	@if [ ! -d ~/.local/share/nvim/site/pack/deps/start/plenary.nvim ]; then \
		git clone --depth 1 https://github.com/nvim-lua/plenary.nvim \
		~/.local/share/nvim/site/pack/deps/start/plenary.nvim; \
	else \
		echo "plenary.nvim already installed"; \
	fi
	@echo "Installing telescope.nvim..."
	@if [ ! -d ~/.local/share/nvim/site/pack/deps/start/telescope.nvim ]; then \
		git clone --depth 1 https://github.com/nvim-telescope/telescope.nvim \
		~/.local/share/nvim/site/pack/deps/start/telescope.nvim; \
	else \
		echo "telescope.nvim already installed"; \
	fi
	@echo "Installing vusted..."
	sudo luarocks install vusted

# Verify SQLCipher is installed
check-sqlcipher:
	@echo "Checking for SQLCipher..."
	@ldconfig -p | grep sqlcipher || echo "SQLCipher not found. Install with: sudo apt install libsqlcipher0"
	@command -v sqlite3 >/dev/null 2>&1 && echo "sqlite3: OK" || echo "sqlite3 not found"

# Clean up test artifacts
clean:
	@echo "Cleaning up test files..."
	rm -rf /tmp/test_telescope_cache.db*
	rm -rf /tmp/test_encrypted.db*
	rm -rf /tmp/test_error.db*
	rm -rf /tmp/telescope_cache_test
	rm -rf /tmp/test_files

# Quick smoke test
smoke:
	@echo "Running smoke test..."
	@nvim --headless -u tests/minimal_init.lua \
		-c "lua assert(require('telescope-cache.sqlcipher_ffi'), 'SQLCipher FFI failed to load')" \
		-c "lua print('✓ SQLCipher FFI loaded successfully')" \
		-c "quit"
