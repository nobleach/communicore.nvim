local environment = require("communicore.environment")

local function tmpdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

local function write_file(path, content)
  local f = assert(io.open(path, "w"))
  f:write(content)
  f:close()
end

describe("environment", function()
  describe("parse_dotenv", function()
    it("parses KEY=value pairs", function()
      local vars = environment.parse_dotenv("HOST=localhost:3000\nTOKEN=abc123")
      assert.are.equal("localhost:3000", vars.HOST)
      assert.are.equal("abc123", vars.TOKEN)
    end)

    it("ignores comments and blank lines", function()
      local vars = environment.parse_dotenv("# comment\n\nHOST=example.com\n   \n#TOKEN=ignored")
      assert.are.equal("example.com", vars.HOST)
      assert.is_nil(vars.TOKEN)
    end)

    it("supports the export prefix", function()
      local vars = environment.parse_dotenv("export HOST=example.com")
      assert.are.equal("example.com", vars.HOST)
    end)

    it("strips double quotes and expands \\n escapes", function()
      local vars = environment.parse_dotenv('GREETING="hello world"\nMULTI="a\\nb"')
      assert.are.equal("hello world", vars.GREETING)
      assert.are.equal("a\nb", vars.MULTI)
    end)

    it("strips single quotes literally", function()
      local vars = environment.parse_dotenv("GREETING='hello world'")
      assert.are.equal("hello world", vars.GREETING)
    end)

    it("supports empty values", function()
      local vars = environment.parse_dotenv("EMPTY=")
      assert.are.equal("", vars.EMPTY)
    end)

    it("trims whitespace around unquoted values", function()
      local vars = environment.parse_dotenv("HOST = example.com  ")
      assert.are.equal("example.com", vars.HOST)
    end)

    it("keeps dots and dashes in keys", function()
      local vars = environment.parse_dotenv("my.key-name=value")
      assert.are.equal("value", vars["my.key-name"])
    end)

    it("handles \\r\\n line endings", function()
      local vars = environment.parse_dotenv("HOST=example.com\r\n")
      assert.are.equal("example.com", vars.HOST)
    end)
  end)

  describe("load", function()
    it("returns an empty table when no .env files exist", function()
      local vars = environment.load(tmpdir(), "qa")
      assert.are.same({}, vars)
    end)

    it("loads .env as shared defaults", function()
      local dir = tmpdir()
      write_file(dir .. "/.env", "HOST=shared.example.com\nSHARED=yes")
      local vars = environment.load(dir, nil)
      assert.are.equal("shared.example.com", vars.HOST)
      assert.are.equal("yes", vars.SHARED)
    end)

    it("overlays .env.<name> over .env", function()
      local dir = tmpdir()
      write_file(dir .. "/.env", "HOST=shared.example.com\nSHARED=yes")
      write_file(dir .. "/.env.qa", "HOST=qa.example.com")
      local vars = environment.load(dir, "qa")
      assert.are.equal("qa.example.com", vars.HOST)
      assert.are.equal("yes", vars.SHARED)
    end)

    it("does not load .env.<name> for a different environment", function()
      local dir = tmpdir()
      write_file(dir .. "/.env", "HOST=shared.example.com")
      write_file(dir .. "/.env.qa", "HOST=qa.example.com")
      local vars = environment.load(dir, "prod")
      assert.are.equal("shared.example.com", vars.HOST)
    end)

    it("tolerates a missing shared .env", function()
      local dir = tmpdir()
      write_file(dir .. "/.env.qa", "HOST=qa.example.com")
      local vars = environment.load(dir, "qa")
      assert.are.equal("qa.example.com", vars.HOST)
    end)
  end)

  describe("resolve", function()
    it("lets file variables override environment variables", function()
      local vars = environment.resolve({ host = "env.example.com", token = "env-token" }, { host = "file.example.com" })
      assert.are.equal("file.example.com", vars.host)
      assert.are.equal("env-token", vars.token)
    end)

    it("tolerates nil inputs", function()
      assert.are.same({}, environment.resolve(nil, nil))
      assert.are.same({ a = "1" }, environment.resolve({ a = "1" }, nil))
      assert.are.same({ a = "1" }, environment.resolve(nil, { a = "1" }))
    end)
  end)

  describe("interpolation end-to-end", function()
    local parser = require("communicore.parser")
    local variables = require("communicore.variables")

    ---Mimics init.lua's run_request flow: parse, load env, resolve, substitute.
    ---@param http string
    ---@param dir string
    ---@param env_name string|nil
    ---@return communicore.Request
    local function resolve_request(http, dir, env_name)
      local req = parser.parse(http)[1]
      local env_vars = environment.load(dir, env_name)
      req.variables = environment.resolve(env_vars, req.variables)
      return variables.substitute_request(req)
    end

    it("interpolates a .env variable into a header", function()
      local dir = tmpdir()
      write_file(dir .. "/.env", "SOME_PASS=foo")
      local resolved = resolve_request("GET https://example.com\nAuthorization: Basic {{SOME_PASS}}", dir, nil)
      assert.are.equal("Basic foo", resolved.headers[1].value)
    end)

    it("interpolates .env variables into the url and body", function()
      local dir = tmpdir()
      write_file(dir .. "/.env", "HOST=api.example.com\nTOKEN=secret")
      local resolved = resolve_request(
        'POST https://{{HOST}}/login\nContent-Type: application/json\n\n{"token": "{{TOKEN}}"}',
        dir,
        nil
      )
      assert.are.equal("https://api.example.com/login", resolved.url)
      assert.are.equal('{"token": "secret"}', resolved.body)
    end)

    it("uses the selected environment's values over shared ones", function()
      local dir = tmpdir()
      write_file(dir .. "/.env", "SOME_PASS=shared")
      write_file(dir .. "/.env.qa", "SOME_PASS=qa-pass")
      local resolved = resolve_request("GET https://example.com\nAuthorization: Basic {{SOME_PASS}}", dir, "qa")
      assert.are.equal("Basic qa-pass", resolved.headers[1].value)
    end)
  end)
end)
