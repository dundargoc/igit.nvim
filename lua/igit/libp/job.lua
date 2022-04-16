require("igit.libp.datatype.string_extension")
local M = require("igit.libp.datatype.Class"):EXTEND()
local a = require("plenary.async")
local List = require("igit.libp.datatype.List")
local log = require("igit.libp.log")

function M:init(opts)
	vim.validate({
		on_stdout = { opts.on_stdout, "function", true },
		stdout_buffer_size = { opts.stdout_buffer_size, "number", true },
		silent = { opts.silent, "boolean", true },
		cwd = { opts.cwd, "string", true },
		env = { opts.env, "table", true },
		detached = { opts.detached, "boolean", true },
	})

	opts.stdout_buffer_size = opts.stdout_buffer_size or 5000
	self.opts = opts
end

M.start = a.wrap(function(self, callback)
	local opts = self.opts
	local stdout_lines = { "" }
	local stderr_lines = ""

	local stdout = vim.loop.new_pipe(false)
	local stderr = vim.loop.new_pipe(false)

	local eof_has_new_line = false
	local on_stdout = function(_, data)
		if self.opts.on_stdout then
			if data == nil then
				return
			end

			eof_has_new_line = data:find("\n$")

			-- The last line in stdout_lines is always a "partial line":
			-- 1. At initialization, we initialized it to "".
			-- 2. For a real partial line (data not ending with "\n"), lines[-1] would be non-empty.
			-- 3. For a complete line (data ending with "\n"), lines[-1] would be "".
			local lines = data:split("\n")
			stdout_lines[#stdout_lines] = stdout_lines[#stdout_lines] .. lines[1]
			vim.list_extend(stdout_lines, lines, 2)

			if #stdout_lines > opts.stdout_buffer_size then
				local partial_line = table.remove(stdout_lines)
				opts.on_stdout(stdout_lines)
				stdout_lines = { partial_line }
			end
		end
	end

	local on_stderr = function(_, data)
		if data then
			stderr_lines = stderr_lines .. data
		end
	end

	local on_exit = function(exit_code, _)
		stdout:read_stop()
		stderr:read_stop()

		if not stdout:is_closing() then
			stdout:close()
		end
		if not stderr:is_closing() then
			stderr:close()
		end

		if exit_code ~= 0 then
			if not opts.silent and not self.terminated_by_client then
				vim.notify(("Error message from\n%s\n\n%s"):format(table.concat(opts.cmds, " "), stderr_lines))
			end
		elseif opts.on_stdout then
			if eof_has_new_line then
				opts.on_stdout(vim.list_slice(stdout_lines, 1, #stdout_lines - 1))
			else
				opts.on_stdout(stdout_lines)
			end

			if not opts.silent and #stderr_lines > 0 then
				vim.notify(stderr_lines)
			end
		end

		if callback then
			callback(exit_code)
		end
	end

	local cmd, args = opts.cmds[1], vim.list_slice(opts.cmds, 2, #opts.cmds)
	-- Remove quotes as spawn will quote each args.
	for i, arg in ipairs(args) do
		args[i] = arg:gsub('([^\\])"', "%1"):gsub("([^\\])'", "%1"):gsub('\\"', '"'):gsub("\\'", "'")
	end

	self.process, self.pid = vim.loop.spawn(
		cmd,
		{ stdio = { nil, stdout, stderr }, args = args, cwd = opts.cwd, detached = opts.detached, env = opts.env },
		vim.schedule_wrap(on_exit)
	)

	if type(self.pid) == "string" then
		stderr_lines = stderr_lines .. ("Command not found: %s"):format(cmd)
		vim.notify(stderr_lines)
		return -1
	else
		stdout:read_start(vim.schedule_wrap(on_stdout))
		stderr:read_start(vim.schedule_wrap(on_stderr))
	end
end, 2)

function M:kill(signal)
	signal = signal or 15
	self.process:kill(signal)
	self.terminated_by_client = true
end

function M:check_output(return_list)
	vim.validate({ return_list = { return_list, "boolean", true } })
	local stdout_lines = {}

	self.opts.on_stdout = function(lines)
		vim.list_extend(stdout_lines, lines)
	end

	local exit_code = self:start()
	if exit_code ~= 0 then
		stdout_lines = nil
	end

	if return_list then
		return List(stdout_lines)
	end
	return table.concat(stdout_lines, "\n")
end

M.start_all = a.wrap(function(cmds, opts, callback)
	a.util.run_all(
		List(cmds)
			:map(function(e)
				return a.wrap(function(cb)
					M(vim.tbl_extend("keep", { cmds = e }, opts or {})):start(cb)
				end, 1)
			end)
			:collect(),
		callback
	)
end, 3)

return M
