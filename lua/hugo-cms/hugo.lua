-- Thin wrapper around the `hugo` CLI.
--
-- All invocations go through `vim.system` with a timeout; callers get a
-- normalised { ok, stdout, stderr, code } result.

local M = {}

local function run(args, opts)
  opts = opts or {}
  local result = vim.system(args, {
    text = true,
    cwd = opts.cwd,
    timeout = opts.timeout or 15000,
  }):wait()
  return {
    ok = result.code == 0,
    code = result.code,
    stdout = result.stdout or "",
    stderr = result.stderr or "",
  }
end

-- Run `hugo new` to create content. `path` is relative to `content/`.
-- When `kind` is nil, Hugo picks the archetype based on the path's section.
function M.new(site_path, path, kind)
  local args = { "hugo", "new" }
  if kind then
    table.insert(args, "--kind")
    table.insert(args, kind)
  end
  table.insert(args, path)
  return run(args, { cwd = site_path })
end

return M
