-- `:Hugo categories` — toggle the `categories` frontmatter list on the current file.

local M = {}

function M.run()
  require("hugo-cms.taxonomy").run("categories", "Categories")
end

return M
