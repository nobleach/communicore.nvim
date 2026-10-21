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

---Checks whether a path exists, whether it is a file or a directory
---(`.git` is a plain file in worktrees and submodules). Pure Lua.
---@param path string
---@return boolean
local function exists(path)
  local f = io.open(path, "r")
  if f then
    f:close()
    return true
  end
  -- io.open fails on directories on some platforms; os.rename(a, a) only
  -- checks existence.
  return os.rename(path, path) == true
end

---Finds the project root of `dir`: the nearest ancestor (including `dir`
---itself) containing a `.git` entry. Returns nil when there is none.
---@param dir string absolute path to start from
---@return string|nil
function M.find_root(dir)
  dir = (dir:gsub("/+$", ""))
  while dir ~= "" do
    if exists(dir .. "/.git") then
      return dir
    end
    dir = dir:match("^(.*)/[^/]+$") or ""
  end
  return nil
end

---Loads environment variables from a single directory: `.env` first (shared
---defaults), then `.env.<name>` (when `name` is given), which overrides the
---shared ones.
---@param dir string directory to look in
---@param name string|nil environment name, e.g. "qa"
---@return table<string, string>
local function load_dir(dir, name)
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

---Loads environment variables for a `.http` file located in `dir`.
---Variables are read from the project root (nearest ancestor containing a
---`.git` entry) first, then from `dir` itself; within each directory
---`.env.<name>` overrides `.env`. Full precedence, lowest to highest:
---root/.env < root/.env.<name> < dir/.env < dir/.env.<name>.
---@param dir string directory of the .http file
---@param name string|nil environment name, e.g. "qa"
---@return table<string, string>
function M.load(dir, name)
  local vars = {}
  local root = M.find_root(dir)
  if root and root ~= dir then
    merge(vars, load_dir(root, name))
  end
  merge(vars, load_dir(dir, name))
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
