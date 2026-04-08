--- @since 25.4.8

local M = {}

local DEFAULTS = {
	args = {},
	channel = "files",
	title = "Television",
}

local FILES_CHANNEL_NAME = "Yazi Files"
local FILES_CHANNEL_FILE = "yazi-files.toml"
local FILES_CHANNEL_BODY = [[
[metadata]
name = "Yazi Files"
description = "File and directory jumping for Yazi"
requirements = ["fd", "bat"]

[source]
command = "fd --hidden --follow --strip-cwd-prefix --exclude .git ."
output = "{}"

[preview]
command = "bat -n --color=always '{}'"
env = { BAT_THEME = "ansi" }
]]

local ZOXIDE_CHANNEL_NAME = "Yazi Zoxide"
local ZOXIDE_CHANNEL_FILE = "yazi-zoxide.toml"
local ZOXIDE_CHANNEL_BODY = [[
[metadata]
name = "Yazi Zoxide"
description = "Directory jumping for Yazi via zoxide"
requirements = ["zoxide"]

[source]
command = "zoxide query -l"
output = "{}"
]]

local function shell_quote(value)
	value = tostring(value)
	return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function television_config_dir()
	local xdg = os.getenv("XDG_CONFIG_HOME")
	if xdg and xdg ~= "" then
		return xdg .. "/television"
	end
	return os.getenv("HOME") .. "/.config/television"
end

local function ensure_channel(file_name, body)
	local cable_dir = television_config_dir() .. "/cable"
	local channel_file = cable_dir .. "/" .. file_name

	os.execute("mkdir -p " .. shell_quote(cable_dir))

	local file = io.open(channel_file, "w")
	if not file then
		return nil, "Cannot write channel file: " .. channel_file
	end

	file:write(body)
	file:close()
	return channel_file, nil
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

	if ctx.mode == "zoxide" then
		local _, channel_err = ensure_channel(ZOXIDE_CHANNEL_FILE, ZOXIDE_CHANNEL_BODY)
		if channel_err then
			return ya.notify {
				title = ctx.title,
				content = channel_err,
				timeout = 5,
				level = "error",
			}
		end
	elseif ctx.channel == FILES_CHANNEL_NAME then
		local _, channel_err = ensure_channel(FILES_CHANNEL_FILE, FILES_CHANNEL_BODY)
		if channel_err then
			return ya.notify {
				title = ctx.title,
				content = channel_err,
				timeout = 5,
				level = "error",
			}
		end
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

	if ctx.mode == "zoxide" then
		local target = output:gsub("[\r\n]+$", "")
		if target ~= "" then
			ya.emit("cd", { target, raw = true })
		end
		return
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
		tv_args[#tv_args + 1] = tostring(arg)
	end

	if ctx.mode == "zoxide" then
		tv_args[#tv_args + 1] = ZOXIDE_CHANNEL_NAME
	else
		tv_args[#tv_args + 1] = ctx.channel
		tv_args[#tv_args + 1] = tostring(ctx.cwd)
	end

	local wrapped = {}
	for _, arg in ipairs(tv_args) do
		wrapped[#wrapped + 1] = shell_quote(arg)
	end

	local child, err = Command("sh")
		:arg("-lc")
		:arg(table.concat(wrapped, " ") .. " < /dev/tty")
		:stdin(Command.NULL)
		:stdout(Command.PIPED)
		:stderr(Command.INHERIT)
		:spawn()

	if not child then
		return nil, Err("Failed to start `tv`, error: %s", err)
	end

	local output, wait_err = child:wait_with_output()
	if not output then
		return nil, Err("Cannot read `tv` output, error: %s", wait_err)
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
