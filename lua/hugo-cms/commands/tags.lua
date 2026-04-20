-- `:Hugo tags` — toggle the `tags` frontmatter list on the current file.

local M = {}

function M.run()
  require("hugo-cms.taxonomy").run("tags", "Tags")
end

return M
