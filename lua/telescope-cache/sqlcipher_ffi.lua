-- SQLCipher FFI wrapper for Neovim
-- Provides lsqlite3-compatible API using LuaJIT FFI to load libsqlcipher directly

local ffi = require('ffi')

-- SQLite C API declarations
ffi.cdef[[
  typedef struct sqlite3 sqlite3;
  typedef struct sqlite3_stmt sqlite3_stmt;

  // Core functions
  int sqlite3_open(const char *filename, sqlite3 **ppDb);
  int sqlite3_close(sqlite3 *db);
  int sqlite3_exec(sqlite3 *db, const char *sql, void *callback, void *arg, char **errmsg);
  const char *sqlite3_errmsg(sqlite3 *db);
  void sqlite3_free(void *ptr);

  // Prepared statements
  int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int nByte, sqlite3_stmt **ppStmt, const char **pzTail);
  int sqlite3_bind_text(sqlite3_stmt *stmt, int idx, const char *val, int n, void(*destructor)(void*));
  int sqlite3_bind_int(sqlite3_stmt *stmt, int idx, int val);
  int sqlite3_bind_int64(sqlite3_stmt *stmt, int idx, int64_t val);
  int sqlite3_step(sqlite3_stmt *stmt);
  const unsigned char *sqlite3_column_text(sqlite3_stmt *stmt, int iCol);
  int sqlite3_column_int(sqlite3_stmt *stmt, int iCol);
  int64_t sqlite3_column_int64(sqlite3_stmt *stmt, int iCol);
  int sqlite3_column_type(sqlite3_stmt *stmt, int iCol);
  int sqlite3_finalize(sqlite3_stmt *stmt);
]]

-- SQLite constants
local SQLITE_OK = 0
local SQLITE_ROW = 100
local SQLITE_DONE = 101
local SQLITE_INTEGER = 1
local SQLITE_FLOAT = 2
local SQLITE_TEXT = 3
local SQLITE_BLOB = 4
local SQLITE_NULL = 5

-- SQLITE_TRANSIENT tells SQLite to make its own copy of the data
local SQLITE_TRANSIENT = ffi.cast("void(*)(void*)", -1)

-- Try to load libsqlcipher with multiple common names
local lib_names = {
  "libsqlcipher.so.0",
  "libsqlcipher.so.1",
  "libsqlcipher.so",
  "sqlcipher.so",
  "libsqlcipher.dylib",      -- macOS
  "libsqlcipher.0.dylib",    -- macOS versioned
}

local C = nil
for _, name in ipairs(lib_names) do
  local ok, lib = pcall(ffi.load, name)
  if ok then
    C = lib
    break
  end
end

if not C then
  return nil, "libsqlcipher not found. Install with: sudo apt install libsqlcipher0"
end

-- Module table
local M = {}

-- Statement wrapper class
local Statement = {}
Statement.__index = Statement

