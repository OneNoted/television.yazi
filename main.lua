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

local function strip_ansi(text)
	text = text:gsub("\27%[[0-9;?]*[%c ]*[@-~]", "")
	text = text:gsub("\27[@-_]", "")
	return text
end

local function parse_selection(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end

	local text = file:read("*a") or ""
	file:close()

	text = strip_ansi(text)

	local selected = nil
	for line in text:gmatch("[^\n]+") do
		local cleaned = line:gsub("\r", "")
		cleaned = cleaned:gsub("^%s*(.-)%s*$", "%1")
		if cleaned ~= "" and not cleaned:match("^Script started on ") and not cleaned:match("^Script done on ") then
			selected = cleaned
		end
	end

	return selected
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

---@param ctx { args: string[], channel: string, cwd: Url, mode: string, title: string }
---@return string?, Error?
function M.run_with(ctx)
	local tv_args = { "tv", "--source-output", "{}" }

	for _, arg in ipairs(ctx.args) do
		tv_args[#tv_args + 1] = arg
	end

	if ctx.mode == "zoxide" then
		tv_args[#tv_args + 1] = "--source-command"
		tv_args[#tv_args + 1] = "zoxide query -l"
	else
		tv_args[#tv_args + 1] = ctx.channel
		tv_args[#tv_args + 1] = tostring(ctx.cwd)
	end

	local transcript = os.tmpname()
	local script_cmd = { "script", "-q", "-e", "-c" }
	local shell_cmd = {}

	for _, arg in ipairs(tv_args) do
		shell_cmd[#shell_cmd + 1] = shell_quote(arg)
	end

	script_cmd[#script_cmd + 1] = table.concat(shell_cmd, " ")
	script_cmd[#script_cmd + 1] = transcript

	local child, err = Command(script_cmd[1])
		:args({ table.unpack(script_cmd, 2) })
		:stdin(Command.INHERIT)
		:stdout(Command.INHERIT)
		:stderr(Command.INHERIT)
		:spawn()

	if not child then
		os.remove(transcript)
		return nil, Err("Failed to start `tv`, error: %s", err)
	end

	local status
	status, err = child:wait()
	if not status then
		os.remove(transcript)
		return nil, Err("Cannot read `tv` output, error: %s", err)
	elseif not status.success and status.code ~= 130 then
		os.remove(transcript)
		return nil, Err("`tv` exited with error code %s", status.code)
	end

	local selected = parse_selection(transcript)
	os.remove(transcript)
	return selected or "", nil
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
