--- @since 25.4.8

local M = {}

local DEFAULTS = {
	args = {},
	channel = "files",
	title = "Television",
}

local function shell_quote(value)
	value = tostring(value)
	return "'" .. value:gsub("'", "'\\''") .. "'"
end

local update_opts = ya.sync(function(state, opts)
	opts = type(opts) == "table" and opts or {}

	state.args = type(opts.args) == "table" and opts.args or DEFAULTS.args
	state.channel = type(opts.channel) == "string" and opts.channel ~= "" and opts.channel or DEFAULTS.channel
	state.title = type(opts.title) == "string" and opts.title ~= "" and opts.title or DEFAULTS.title
end)

local context = ya.sync(function(state, job_args)
	local args = {}
	local mode = "files"

	if type(job_args) == "table" and type(job_args[1]) == "string" and not job_args[1]:match("^%-") then
		mode = job_args[1]
		job_args = { table.unpack(job_args, 2) }
	end

	for _, arg in ipairs(state.args or DEFAULTS.args) do
		args[#args + 1] = tostring(arg)
	end

	for _, arg in ipairs(job_args or {}) do
		args[#args + 1] = tostring(arg)
	end

	return {
		args = args,
		channel = state.channel or DEFAULTS.channel,
		cwd = cx.active.current.cwd,
		mode = mode,
		title = state.title or DEFAULTS.title,
	}
end)

function M:setup(opts) update_opts(opts) end

function M:entry(job)
	ya.emit("escape", { visual = true })

	local ctx = context(job and type(job.args) == "table" and job.args or {})
	if ctx.mode == "files" and ctx.cwd.scheme.is_virtual then
		return ya.notify {
			title = ctx.title,
			content = "Not supported under virtual filesystems",
			timeout = 5,
			level = "warn",
		}
	end

	ya.emit("shell", {
		M.shell_command(ctx),
		block = true,
	})
end

---@param ctx { args: string[], channel: string, cwd: Url, mode: string, title: string }
---@return string
function M.shell_command(ctx)
	local tv_args = { "tv", "--source-output", "{}" }
	local cwd = tostring(ctx.cwd)

	for _, arg in ipairs(ctx.args) do
		tv_args[#tv_args + 1] = arg
	end

	if ctx.mode == "zoxide" then
		tv_args[#tv_args + 1] = "--source-command"
		tv_args[#tv_args + 1] = "zoxide query -l --exclude " .. shell_quote(cwd)
	else
		tv_args[#tv_args + 1] = ctx.channel
		tv_args[#tv_args + 1] = cwd
	end

	local shell_cmd = {}

	for _, arg in ipairs(tv_args) do
		shell_cmd[#shell_cmd + 1] = shell_quote(arg)
	end

	local lines = {
		"sel=$(" .. table.concat(shell_cmd, " ") .. ")",
		"rc=$?",
		'[ "$rc" -eq 130 ] && exit 0',
		'[ "$rc" -eq 0 ] || exit "$rc"',
		'[ -n "$sel" ] || exit 0',
	}

	if ctx.mode == "zoxide" then
		lines[#lines + 1] = 'ya emit cd "$sel"'
	else
		lines[#lines + 1] = "cwd=" .. shell_quote(cwd)
		lines[#lines + 1] = 'case "$sel" in'
		lines[#lines + 1] = '  /*) target="$sel" ;;'
		lines[#lines + 1] = '  *) target="$cwd/$sel" ;;'
		lines[#lines + 1] = "esac"
		lines[#lines + 1] = 'if [ -d "$target" ]; then'
		lines[#lines + 1] = '  ya emit cd "$target"'
		lines[#lines + 1] = "else"
		lines[#lines + 1] = '  ya emit reveal "$target"'
		lines[#lines + 1] = "fi"
	end

	return table.concat(lines, "\n")
end

return M
