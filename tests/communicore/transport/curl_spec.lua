local curl = require("communicore.transport.curl")

--- Helper: find the index of a value in an argv list.
local function index_of(argv, value)
  for i, v in ipairs(argv) do
    if v == value then
      return i
    end
  end
end

describe("transport.curl", function()
  describe("build_command", function()
    it("builds a simple GET command", function()
      local argv = curl.build_command({
        method = "GET",
        url = "https://example.com/users",
        headers = {},
      })
      assert.are.equal("curl", argv[1])
      assert.are.equal("https://example.com/users", argv[#argv])
      assert.is_truthy(index_of(argv, "-X") or index_of(argv, "--request"))
    end)

    it("passes each header with -H", function()
      local argv = curl.build_command({
        method = "GET",
        url = "https://example.com",
        headers = {
          { name = "Accept", value = "application/json" },
          { name = "Authorization", value = "Bearer tok" },
        },
      })
      local seen = {}
      for i, v in ipairs(argv) do
        if v == "-H" then
          seen[argv[i + 1]] = true
        end
      end
      assert.is_true(seen["Accept: application/json"] or false)
      assert.is_true(seen["Authorization: Bearer tok"] or false)
    end)

    it("passes the body with --data-raw", function()
      local argv = curl.build_command({
        method = "POST",
        url = "https://example.com/users",
        headers = {},
        body = '{"name":"Jim"}',
      })
      local i = index_of(argv, "--data-raw")
      assert.is_truthy(i)
      assert.are.equal('{"name":"Jim"}', argv[i + 1])
    end)

    it("omits the body flag when there is no body", function()
      local argv = curl.build_command({
        method = "DELETE",
        url = "https://example.com/users/1",
        headers = {},
      })
      assert.is_nil(index_of(argv, "--data-raw"))
    end)

    it("maps HTTP/1.1 and HTTP/2 to curl flags", function()
      local argv = curl.build_command({
        method = "GET",
        url = "https://example.com",
        headers = {},
        http_version = "HTTP/1.1",
      })
      assert.is_truthy(index_of(argv, "--http1.1"))

      argv = curl.build_command({
        method = "GET",
        url = "https://example.com",
        headers = {},
        http_version = "HTTP/2",
      })
      assert.is_truthy(index_of(argv, "--http2"))
    end)
  end)

  describe("parse_response", function()
    it("parses status, headers and body", function()
      local raw = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nX-Req: 1\r\n\r\n{\"ok\":true}"
      local resp = curl.parse_response(raw)
      assert.are.equal(200, resp.status)
      assert.are.equal("application/json", resp.headers[1].value)
      assert.are.equal('{"ok":true}', resp.body)
    end)

    it("handles LF-only header separators", function()
      local raw = "HTTP/1.1 404 Not Found\nContent-Type: text/plain\n\nmissing"
      local resp = curl.parse_response(raw)
      assert.are.equal(404, resp.status)
      assert.are.equal("missing", resp.body)
    end)

    it("handles an empty body", function()
      local raw = "HTTP/1.1 204 No Content\r\n\r\n"
      local resp = curl.parse_response(raw)
      assert.are.equal(204, resp.status)
      assert.are.equal("", resp.body)
    end)
  end)
end)
