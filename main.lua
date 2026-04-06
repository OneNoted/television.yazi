--- @since 25.4.8

local M = {}

local DEFAULTS = {
	args = {},
	channel = "files",
	title = "Television",
}

local update_opts = ya.sync(function(state, opts)
	opts = type(opts) == "table" and opts or {}

	state.args = type(opts.args) == "table" and opts.args or DEFAULTS.args
	state.channel = type(opts.channel) == "string" and opts.channel ~= "" and opts.channel or DEFAULTS.channel
	state.title = type(opts.title) == "string" and opts.title ~= "" and opts.title or DEFAULTS.title
end)

local context = ya.sync(function(state, job_args)
	local args = {}

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
		title = state.title or DEFAULTS.title,
	}
end)

function M:setup(opts) update_opts(opts) end

function M:entry(job)
	ya.emit("escape", { visual = true })

	local ctx = context(job and type(job.args) == "table" and job.args or {})
	if ctx.cwd.scheme.is_virtual then
		return ya.notify {
			title = ctx.title,
			content = "Not supported under virtual filesystems",
			timeout = 5,
			level = "warn",
		}
	end

	local permit = ui.hide()
	local output, err = M.run_with(ctx)
	permit:drop()

	if not output then
		return ya.notify {
			title = ctx.title,
			content = tostring(err),
			timeout = 5,
			level = "error",
		}
	end

	local urls = M.split_urls(ctx.cwd, output)
	if #urls == 1 then
		local cha = fs.cha(urls[1])
		ya.emit(cha and cha.is_dir and "cd" or "reveal", { urls[1], raw = true })
	elseif #urls > 1 then
		urls.state = "on"
		ya.emit("toggle_all", urls)
	end
end

---@param ctx { args: string[], channel: string, cwd: Url, title: string }
---@return string?, Error?
function M.run_with(ctx)
	local child, err = Command("tv")
		:args(ctx.args)
		:arg("--source-output")
		:arg("{}")
		:arg(ctx.channel)
		:arg(tostring(ctx.cwd))
		:stdin(Command.INHERIT)
		:stdout(Command.PIPED)
		:spawn()

	if not child then
		return nil, Err("Failed to start `tv`, error: %s", err)
	end

	local output
	output, err = child:wait_with_output()
	if not output then
		return nil, Err("Cannot read `tv` output, error: %s", err)
	elseif not output.status.success and output.status.code ~= 130 then
		return nil, Err("`tv` exited with error code %s", output.status.code)
	end

	return output.stdout, nil
end

---@param cwd Url
---@param output string
---@return Url[]
function M.split_urls(cwd, output)
	local urls = {}

	for line in output:gmatch("[^\r\n]+") do
		local url = Url(line)
		if url.is_absolute then
			urls[#urls + 1] = url
		else
			urls[#urls + 1] = cwd:join(url)
		end
	end

	return urls
end

return M
