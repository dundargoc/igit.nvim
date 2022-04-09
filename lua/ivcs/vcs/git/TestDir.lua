local M = require("ivcs.libp.datatype.Class"):EXTEND()
local test_util = require("ivcs.test_util")
local git = test_util.git
local uv = vim.loop
local log = require("ivcs.log")

function M:init()
	self.files = { "f1", "f2" }
	self.non_existing_files = { "nf1", "nf2" }
	self.path1 = { "b1", "b2" }
	self.path2 = { "b3", "b4" }
end

function M:touch_non_existing_file(ind)
	test_util.jobrun(("touch " .. self.non_existing_files[ind]))
	return self.non_existing_files[ind]
end

function M:refresh()
	if self.root ~= nil then
		test_util.jobrun(("rm -rf %s"):format(self.root))
		test_util.jobrun(("cp -r %s_bak %s"):format(self.root, self.root))
		return self.root
	end
	self.root = self:create_dir()
	test_util.jobrun(("cp -r %s %s_bak"):format(self.root, self.root))
	return self.root
end

function M:current_branch()
	return vim.fn.trim(vim.fn.system(git.branch("--show-current")))
end

function M:branches()
	return test_util.check_output(git.branch())
end

function M:create_dir()
	local root = "/tmp/ivcs-test"
	test_util.jobrun(("rm -rf %s %s_bak"):format(root, root))
	assert(uv.fs_mkdir(root, 448), "Faile to create directory")
	local run = function(cmd)
		test_util.jobrun(cmd, { cwd = root })
	end
	run(("git init --initial-branch %s ."):format(self.path1[1]))
	run(('echo "line 1" > %s'):format(self.files[1]))
	run(git.add("."))
	run(git.commit('-m "first"'))

	run(git.checkout("-b " .. self.path1[2]))
	run(('echo "line 2" >> %s'):format(self.files[1]))
	run(git.add("."))
	run(git.commit('-m "second"'))

	run(git.checkout(self.path1[1]))

	run(git.checkout("-b " .. self.path2[1]))
	run(('echo "line 1" >> %s'):format(self.files[2]))
	run(git.add("."))
	run(git.commit('-m "path2 first"'))

	run(git.checkout("-b " .. self.path2[2]))
	run(('echo "line 2" >> %s'):format(self.files[2]))
	run(git.add("."))
	run(git.commit('-m "path2 second"'))

	run(('echo "line 2" >> %s'):format(self.files[2]))
	run(git.add("."))
	run(git.commit('-m "path2 third"'))

	run(git.checkout(self.path1[1]))
	return root
end

return M
