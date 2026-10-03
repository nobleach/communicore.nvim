local parser = require("communicore.parser")

local function parse(content)
  return parser.parse(content)
end

describe("parser", function()
  describe("request line", function()
    it("parses a simple GET request", function()
      local requests = parse("GET https://example.com")
      assert.are.equal(1, #requests)
      local req = requests[1]
      assert.are.equal("GET", req.method)
      assert.are.equal("https://example.com", req.url)
      assert.is_nil(req.http_version)
      assert.is_nil(req.body)
    end)

    it("defaults the method to GET when omitted", function()
      local requests = parse("https://example.com/api/users")
      assert.are.equal(1, #requests)
      assert.are.equal("GET", requests[1].method)
      assert.are.equal("https://example.com/api/users", requests[1].url)
    end)

    it("parses POST, PUT, PATCH and DELETE methods", function()
      for _, method in ipairs({ "POST", "PUT", "PATCH", "DELETE" }) do
        local requests = parse(method .. " https://example.com/resource")
        assert.are.equal(1, #requests)
        assert.are.equal(method, requests[1].method)
      end
    end)

    it("parses other standard methods", function()
      for _, method in ipairs({ "HEAD", "OPTIONS", "CONNECT", "TRACE" }) do
        local requests = parse(method .. " https://example.com/")
        assert.are.equal(method, requests[1].method)
      end
    end)

    it("parses an optional HTTP version", function()
      local requests = parse("GET https://example.com HTTP/1.1")
      assert.are.equal("HTTP/1.1", requests[1].http_version)

      requests = parse("GET https://example.com HTTP/2")
      assert.are.equal("HTTP/2", requests[1].http_version)
    end)

    it("trims surrounding whitespace on the request line", function()
      local requests = parse("   GET   https://example.com   ")
      assert.are.equal("GET", requests[1].method)
      assert.are.equal("https://example.com", requests[1].url)
    end)

    it("keeps query strings intact", function()
      local requests = parse("GET https://example.com/search?q=hello world&page=2")
      assert.are.equal("https://example.com/search?q=hello world&page=2", requests[1].url)
    end)
  end)

  describe("multi-line URLs", function()
    it("appends indented continuation lines to the URL", function()
      local requests = parse(table.concat({
        "GET https://example.com/api",
        "  /users",
        "  ?page=2",
        "  &limit=10",
      }, "\n"))
      assert.are.equal(1, #requests)
      assert.are.equal("https://example.com/api/users?page=2&limit=10", requests[1].url)
    end)

    it("supports query parameters on lines starting with ? or &", function()
      local requests = parse(table.concat({
        "GET https://example.com/api/users",
        "?page=2",
        "&limit=10",
      }, "\n"))
      assert.are.equal("https://example.com/api/users?page=2&limit=10", requests[1].url)
    end)

    it("does not treat indented lines after a header as URL continuations", function()
      local requests = parse(table.concat({
        "GET https://example.com",
        "Accept: application/json",
        "  not-part-of-the-url",
      }, "\n"))
      assert.are.equal("https://example.com", requests[1].url)
    end)
  end)

  describe("headers", function()
    it("parses headers in Name: Value format", function()
      local requests = parse(table.concat({
        "GET https://example.com",
        "Accept: application/json",
        "Authorization: Bearer token123",
      }, "\n"))
      local headers = requests[1].headers
      assert.are.equal(2, #headers)
      assert.are.equal("Accept", headers[1].name)
      assert.are.equal("application/json", headers[1].value)
      assert.are.equal("Authorization", headers[2].name)
      assert.are.equal("Bearer token123", headers[2].value)
    end)

    it("tolerates missing or extra whitespace around the colon", function()
      local requests = parse(table.concat({
        "GET https://example.com",
        "Accept:application/json",
        "X-Custom :   spaced   ",
      }, "\n"))
      assert.are.equal("application/json", requests[1].headers[1].value)
      assert.are.equal("X-Custom", requests[1].headers[2].name)
      assert.are.equal("spaced", requests[1].headers[2].value)
    end)

    it("keeps colons inside header values", function()
      local requests = parse(table.concat({
        "GET https://example.com",
        "Authorization: Bearer abc:def",
      }, "\n"))
      assert.are.equal("Bearer abc:def", requests[1].headers[1].value)
    end)

    it("supports multi-line header values via indentation", function()
      local requests = parse(table.concat({
        "GET https://example.com",
        "X-Long-Header: first",
        "  second",
      }, "\n"))
      assert.are.equal("first second", requests[1].headers[1].value)
    end)

    it("preserves duplicate headers in order", function()
      local requests = parse(table.concat({
        "GET https://example.com",
        "X-Multi: one",
        "X-Multi: two",
      }, "\n"))
      assert.are.equal(2, #requests[1].headers)
      assert.are.equal("one", requests[1].headers[1].value)
      assert.are.equal("two", requests[1].headers[2].value)
    end)
  end)

  describe("body", function()
    it("parses a JSON body after a blank line", function()
      local requests = parse(table.concat({
        "POST https://example.com/users",
        "Content-Type: application/json",
        "",
        "{",
        '  "name": "John"',
        "}",
      }, "\n"))
      assert.are.equal('{\n  "name": "John"\n}', requests[1].body)
    end)

    it("preserves blank lines inside the body", function()
      local requests = parse(table.concat({
        "POST https://example.com/text",
        "Content-Type: text/plain",
        "",
        "line one",
        "",
        "line two",
      }, "\n"))
      assert.are.equal("line one\n\nline two", requests[1].body)
    end)

    it("strips trailing blank lines from the body", function()
      local requests = parse(table.concat({
        "POST https://example.com/text",
        "",
        "content",
        "",
        "",
      }, "\n"))
      assert.are.equal("content", requests[1].body)
    end)

    it("does not treat # lines inside the body as comments", function()
      local requests = parse(table.concat({
        "POST https://example.com/text",
        "Content-Type: text/plain",
        "",
        "# not a comment",
        "#!shebang-ish",
      }, "\n"))
      assert.are.equal("# not a comment\n#!shebang-ish", requests[1].body)
    end)

    it("has no body when none is given", function()
      local requests = parse(table.concat({
        "GET https://example.com",
        "Accept: application/json",
      }, "\n"))
      assert.is_nil(requests[1].body)
    end)

    it("joins urlencoded form body lines with &", function()
      local requests = parse(table.concat({
        "POST https://example.com/login",
        "Content-Type: application/x-www-form-urlencoded",
        "",
        "username=admin",
        "&password=secret",
        "&remember=true",
      }, "\n"))
      assert.are.equal("username=admin&password=secret&remember=true", requests[1].body)
    end)

    it("stops the body at a response handler line", function()
      local requests = parse(table.concat({
        "POST https://example.com/users",
        "Content-Type: application/json",
        "",
        '{"a": 1}',
        "> {%",
        "  client.global.set('x', 1);",
        "%}",
      }, "\n"))
      assert.are.equal('{"a": 1}', requests[1].body)
    end)
  end)

  describe("separators and comments", function()
    it("parses multiple requests separated by ###", function()
      local requests = parse(table.concat({
        "GET https://example.com/users/1",
        "###",
        "POST https://example.com/users",
        "Content-Type: application/json",
        "",
        '{"name": "New User"}',
        "###",
        "DELETE https://example.com/users/2",
      }, "\n"))
      assert.are.equal(3, #requests)
      assert.are.equal("GET", requests[1].method)
      assert.are.equal("POST", requests[2].method)
      assert.are.equal('{"name": "New User"}', requests[2].body)
      assert.are.equal("DELETE", requests[3].method)
    end)

    it("supports more than three # as a separator", function()
      local requests = parse(table.concat({
        "GET https://example.com/a",
        "#####",
        "GET https://example.com/b",
      }, "\n"))
      assert.are.equal(2, #requests)
    end)

    it("uses text after ### as the request title", function()
      local requests = parse(table.concat({
        "### Get all users",
        "GET https://example.com/users",
        "### Create a new user",
        "POST https://example.com/users",
      }, "\n"))
      assert.are.equal("Get all users", requests[1].name)
      assert.are.equal("Create a new user", requests[2].name)
    end)

    it("ignores # comment lines", function()
      local requests = parse(table.concat({
        "# This is a comment",
        "GET https://example.com",
        "# Another comment",
      }, "\n"))
      assert.are.equal(1, #requests)
      assert.are.equal("https://example.com", requests[1].url)
    end)

    it("ignores // comment lines", function()
      local requests = parse(table.concat({
        "// This is a comment",
        "GET https://example.com",
      }, "\n"))
      assert.are.equal(1, #requests)
    end)

    it("ignores comments between the request line and headers", function()
      local requests = parse(table.concat({
        "GET https://example.com",
        "# a comment",
        "// another comment",
        "Accept: application/json",
      }, "\n"))
      assert.are.equal(1, #requests[1].headers)
      assert.are.equal("Accept", requests[1].headers[1].name)
    end)

    it("does not mistake a single # line inside a block for a separator", function()
      local requests = parse(table.concat({
        "GET https://example.com",
        "# just a comment",
        "Accept: application/json",
      }, "\n"))
      assert.are.equal(1, #requests)
    end)
  end)

  describe("file variables", function()
    it("collects @variable definitions", function()
      local requests = parse(table.concat({
        "@host = api.example.com",
        "@port = 8080",
        "",
        "GET https://{{host}}:{{port}}/users",
      }, "\n"))
      assert.are.equal(1, #requests)
      assert.are.equal("api.example.com", requests[1].variables.host)
      assert.are.equal("8080", requests[1].variables.port)
      assert.are.equal("https://{{host}}:{{port}}/users", requests[1].url)
    end)

    it("scopes variables to requests declared after them", function()
      local requests = parse(table.concat({
        "GET https://example.com/first",
        "###",
        "@host = api.example.com",
        "GET https://{{host}}/second",
      }, "\n"))
      assert.is_nil(requests[1].variables.host)
      assert.are.equal("api.example.com", requests[2].variables.host)
    end)

    it("allows variables to be redefined for later requests", function()
      local requests = parse(table.concat({
        "@env = dev",
        "GET https://example.com/first",
        "###",
        "@env = prod",
        "GET https://example.com/second",
      }, "\n"))
      assert.are.equal("dev", requests[1].variables.env)
      assert.are.equal("prod", requests[2].variables.env)
    end)

    it("does not create requests from variable-only files", function()
      local requests = parse("@host = example.com\n@port = 8080")
      assert.are.equal(0, #requests)
    end)
  end)

  describe("source positions", function()
    it("tracks the line and end_line of each request", function()
      local requests = parse(table.concat({
        "# comment", -- 1
        "@host = example.com", -- 2
        "", -- 3
        "### First", -- 4
        "GET https://example.com/a", -- 5
        "Accept: application/json", -- 6
        "", -- 7
        "### Second", -- 8
        "POST https://example.com/b", -- 9
        "", -- 10
        "body line", -- 11
      }, "\n"))
      assert.are.equal(5, requests[1].line)
      assert.are.equal(7, requests[1].end_line)
      assert.are.equal(9, requests[2].line)
      assert.are.equal(11, requests[2].end_line)
    end)

    it("finds the request at a given cursor line", function()
      local requests = parse(table.concat({
        "GET https://example.com/a", -- 1
        "", -- 2
        "###", -- 3
        "POST https://example.com/b", -- 4
        "", -- 5
        "{}", -- 6
      }, "\n"))
      assert.are.equal("GET", parser.find_request_at(requests, 1).method)
      -- lines between requests map to the next request
      assert.are.equal("POST", parser.find_request_at(requests, 3).method)
      assert.are.equal("POST", parser.find_request_at(requests, 6).method)
      -- past the last request there is nothing
      assert.is_nil(parser.find_request_at(requests, 42))
    end)
  end)

  describe("edge cases", function()
    it("returns no requests for an empty file", function()
      assert.are.equal(0, #parse(""))
      assert.are.equal(0, #parse("\n\n\n"))
    end)

    it("returns no requests for a comments-only file", function()
      assert.are.equal(0, #parse("# hello\n// world"))
    end)

    it("ignores leading blank lines", function()
      local requests = parse("\n\nGET https://example.com")
      assert.are.equal(1, #requests)
      assert.are.equal(3, requests[1].line)
    end)

    it("handles \\r\\n line endings", function()
      local requests = parse("GET https://example.com\r\nAccept: application/json\r\n")
      assert.are.equal("https://example.com", requests[1].url)
      assert.are.equal("application/json", requests[1].headers[1].value)
    end)
  end)
end)
