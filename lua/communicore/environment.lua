---Named environment support via dotenv files.
---Follows the dotenv-flow / Next.js / Vite convention: `.env` holds shared
---defaults and `.env.<name>` holds variables for the named environment,
---overriding the shared ones.
---Pure Lua (io only): no Neovim API dependencies.

local M = {}

---@param str string
---@return string
local function trim(str)
  return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end

---Parses dotenv-formatted content into a key/value table.
---Supports comments (#), the `export` prefix, single/double quoted values
---(\n is expanded in double quotes) and empty values.
---@param content string
---@return table<string, string>
function M.parse_dotenv(content)
  local vars = {}
  for line in (content .. "\n"):gmatch("(.-)\n") do
    line = trim((line:gsub("\r$", "")))
    if line ~= "" and not line:match("^#") then
      line = line:gsub("^export%s+", "")
      local key, value = line:match("^([%w_.%-]+)%s*=%s*(.-)%s*$")
      if key then
        local quoted = value:match('^"(.*)"$')
        if quoted then
          vars[key] = quoted:gsub("\\n", "\n")
        else
          quoted = value:match("^'(.*)'$")
          vars[key] = quoted or value
        end
      end
    end
  end
  return vars
end

---@param path string
---@return string|nil
local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

---@param base table<string, string>
---@param overlay table<string, string>|nil
---@return table<string, string>
local function merge(base, overlay)
  for k, v in pairs(overlay or {}) do
    base[k] = v
  end
  return base
end

---Loads environment variables from `dir`: `.env` first (shared defaults),
---then `.env.<name>` (when `name` is given), which overrides the shared ones.
---@param dir string directory to look in
---@param name string|nil environment name, e.g. "qa"
---@return table<string, string>
function M.load(dir, name)
  local vars = {}
  local shared = read_file(dir .. "/.env")
  if shared then
    merge(vars, M.parse_dotenv(shared))
  end
  if name and name ~= "" then
    local specific = read_file(dir .. "/.env." .. name)
    if specific then
      merge(vars, M.parse_dotenv(specific))
    end
  end
  return vars
end

---Merges environment variables with in-file @variables.
---File variables win, matching JetBrains/VS Code precedence.
---@param env_vars table<string, string>|nil
---@param file_vars table<string, string>|nil
---@return table<string, string>
function M.resolve(env_vars, file_vars)
  return merge(merge({}, env_vars), file_vars)
end

return M
