local navigate = require("communicore.navigate")

local SPEC_CONTENT = {
  "@host = example.com",
  "",
  "### First",
  "GET http://{{host}}/one",
  "Accept: application/json",
  "",
  "### Second",
  "POST http://{{host}}/two",
  "",
  '{"a": 1}',
  "",
  "### Third",
  "PUT http://{{host}}/three",
}

---Runs `fn` with tree-sitter stubbed out, forcing the internal-parser fallback.
local function with_fallback(fn)
  local orig = vim.treesitter.get_parser
  vim.treesitter.get_parser = function()
    error("no parser for 'http' language")
  end
  local ok, err = pcall(fn)
  vim.treesitter.get_parser = orig
  if not ok then
    error(err, 2)
  end
end

---@param lines string[]
local function open_buffer(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "http"
  return buf
end

local function cursor_line()
  return vim.api.nvim_win_get_cursor(0)[1]
end

describe("navigate", function()
  after_each(function()
    vim.api.nvim_buf_delete(0, { force = true })
  end)

  -- The same behavior specs run against the tree-sitter backend and,
  -- with tree-sitter stubbed out, against the internal-parser fallback.
  for _, backend in ipairs({ "treesitter", "fallback" }) do
    local function run(fn)
      if backend == "fallback" then
        with_fallback(fn)
      else
        fn()
      end
    end

    describe("(" .. backend .. " backend)", function()
      it("jumps to the next request start after the cursor", function()
        run(function()
          open_buffer(SPEC_CONTENT)
          vim.api.nvim_win_set_cursor(0, { 1, 0 })
          navigate.next_request()
          assert.are.equal(4, cursor_line())

          navigate.next_request()
          assert.are.equal(8, cursor_line())

          navigate.next_request()
          assert.are.equal(13, cursor_line())
        end)
      end)

      it("jumps to the previous request start before the cursor", function()
        run(function()
          open_buffer(SPEC_CONTENT)
          vim.api.nvim_win_set_cursor(0, { 13, 0 })
          navigate.prev_request()
          assert.are.equal(8, cursor_line())

          navigate.prev_request()
          assert.are.equal(4, cursor_line())
        end)
      end)

      it("jumps to the start of the current request when inside its block", function()
        run(function()
          open_buffer(SPEC_CONTENT)
          vim.api.nvim_win_set_cursor(0, { 10, 0 }) -- inside the second body
          navigate.prev_request()
          assert.are.equal(8, cursor_line())
        end)
      end)

      it("skips comments and separators between requests", function()
        run(function()
          open_buffer(SPEC_CONTENT)
          vim.api.nvim_win_set_cursor(0, { 6, 0 }) -- blank line before ### Second
          navigate.next_request()
          assert.are.equal(8, cursor_line())

          vim.api.nvim_win_set_cursor(0, { 12, 0 }) -- ### Third separator
          navigate.prev_request()
          assert.are.equal(8, cursor_line())
        end)
      end)

      it("does not move past the last or before the first request", function()
        run(function()
          open_buffer(SPEC_CONTENT)
          vim.api.nvim_win_set_cursor(0, { 13, 0 })
          navigate.next_request()
          assert.are.equal(13, cursor_line())

          vim.api.nvim_win_set_cursor(0, { 4, 0 })
          navigate.prev_request()
          assert.are.equal(4, cursor_line())
        end)
      end)
    end)
  end

  it("does not move when the buffer has no requests", function()
    open_buffer({ "# just a comment", "", "@var = 1" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    navigate.next_request()
    assert.are.equal(1, cursor_line())
    navigate.prev_request()
    assert.are.equal(1, cursor_line())
  end)

  describe("_target_line", function()
    local lines = { 4, 8, 13 }

    it("finds the first line strictly after the cursor", function()
      assert.are.equal(4, navigate._target_line(lines, 1, 1))
      assert.are.equal(8, navigate._target_line(lines, 4, 1))
      assert.are.equal(8, navigate._target_line(lines, 6, 1))
      assert.are.equal(13, navigate._target_line(lines, 12, 1))
    end)

    it("finds the last line strictly before the cursor", function()
      assert.are.equal(8, navigate._target_line(lines, 13, -1))
      assert.are.equal(8, navigate._target_line(lines, 10, -1))
      assert.are.equal(4, navigate._target_line(lines, 8, -1))
    end)

    it("returns nil when there is no target", function()
      assert.is_nil(navigate._target_line(lines, 13, 1))
      assert.is_nil(navigate._target_line(lines, 4, -1))
      assert.is_nil(navigate._target_line({}, 1, 1))
    end)
  end)
end)
