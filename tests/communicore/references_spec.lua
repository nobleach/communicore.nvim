local references = require("communicore.references")
local store = require("communicore.store")

describe("references", function()
  before_each(function()
    store.clear()
  end)

  describe("collect", function()
    it("finds request references in url, headers and body", function()
      local refs = references.collect({
        url = "https://example.com/{{other.response.body.$.id}}",
        headers = {
          { name = "Authorization", value = "Bearer {{login.response.body.$.token}}" },
          { name = "Accept", value = "application/json" },
        },
        body = '{"parent": "{{parent.request.body.*}}"}',
        variables = {},
      })
      assert.is_true(refs["other.response.body.$.id"] or false)
      assert.is_true(refs["login.response.body.$.token"] or false)
      assert.is_true(refs["parent.request.body.*"] or false)
    end)

    it("ignores plain variables", function()
      local refs = references.collect({
        url = "https://{{host}}/users",
        headers = {},
        variables = {},
      })
      assert.is_nil(next(refs))
    end)
  end)

  describe("resolve", function()
    before_each(function()
      store.save("login", {
        request = { body = '{"user":"admin"}', headers = { { name = "X-Req", value = "1" } } },
        response = {
          body = '{"token":"jwt-token-123","data":{"items":[{"id":7},{"id":8}]}}',
          headers = { { name = "Content-Type", value = "application/json" } },
        },
      })
    end)

    it("resolves a JSON body path (VS Code form)", function()
      assert.are.equal("jwt-token-123", references.resolve("login.response.body.$.token"))
    end)

    it("resolves a jq-style bare path", function()
      assert.are.equal("jwt-token-123", references.resolve("login.response.body.token"))
    end)

    it("resolves nested keys and 0-based array indices", function()
      assert.are.equal("7", references.resolve("login.response.body.$.data.items[0].id"))
      assert.are.equal("8", references.resolve("login.response.body.data.items[1].id"))
    end)

    it("resolves the whole body with *", function()
      local body = references.resolve("login.response.body.*")
      assert.is_truthy(body:find("jwt%-token%-123"))
    end)

    it("resolves response headers case-insensitively", function()
      assert.are.equal("application/json", references.resolve("login.response.headers.Content-Type"))
      assert.are.equal("application/json", references.resolve("login.response.headers.content-type"))
    end)

    it("resolves the original request body", function()
      assert.are.equal('{"user":"admin"}', references.resolve("login.request.body.*"))
    end)

    it("resolves original request headers", function()
      assert.are.equal("1", references.resolve("login.request.headers.x-req"))
    end)

    it("returns nil for unknown request names", function()
      assert.is_nil(references.resolve("unknown.response.body.$.token"))
    end)

    it("returns nil for missing keys", function()
      assert.is_nil(references.resolve("login.response.body.$.missing"))
    end)

    it("returns nil for a path into a non-JSON body", function()
      store.save("plain", { response = { body = "not json", headers = {} } })
      assert.is_nil(references.resolve("plain.response.body.$.token"))
      -- but the whole body is still available
      assert.are.equal("not json", references.resolve("plain.response.body.*"))
    end)
  end)
end)
