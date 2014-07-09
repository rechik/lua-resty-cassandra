package.path = package.path .. ";spec/?.lua"
ngx = require("fake_ngx")
local cassandra = require("cassandra")

describe("cassandra", function()
  before_each(function()
    session = cassandra.new()
    session:set_timeout(1000)
    connected, err = session:connect("127.0.0.1", 9042)
    local res, err = pcall(session.execute, session, [[
      CREATE KEYSPACE lua_tests
      WITH REPLICATION = { 'class' : 'SimpleStrategy', 'replication_factor' : 3 }
    ]])
  end)

  it("should be possible to connect", function()
    assert.truthy(connected)
  end)

  it("should be queryable", function()
    local rows, err = session:execute("SELECT cql_version, native_protocol_version, release_version FROM system.local");
    assert.same(1, #rows)
    assert.same(rows[1].native_protocol_version, "2")
  end)

  it("should support prepared statements", function()
    local stmt, err = session:prepare("SELECT native_protocol_version FROM system.local");
    assert.truthy(stmt)
    local rows = session:execute(stmt)
    assert.same(1, #rows)
    assert.same(rows[1].native_protocol_version, "2")
  end)

  it("should catch errors", function()
    local ok, err = pcall(session.set_keyspace, session, "invalid_keyspace")
    assert.truthy(string.find(err, "Keyspace 'invalid_keyspace' does not exist"))
  end)

  it("should be possible to use a namespace", function()
    local ok, err = session:set_keyspace("lua_tests")
    assert.truthy(ok)
  end)

  describe("a table", function()
    before_each(function()
      session:set_keyspace("lua_tests")
      local res, err = session:execute("SELECT columnfamily_name FROM system.schema_columnfamilies WHERE keyspace_name='lua_tests' and columnfamily_name='users'")
      if #res > 0 then
        session:execute("DROP TABLE users")
      end
      table_created, err = session:execute([[
          CREATE TABLE users (
            user_id uuid PRIMARY KEY,
            name varchar,
            age int
          )
      ]])
    end)

    it("should be possible to be created", function()
      assert.same("lua_tests.users CREATED", table_created)
    end)

    it("should be possible to insert a row", function()
      local ok, err = session:execute([[
        INSERT INTO users (name, age, user_id)
        VALUES ('John O''Reilly', 42, 2644bada-852c-11e3-89fb-e0b9a54a6d93)
      ]])
      assert.truthy(ok)
    end)

    it("should support arguments", function()
      local ok, err = session:execute([[
        INSERT INTO users (name, age, user_id)
        VALUES (?, ?, ?)
      ]], {"Juarez S' Bochi", 31, {type="uuid", value="1144bada-852c-11e3-89fb-e0b9a54a6d11"}})
      local users, err = session:execute("SELECT name, age, user_id from users")
      assert.same(1, #users)
      local user = users[1]
      assert.same("Juarez S' Bochi", user.name)
      assert.same("1144bada-852c-11e3-89fb-e0b9a54a6d11", user.user_id)
      assert.same(31, user.age)
      assert.truthy(ok)
    end)
  end)
end)