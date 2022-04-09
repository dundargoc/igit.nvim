local a = require("plenary.async")
local describe = a.tests.describe
local it = a.tests.it
local igit = require("ivcs.vcs.git")
local util = require("ivcs.test_util")
local git = util.git
local test_dir = require("ivcs.vcs.git.TestDir")()
local path = require("ivcs.libp.path")
local Set = require("ivcs.libp.datatype.Set")
local log = require("ivcs.log")

describe("Branch", function()
	igit.setup()
	local buffer_reload_waiter = util.BufReloadWaiter()

	-- todo: Use a.before_each after plenary#350
	before_each(a.util.will_block(function()
		local root = test_dir:refresh()
		vim.cmd(("edit %s"):format(path.path_join(root, test_dir.files[1])))
		igit.setup()
		igit.branch:open()
		buffer_reload_waiter:wait()
		util.setrow(1)
	end))

	describe("switch", function()
		it("Switches the branch", function()
			util.setrow(2)
			igit.branch:switch()
			assert.are.same(test_dir.path1[2], test_dir:current_branch())
			util.setrow(1)
			igit.branch:switch()
			assert.are.same(test_dir.path1[1], test_dir:current_branch())
		end)
	end)

	describe("parse_line", function()
		it("Parses the information of the lines", function()
			assert.are.same(igit.branch.parse_line(1), igit.branch:parse_line())
			assert.are.same({ branch = test_dir.path1[1], is_current = true }, igit.branch:parse_line())
			assert.are.same({ branch = test_dir.path1[2], is_current = false }, igit.branch:parse_line(2))
		end)
	end)

	describe("rename", function()
		it("Renames branches", function()
			igit.branch:rename()
			vim.api.nvim_buf_set_lines(0, 0, 1, true, { util.new_name(test_dir.path1[1]) })
			vim.api.nvim_buf_set_lines(0, 1, 2, true, { util.new_name(test_dir.path1[2]) })
			vim.cmd("write")
			buffer_reload_waiter:wait()
			assert.are.same(util.new_name(test_dir.path1[1]), test_dir:current_branch())
			assert.are.same({
				branch = util.new_name(test_dir.path1[1]),
				is_current = true,
			}, igit.branch:parse_line(1))
			assert.are.same({
				branch = util.new_name(test_dir.path1[2]),
				is_current = false,
			}, igit.branch:parse_line(2))
		end)
	end)

	describe("new_branch", function()
		it("Adds new branches", function()
			local ori_branches = Set(test_dir:branches())
			igit.branch:new_branch()
			local linenr = vim.fn.line(".") - 1
			local new_branch1 = util.new_name(test_dir.path1[1])
			local new_branch2 = util.new_name(test_dir.path1[2])
			local current_branch = test_dir:current_branch()
			vim.api.nvim_buf_set_lines(0, linenr, linenr, true, { new_branch1, new_branch2 })
			vim.cmd("write")
			buffer_reload_waiter:wait()
			assert.are.same(test_dir.path1[1], current_branch)
			local new_branches = Set(test_dir:branches())
			assert.are.same(Set.size(ori_branches) + 2, Set.size(new_branches))
			assert.is_truthy(Set.has(new_branches, new_branch1))
			assert.is_truthy(Set.has(new_branches, new_branch2))

			assert.are.same(
				util.check_output(git["rev-parse"](new_branch1)),
				util.check_output(git["rev-parse"](current_branch))
			)
			assert.are.same(
				util.check_output(git["rev-parse"](new_branch2)),
				util.check_output(git["rev-parse"](current_branch))
			)
		end)

		it("Hononrs mark", function()
			vim.api.nvim_win_set_cursor(0, { 2, 0 })
			igit.branch:mark()
			igit.branch:new_branch()
			local linenr = vim.fn.line(".") - 1
			local new_branch2 = util.new_name(test_dir.path1[2])
			vim.api.nvim_buf_set_lines(0, linenr, linenr, true, { new_branch2 })
			vim.cmd("write")
			buffer_reload_waiter:wait()
			assert.are.same(
				util.check_output(git["rev-parse"](new_branch2)),
				util.check_output(git["rev-parse"](new_branch2))
			)
		end)
	end)

	describe("force_delete_branch", function()
		it("Deletes branch in normal mode", function()
			local ori_branches = Set(test_dir:branches())
			igit.branch:force_delete_branch()
			assert.are.same(ori_branches, Set(test_dir:branches()))
			util.setrow(2)
			igit.branch:force_delete_branch()
			local new_branches = Set(test_dir:branches())
			assert.are.same(Set.size(ori_branches) - 1, Set.size(new_branches))
			assert.is_falsy(Set.has(new_branches, test_dir.path1[2]))
		end)

		it("Delete branches in visual mode", function()
			local ori_branches = Set(test_dir:branches())
			vim.cmd("normal! Vj")
			igit.branch:force_delete_branch()
			local new_branches = Set(test_dir:branches())
			assert.are.same(Set.size(ori_branches) - 1, Set.size(new_branches))
			assert.is_falsy(Set.has(new_branches, test_dir.path1[2]))
		end)
	end)
end)
