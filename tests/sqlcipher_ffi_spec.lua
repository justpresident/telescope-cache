-- tests/sqlcipher_ffi_spec.lua
-- Tests for SQLCipher FFI module

local ffi = require('ffi')

describe("SQLCipher FFI", function()
  local sqlcipher

  before_each(function()
    -- Reset module to get fresh instance
    package.loaded['telescope-cache.sqlcipher_ffi'] = nil
    sqlcipher = require('telescope-cache.sqlcipher_ffi')
  end)

  describe("module loading", function()
    it("should load successfully", function()
      assert.is_not_nil(sqlcipher)
    end)

    it("should export open function", function()
      assert.is_function(sqlcipher.open)
    end)

    it("should export constants", function()
      assert.is_number(sqlcipher.OK)
      assert.is_number(sqlcipher.ROW)
      assert.is_number(sqlcipher.DONE)
      assert.equals(0, sqlcipher.OK)
      assert.equals(100, sqlcipher.ROW)
      assert.equals(101, sqlcipher.DONE)
    end)
  end)

  describe("database operations", function()
    local test_db_path = "/tmp/test_telescope_cache.db"

    before_each(function()
      -- Clean up any existing test database
      os.remove(test_db_path)
      os.remove(test_db_path .. "-wal")
      os.remove(test_db_path .. "-shm")
    end)

    after_each(function()
      -- Clean up test database
      os.remove(test_db_path)
      os.remove(test_db_path .. "-wal")
      os.remove(test_db_path .. "-shm")
    end)

    it("should create encrypted database with password", function()
      local db, err = sqlcipher.open(test_db_path, "test_password_123")
      assert.is_not_nil(db, err)
      assert.is_table(db)
      db:close()
    end)

    it("should create unencrypted database without password", function()
      local db, err = sqlcipher.open(test_db_path, nil)
      assert.is_not_nil(db, err)
      assert.is_table(db)
      db:close()
    end)

    it("should execute SQL statements", function()
      local db = sqlcipher.open(test_db_path, "test_password_123")

      local result, err = db:exec("CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT);")
      assert.equals(0, result, err)

      db:close()
    end)

    it("should prepare and execute statements", function()
      local db = sqlcipher.open(test_db_path, "test_password_123")

      -- Create table
      db:exec("CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT);")

      -- Insert data
      local stmt = db:prepare("INSERT INTO test (value) VALUES (?)")
      assert.is_not_nil(stmt)
      stmt:bind(1, "hello")
      local rc = stmt:step()
      assert.is_true(rc == sqlcipher.DONE or rc == sqlcipher.OK)
      stmt:finalize()

      -- Query data
      local stmt2 = db:prepare("SELECT value FROM test WHERE id = 1")
      assert.is_not_nil(stmt2)
      rc = stmt2:step()
      assert.equals(sqlcipher.ROW, rc)
      local value = stmt2:get_value(0)
      assert.equals("hello", value)
      stmt2:finalize()

      db:close()
    end)

    it("should fail to open encrypted database with wrong password", function()
      -- Create database with password
      local db1 = sqlcipher.open(test_db_path, "correct_password")
      db1:exec("CREATE TABLE test (id INTEGER);")
      db1:close()

      -- Try to open with wrong password
      local db2, err = sqlcipher.open(test_db_path, "wrong_password")

      -- Database opens, but operations should fail
      if db2 then
        local result = db2:exec("SELECT * FROM test")
        -- Should fail because password is wrong
        assert.is_not_equal(0, result)
        db2:close()
      end
    end)

    it("should properly escape quotes in password", function()
      local tricky_password = "pass'word\"with'quotes"
      local db = sqlcipher.open(test_db_path, tricky_password)
      assert.is_not_nil(db)

      local result = db:exec("CREATE TABLE test (id INTEGER);")
      assert.equals(0, result)

      db:close()
    end)

    it("should handle integer binding", function()
      local db = sqlcipher.open(test_db_path, "test_password")
      db:exec("CREATE TABLE test (id INTEGER, value INTEGER);")

      local stmt = db:prepare("INSERT INTO test (id, value) VALUES (?, ?)")
      stmt:bind(1, 42)
      stmt:bind(2, 999)
      stmt:step()
      stmt:finalize()

      -- Verify
      local stmt2 = db:prepare("SELECT value FROM test WHERE id = 42")
      stmt2:step()
      local value = stmt2:get_value(0)
      assert.equals(999, value)
      stmt2:finalize()

      db:close()
    end)

    it("should handle large integers (int64)", function()
      local db = sqlcipher.open(test_db_path, "test_password")
      db:exec("CREATE TABLE test (big_num INTEGER);")

      local large_num = 9007199254740991 -- Max safe integer in Lua
      local stmt = db:prepare("INSERT INTO test (big_num) VALUES (?)")
      stmt:bind(1, large_num)
      stmt:step()
      stmt:finalize()

      -- Verify
      local stmt2 = db:prepare("SELECT big_num FROM test")
      stmt2:step()
      local value = stmt2:get_value(0)
      assert.equals(large_num, value)
      stmt2:finalize()

      db:close()
    end)
  end)

  describe("encryption verification", function()
    local test_db_path = "/tmp/test_encrypted.db"

    before_each(function()
      os.remove(test_db_path)
      os.remove(test_db_path .. "-wal")
      os.remove(test_db_path .. "-shm")
    end)

    after_each(function()
      os.remove(test_db_path)
      os.remove(test_db_path .. "-wal")
      os.remove(test_db_path .. "-shm")
    end)

    it("should create encrypted database file", function()
      local db = sqlcipher.open(test_db_path, "encryption_password")
      db:exec("CREATE TABLE test (data TEXT);")
      db:exec("INSERT INTO test (data) VALUES ('sensitive_data');")
      db:close()

      -- Read raw file bytes
      local file = io.open(test_db_path, "rb")
      assert.is_not_nil(file)
      local header = file:read(16)
      file:close()

      -- Encrypted database should NOT start with "SQLite format 3"
      assert.is_not_equal("SQLite format 3", header:sub(1, 15))
    end)

    it("unencrypted database should have SQLite header", function()
      local db = sqlcipher.open(test_db_path, nil)
      db:exec("CREATE TABLE test (data TEXT);")
      db:close()

      -- Read raw file bytes
      local file = io.open(test_db_path, "rb")
      assert.is_not_nil(file)
      local header = file:read(16)
      file:close()

      -- Unencrypted database SHOULD start with "SQLite format 3"
      assert.equals("SQLite format 3", header:sub(1, 15))
    end)
  end)

  describe("error handling", function()
    it("should return error for invalid path", function()
      local db, err = sqlcipher.open("/invalid/path/that/does/not/exist/db.sqlite", "password")
      assert.is_nil(db)
      assert.is_string(err)
    end)

    it("should handle failed prepare", function()
      local db = sqlcipher.open("/tmp/test_error.db", "password")

      -- Try to prepare invalid SQL
      local stmt, err = db:prepare("INVALID SQL SYNTAX")
      assert.is_nil(stmt)
      assert.is_string(err)

      db:close()
      os.remove("/tmp/test_error.db")
    end)
  end)
end)
