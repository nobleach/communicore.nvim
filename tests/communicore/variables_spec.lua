local variables = require("communicore.variables")

describe("variables", function()
  describe("substitute", function()
    it("replaces {{name}} placeholders", function()
      local out = variables.substitute("https://{{host}}/users", { host = "api.example.com" })
      assert.are.equal("https://api.example.com/users", out)
    end)

    it("replaces multiple placeholders in one string", function()
      local out = variables.substitute("https://{{host}}:{{port}}/{{version}}", {
        host = "api.example.com",
        port = "8080",
        version = "v2",
      })
      assert.are.equal("https://api.example.com:8080/v2", out)
    end)

    it("resolves variables that reference other variables", function()
      local out = variables.substitute("{{baseUrl}}/users", {
        host = "api.example.com",
        port = "8080",
        baseUrl = "https://{{host}}:{{port}}",
      })
      assert.are.equal("https://api.example.com:8080/users", out)
    end)

    it("leaves unknown variables untouched", function()
      local out = variables.substitute("https://{{unknown}}/x", {})
      assert.are.equal("https://{{unknown}}/x", out)
    end)

    it("trims whitespace inside the braces", function()
      local out = variables.substitute("{{ host }}", { host = "example.com" })
      assert.are.equal("example.com", out)
    end)

    it("does not loop forever on cyclic references", function()
      local out = variables.substitute("{{a}}", { a = "{{b}}", b = "{{a}}" })
      -- cycle detection: must terminate; unresolved placeholders may remain
      assert.is_string(out)
    end)

    it("returns non-string input unchanged", function()
      assert.is_nil(variables.substitute(nil, {}))
    end)
  end)

  describe("substitute_request", function()
    it("resolves url, headers and body", function()
      local req = {
        method = "POST",
        url = "https://{{host}}/users",
        headers = {
          { name = "Authorization", value = "Bearer {{token}}" },
          { name = "Content-Type", value = "application/json" },
        },
        body = '{"name": "{{name}}"}',
        variables = { host = "api.example.com", token = "secret", name = "Jim" },
      }
      local resolved = variables.substitute_request(req)
      assert.are.equal("https://api.example.com/users", resolved.url)
      assert.are.equal("Bearer secret", resolved.headers[1].value)
      assert.are.equal("application/json", resolved.headers[2].value)
      assert.are.equal('{"name": "Jim"}', resolved.body)
    end)

    it("does not mutate the original request", function()
      local req = {
        method = "GET",
        url = "https://{{host}}",
        headers = {},
        variables = { host = "example.com" },
      }
      variables.substitute_request(req)
      assert.are.equal("https://{{host}}", req.url)
    end)
  end)
end)
