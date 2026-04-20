-- Auto-load entry. Registers the `:Hugo` user command so it is always
-- available, even if the user has not called `require("hugo-cms").setup()`.

if vim.g.loaded_hugo_cms then
  return
end
vim.g.loaded_hugo_cms = true

require("hugo-cms").register_commands()
