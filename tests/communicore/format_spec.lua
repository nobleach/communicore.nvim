local format = require("communicore.format")

describe("format", function()
  it("formats a flat object with two-space indent", function()
    local formatted = format.json('{"token":"abc123","expires_in":3600}')
    assert.are.equal(
      [[{
  "token": "abc123",
  "expires_in": 3600
}]],
      formatted
    )
  end)

  it("formats nested objects and arrays", function()
    local formatted = format.json('{"data":{"items":[{"id":1},{"id":2}],"count":2}}')
    assert.are.equal(
      [[{
  "data": {
    "items": [
      {
        "id": 1
      },
      {
        "id": 2
      }
    ],
    "count": 2
  }
}]],
      formatted
    )
  end)

  it("keeps empty containers on one line", function()
    assert.are.equal("{}", format.json("{}"))
    assert.are.equal("[]", format.json("[]"))
    assert.are.equal(
      [[{
  "a": {},
  "b": []
}]],
      format.json('{"a":{},"b":[]}')
    )
  end)

  it("preserves key order", function()
    local formatted = format.json('{"z":1,"a":2,"m":3}')
    assert.are.equal(
      [[{
  "z": 1,
  "a": 2,
  "m": 3
}]],
      formatted
    )
  end)

  it("preserves number lexemes exactly", function()
    local formatted = format.json('[1e3, 2.50, 123456789012345678901, -0.5E-2]')
    assert.are.equal(
      [==[[
  1e3,
  2.50,
  123456789012345678901,
  -0.5E-2
]]==],
      formatted
    )
  end)

  it("does not touch string contents", function()
    local formatted = format.json([[{"a":"x: y, {z}","b":"quote \" backslash \\","c":"tab\there"}]])
    assert.are.equal(
      [[{
  "a": "x: y, {z}",
  "b": "quote \" backslash \\",
  "c": "tab\there"
}]],
      formatted
    )
  end)

  it("formats top-level scalars", function()
    assert.are.equal("42", format.json("42"))
    assert.are.equal('"hi"', format.json(' "hi" '))
    assert.are.equal("true", format.json("true"))
    assert.are.equal("null", format.json("null"))
  end)

  it("ignores insignificant whitespace in the input", function()
    local formatted = format.json('{  "a" : 1 ,\n\t"b" : [ 1 , 2 ] }')
    assert.are.equal(
      [[{
  "a": 1,
  "b": [
    1,
    2
  ]
}]],
      formatted
    )
  end)

  it("returns nil and an error for invalid JSON", function()
    local formatted, err = format.json('{"a":}')
    assert.is_nil(formatted)
    assert.is_string(err)
  end)

  it("returns nil and an error for empty input", function()
    local formatted, err = format.json("")
    assert.is_nil(formatted)
    assert.is_string(err)
  end)

  it("supports a custom indent unit", function()
    assert.are.equal(
      '{\n\t"a": 1\n}',
      format.json('{"a":1}', "\t")
    )
  end)
end)