function Statement:bind(index, value)
  if not self._stmt then
    error("Statement already finalized")
  end

  local rc

  if type(value) == "number" then
    -- Check if it's an integer that fits in int32
    if math.floor(value) == value and value >= -2147483648 and value <= 2147483647 then
      rc = C.sqlite3_bind_int(self._stmt, index, value)
    else
      rc = C.sqlite3_bind_int64(self._stmt, index, value)
    end
  elseif type(value) == "string" then
    rc = C.sqlite3_bind_text(self._stmt, index, value, #value, SQLITE_TRANSIENT)
  elseif value == nil then
    -- For nil, we could bind NULL, but lsqlite3 might handle this differently
    -- For now, treat as error
    error("Cannot bind nil value")
  else
    error("Unsupported bind type: " .. type(value))
  end

  if rc ~= SQLITE_OK then
    return false
  end
  return true
end

function Statement:step()
  if not self._stmt then
    error("Statement already finalized")
  end

  local rc = C.sqlite3_step(self._stmt)
  return rc
end

function Statement:get_value(index)
  if not self._stmt then
    error("Statement already finalized")
  end

  local col_type = C.sqlite3_column_type(self._stmt, index)

  if col_type == SQLITE_INTEGER then
    return tonumber(C.sqlite3_column_int64(self._stmt, index))
  elseif col_type == SQLITE_TEXT then
    local text = C.sqlite3_column_text(self._stmt, index)
    if text ~= nil then
      return ffi.string(text)
    end
    return nil
  elseif col_type == SQLITE_FLOAT then
    -- We didn't declare sqlite3_column_double, but for compatibility
    -- we can still return integers as numbers
    return tonumber(C.sqlite3_column_int64(self._stmt, index))
  elseif col_type == SQLITE_NULL then
    return nil
  end

  return nil
end

function Statement:finalize()
  if self._stmt then
    C.sqlite3_finalize(self._stmt)
    self._stmt = nil
  end
end

-- Add __gc metamethod for automatic cleanup
Statement.__gc = Statement.finalize

-- Database wrapper class
local Database = {}
Database.__index = Database

function Database:exec(sql)
  if not self._db then
    return nil, "Database closed"
  end

  local errmsg = ffi.new("char*[1]")
  local rc = C.sqlite3_exec(self._db, sql, nil, nil, errmsg)

  if rc ~= SQLITE_OK then
    local err = "unknown error"
    if errmsg[0] ~= nil then
      err = ffi.string(errmsg[0])
      C.sqlite3_free(errmsg[0])
    end
    return rc, err
  end

  return 0  -- lsqlite3 returns 0 on success
end

function Database:prepare(sql)
  if not self._db then
    return nil, "Database closed"
  end

  local stmt = ffi.new("sqlite3_stmt*[1]")
  local rc = C.sqlite3_prepare_v2(self._db, sql, #sql, stmt, nil)

  if rc ~= SQLITE_OK then
    return nil, self:errmsg()
  end

  -- Return wrapped statement
  return setmetatable({
    _stmt = stmt[0],
    _db = self._db,
  }, Statement)
end

function Database:close()
  if self._db then
    C.sqlite3_close(self._db)
    self._db = nil
  end
end

function Database:errmsg()
  if not self._db then
    return "Database closed"
  end
  return ffi.string(C.sqlite3_errmsg(self._db))
end

-- Add __gc metamethod for automatic cleanup
Database.__gc = Database.close

-- Module functions

-- Open database with optional encryption key
-- Returns: database object on success, nil + error message on failure
function M.open(path, key)
  local db = ffi.new("sqlite3*[1]")

  -- Step 1: Open database
  local rc = C.sqlite3_open(path, db)
  if rc ~= SQLITE_OK then
    return nil, "Failed to open database: error code " .. rc
  end

  local db_ptr = db[0]

  -- Step 2: IMMEDIATELY set encryption key (before any other operations)
  if key and key ~= "" then
    -- Escape single quotes in key
    local escaped_key = key:gsub("'", "''")
    local key_sql = string.format("PRAGMA key = '%s';", escaped_key)

    local errmsg = ffi.new("char*[1]")
    rc = C.sqlite3_exec(db_ptr, key_sql, nil, nil, errmsg)

    if rc ~= SQLITE_OK then
      local err = "unknown error"
      if errmsg[0] ~= nil then
        err = ffi.string(errmsg[0])
        C.sqlite3_free(errmsg[0])
      end
      C.sqlite3_close(db_ptr)
      return nil, "Failed to set encryption key: " .. err
    end
  end

  -- Step 3: Apply hardening PRAGMAs
  local pragmas = {
    "PRAGMA cipher_page_size = 4096;",
    "PRAGMA kdf_iter = 256000;",
    "PRAGMA journal_mode = WAL;",
    "PRAGMA temp_store = MEMORY;",
  }

  for _, pragma in ipairs(pragmas) do
    rc = C.sqlite3_exec(db_ptr, pragma, nil, nil, nil)
    -- We don't fail on pragma errors, just log them if vim is available
    if rc ~= SQLITE_OK and vim then
      vim.notify("Warning: " .. pragma .. " failed", vim.log.levels.WARN)
    end
  end

  -- Return wrapped database handle
  return setmetatable({
    _db = db_ptr,
    _path = path,
  }, Database)
end

-- Export constants for compatibility
M.OK = SQLITE_OK
M.ROW = SQLITE_ROW
M.DONE = SQLITE_DONE

return M
