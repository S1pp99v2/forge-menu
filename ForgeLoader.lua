-- 锻造菜单加载器：每次按最新提交拉脚本，避开 CDN 缓存。

local REPO = "S1pp99v2/forge-menu"
local FILE = "ForgeFarm.lua"
local CACHE_FILE = "ForgeFarm.cache.lua"

local function grab(name)
	local found
	pcall(function()
		found = ({
			getgenv = getgenv,
			loadstring = loadstring,
			writefile = writefile,
			readfile = readfile,
			isfile = isfile,
			request = request,
			http_request = http_request,
		})[name]
	end)
	if type(found) == "function" then
		return found
	end
	pcall(function()
		found = _G[name]
	end)
	if type(found) == "function" then
		return found
	end
	pcall(function()
		local genv = getgenv
		if type(genv) == "function" then
			found = genv()[name]
		end
	end)
	if type(found) == "function" then
		return found
	end
	return nil
end

local getgenvFn = grab("getgenv")
local loadstringFn = grab("loadstring")
local writefileFn = grab("writefile")
local readfileFn = grab("readfile")
local isfileFn = grab("isfile")

local env = _G
if type(getgenvFn) == "function" then
	pcall(function()
		local g = getgenvFn()
		if type(g) == "table" then
			env = g
		end
	end)
end

local function httpGet(url)
	local body
	pcall(function()
		body = game:HttpGet(url)
	end)
	if type(body) == "string" and body ~= "" then
		return body
	end
	local req = grab("request") or grab("http_request")
	if type(req) ~= "function" then
		pcall(function()
			req = syn and syn.request
		end)
	end
	if type(req) == "function" then
		local ok, res = pcall(req, { Url = url, Method = "GET" })
		if ok and type(res) == "table" and type(res.Body) == "string" then
			return res.Body
		end
	end
	return nil
end

local function latestSha()
	local body = httpGet("https://api.github.com/repos/" .. REPO .. "/commits/main")
	if type(body) ~= "string" then
		return nil
	end
	return string.match(body, '"sha"%s*:%s*"([a-f0-9]+)"')
end

local function urlList()
	local stamp = tostring(os.time())
	local sha = latestSha()
	local list = {}
	if type(sha) == "string" and #sha >= 7 then
		list[#list + 1] = "https://cdn.jsdelivr.net/gh/" .. REPO .. "@" .. sha .. "/" .. FILE
		print("[Forge] commit " .. string.sub(sha, 1, 7))
	end
	list[#list + 1] = "https://cdn.jsdelivr.net/gh/" .. REPO .. "@main/" .. FILE .. "?t=" .. stamp
	list[#list + 1] = "https://github.com/" .. REPO .. "/raw/main/" .. FILE .. "?t=" .. stamp
	list[#list + 1] = "https://raw.githubusercontent.com/" .. REPO .. "/main/" .. FILE .. "?t=" .. stamp
	return list
end

local function goodSource(src)
	return type(src) == "string" and #src > 80 and string.find(src, "ForgeFarm")
end

local function runSource(src, from)
	if type(loadstringFn) ~= "function" then
		warn("[Forge] 没有 loadstring")
		return
	end
	local fn, err = loadstringFn(src)
	if type(fn) ~= "function" then
		warn("[Forge] 编译失败: " .. tostring(err))
		return
	end
	print("[Forge] load from " .. from)
	fn()
end

local urls = urlList()
env._ForgeScriptUrls = urls
env._ForgeScriptUrl = urls[1]

local src = nil
for _, url in ipairs(urls) do
	src = httpGet(url)
	if goodSource(src) then
		env._ForgeScriptUrl = url
		print("[Forge] remote " .. url)
		break
	end
	src = nil
end

if goodSource(src) then
	if type(writefileFn) == "function" then
		pcall(writefileFn, CACHE_FILE, src)
	end
	runSource(src, "remote")
	return
end

print("[Forge] 远程失败，尝试本地缓存")
if type(isfileFn) == "function" and type(readfileFn) == "function" then
	local ok, cached = pcall(function()
		if isfileFn(CACHE_FILE) then
			return readfileFn(CACHE_FILE)
		end
		return nil
	end)
	if ok and goodSource(cached) then
		runSource(cached, "cache")
		return
	end
end

warn("[Forge] 远程和缓存都不可用")
