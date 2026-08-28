--!nocheck
--!nolint
local FORGE_VERSION = "1.1.14"
print("[Forge] boot " .. FORGE_VERSION)

local function grab(name)
	local found
	pcall(function()
		found = ({
			getgenv = getgenv,
			getfenv = getfenv,
			loadstring = loadstring,
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
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
if not player then
	local t0 = os.clock()
	while not Players.LocalPlayer and os.clock() - t0 < 3 do
		task.wait(0.05)
	end
	player = Players.LocalPlayer
end
if not player then
	warn("[Forge] no player")
	return
end

local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 3)
if not playerGui then
	warn("[Forge] no PlayerGui")
	return
end

local GUI_NAME = "ForgeFarmClient"
local GUI_TAG = "ForgeFarm"

local env = _G
if type(getgenvFn) == "function" then
	pcall(function()
		local g = getgenvFn()
		if type(g) == "table" then
			env = g
		end
	end)
end
env._ForgeVersion = FORGE_VERSION
pcall(function()
	if type(env._ForgeShutdown) == "function" then
		env._ForgeShutdown()
	end
end)
env._ForgeShutdown = nil
env._ForgeFarmGen = (tonumber(env._ForgeFarmGen) or 0) + 1
local myGen = tonumber(env._ForgeFarmGen) or 1
local alive = true

local function stillMine()
	return alive and env._ForgeFarmGen == myGen
end

local function wipeOld(container)
	if not container then
		return
	end
	for _, gui in ipairs(container:GetChildren()) do
		local tagged = false
		pcall(function()
			tagged = gui:GetAttribute(GUI_TAG) == true
		end)
		if tagged or gui.Name == GUI_NAME then
			pcall(function()
				gui:Destroy()
			end)
		end
	end
end
wipeOld(playerGui)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = GUI_NAME
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 2147483647
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Enabled = true
pcall(function()
	screenGui:SetAttribute(GUI_TAG, true)
end)
screenGui.Parent = playerGui
if screenGui.Parent == nil then
	warn("[Forge] gui parent failed")
	return
end
print("[Forge] gui")

local C = {
	bg = Color3.fromRGB(16, 20, 26),
	panel = Color3.fromRGB(22, 28, 36),
	btn = Color3.fromRGB(32, 40, 52),
	on = Color3.fromRGB(36, 72, 52),
	off = Color3.fromRGB(32, 40, 52),
	text = Color3.fromRGB(230, 234, 240),
	dim = Color3.fromRGB(140, 150, 164),
	line = Color3.fromRGB(48, 58, 72),
	tab = Color3.fromRGB(40, 56, 72),
	exit = Color3.fromRGB(72, 28, 32),
}

local state = {
	mineOn = false,
	atkOn = false,
	huntOn = false,
	potOn = false,
	sellOn = false,
	sellDesc = true,
	sellOwned = false,
	sellWait = 60,
	uiOn = true,
	page = "auto",
	guideStage = "all",
	openGuide = nil,
	flySpeed = 70,
	standDist = 4.5,
	standPitch = 0,
	huntHeight = 12,
	huntSingle = false,
	selected = {},
	huntSel = {},
	potSel = {},
	sellSel = {},
	openMap = nil,
	openSell = "ore",
	status = "待机",
	winW = 920,
	winH = 400,
	winX = 22,
	winY = 88,
}

local Flow = {
	target = nil,
	hoverOn = false,
	savedPlat = false,
	savedRot = true,
	arriveAt = 0,
	holding = false,
	clipSaved = nil,
	camZoom = 14,
	occlusionOn = false,
	savedOcclusion = nil,
	conns = {},
	checks = {},
	huntChecks = {},
	potChecks = {},
	sellChecks = {},
	mapHeads = {},
	sellHeads = {},
	swingBusy = false,
	window = nil,
	huntTarget = nil,
	buyName = nil,
	sellFly = nil,
	sellTalk = false,
	nextSellAt = 0,
	lastDrink = {},
	lastSell = 0,
	sellItems = {},
}

local CFG_FILE = "ForgeFarm.json"
local writefileFn = grab("writefile")
local readfileFn = grab("readfile")
local isfileFn = grab("isfile")
pcall(function()
	if type(writefile) == "function" then
		writefileFn = writefile
	end
	if type(readfile) == "function" then
		readfileFn = readfile
	end
	if type(isfile) == "function" then
		isfileFn = isfile
	end
end)

function Flow.applyCfg(cfg)
	if type(cfg) ~= "table" then
		return
	end
	if tonumber(cfg.flySpeed) then
		state.flySpeed = math.clamp(tonumber(cfg.flySpeed), 8, 160)
	end
	if tonumber(cfg.standDist) then
		state.standDist = math.clamp(tonumber(cfg.standDist), 2, 24)
	end
	if tonumber(cfg.standPitch) then
		state.standPitch = math.clamp(tonumber(cfg.standPitch), -90, 90)
	end
	if cfg.atkOn == true then
		state.atkOn = true
	end
	if tonumber(cfg.huntHeight) then
		state.huntHeight = math.clamp(tonumber(cfg.huntHeight), 8, 28)
	end
	if tonumber(cfg.sellWait) then
		state.sellWait = math.clamp(math.floor(tonumber(cfg.sellWait)), 10, 600)
	end
	if cfg.huntSingle == true then
		state.huntSingle = true
	end
	if type(cfg.huntSel) == "table" then
		state.huntSel = {}
		for _, name in ipairs(cfg.huntSel) do
			if type(name) == "string" and name ~= "" then
				state.huntSel[name] = true
			end
		end
	end
	if type(cfg.potSel) == "table" then
		state.potSel = {}
		for _, name in ipairs(cfg.potSel) do
			if type(name) == "string" and name ~= "" then
				state.potSel[name] = true
			end
		end
	end
	if type(cfg.sellSel) == "table" then
		state.sellSel = {}
		for _, name in ipairs(cfg.sellSel) do
			if type(name) == "string" and name ~= "" then
				state.sellSel[name] = true
			end
		end
	end
	if cfg.sellDesc == false then
		state.sellDesc = false
	end
	if cfg.sellOwned == true then
		state.sellOwned = true
	end
	if tonumber(cfg.winW) and tonumber(cfg.winH) then
		state.winW = math.clamp(tonumber(cfg.winW), 640, 1600)
		state.winH = math.clamp(tonumber(cfg.winH), 280, 1000)
	end
	if tonumber(cfg.winX) then
		state.winX = tonumber(cfg.winX)
	end
	if tonumber(cfg.winY) then
		state.winY = tonumber(cfg.winY)
	end
	if type(cfg.selected) == "table" then
		state.selected = {}
		for _, name in ipairs(cfg.selected) do
			if type(name) == "string" and name ~= "" then
				state.selected[name] = true
			end
		end
	end
end

function Flow.loadCfg()
	if type(readfileFn) ~= "function" then
		return false
	end
	local exists = true
	if type(isfileFn) == "function" then
		local ok, yes = pcall(isfileFn, CFG_FILE)
		exists = ok and yes == true
	end
	if not exists then
		return false
	end
	local ok, raw = pcall(readfileFn, CFG_FILE)
	if not (ok and type(raw) == "string" and raw ~= "") then
		return false
	end
	local ok2, cfg = pcall(function()
		return HttpService:JSONDecode(raw)
	end)
	if not (ok2 and type(cfg) == "table") then
		return false
	end
	Flow.applyCfg(cfg)
	return true
end

function Flow.dumpCfg()
	local sel = {}
	for name, on in pairs(state.selected) do
		if on then
			sel[#sel + 1] = name
		end
	end
	table.sort(sel)
	local huntSel = {}
	for name, on in pairs(state.huntSel) do
		if on then
			huntSel[#huntSel + 1] = name
		end
	end
	table.sort(huntSel)
	local potSel = {}
	for name, on in pairs(state.potSel) do
		if on then
			potSel[#potSel + 1] = name
		end
	end
	table.sort(potSel)
	local sellSel = {}
	for name, on in pairs(state.sellSel) do
		if on then
			sellSel[#sellSel + 1] = name
		end
	end
	table.sort(sellSel)
	local win = Flow.window
	return {
		flySpeed = state.flySpeed,
		standDist = state.standDist,
		standPitch = state.standPitch,
		atkOn = state.atkOn == true,
		huntHeight = state.huntHeight,
		huntSingle = state.huntSingle == true,
		selected = sel,
		huntSel = huntSel,
		potSel = potSel,
		sellSel = sellSel,
		sellDesc = state.sellDesc == true,
		sellOwned = state.sellOwned == true,
		sellWait = state.sellWait,
		winW = win and win.AbsoluteSize.X or state.winW,
		winH = win and win.AbsoluteSize.Y or state.winH,
		winX = win and win.AbsolutePosition.X or state.winX,
		winY = win and win.AbsolutePosition.Y or state.winY,
	}
end

local loadstringFn = grab("loadstring")
pcall(function()
	if type(loadstring) == "function" then
		loadstringFn = loadstring
	end
end)

function Flow.httpGet(url)
	if type(url) ~= "string" or url == "" then
		return nil
	end
	local body
	pcall(function()
		body = game:HttpGet(url)
	end)
	if type(body) == "string" and body ~= "" then
		return body
	end
	local req
	pcall(function()
		req = request or http_request
	end)
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

function Flow.reloadRemote()
	local urls = {}
	if type(env._ForgeScriptUrls) == "table" then
		for _, u in ipairs(env._ForgeScriptUrls) do
			urls[#urls + 1] = u
		end
	end
	if type(env._ForgeScriptUrl) == "string" and env._ForgeScriptUrl ~= "" then
		urls[#urls + 1] = env._ForgeScriptUrl
	end
	if #urls == 0 then
		return false, "本地脚本，没有远程地址"
	end
	local body = nil
	for _, url in ipairs(urls) do
		body = Flow.httpGet(url)
		if type(body) == "string" and #body > 80 and string.find(body, "ForgeFarm") then
			env._ForgeScriptUrl = url
			break
		end
		body = nil
	end
	if type(body) ~= "string" then
		return false, "下载失败"
	end
	if type(writefileFn) == "function" then
		pcall(writefileFn, "ForgeFarm.cache.lua", body)
	end
	if type(loadstringFn) ~= "function" then
		return false, "没有 loadstring"
	end
	local fn, err = loadstringFn(body)
	if type(fn) ~= "function" then
		return false, tostring(err or "编译失败")
	end
	task.defer(function()
		if type(env._ForgeShutdown) == "function" then
			pcall(env._ForgeShutdown)
		end
		fn()
	end)
	return true
end

function Flow.saveCfg()
	if type(writefileFn) ~= "function" then
		return false, "没有写文件接口"
	end
	local ok, raw = pcall(function()
		return HttpService:JSONEncode(Flow.dumpCfg())
	end)
	if not (ok and type(raw) == "string") then
		return false, "编码失败"
	end
	local ok2, err = pcall(writefileFn, CFG_FILE, raw)
	if not ok2 then
		return false, tostring(err)
	end
	return true
end

Flow.maps = {
	{
		id = 1,
		title = "地图1 石醒十字",
		rocks = { "Pebble", "Rock", "Boulder", "Lucky Block" },
	},
	{
		id = 2,
		title = "地图2 遗忘王国",
		rocks = {
			"Basalt Rock",
			"Basalt Core",
			"Basalt Vein",
			"Volcanic Rock",
			"Earth Crystal",
			"Cyan Crystal",
			"Crimson Crystal",
			"Violet Crystal",
			"Light Crystal",
		},
	},
	{
		id = 3,
		title = "地图3 霜尖原野",
		rocks = {
			"Icy Pebble",
			"Icy Rock",
			"Icy Boulder",
			"Small Ice Crystal",
			"Medium Ice Crystal",
			"Large Ice Crystal",
			"Floating Crystal",
			"Small Red Crystal",
			"Medium Red Crystal",
			"Large Red Crystal",
			"Heart Of The Island",
			"Iceberg",
		},
	},
	{
		id = 4,
		title = "地图4 绯红樱岛",
		rocks = {
			"Bamboo Pebble",
			"Bamboo Rock",
			"Bamboo Boulder",
			"Hana Pebble",
			"Glowy Rock",
			"Blossom Boulder",
			"Spirit Rock",
			"Soul Boulder",
			"Sakura Crystal",
			"Thunder Core",
		},
	},
}

Flow.zh = {
	Pebble = "石子",
	Rock = "岩石",
	Boulder = "巨石",
	["Lucky Block"] = "幸运方块",
	["Basalt Rock"] = "玄武岩",
	["Basalt Core"] = "玄武岩芯",
	["Basalt Vein"] = "玄武岩脉",
	["Volcanic Rock"] = "火山岩",
	["Earth Crystal"] = "大地水晶",
	["Cyan Crystal"] = "青色水晶",
	["Crimson Crystal"] = "绯红水晶",
	["Violet Crystal"] = "紫色水晶",
	["Light Crystal"] = "光明水晶",
	["Icy Pebble"] = "冰石子",
	["Icy Rock"] = "冰岩石",
	["Icy Boulder"] = "冰巨石",
	["Small Ice Crystal"] = "小冰晶",
	["Medium Ice Crystal"] = "中冰晶",
	["Large Ice Crystal"] = "大冰晶",
	["Floating Crystal"] = "浮空水晶",
	["Small Red Crystal"] = "小红晶",
	["Medium Red Crystal"] = "中红晶",
	["Large Red Crystal"] = "大红晶",
	["Heart Of The Island"] = "岛之心",
	Iceberg = "冰山",
	["Bamboo Pebble"] = "竹石子",
	["Bamboo Rock"] = "竹岩石",
	["Bamboo Boulder"] = "竹巨石",
	["Hana Pebble"] = "花石子",
	["Glowy Rock"] = "辉光岩",
	["Blossom Boulder"] = "花巨石",
	["Spirit Rock"] = "灵岩",
	["Soul Boulder"] = "魂巨石",
	["Sakura Crystal"] = "樱花水晶",
	["Thunder Core"] = "雷核",
}

function Flow.rockLabel(name)
	return Flow.zh[name] or name
end

Flow.zhGear = {
	Dagger = "匕首",
	["Falchion Knife"] = "弯刀匕",
	["Gladius Dagger"] = "短剑匕",
	Hook = "钩刃",
	Kunai = "苦无",
	Tanto = "短刀",
	Falchion = "弯刃剑",
	Gladius = "短剑",
	Cutlass = "弯刀",
	Rapier = "刺剑",
	Chaos = "混沌剑",
	["Hell Slayer"] = "地狱屠",
	["Crystalized Broadsword"] = "结晶阔剑",
	["Hook Blade"] = "钩剑",
	Chokuto = "直刀",
	["Dragon Blade"] = "龙刃",
	Uchigatana = "打刀",
	Tachi = "太刀",
	["Kurokiba-gatana"] = "黑牙太刀",
	["Great Sword"] = "巨剑",
	Hammer = "锤子",
	["Dragon Slayer"] = "屠龙剑",
	["Colossal Gemblade"] = "巨晶刃",
	["Colossal Terrorblade"] = "巨恐刃",
	["Dark Knight's Greatsword"] = "暗骑大剑",
	["Grave Maker"] = "葬锤",
	["Angelic Spear"] = "天使矛",
	Scythe = "镰刀",
	["Light Helmet"] = "轻盔",
	["Light Chestplate"] = "轻胸甲",
	["Light Leggings"] = "轻护腿",
	["Medium Helmet"] = "中盔",
	["Medium Chestplate"] = "中胸甲",
	["Medium Leggings"] = "中护腿",
	["Knight Helmet"] = "骑士盔",
	["Knight Chestplate"] = "骑士胸甲",
	["Knight Leggings"] = "骑士护腿",
	["Dark Knight Helmet"] = "暗骑盔",
	["Dark Knight Chestplate"] = "暗骑胸甲",
	["Dark Knight Leggings"] = "暗骑护腿",
	["Raven's Helmet"] = "鸦盔",
	["Raven's Chestplate"] = "鸦胸甲",
	["Raven's Leggings"] = "鸦护腿",
	["Samurai Helmet"] = "武士盔",
	["Samurai Chestplate"] = "武士胸甲",
	["Samurai Leggings"] = "武士护腿",
	["Shogun's Helmet"] = "将军盔",
	["Shogun's Chestplate"] = "将军胸甲",
	["Shogun's Leggings"] = "将军护腿",
	["Ninja's Headgear"] = "忍者头",
	["Ninja's Armor"] = "忍者甲",
	["Ninja's Leggings"] = "忍者腿",
	["Goblin's Crown"] = "哥布林王冠",
	["Vanguard Helmet"] = "先锋盔",
	["Vanguard Chestplate"] = "先锋胸甲",
	["Vanguard Leggings"] = "先锋护腿",
}

Flow.classLock = {
	Dagger = 3,
	StraightSword = 9,
	Mace = 14,
	Gauntlet = 14,
	Axe = 18,
	Katana = 18,
	GreatSword = 24,
	Spear = 24,
	GreatAxe = 31,
	ColossalSword = 50,
	LightHelmet = 3,
	LightLeggings = 11,
	LightChestplate = 15,
	MediumHelmet = 20,
	MediumLeggings = 24,
	MediumChestplate = 30,
	HeavyHelmet = 35,
	HeavyLeggings = 42,
	HeavyChestplate = 52,
}

Flow.classZh = {
	Dagger = "匕首",
	StraightSword = "直剑",
	Mace = "锤",
	Gauntlet = "拳套",
	Axe = "斧",
	Katana = "太刀",
	GreatSword = "大剑",
	Spear = "矛",
	GreatAxe = "巨斧",
	ColossalSword = "巨剑",
	LightHelmet = "轻盔",
	LightLeggings = "轻护腿",
	LightChestplate = "轻胸甲",
	MediumHelmet = "中盔",
	MediumLeggings = "中护腿",
	MediumChestplate = "中胸甲",
	HeavyHelmet = "重盔",
	HeavyLeggings = "重护腿",
	HeavyChestplate = "重胸甲",
}

Flow.gearClass = {
	Dagger = "Dagger",
	["Falchion Knife"] = "Dagger",
	["Gladius Dagger"] = "Dagger",
	Hook = "Dagger",
	Kunai = "Dagger",
	Tanto = "Dagger",
	Falchion = "StraightSword",
	Gladius = "StraightSword",
	Cutlass = "StraightSword",
	Rapier = "StraightSword",
	Chaos = "StraightSword",
	["Hell Slayer"] = "StraightSword",
	["Crystalized Broadsword"] = "StraightSword",
	["Hook Blade"] = "StraightSword",
	Chokuto = "StraightSword",
	["Dragon Blade"] = "StraightSword",
	Uchigatana = "Katana",
	Tachi = "Katana",
	["Kurokiba-gatana"] = "Katana",
	["Great Sword"] = "ColossalSword",
	Hammer = "ColossalSword",
	["Dragon Slayer"] = "ColossalSword",
	["Colossal Gemblade"] = "ColossalSword",
	["Colossal Terrorblade"] = "ColossalSword",
	["Dark Knight's Greatsword"] = "GreatSword",
	["Grave Maker"] = "Mace",
	["Angelic Spear"] = "Spear",
	Scythe = "GreatAxe",
	["Light Helmet"] = "LightHelmet",
	["Light Chestplate"] = "LightChestplate",
	["Light Leggings"] = "LightLeggings",
	["Medium Helmet"] = "MediumHelmet",
	["Medium Chestplate"] = "MediumChestplate",
	["Medium Leggings"] = "MediumLeggings",
	["Knight Helmet"] = "HeavyHelmet",
	["Knight Chestplate"] = "HeavyChestplate",
	["Knight Leggings"] = "HeavyLeggings",
	["Dark Knight Helmet"] = "HeavyHelmet",
	["Dark Knight Chestplate"] = "HeavyChestplate",
	["Dark Knight Leggings"] = "HeavyLeggings",
	["Raven's Helmet"] = "HeavyHelmet",
	["Raven's Chestplate"] = "HeavyChestplate",
	["Raven's Leggings"] = "HeavyLeggings",
	["Samurai Helmet"] = "MediumHelmet",
	["Samurai Chestplate"] = "MediumChestplate",
	["Samurai Leggings"] = "MediumLeggings",
	["Shogun's Helmet"] = "HeavyHelmet",
	["Shogun's Chestplate"] = "HeavyChestplate",
	["Shogun's Leggings"] = "HeavyLeggings",
	["Ninja's Headgear"] = "LightHelmet",
	["Ninja's Armor"] = "LightChestplate",
	["Ninja's Leggings"] = "LightLeggings",
	["Goblin's Crown"] = "HeavyHelmet",
	["Vanguard Helmet"] = "HeavyHelmet",
	["Vanguard Chestplate"] = "HeavyChestplate",
	["Vanguard Leggings"] = "HeavyLeggings",
}

function Flow.forgeTotal(lock)
	local n = tonumber(lock) or 10
	for _, step in ipairs({ 10, 20, 30, 40, 50, 60 }) do
		if step >= n then
			return step
		end
	end
	return 60
end

function Flow.mixCounts(mix, total)
	local list = mix or {}
	local sum = 0
	for _, part in ipairs(list) do
		sum = sum + (tonumber(part[2]) or 0)
	end
	if sum <= 0 or total <= 0 or #list == 0 then
		return {}
	end
	local out = {}
	local used = 0
	for i, part in ipairs(list) do
		local n
		if i == #list then
			n = math.max(1, total - used)
		else
			n = math.max(1, math.floor(total * part[2] / sum + 0.5))
			if part[2] / sum >= 0.29 then
				n = math.max(n, math.ceil(total * 0.3 - 1e-9))
			end
			used = used + n
		end
		out[i] = { part[1], n }
	end
	if out[#out] and out[#out][2] < 1 and out[1] then
		out[1][2] = math.max(1, out[1][2] - 1)
		out[#out][2] = 1
	end
	return out
end

function Flow.mixLine(counts)
	local bits = {}
	for _, part in ipairs(counts or {}) do
		bits[#bits + 1] = Flow.sellLabel(part[1]) .. " " .. tostring(part[2]) .. "颗"
	end
	return table.concat(bits, " + ")
end

function Flow.mixTotal(counts)
	local n = 0
	for _, part in ipairs(counts or {}) do
		n = n + (tonumber(part[2]) or 0)
	end
	return n
end

function Flow.gearLabel(name)
	return Flow.zhGear[name] or Flow.zhSell[name] or Flow.zh[name] or name
end

Flow.guideMaps = {
	{
		id = 1,
		title = "地图1 石醒十字",
		areas = {
			{
				stage = "early",
				stageName = "前期",
				area = "铁谷 · 石子",
				rocks = { "Pebble" },
				tip = "石子掉石头、砂岩、铜铁和粪矿。点下面任意一把武器或一套护甲，看这炉要扔几颗。",
				mix = { { "Iron", 7 }, { "Poopite", 3 } },
				note = "铁铺伤害，粪矿给臭味圈。词条矿至少要占三成，所以 10 颗里粪矿固定 3 颗。",
				weapons = { "Dagger", "Falchion Knife", "Gladius", "Falchion", "Cutlass" },
				armorSets = {
					{ title = "轻甲一套", items = { "Light Helmet", "Light Chestplate", "Light Leggings" } },
				},
			},
			{
				stage = "mid",
				stageName = "中期",
				area = "铁谷 · 岩石",
				rocks = { "Rock" },
				tip = "岩石出银、锡、香蕉矿。这层几乎没进攻词条，用香蕉矿铺倍率。",
				mix = { { "Bananite", 7 }, { "Silver", 3 } },
				note = "香蕉矿 7 颗铺倍率，银 3 颗凑数。",
				weapons = { "Dagger", "Gladius", "Falchion", "Cutlass", "Great Sword" },
				armorSets = {
					{ title = "中甲一套", items = { "Medium Helmet", "Medium Chestplate", "Medium Leggings" } },
				},
			},
			{
				stage = "late",
				stageName = "后期",
				area = "铁谷 · 巨石",
				rocks = { "Boulder" },
				tip = "巨石出金、铂、艾特。图1毕业。幸运方块的菲奇矿倍率是 0，别拿去锻。",
				mix = { { "Gold", 7 }, { "Poopite", 3 } },
				note = "金 7 颗铺面板，粪矿 3 颗吃满臭味。",
				weapons = { "Falchion", "Cutlass", "Uchigatana", "Great Sword", "Hammer" },
				armorSets = {
					{ title = "骑士重甲一套", items = { "Knight Helmet", "Knight Chestplate", "Knight Leggings" } },
				},
			},
		},
	},
	{
		id = 2,
		title = "地图2 遗忘王国",
		areas = {
			{
				stage = "early",
				stageName = "前期",
				area = "遗忘王国 · 玄武岩口",
				rocks = { "Basalt Rock" },
				tip = "玄武岩出眼矿、钴钛、青金石。眼矿是图2第一根进攻词条。",
				mix = { { "Cobalt", 7 }, { "Eye Ore", 3 } },
				note = "钴 7 颗铺倍率，眼矿 3 颗：生命少一点、增伤多一点。",
				weapons = { "Hook", "Cutlass", "Rapier", "Tachi", "Great Sword" },
				armorSets = {
					{ title = "暗骑重甲一套", items = { "Dark Knight Helmet", "Dark Knight Chestplate", "Dark Knight Leggings" } },
				},
			},
			{
				stage = "mid",
				stageName = "中期",
				area = "遗忘王国 · 岩脉",
				rocks = { "Basalt Core", "Basalt Vein" },
				tip = "岩脉出对决矿、秘银、光矿。武器走暴击，护甲走生命和移速。",
				mix = { { "Emerald", 7 }, { "Rivalite", 3 } },
				note = "绿宝石 7 颗铺倍率，对决矿 3 颗上暴击。",
				armorMix = { { "Emerald", 4 }, { "Mythril", 3 }, { "Lightite", 3 } },
				armorNote = "绿宝石 4 颗铺倍率，秘银 3 颗生命，光矿 3 颗移速。",
				weapons = { "Cutlass", "Chaos", "Tachi", "Dark Knight's Greatsword", "Dragon Slayer" },
				armorSets = {
					{ title = "暗骑重甲一套", items = { "Dark Knight Helmet", "Dark Knight Chestplate", "Dark Knight Leggings" } },
					{ title = "武士中甲一套", items = { "Samurai Helmet", "Samurai Chestplate", "Samurai Leggings" } },
				},
			},
			{
				stage = "late",
				stageName = "后期",
				area = "火山深处 · 哥布林洞",
				rocks = { "Volcanic Rock", "Earth Crystal", "Cyan Crystal", "Crimson Crystal", "Violet Crystal", "Light Crystal" },
				tip = "火山出火矿、岩浆矿、恶魔矿、暗晶。奥术水晶没有词条，只拿来凑颗数。",
				mix = { { "Arcane Crystal", 4 }, { "Magmaite", 3 }, { "Fireite", 3 } },
				note = "奥术水晶 4 颗铺倍率，岩浆矿 3 颗爆炸，火矿 3 颗燃烧。",
				armorMix = { { "Obsidian", 4 }, { "Demonite", 3 }, { "Darkryte", 3 } },
				armorNote = "黑曜石 4 颗生命，恶魔矿 3 颗反伤着火，暗晶 3 颗幻步。",
				weapons = { "Chaos", "Hell Slayer", "Dark Knight's Greatsword", "Scythe", "Dragon Slayer" },
				armorSets = {
					{ title = "暗骑重甲一套", items = { "Dark Knight Helmet", "Dark Knight Chestplate", "Dark Knight Leggings" } },
				},
			},
		},
	},
	{
		id = 3,
		title = "地图3 霜尖原野",
		areas = {
			{
				stage = "early",
				stageName = "前期",
				area = "霜原 · 冰石",
				rocks = { "Icy Pebble", "Icy Rock", "Icy Boulder" },
				tip = "冰石出钨、石墨、以太矿、雪矿、冰矿。石墨是图3第一件盾。",
				mix = { { "Tungsten", 4 }, { "Snowite", 3 }, { "Aetherit", 3 } },
				note = "钨 4 颗铺倍率，雪矿 3 颗下雪，以太矿 3 颗攻速。",
				armorMix = { { "Tungsten", 4 }, { "Graphite", 3 }, { "Aetherit", 3 } },
				armorNote = "钨 4 颗，石墨 3 颗上盾，以太矿 3 颗移速。",
				weapons = { "Crystalized Broadsword", "Hell Slayer", "Hook Blade", "Angelic Spear", "Colossal Gemblade" },
				armorSets = {
					{ title = "鸦骑士一套", items = { "Raven's Helmet", "Raven's Chestplate", "Raven's Leggings" } },
				},
			},
			{
				stage = "mid",
				stageName = "中期",
				area = "山巅 · 冰晶",
				rocks = { "Small Ice Crystal", "Medium Ice Crystal", "Large Ice Crystal", "Floating Crystal" },
				tip = "山巅出绯红矿、虚空星、空灵矿、巨兽矿。暴击从虚空星开始。",
				mix = { { "Gargantuan", 4 }, { "Voidstar", 3 }, { "Crimsonite", 3 } },
				note = "巨兽 4 颗爆炸着火，虚空星 3 颗暴击，绯红矿 3 颗增伤。",
				armorMix = { { "Etherealite", 4 }, { "Sanctis", 3 }, { "Velchire", 3 } },
				armorNote = "空灵矿 4 颗生命，圣域 3 颗体力，魔翼 3 颗移速。",
				weapons = { "Hell Slayer", "Crystalized Broadsword", "Grave Maker", "Angelic Spear", "Colossal Gemblade" },
				armorSets = {
					{ title = "鸦骑士一套", items = { "Raven's Helmet", "Raven's Chestplate", "Raven's Leggings" } },
				},
			},
			{
				stage = "late",
				stageName = "后期",
				area = "鸦窟 · 冰山",
				rocks = { "Small Red Crystal", "Medium Red Crystal", "Large Red Crystal", "Heart Of The Island", "Iceberg" },
				tip = "红晶和岛之心出失心、杜兰。冰山只掉沧龙矿，肉但极慢。",
				mix = { { "Gargantuan", 7 }, { "Stolen Heart", 3 } },
				note = "巨兽 7 颗铺倍率，失心 3 颗吸血。",
				armorMix = { { "Duranite", 4 }, { "Heart Of The Island", 3 }, { "Etherealite", 3 } },
				armorNote = "杜兰 4 颗盾，岛之心 3 颗狂暴，空灵矿 3 颗生命。",
				weapons = { "Hell Slayer", "Crystalized Broadsword", "Grave Maker", "Colossal Gemblade", "Colossal Terrorblade" },
				armorSets = {
					{ title = "鸦骑士一套", items = { "Raven's Helmet", "Raven's Chestplate", "Raven's Leggings" } },
				},
			},
		},
	},
	{
		id = 4,
		title = "地图4 绯红樱岛",
		areas = {
			{
				stage = "early",
				stageName = "前期",
				area = "竹洞",
				rocks = { "Bamboo Pebble", "Bamboo Rock", "Bamboo Boulder" },
				tip = "竹洞出缟玛瑙、虎眼石、地矿、青玉。图4第一根暴击矿是缟玛瑙。",
				mix = { { "Onyx", 4 }, { "Tiger's Eye", 3 }, { "Magit", 3 } },
				note = "缟玛瑙 4 颗暴击，虎眼 3 颗攻速增伤（掉血），魔力矿 3 颗凑倍率。",
				armorMix = { { "Cyanite Jade", 4 }, { "Earthite", 3 }, { "Duquack", 3 } },
				armorNote = "青玉 4 颗生命，地矿 3 颗生命，鸭矿 3 颗跳跃闪避。",
				weapons = { "Kunai", "Tanto", "Chokuto", "Uchigatana", "Tachi" },
				armorSets = {
					{ title = "忍者轻甲一套", items = { "Ninja's Headgear", "Ninja's Armor", "Ninja's Leggings" } },
					{ title = "武士中甲一套", items = { "Samurai Helmet", "Samurai Chestplate", "Samurai Leggings" } },
				},
			},
			{
				stage = "mid",
				stageName = "中期",
				area = "圣树",
				rocks = { "Hana Pebble", "Glowy Rock", "Blossom Boulder" },
				tip = "圣树出封咒、日石、招财猫、天球、陨石。点进去看每件要几颗。",
				mix = { { "Sun Stone", 4 }, { "Sealed Curse", 3 }, { "Onyx", 3 } },
				note = "日石 4 颗火，封咒 3 颗增伤（掉血掉速），缟玛瑙 3 颗暴击。",
				armorMix = { { "Heavenly Orb", 4 }, { "Lucky Cat", 3 }, { "Duquack", 3 } },
				armorNote = "天球 4 颗盾和回血，招财猫 3 颗幸运多掉，鸭矿 3 颗机动。",
				weapons = { "Tanto", "Uchigatana", "Kurokiba-gatana", "Dragon Blade", "Colossal Terrorblade" },
				armorSets = {
					{ title = "武士中甲一套", items = { "Samurai Helmet", "Samurai Chestplate", "Samurai Leggings" } },
					{ title = "将军重甲一套", items = { "Shogun's Helmet", "Shogun's Chestplate", "Shogun's Leggings" } },
				},
				craft = {
					dest = "Kokorite",
					parts = { { "Sealed Curse", 5 }, { "Roosite", 7 } },
					gold = 4000,
					station = "绯红樱岛锻造台",
				},
			},
			{
				stage = "late",
				stageName = "后期",
				area = "灵窟 · 虚空",
				rocks = { "Spirit Rock", "Soul Boulder", "Sakura Crystal", "Thunder Core" },
				tip = "灵岩要灵镐。阴、阳打灵窟怪。九尾矿打阿修罗化身。星系矿在虚空合成。",
				mix = { { "Galaxite", 7 }, { "Kyubite", 3 } },
				note = "星系矿 7 颗黑洞暴击，九尾 3 颗火。没有星系矿就改用阴阳 3 颗 + 陨石 3 颗 + 日石 4 颗。",
				armorMix = { { "Galaxite", 7 }, { "Sentira", 3 } },
				armorNote = "星系矿 7 颗盾和回血，感知矿 3 颗再叠盾和反伤。",
				weapons = { "Tanto", "Kurokiba-gatana", "Dragon Blade", "Colossal Terrorblade", "Colossal Gemblade" },
				armorSets = {
					{ title = "将军重甲一套", items = { "Shogun's Helmet", "Shogun's Chestplate", "Shogun's Leggings" } },
					{ title = "忍者轻甲一套", items = { "Ninja's Headgear", "Ninja's Armor", "Ninja's Leggings" } },
				},
				craft = {
					dest = "Galaxite",
					parts = { { "Anti Matter", 3 }, { "Singularity", 1 }, { "Supermassive Black Hole", 1 } },
					gold = 25000,
					station = "星系守护",
				},
				craft2 = {
					dest = "Yin-Yang",
					parts = { { "Yin", 1 }, { "Yang", 1 } },
					gold = 5000,
					station = "绯红樱岛锻造台",
				},
			},
		},
	},
}

Flow.needPick = {
	["Spirit Rock"] = { "Spirit Pickaxe", "Yin-Yang Pickaxe", "Dev's Bane Pickaxe" },
	["Soul Boulder"] = { "Spirit Pickaxe", "Yin-Yang Pickaxe", "Dev's Bane Pickaxe" },
	["Sakura Crystal"] = { "Yin-Yang Pickaxe", "Dev's Bane Pickaxe" },
	["Thunder Core"] = { "Yin-Yang Pickaxe", "Dev's Bane Pickaxe" },
}

Flow.placeMap = {
	[110459623978232] = 1,
	[76558904092080] = 1,
	[135705807579824] = 2,
	[129009554587176] = 2,
	[110052129429616] = 3,
	[131884594917121] = 3,
	[101696938171246] = 4,
	[74414241680540] = 4,
	[128748756607024] = 4,
}

Flow.mobsByMap = {
	[1] = { "Zombie", "Delver Zombie", "Elite Zombie", "Brute Zombie" },
	[2] = {
		"Bomber",
		"Skeleton Rogue",
		"Axe Skeleton",
		"Deathaxe Skeleton",
		"Elite Rogue Skeleton",
		"Elite Deathaxe Skeleton",
		"Blight Pyromancer",
		"Reaper",
		"Slime",
		"Blazing Slime",
	},
	[3] = {
		"Crystal Spider",
		"Diamond Spider",
		"Prismarine Spider",
		"Common Orc",
		"Elite Orc",
		"Yeti",
		"Crystal Golem",
		"Mini Demonic Spider",
		"Demonic Spider",
		"Demonic Queen Spider",
		"Chuthlu",
		"Skeleton Pirate",
	},
	[4] = {
		"Mountain Ape",
		"Savage Ape",
		"Samurai Ape",
		"Monk Panda",
		"Brute Oni",
		"Frostburn Oni",
		"Warlord Oni",
		"Hellflame Oni",
		"Pale Oni",
		"Spirit Golem",
		"Hellbringer",
	},
}

Flow.mobAsset = {
	["Elite Zombie"] = "EliteZombie",
	["Delver Zombie"] = "Delver Zombie",
	Zombie = "Zombie",
	["Brute Zombie"] = "Brute Zombie",
}

Flow.zhMob = {
	Zombie = "僵尸",
	["Elite Zombie"] = "精英僵尸",
	["Delver Zombie"] = "矿工僵尸",
	["Brute Zombie"] = "蛮僵尸",
	Bomber = "自爆者",
	["Skeleton Rogue"] = "骷髅盗贼",
	["Axe Skeleton"] = "斧骷髅",
	["Deathaxe Skeleton"] = "死斧骷髅",
	["Elite Rogue Skeleton"] = "精英盗贼骷髅",
	["Elite Deathaxe Skeleton"] = "精英死斧骷髅",
	["Blight Pyromancer"] = "枯萎火法",
	Reaper = "收割者",
	Slime = "史莱姆",
	["Blazing Slime"] = "烈焰史莱姆",
	["Crystal Spider"] = "水晶蜘蛛",
	["Diamond Spider"] = "钻石蜘蛛",
	["Prismarine Spider"] = "海晶蜘蛛",
	["Common Orc"] = "普通兽人",
	["Elite Orc"] = "精英兽人",
	Yeti = "雪人",
	["Crystal Golem"] = "水晶魔像",
	["Mini Demonic Spider"] = "小恶魔蜘蛛",
	["Demonic Spider"] = "恶魔蜘蛛",
	["Demonic Queen Spider"] = "恶魔蛛后",
	Chuthlu = "克苏鲁",
	["Skeleton Pirate"] = "骷髅海盗",
	["Mountain Ape"] = "山猿",
	["Savage Ape"] = "狂猿",
	["Samurai Ape"] = "武士猿",
	["Monk Panda"] = "武僧熊猫",
	["Brute Oni"] = "蛮鬼",
	["Frostburn Oni"] = "霜火鬼",
	["Warlord Oni"] = "鬼武将",
	["Hellflame Oni"] = "狱炎鬼",
	["Pale Oni"] = "苍白鬼",
	["Spirit Golem"] = "灵魔像",
	Hellbringer = "地狱使者",
}

function Flow.mobLabel(name)
	return Flow.zhMob[name] or name
end

Flow.potions = {
	{ id = "HealthPotion1", kind = "health", price = 150, maxBuy = 3 },
	{ id = "HealthPotion2", kind = "health", price = 350, maxBuy = 3 },
	{ id = "HealthPotion3", kind = "health", price = 2500, maxBuy = 3 },
	{ id = "AttackDamagePotion1", kind = "buff", price = 250, maxBuy = 3 },
	{ id = "MovementSpeedPotion1", kind = "buff", price = 200, maxBuy = 3 },
	{ id = "LuckPotion1", kind = "buff", price = 350, maxBuy = 10 },
	{ id = "MinerPotion1", kind = "buff", price = 500, maxBuy = 10 },
	{ id = "ChristmasPotion", kind = "buff", price = 0, maxBuy = 0 },
	{ id = "FungisMushroom", kind = "buff", price = 0, maxBuy = 0 },
	{ id = "NewXPBoostAida", kind = "buff", price = 0, maxBuy = 0 },
}

Flow.zhPot = {
	HealthPotion1 = "生命药水 I",
	HealthPotion2 = "生命药水 II",
	HealthPotion3 = "生命药水 III",
	AttackDamagePotion1 = "伤害药水 I",
	MovementSpeedPotion1 = "速度药水 I",
	LuckPotion1 = "幸运药水 I",
	MinerPotion1 = "采矿药水 I",
	ChristmasPotion = "圣诞药水",
	FungisMushroom = "蘑菇药水",
	NewXPBoostAida = "经验药水",
}

function Flow.potLabel(name)
	return Flow.zhPot[name] or name
end

function Flow.potInfo(id)
	for _, p in ipairs(Flow.potions) do
		if p.id == id then
			return p
		end
	end
	return nil
end

Flow.zhSell = {
	["Aether Lotus"] = "以太莲",
	Aetherit = "以太矿",
	Aite = "艾特矿",
	Amethyst = "紫晶",
	Ancienite = "古矿",
	["Anti Matter"] = "反物质",
	Aqujade = "水玉",
	["Arcane Crystal"] = "奥术水晶",
	["Aurelia-no-Ki"] = "金木",
	Azuryxite = "苍穹矿",
	Bamboo = "竹子",
	Bananite = "香蕉矿",
	["Blue Crystal"] = "蓝水晶",
	["Blue Gem Quill"] = "蓝宝石羽",
	Boneite = "骨矿",
	Cardboardite = "纸板矿",
	Ceyite = "赛伊矿",
	Cobalt = "钴",
	Coinite = "硬币矿",
	Copper = "铜",
	["Crimson Crystal"] = "绯红水晶",
	Crimsonite = "绯红矿",
	Cryptex = "密匣矿",
	Cuprite = "赤铜矿",
	["Cyanite Jade"] = "青玉",
	["Dark Boneite"] = "暗骨矿",
	Darkryte = "暗晶矿",
	Demonite = "恶魔矿",
	Diamond = "钻石",
	Dorabell = "朵拉铃",
	Duquack = "鸭矿",
	Duranite = "杜兰矿",
	Earthite = "地矿",
	Emerald = "绿宝石",
	Etherealite = "空灵矿",
	["Evil Eye"] = "邪眼",
	["Eye Ore"] = "眼矿",
	Fichillium = "菲奇矿",
	Fichilliumorite = "菲奇晶矿",
	["Fierce Jade"] = "猛玉",
	Fireite = "火矿",
	Frogite = "蛙矿",
	["Frost Fossil"] = "霜化石",
	Fruite = "果矿",
	Galaxite = "星系矿",
	Galestor = "星狱矿",
	Gargantuan = "巨兽矿",
	Gold = "金",
	["Golem Heart"] = "魔像之心",
	Graphite = "石墨",
	Grass = "草",
	["Green Crystal"] = "绿水晶",
	Gulabite = "古拉矿",
	["Heart Of The Island"] = "岛之心",
	["Heat Steel"] = "热钢",
	Heavenite = "天堂矿",
	["Heavenly Orb"] = "天球",
	Iceite = "冰矿",
	Iron = "铁",
	Kitsunite = "狐矿",
	Kokorite = "心矿",
	Kyomutite = "虚矿",
	Kyubite = "九尾矿",
	["Lapis Lazuli"] = "青金石",
	Larimar = "拉利玛",
	Lgarite = "艾尔加矿",
	Lightite = "光矿",
	["Lucky Cat"] = "招财猫",
	["Magenta Crystal"] = "品红水晶",
	Magit = "魔力矿",
	Magmaite = "岩浆矿",
	Malachite = "孔雀石",
	Marblite = "大理石矿",
	Matter = "物质",
	Melonite = "梅洛矿",
	Meteorite = "陨石",
	Mistvein = "雾脉",
	Moltenfrost = "熔霜",
	["Moon Stone"] = "月石",
	Mosasaursit = "沧龙矿",
	Mushroomite = "蘑菇矿",
	Mythril = "秘银",
	Neurotite = "神经矿",
	["North Star"] = "北极星",
	Obsidian = "黑曜石",
	["Oni Mask"] = "鬼面",
	Onite = "鬼矿",
	Onyx = "缟玛瑙",
	["Orange Crystal"] = "橙水晶",
	Platinum = "铂",
	Poopite = "粪矿",
	["Prismatic Heart"] = "棱镜之心",
	Pumice = "浮石",
	Quartz = "石英",
	["Rainbow Crystal"] = "彩虹水晶",
	Rivalite = "对决矿",
	["Rock Seed"] = "石种",
	Roosite = "袋鼠矿",
	["Root Spire"] = "根塔",
	Ruby = "红宝石",
	Ryuseki = "龙石",
	Sakuranite = "樱矿",
	Sakurite = "樱花矿",
	Sanctis = "圣域矿",
	["Sand Stone"] = "砂岩",
	Sapphire = "蓝宝石",
	Scheelite = "白钨矿",
	["Sealed Curse"] = "封咒",
	Seedheart = "种心",
	Sentira = "感知矿",
	Shikanite = "鹿矿",
	Silver = "银",
	Singularity = "奇点",
	Slimite = "史莱姆矿",
	Snowite = "雪矿",
	["Star Dust"] = "星尘",
	Starite = "星矿",
	["Stolen Heart"] = "失心",
	Stone = "石头",
	Sulfur = "硫磺",
	["Sun Stone"] = "日石",
	["Supermassive Black Hole"] = "超大黑洞",
	Suryafal = "日陨矿",
	Takenokoishi = "笋石",
	Takiseki = "瀑石",
	["Tide Carve"] = "潮刻",
	["Tiger's Eye"] = "虎眼石",
	Tin = "锡",
	Titanium = "钛",
	Topaz = "黄玉",
	Tungsten = "钨",
	Uranium = "铀",
	Vanegos = "瓦内矿",
	Velchire = "魔翼矿",
	Viridite = "翠绿矿",
	Voidfractal = "虚空分形",
	Voidstar = "虚空星",
	["Volcanic Rock"] = "火山岩",
	Vooite = "巫毒矿",
	["Water Stone"] = "水石",
	Wolfarite = "狼矿",
	Wraith = "怨灵矿",
	Yang = "阳",
	["Yeti Heart"] = "雪人心",
	Yin = "阴",
	["Yin-Yang"] = "阴阳",
	Zenstone = "禅石",
	Zephyte = "西风矿",
	["Tiny Essence"] = "微精华",
	["Small Essence"] = "小精华",
	["Medium Essence"] = "中精华",
	["Large Essence"] = "大精华",
	["Greater Essence"] = "强精华",
	["Superior Essence"] = "超精华",
	["Epic Essence"] = "史诗精华",
	["Legendary Essence"] = "传奇精华",
	["Mythical Essence"] = "神话精华",
	["Developer Sigil"] = "开发印记",
	["Blast Chip"] = "爆破碎片",
	["Chill Dust"] = "寒霜粉",
	["Chill Dust II"] = "寒霜粉 II",
	["Flame Spark"] = "火花",
	["Flame Spark II"] = "火花 II",
	["Miner Shard"] = "矿工碎片",
	["Miner Shard II"] = "矿工碎片 II",
	["Thunder Shard"] = "雷霆碎片",
	["Ward Patch"] = "守护补丁",
}

function Flow.sellLabel(name)
	return Flow.zhSell[name] or Flow.zh[name] or name
end

function Flow.buildSellCatalog()
	Flow.sellItems = {}
	local seen = {}
	local function add(id, kind, sort, extra, icon)
		if type(id) ~= "string" or id == "" then
			return
		end
		local key = kind .. ":" .. id
		local item = seen[key]
		if item then
			item.sort = tonumber(sort) or item.sort
			item.label = extra or Flow.sellLabel(id)
			if type(icon) == "string" then
				item.icon = icon
			end
			return
		end
		item = {
			id = id,
			kind = kind,
			sort = tonumber(sort) or 0,
			label = extra or Flow.sellLabel(id),
			icon = type(icon) == "string" and icon or nil,
		}
		seen[key] = item
		table.insert(Flow.sellItems, item)
	end
	local ok, Ore = pcall(require, ReplicatedStorage.Shared.Data.Ore)
	if ok and type(Ore) == "table" then
		for _, v in ipairs(Ore) do
			if type(v) == "table" and type(v.Name) == "string" then
				add(v.Name, "ore", v.Multiplier, nil, v.Slot and v.Slot.Icon)
			end
		end
		if type(_G.OreKeyData) == "table" then
			for _, info in ipairs(Flow.sellItems) do
				if info.kind == "ore" then
					local key = _G.OreKeyData[info.id]
					local ore = key and Ore[key.Index]
					if type(ore) == "table" then
						info.sort = tonumber(ore.Multiplier) or info.sort
						info.label = Flow.sellLabel(info.id)
						if ore.Slot and type(ore.Slot.Icon) == "string" then
							info.icon = ore.Slot.Icon
						end
					end
				end
			end
		end
	end
	local ok2, Mat = pcall(require, ReplicatedStorage.Shared.Data.Materials)
	if ok2 and type(Mat) == "table" and type(Mat.Items) == "table" then
		for _, v in ipairs(Mat.Items) do
			if type(v) == "table" and type(v.Name) == "string" then
				add(v.Name, "mat", v.Price, nil, v.Slot and v.Slot.Icon)
			end
		end
	end
	local ok3, Runes = pcall(require, ReplicatedStorage.Shared.Data.Runes)
	if ok3 and type(Runes) == "table" and type(Runes.Runes) == "table" then
		for id, v in pairs(Runes.Runes) do
			if type(v) == "table" then
				local lab = Flow.sellLabel(v.Name or id)
				add(id, "rune", v.SellPriceMultiplier or v.PriceMultiplier or 1, lab, v.Slot and v.Slot.Icon)
			end
		end
	end
end
Flow.buildSellCatalog()

local function bindFarm()
	local function hook(conn)
		if conn then
			table.insert(Flow.conns, conn)
		end
		return conn
	end

	function Flow.hrp()
		local char = player.Character
		return char and char:FindFirstChild("HumanoidRootPart") or nil
	end

	function Flow.hum()
		local char = player.Character
		return char and char:FindFirstChildOfClass("Humanoid") or nil
	end

	function Flow.toolRF()
		local ok, rf = pcall(function()
			return ReplicatedStorage.Shared.Packages.Knit.Services.ToolService.RF.ToolActivated
		end)
		if ok then
			return rf
		end
		return nil
	end

	function Flow.toolCtrl()
		if Flow._tc then
			return Flow._tc
		end
		local ok, knit = pcall(require, ReplicatedStorage.Shared.Packages.Knit)
		if ok and knit then
			local ok2, tc = pcall(function()
				return knit.GetController("ToolController")
			end)
			if ok2 and type(tc) == "table" then
				Flow._tc = tc
				return tc
			end
		end
		return nil
	end

	local function findTool(name)
		local char = player.Character
		if char then
			local t = char:FindFirstChild(name)
			if t and t:IsA("Tool") then
				return t
			end
		end
		local pack = player:FindFirstChild("Backpack")
		if pack then
			local t = pack:FindFirstChild(name)
			if t and t:IsA("Tool") then
				return t
			end
		end
		return nil
	end

	function Flow.getPickaxe()
		return findTool("Pickaxe")
	end

	function Flow.getWeapon()
		return findTool("Weapon")
	end

	function Flow.swingWeapon()
		local rf = Flow.toolRF()
		if not rf then
			return false
		end
		if not state.mineOn then
			local tool = Flow.getWeapon()
			local hum = Flow.hum()
			if tool and hum and tool.Parent ~= player.Character then
				pcall(function()
					hum:EquipTool(tool)
				end)
			end
		end
		local ok = pcall(function()
			rf:InvokeServer("Weapon")
		end)
		local held = player.Character and player.Character:FindFirstChild("Weapon")
		if held then
			pcall(function()
				held:Activate()
			end)
		end
		return ok
	end

	function Flow.replicaData()
		if Flow._rep and Flow._rep.Data then
			return Flow._rep.Data
		end
		local ok, knit = pcall(require, ReplicatedStorage.Shared.Packages.Knit)
		if ok and knit then
			local ok2, pc = pcall(function()
				return knit.GetController("PlayerController")
			end)
			if ok2 and pc and pc.Replica then
				Flow._rep = pc.Replica
				return pc.Replica.Data
			end
		end
		return nil
	end

	function Flow.mobType(model)
		if not (model and model:IsA("Model")) then
			return nil
		end
		if model:GetAttribute("IsNpc") ~= true then
			return nil
		end
		local n = model.Name
		local base = string.match(n, "^(.-)%d+$")
		if type(base) == "string" and base ~= "" then
			return base
		end
		return n
	end

	function Flow.mobCenter(model)
		local hrp = model and model:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			return hrp.Position
		end
		return Flow.centerOf(model)
	end

	function Flow.aliveHunt(model)
		if not (model and model.Parent) then
			return false
		end
		local kind = Flow.mobType(model)
		if not kind or not state.huntSel[kind] then
			return false
		end
		local hum = model:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then
			return false
		end
		return true
	end

	function Flow.huntStandCF(model)
		local center = Flow.mobCenter(model)
		if not center then
			return nil
		end
		local height = math.clamp(tonumber(state.huntHeight) or 12, 8, 28)
		return CFrame.lookAt(center + Vector3.new(0, height, 0), center)
	end

	function Flow.findHunt()
		local living = workspace:FindFirstChild("Living")
		if not living then
			return nil
		end
		local hrp = Flow.hrp()
		local origin = hrp and hrp.Position
		local best, bestD
		for _, model in ipairs(living:GetChildren()) do
			if Flow.aliveHunt(model) then
				local pos = Flow.mobCenter(model)
				if pos then
					local d = origin and (pos - origin).Magnitude or 0
					if not bestD or d < bestD then
						best = model
						bestD = d
					end
				end
			end
		end
		return best
	end

	function Flow.hasHuntSel()
		for _, on in pairs(state.huntSel) do
			if on then
				return true
			end
		end
		return false
	end

	function Flow.equipRF()
		local ok, rf = pcall(function()
			return ReplicatedStorage.Shared.Packages.Knit.Services.CharacterService.RF.EquipMisc
		end)
		if ok then
			return rf
		end
		return nil
	end

	function Flow.buyRF()
		local ok, rf = pcall(function()
			return ReplicatedStorage.Shared.Packages.Knit.Services.ProximityService.RF.Purchase
		end)
		if ok then
			return rf
		end
		return nil
	end

	function Flow.potionQty(id)
		local data = Flow.replicaData()
		local misc = data and data.Inventory and data.Inventory.Misc
		if type(misc) ~= "table" then
			return 0
		end
		local n = 0
		for _, item in pairs(misc) do
			if type(item) == "table" and item.Name == id then
				n = n + (tonumber(item.Quantity) or 1)
			end
		end
		return n
	end

	function Flow.potionRemain(id)
		local data = Flow.replicaData()
		local pots = data and data.Potions
		if type(pots) ~= "table" then
			return nil
		end
		return tonumber(pots[id])
	end

	function Flow.gold()
		local data = Flow.replicaData()
		if not data then
			return 0
		end
		return tonumber(data.Gold) or tonumber(data.Cash) or 0
	end

	function Flow.shopModel(id)
		local prox = workspace:FindFirstChild("Proximity")
		local m = prox and prox:FindFirstChild(id)
		if m then
			return m
		end
		local shops = workspace:FindFirstChild("Shops")
		if shops then
			m = shops:FindFirstChild(id, true)
			if m then
				return m
			end
		end
		return nil
	end

	function Flow.shopPos(id)
		local m = Flow.shopModel(id)
		if not m then
			return nil
		end
		local part = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
		return part and part.Position or nil
	end

	function Flow.potionTool(id)
		local char = player.Character
		if char then
			local t = char:FindFirstChild(id)
			if t and t:IsA("Tool") then
				return t
			end
		end
		local pack = player:FindFirstChild("Backpack")
		if pack then
			local t = pack:FindFirstChild(id)
			if t and t:IsA("Tool") then
				return t
			end
		end
		return nil
	end

	function Flow.restoreMainTool()
		local hum = Flow.hum()
		if not hum then
			return
		end
		local tool
		if state.huntOn and not state.mineOn then
			tool = Flow.getWeapon()
		else
			tool = Flow.getPickaxe()
		end
		if tool and tool.Parent ~= player.Character then
			pcall(function()
				hum:EquipTool(tool)
			end)
		end
	end

	function Flow.drinkPotion(id)
		local tool = Flow.potionTool(id)
		if not tool then
			local rf = Flow.equipRF()
			if not rf then
				return false
			end
			pcall(function()
				rf:InvokeServer(id)
			end)
			local t0 = os.clock()
			repeat
				task.wait(0.05)
				tool = Flow.potionTool(id)
			until tool or os.clock() - t0 > 0.9
		end
		if not tool then
			return false
		end
		local hum = Flow.hum()
		if hum and tool.Parent ~= player.Character then
			pcall(function()
				hum:EquipTool(tool)
			end)
			task.wait(0.1)
		end
		local ok = pcall(function()
			local rf = Flow.toolRF()
			if rf then
				rf:InvokeServer(id)
			end
		end)
		local held = player.Character and player.Character:FindFirstChild(id)
		if held then
			pcall(function()
				held:Activate()
			end)
		end
		Flow.lastDrink[id] = os.clock()
		task.wait(0.15)
		Flow.restoreMainTool()
		return ok
	end

	function Flow.buyPotion(id, amt)
		local rf = Flow.buyRF()
		if not rf then
			return false
		end
		local ok = pcall(function()
			rf:InvokeServer(id, amt or 1)
		end)
		return ok
	end

	function Flow.favMap()
		local data = Flow.replicaData()
		local fav = data and data.Favorites
		return type(fav) == "table" and fav or {}
	end

	function Flow.sellQty(info)
		local data = Flow.replicaData()
		if not (info and data) then
			return 0
		end
		if info.kind == "ore" then
			return math.max(0, tonumber(data.Inventory and data.Inventory[info.id]) or 0)
		end
		local misc = data.Inventory and data.Inventory.Misc
		if type(misc) ~= "table" then
			return 0
		end
		local n = 0
		for _, item in pairs(misc) do
			if type(item) == "table" then
				if info.kind == "mat" and item.Name == info.id then
					n = n + (tonumber(item.Quantity) or 1)
				elseif info.kind == "rune" and item.Id == info.id then
					n = n + 1
				end
			end
		end
		return n
	end

	function Flow.makeSellBasket()
		local data = Flow.replicaData()
		if not data then
			return {}
		end
		local fav = Flow.favMap()
		local basket = {}
		local misc = data.Inventory and data.Inventory.Misc
		for _, info in ipairs(Flow.sellItems) do
			if state.sellSel[info.id] then
				if info.kind == "ore" then
					if not fav[info.id] then
						local q = math.max(0, tonumber(data.Inventory and data.Inventory[info.id]) or 0)
						if q > 0 then
							basket[info.id] = q
						end
					end
				elseif info.kind == "mat" then
					if not fav[info.id] then
						local q = Flow.sellQty(info)
						if q > 0 then
							basket[info.id] = q
						end
					end
				elseif info.kind == "rune" and type(misc) == "table" then
					for _, item in pairs(misc) do
						if type(item) == "table" and item.Id == info.id and type(item.GUID) == "string" and not fav[item.GUID] then
							basket[item.GUID] = 1
						end
					end
				end
			end
		end
		return basket
	end

	function Flow.sellerNpc()
		local prox = workspace:FindFirstChild("Proximity")
		return prox and prox:FindFirstChild("Greedy Cey") or nil
	end

	function Flow.sellerPos()
		local npc = Flow.sellerNpc()
		if not npc then
			return nil
		end
		local part = npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart or npc:FindFirstChildWhichIsA("BasePart", true)
		return part and part.Position or nil
	end

	function Flow.sellerStandCF()
		local npc = Flow.sellerNpc()
		if not npc then
			return nil
		end
		local hrp = npc:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			return hrp.CFrame * CFrame.new(0, 0, -10)
		end
		local pos = Flow.sellerPos()
		return pos and CFrame.new(pos + Vector3.new(0, 3, 8)) or nil
	end

	function Flow.nearSeller()
		local pos = Flow.sellerPos()
		local hrp = Flow.hrp()
		if not (pos and hrp) then
			return false
		end
		return (hrp.Position - pos).Magnitude <= 18
	end

	function Flow.hasSellAnywhere()
		local data = Flow.replicaData()
		return data and data.Gamepasses and data.Gamepasses.SellAnywhere == true
	end

	function Flow.qtyForBasketKey(key)
		local data = Flow.replicaData()
		if not (data and data.Inventory and type(key) == "string") then
			return 0
		end
		local n = tonumber(data.Inventory[key])
		if n then
			return n
		end
		local misc = data.Inventory.Misc
		if type(misc) ~= "table" then
			return 0
		end
		local q = 0
		for _, item in pairs(misc) do
			if type(item) == "table" then
				if item.GUID == key then
					q = q + 1
				elseif item.Name == key then
					q = q + (tonumber(item.Quantity) or 1)
				end
			end
		end
		return q
	end

	function Flow.snapBasket(basket)
		local data = Flow.replicaData()
		local snap = { gold = data and tonumber(data.Gold) or 0 }
		for id in pairs(basket) do
			snap[id] = Flow.qtyForBasketKey(id)
		end
		return snap
	end

	function Flow.soldSince(snap, basket)
		if not (snap and basket) then
			return false
		end
		for id in pairs(basket) do
			if Flow.qtyForBasketKey(id) < (snap[id] or 0) then
				return true
			end
		end
		return false
	end

	function Flow.hasAnySellSel()
		for _, on in pairs(state.sellSel) do
			if on then
				return true
			end
		end
		return false
	end

	function Flow.clickSellDeal()
		local gui = playerGui:FindFirstChild("DialogueUI")
		if not (gui and gui.Enabled) then
			return false
		end
		local bill = gui:FindFirstChild("ResponseBillboard")
		local list = bill and bill:FindFirstChild("List")
		if not list then
			return false
		end
		for _, fr in ipairs(list:GetChildren()) do
			local btn = fr:FindFirstChild("Button")
			local order = fr:FindFirstChild("Order")
			local text = btn and tostring(btn.Text) or ""
			local yes = string.find(text, "Deal", 1, true) or (order and order.Text == "1.")
			if btn and btn:IsA("GuiButton") and yes then
				pcall(function()
					if type(getconnections) == "function" then
						for _, conn in ipairs(getconnections(btn.MouseButton1Click)) do
							if conn.Fire then
								conn:Fire()
							end
						end
					end
				end)
				pcall(function()
					btn:Activate()
				end)
				return true
			end
		end
		return false
	end

	function Flow.openSellConfirm(basket)
		local ok, knit = pcall(require, ReplicatedStorage.Shared.Packages.Knit)
		if not (ok and knit) then
			return false
		end
		local ui = knit.GetController("UIController")
		if ui and ui.Modules and ui.Modules.MiscSell then
			ui.Modules.MiscSell.SellInfo = ui.Modules.MiscSell.SellInfo or {}
			ui.Modules.MiscSell.SellInfo.Basket = basket
		end
		local npc = Flow.sellerNpc()
		local gui = playerGui:FindFirstChild("DialogueUI")
		if gui and gui.Enabled then
			local speaker = gui:FindFirstChild("Speaker", true)
			if speaker and speaker.Text == "Greedy Cey" then
				return true
			end
			pcall(function()
				gui.Enabled = false
			end)
			task.wait(0.15)
		end
		local prox = knit.GetService("ProximityService")
		if prox and npc then
			pcall(function()
				prox:ForceDialogue(npc, "SellConfirmMisc"):await()
			end)
		end
		gui = playerGui:FindFirstChild("DialogueUI")
		if gui and gui.Enabled then
			return true
		end
		local tree = ReplicatedStorage:FindFirstChild("Dialogues")
		tree = tree and tree:FindFirstChild("MiscSell")
		tree = tree and tree:FindFirstChild("SellConfirmMisc")
		local bind = ReplicatedStorage:FindFirstChild("DialogueBindable", true)
		if tree and bind and npc then
			local part = npc:FindFirstChild("HumanoidRootPart")
			pcall(function()
				bind:Fire(tree, {
					Speaker = "Greedy Cey",
					SpeakerCharacter = npc,
					Range = 40,
					Position = part and part.Position or npc:GetPivot().Position,
				})
			end)
		end
		gui = playerGui:FindFirstChild("DialogueUI")
		return gui and gui.Enabled == true
	end

	function Flow.farmOn()
		return state.mineOn or state.huntOn
	end

	function Flow.sellInterval()
		return math.clamp(math.floor(tonumber(state.sellWait) or 60), 10, 600)
	end

	function Flow.armSellClock()
		if state.sellOn and Flow.farmOn() and not Flow.sellFly then
			if not Flow.nextSellAt or Flow.nextSellAt <= 0 then
				Flow.nextSellAt = os.clock() + Flow.sellInterval()
			end
		end
	end

	function Flow.clearSellTrip()
		Flow.sellFly = nil
		Flow.sellTalk = false
	end

	function Flow.doSell(basket)
		if type(basket) ~= "table" or next(basket) == nil then
			return false
		end
		if not Flow.nearSeller() then
			return false
		end
		local snap = Flow.snapBasket(basket)
		Flow.sellTalk = true
		pcall(function()
			Flow.setFlyBody(false)
		end)
		pcall(function()
			Flow.openSellConfirm(basket)
			local gui = playerGui:FindFirstChild("DialogueUI")
			local prompt = gui and gui:FindFirstChild("PromptFrame")
			if prompt and prompt:IsA("GuiButton") then
				pcall(function()
					prompt:Activate()
				end)
			end
			local t0 = os.clock()
			local clicked = false
			repeat
				task.wait(0.12)
				if Flow.clickSellDeal() then
					clicked = true
				end
			until clicked or Flow.soldSince(snap, basket) or os.clock() - t0 > 7
			if not Flow.soldSince(snap, basket) then
				local knit = require(ReplicatedStorage.Shared.Packages.Knit)
				local ui = knit.GetController("UIController")
				if ui and ui.Modules and ui.Modules.MiscSell then
					ui.Modules.MiscSell.SellInfo = ui.Modules.MiscSell.SellInfo or {}
					ui.Modules.MiscSell.SellInfo.Basket = basket
				end
				knit.GetService("DialogueService"):RunCommand("SellConfirm", { Basket = basket }):await()
				task.wait(0.35)
			end
		end)
		Flow.sellTalk = false
		return Flow.soldSince(snap, basket)
	end

	function Flow.tickSell()
		if not state.sellOn then
			Flow.clearSellTrip()
			Flow.nextSellAt = 0
			return
		end
		if not Flow.farmOn() then
			Flow.clearSellTrip()
			Flow.nextSellAt = 0
			return
		end
		if Flow.sellTalk then
			return
		end
		if Flow.sellFly then
			local basket = Flow.makeSellBasket()
			if next(basket) == nil then
				Flow.clearSellTrip()
				Flow.nextSellAt = os.clock() + Flow.sellInterval()
				return
			end
			if not Flow.sellerPos() then
				state.status = "这图不能卖"
				return
			end
			if Flow.nearSeller() then
				if Flow.doSell(basket) then
					Flow.clearSellTrip()
					Flow.lastSell = os.clock()
					Flow.nextSellAt = os.clock() + Flow.sellInterval()
					state.status = "已出售"
					return
				end
				state.status = "出售确认"
				return
			end
			state.status = "去商人"
			return
		end
		Flow.armSellClock()
		local due = Flow.nextSellAt or 0
		if due > os.clock() then
			return
		end
		if not Flow.hasAnySellSel() then
			Flow.nextSellAt = os.clock() + Flow.sellInterval()
			return
		end
		local basket = Flow.makeSellBasket()
		if next(basket) == nil then
			Flow.nextSellAt = os.clock() + Flow.sellInterval()
			return
		end
		if not Flow.sellerPos() then
			state.status = "这图不能卖"
			Flow.nextSellAt = os.clock() + 15
			return
		end
		Flow.sellFly = true
		state.status = "去商人"
	end

	function Flow.needPotion(id)
		local info = Flow.potInfo(id)
		if not info then
			return nil
		end
		if Flow.potionQty(id) <= 0 then
			return "buy"
		end
		local last = Flow.lastDrink[id] or 0
		if os.clock() - last < 2.2 then
			return nil
		end
		local rem = Flow.potionRemain(id)
		if info.kind == "health" then
			local hum = Flow.hum()
			if rem and rem > 1 then
				return nil
			end
			if hum and hum.MaxHealth > 0 and hum.Health < hum.MaxHealth * 0.82 then
				return "drink"
			end
			return nil
		end
		if rem == nil or rem <= 12 then
			return "drink"
		end
		return nil
	end

	function Flow.pickaxeName()
		local tool = Flow.getPickaxe()
		if not tool then
			return nil
		end
		local json = tool:GetAttribute("ItemJSON")
		if type(json) == "string" then
			local n = string.match(json, '"Name"%s*:%s*"([^"]+)"')
			if n and n ~= "" then
				return n
			end
		end
		return tool.Name
	end

	function Flow.canMineType(name)
		local need = Flow.needPick[name]
		if not need then
			return true
		end
		local have = Flow.pickaxeName()
		if not have then
			return false
		end
		for _, n in ipairs(need) do
			if n == have then
				return true
			end
		end
		return false
	end

	function Flow.equipPick()
		local tool = Flow.getPickaxe()
		local hum = Flow.hum()
		if not (tool and hum) then
			return false
		end
		if tool.Parent ~= player.Character then
			pcall(function()
				hum:EquipTool(tool)
			end)
		end
		return player.Character and player.Character:FindFirstChild("Pickaxe") ~= nil
	end

	function Flow.isBusy(model)
		local who = model:GetAttribute("LastHitPlayer")
		if not who or who == player.Name then
			return false
		end
		local hp = tonumber(model:GetAttribute("Health")) or 0
		local max = tonumber(model:GetAttribute("MaxHealth")) or hp
		return hp < max - 0.5
	end

	function Flow.aliveTarget(model)
		if not (model and model.Parent) then
			return false
		end
		if not state.selected[model.Name] then
			return false
		end
		local hp = tonumber(model:GetAttribute("Health")) or 0
		return hp > 0
	end

	function Flow.centerOf(model)
		local hb = model:FindFirstChild("Hitbox")
		if hb and hb:IsA("BasePart") then
			return hb.Position
		end
		local ok, cf = pcall(function()
			return model:GetPivot()
		end)
		if ok and cf then
			return cf.Position
		end
		local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		return part and part.Position or nil
	end

	function Flow.rockCrit(model)
		if not model then
			return nil
		end
		local p = model:FindFirstChild("RockCritical")
		if not (p and p:IsA("BasePart")) then
			p = model:FindFirstChild("RockCritical", true)
		end
		if p and p:IsA("BasePart") and p.Parent then
			return p
		end
		return nil
	end

	function Flow.pinCrit(model)
		local crit = Flow.rockCrit(model)
		local hrp = Flow.hrp()
		local look = Flow.centerOf(model)
		if not (crit and hrp and look) then
			return false
		end
		local delta = look - hrp.Position
		if delta.Magnitude < 0.2 then
			return false
		end
		local dir = delta.Unit
		local pos = hrp.Position + dir * 1.55
		local up = -dir
		local right = up:Cross(Vector3.yAxis)
		if right.Magnitude < 0.12 then
			right = up:Cross(Vector3.xAxis)
		end
		right = right.Unit
		local back = right:Cross(up)
		pcall(function()
			crit.CanCollide = false
			crit.CFrame = CFrame.fromMatrix(pos, right, up, -back)
			crit:SetAttribute("surfaceX", dir.X)
			crit:SetAttribute("surfaceY", dir.Y)
			crit:SetAttribute("surfaceZ", dir.Z)
		end)
		return true
	end

	function Flow.standCF(model)
		local center = Flow.centerOf(model)
		if not center then
			return nil
		end
		local pitch = math.rad(math.clamp(tonumber(state.standPitch) or 0, -90, 90))
		local dist = math.max(tonumber(state.standDist) or 4.5, 1)
		local hrp = Flow.hrp()
		local flat = hrp and Vector3.new(hrp.Position.X - center.X, 0, hrp.Position.Z - center.Z) or Vector3.new(0, 0, -1)
		if flat.Magnitude < 0.2 then
			flat = Vector3.new(0, 0, -1)
		else
			flat = flat.Unit
		end
		local dir = flat * math.cos(pitch) + Vector3.yAxis * math.sin(pitch)
		if dir.Magnitude < 0.05 then
			dir = Vector3.yAxis * (pitch >= 0 and 1 or -1)
		else
			dir = dir.Unit
		end
		local pos = center + dir * dist
		return Flow.lookCF(pos, center)
	end

	function Flow.holdBV()
		local hrp = Flow.hrp()
		if not hrp then
			return nil
		end
		local bv = hrp:FindFirstChild("ForgeFlyHold")
		if not bv then
			bv = Instance.new("BodyVelocity")
			bv.Name = "ForgeFlyHold"
			bv.MaxForce = Vector3.new(400000, 400000, 400000)
			bv.P = 1250
			bv.Velocity = Vector3.zero
			bv.Parent = hrp
		end
		return bv
	end

	function Flow.clearHold()
		local hrp = Flow.hrp()
		if not hrp then
			return
		end
		local bv = hrp:FindFirstChild("ForgeFlyHold")
		if bv then
			bv:Destroy()
		end
	end

	function Flow.applyNoclip()
		local char = player.Character
		if not char then
			return
		end
		if type(Flow.clipSaved) ~= "table" then
			Flow.clipSaved = {}
		end
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") then
				if Flow.clipSaved[d] == nil then
					Flow.clipSaved[d] = d.CanCollide
				end
				d.CanCollide = false
			end
		end
	end

	function Flow.restoreNoclip()
		if type(Flow.clipSaved) ~= "table" then
			return
		end
		for part, col in pairs(Flow.clipSaved) do
			if part and part.Parent then
				pcall(function()
					part.CanCollide = col
				end)
			end
		end
		Flow.clipSaved = nil
	end

	function Flow.setFlyBody(on)
		local hrp = Flow.hrp()
		local hum = Flow.hum()
		if on then
			if not Flow.hoverOn then
				Flow.savedPlat = hum and hum.PlatformStand or false
				Flow.savedRot = not hum or hum.AutoRotate ~= false
				Flow.hoverOn = true
			end
			if hrp then
				hrp.Anchored = false
			end
			if hum then
				hum.PlatformStand = true
				hum.AutoRotate = false
			end
			Flow.applyNoclip()
			Flow.holdBV()
		elseif Flow.hoverOn then
			Flow.hoverOn = false
			Flow.clearHold()
			Flow.restoreNoclip()
			if hum then
				hum.PlatformStand = Flow.savedPlat == true
				hum.AutoRotate = Flow.savedRot ~= false
			end
		end
	end

	function Flow.eachRock(fn)
		local folder = workspace:FindFirstChild("Rocks")
		if not folder then
			return
		end
		for _, zone in ipairs(folder:GetChildren()) do
			for _, slot in ipairs(zone:GetChildren()) do
				local occ = false
				pcall(function()
					occ = slot:GetAttribute("IsOccupied") == true
				end)
				if occ then
					local model = slot:FindFirstChildWhichIsA("Model")
					if model then
						fn(model, slot)
					end
				end
			end
		end
	end

	function Flow.findNearest()
		local hrp = Flow.hrp()
		if not hrp then
			return nil
		end
		local best = nil
		local bestD = nil
		local blocked = 0
		Flow.eachRock(function(model)
			if not state.selected[model.Name] then
				return
			end
			local hp = tonumber(model:GetAttribute("Health")) or 0
			if hp <= 0 then
				return
			end
			if not Flow.canMineType(model.Name) then
				blocked = blocked + 1
				return
			end
			if Flow.isBusy(model) then
				return
			end
			local center = Flow.centerOf(model)
			if not center then
				return
			end
			local d = (center - hrp.Position).Magnitude
			if Flow.rockCrit(model) then
				d = d - 10000
			end
			if not bestD or d < bestD then
				best = model
				bestD = d
			end
		end)
		if not best and blocked > 0 then
			state.status = "镐不对"
		end
		return best
	end

	function Flow.countReady()
		local n = 0
		Flow.eachRock(function(model)
			if state.selected[model.Name] and (tonumber(model:GetAttribute("Health")) or 0) > 0 then
				n = n + 1
			end
		end)
		return n
	end

	function Flow.hasAnySelected()
		for _, on in pairs(state.selected) do
			if on then
				return true
			end
		end
		return false
	end

	function Flow.lookCF(pos, look)
		if not look or (look - pos).Magnitude < 0.08 then
			return CFrame.new(pos)
		end
		return CFrame.lookAt(pos, look)
	end

	function Flow.flyJob()
		if Flow.sellTalk then
			return nil
		end
		if Flow.sellFly and Flow.sellerStandCF() then
			local dest = Flow.sellerStandCF()
			local look = Flow.sellerPos()
			return dest, look or dest.Position, "sell"
		end
		if Flow.buyName and Flow.shopPos(Flow.buyName) then
			local pos = Flow.shopPos(Flow.buyName)
			return CFrame.new(pos + Vector3.new(0, 5, 0)), pos, "buy"
		end
		if state.huntOn and Flow.aliveHunt(Flow.huntTarget) then
			local dest = Flow.huntStandCF(Flow.huntTarget)
			local look = Flow.mobCenter(Flow.huntTarget)
			if dest and look then
				return dest, look, "hunt"
			end
		end
		if state.mineOn and Flow.aliveTarget(Flow.target) then
			local dest = Flow.standCF(Flow.target)
			local look = Flow.centerOf(Flow.target)
			if dest and look then
				return dest, look, "mine"
			end
		end
		return nil
	end

	function Flow.applyFly(dt)
		if Flow.sellTalk then
			Flow.setFlyBody(false)
			return
		end
		local dest, look = Flow.flyJob()
		if state.mineOn and Flow.target then
			pcall(Flow.pinCrit, Flow.target)
		end
		if not dest then
			Flow.setFlyBody(false)
			return
		end
		local hrp = Flow.hrp()
		if not hrp then
			return
		end
		Flow.setFlyBody(true)
		Flow.applyNoclip()
		hrp.Anchored = false
		local delta = dest.Position - hrp.Position
		local dist = delta.Magnitude
		local speed = math.max(tonumber(state.flySpeed) or 70, 8)
		local bv = Flow.holdBV()
		if dist <= 2 then
			if bv then
				bv.Velocity = Vector3.zero
			end
			hrp.CFrame = Flow.lookCF(dest.Position, look or dest.Position)
			hrp.AssemblyLinearVelocity = Vector3.zero
			return
		end
		local dir = delta.Unit
		local step = math.min(dist, speed * (dt or 0.016))
		local pos = hrp.Position + dir * step
		hrp.CFrame = Flow.lookCF(pos, look or dest.Position)
		if bv then
			bv.Velocity = dir * speed
		end
		hrp.AssemblyLinearVelocity = dir * speed
	end

	function Flow.atStand(model)
		local hrp = Flow.hrp()
		local dest = model and Flow.standCF(model)
		if not (hrp and dest) then
			return false
		end
		return (hrp.Position - dest.Position).Magnitude <= 2.4
	end

	function Flow.stopHold()
		Flow.holding = false
		local tc = Flow._tc
		if tc then
			pcall(function()
				tc.holdingM1 = false
			end)
		end
	end

	function Flow.startHold()
		if Flow.holding then
			return true
		end
		if not Flow.equipPick() then
			state.status = "没有镐"
			return false
		end
		local tool = Flow.getPickaxe()
		local tc = Flow.toolCtrl()
		if tc and tool then
			Flow.holding = true
			pcall(function()
				tc.holdingM1 = true
			end)
			task.spawn(function()
				local ok, err = pcall(function()
					tc:ToolActivated(tool)
				end)
				if not ok then
					state.status = tostring(err)
				end
				Flow.holding = false
			end)
			return true
		end
		local rf = Flow.toolRF()
		if not rf then
			state.status = "没有挖掘远程"
			return false
		end
		pcall(function()
			if tool then
				tool:Activate()
			end
			rf:InvokeServer("Pickaxe")
		end)
		return true
	end

	function Flow.tickMine()
		if state.huntOn or Flow.buyName or Flow.sellFly then
			Flow.stopHold()
			return
		end
		if not state.mineOn then
			Flow.stopHold()
			Flow.target = nil
			Flow.arriveAt = 0
			state.status = "待机"
			return
		end
		if not Flow.hasAnySelected() then
			Flow.stopHold()
			Flow.target = nil
			Flow.arriveAt = 0
			state.status = "先选石头"
			return
		end
		if not Flow.aliveTarget(Flow.target) then
			Flow.stopHold()
			Flow.target = Flow.findNearest()
			Flow.arriveAt = 0
		elseif not Flow.rockCrit(Flow.target) then
			local other = Flow.findNearest()
			if other and other ~= Flow.target and Flow.rockCrit(other) then
				Flow.stopHold()
				Flow.target = other
				Flow.arriveAt = 0
			end
		end
		if not Flow.target then
			state.status = "等待刷新  场上" .. tostring(Flow.countReady())
			return
		end
		if not Flow.atStand(Flow.target) then
			Flow.stopHold()
			Flow.arriveAt = 0
			state.status = "飞向 " .. Flow.rockLabel(Flow.target.Name)
			return
		end
		if Flow.arriveAt == 0 then
			Flow.arriveAt = os.clock()
		end
		if os.clock() - Flow.arriveAt < 0.2 then
			state.status = "到位 " .. Flow.rockLabel(Flow.target.Name)
			return
		end
		local crit = Flow.rockCrit(Flow.target)
		if crit then
			Flow.pinCrit(Flow.target)
		end
		state.status = (crit and "暴击 " or "挖掘 ") .. Flow.rockLabel(Flow.target.Name)
		Flow.startHold()
	end

	function Flow.atHuntStand(model)
		local hrp = Flow.hrp()
		local dest = model and Flow.huntStandCF(model)
		if not (hrp and dest) then
			return false
		end
		return (hrp.Position - dest.Position).Magnitude <= 2.8
	end

	function Flow.tickHunt()
		if not state.huntOn then
			Flow.huntTarget = nil
			return
		end
		if Flow.buyName or Flow.sellFly then
			return
		end
		if not Flow.hasHuntSel() then
			Flow.huntTarget = nil
			state.status = "先选怪物"
			return
		end
		if not Flow.aliveHunt(Flow.huntTarget) then
			Flow.huntTarget = Flow.findHunt()
		end
		if not Flow.huntTarget then
			state.status = "等待怪物"
			return
		end
		local kind = Flow.mobType(Flow.huntTarget)
		if not Flow.atHuntStand(Flow.huntTarget) then
			state.status = "飞向 " .. Flow.mobLabel(kind)
			return
		end
		state.status = "攻击 " .. Flow.mobLabel(kind)
		if state.mineOn then
			Flow.stopHold()
		end
	end

	function Flow.tickPot()
		if Flow.sellFly or Flow.sellTalk then
			return
		end
		if not state.potOn then
			Flow.buyName = nil
			return
		end
		local picked = nil
		for _, info in ipairs(Flow.potions) do
			if state.potSel[info.id] then
				picked = info
				local need = Flow.needPotion(info.id)
				if need == "drink" then
					Flow.buyName = nil
					state.status = "喝 " .. Flow.potLabel(info.id)
					Flow.drinkPotion(info.id)
					return
				end
				if need == "buy" then
					local pos = Flow.shopPos(info.id)
					local canBuy = pos and (info.price <= 0 or Flow.gold() >= info.price)
					if canBuy then
						Flow.buyName = info.id
						local hrp = Flow.hrp()
						if hrp and (hrp.Position - pos).Magnitude > 9 then
							state.status = "去买 " .. Flow.potLabel(info.id)
							return
						end
						local amt = math.max(1, math.min(info.maxBuy > 0 and info.maxBuy or 3, 3))
						state.status = "购买 " .. Flow.potLabel(info.id)
						Flow.buyPotion(info.id, amt)
						task.wait(0.35)
						Flow.buyName = nil
						return
					end
				end
			end
		end
		Flow.buyName = nil
		if not picked then
			if not (state.mineOn or state.huntOn) then
				state.status = "先选药水"
			end
		end
	end

	function Flow.refreshChecks()
		for name, btn in pairs(Flow.checks) do
			if btn and btn.Parent then
				local on = state.selected[name] == true
				btn.BackgroundColor3 = on and C.on or C.off
				local lab = btn:FindFirstChild("NameLab")
				local label = Flow.rockLabel(name)
				if lab then
					lab.Text = (on and "开  " or "关  ") .. label
				else
					btn.Text = (on and "开    " or "关    ") .. label
				end
			end
		end
		for _, pack in pairs(Flow.mapHeads) do
			if pack and pack.update then
				pack.update()
			end
		end
	end

	function Flow.paintCard(btn, on, text)
		if not (btn and btn.Parent) then
			return
		end
		btn.BackgroundColor3 = on and C.on or C.off
		local lab = btn:FindFirstChild("NameLab")
		if lab then
			lab.Text = (on and "开  " or "关  ") .. text
		end
	end

	function Flow.refreshHuntChecks()
		for name, btn in pairs(Flow.huntChecks) do
			Flow.paintCard(btn, state.huntSel[name] == true, Flow.mobLabel(name))
		end
	end

	function Flow.refreshPotChecks()
		for name, btn in pairs(Flow.potChecks) do
			local qty = Flow.potionQty(name)
			Flow.paintCard(btn, state.potSel[name] == true, Flow.potLabel(name) .. "  x" .. tostring(qty))
		end
	end

	function Flow.refreshSellList()
		local byKind = { ore = {}, mat = {}, rune = {} }
		for _, info in ipairs(Flow.sellItems) do
			local qty = Flow.sellQty(info)
			if (not state.sellOwned) or qty > 0 then
				local pack = byKind[info.kind]
				if pack then
					pack[#pack + 1] = info
				end
			end
		end
		local function sortPack(list)
			table.sort(list, function(a, b)
				if a.sort == b.sort then
					return a.id < b.id
				end
				if state.sellDesc then
					return a.sort > b.sort
				end
				return a.sort < b.sort
			end)
		end
		sortPack(byKind.ore)
		sortPack(byKind.mat)
		sortPack(byKind.rune)
		local fav = Flow.favMap()
		local function paintKind(kind, list)
			for i, info in ipairs(list) do
				local btn = Flow.sellChecks[info.id]
				if btn and btn.Parent then
					btn.Visible = true
					btn.LayoutOrder = i
					local on = state.sellSel[info.id] == true
					btn.BackgroundColor3 = on and C.on or C.off
					local qty = Flow.sellQty(info)
					local starred = fav[info.id] == true
					local lab = btn:FindFirstChild("NameLab")
					local meta = btn:FindFirstChild("MetaLab")
					local title = (on and "开  " or "关  ") .. info.label
					if starred then
						title = title .. "  ★"
					end
					if lab then
						lab.Text = title
						lab.TextColor3 = qty > 0 and C.text or C.dim
					end
					if meta then
						if info.kind == "ore" then
							meta.Text = tostring(info.sort) .. "x   x" .. tostring(qty)
						elseif info.kind == "mat" then
							meta.Text = string.format("%g金   x%d", info.sort, qty)
						else
							meta.Text = "x" .. tostring(qty)
						end
						meta.TextColor3 = qty > 0 and C.text or C.dim
					end
				end
			end
			for id, btn in pairs(Flow.sellChecks) do
				local info = nil
				for _, it in ipairs(Flow.sellItems) do
					if it.id == id then
						info = it
						break
					end
				end
				if info and info.kind == kind and btn and btn.Parent then
					local show = false
					for _, it in ipairs(list) do
						if it.id == id then
							show = true
							break
						end
					end
					btn.Visible = show
				end
			end
		end
		paintKind("ore", byKind.ore)
		paintKind("mat", byKind.mat)
		paintKind("rune", byKind.rune)
		for kind, pack in pairs(Flow.sellHeads) do
			if pack and pack.update then
				pack.update(#byKind[kind])
			end
			if pack and pack.body and pack.body.Visible and type(Flow.ensureSellIcons) == "function" then
				Flow.ensureSellIcons(pack.body)
			end
		end
	end

	function Flow.restoreCamOcclusion()
		if Flow.occlusionOn then
			pcall(function()
				player.DevCameraOcclusionMode = Flow.savedOcclusion or Enum.DevCameraOcclusionMode.Zoom
			end)
			Flow.occlusionOn = false
		end
	end

	function Flow.applyFreeCam()
		if Flow.sellTalk then
			return
		end
		if not (state.mineOn or state.huntOn or Flow.buyName or Flow.sellFly) then
			Flow.restoreCamOcclusion()
			return
		end
		local cam = workspace.CurrentCamera
		local hrp = Flow.hrp()
		if not (cam and hrp) then
			return
		end
		if not Flow.occlusionOn then
			pcall(function()
				Flow.savedOcclusion = player.DevCameraOcclusionMode
				player.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam
			end)
			local focus0 = hrp.Position + Vector3.new(0, 1.5, 0)
			Flow.camZoom = math.clamp((cam.CFrame.Position - focus0).Magnitude, 4, player.CameraMaxZoomDistance)
			Flow.occlusionOn = true
		end
		local focus = hrp.Position + Vector3.new(0, 1.5, 0)
		local look = cam.CFrame.LookVector
		local zoom = math.clamp(Flow.camZoom or 14, math.max(player.CameraMinZoomDistance, 2), player.CameraMaxZoomDistance)
		cam.CFrame = CFrame.lookAt(focus - look * zoom, focus)
	end

	pcall(function()
		RunService:BindToRenderStep("ForgeFly", Enum.RenderPriority.Character.Value + 5, function(dt)
			if not stillMine() then
				return
			end
			Flow.applyFly(dt)
		end)
	end)
	pcall(function()
		RunService:BindToRenderStep("ForgeCam", Enum.RenderPriority.Camera.Value + 1, function()
			if not stillMine() then
				return
			end
			Flow.applyFreeCam()
		end)
	end)
	hook(UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			local maxz = player.CameraMaxZoomDistance
			local minz = math.max(player.CameraMinZoomDistance, 2)
			Flow.camZoom = math.clamp((Flow.camZoom or 14) - input.Position.Z * 4, minz, maxz)
		end
	end))

	task.spawn(function()
		while stillMine() do
			if state.mineOn then
				local ok, err = pcall(Flow.tickMine)
				if not ok then
					state.status = tostring(err)
				end
				task.wait(0.12)
			else
				Flow.target = nil
				if not (state.huntOn or state.potOn) and (string.find(state.status, "挖掘") or string.find(state.status, "飞向") or string.find(state.status, "到位")) then
					state.status = "待机"
				end
				task.wait(0.2)
			end
		end
	end)

	task.spawn(function()
		while stillMine() do
			if state.huntOn then
				local ok, err = pcall(Flow.tickHunt)
				if not ok then
					state.status = tostring(err)
				end
				task.wait(0.12)
			else
				Flow.huntTarget = nil
				task.wait(0.2)
			end
		end
	end)

	task.spawn(function()
		while stillMine() do
			if state.potOn then
				local ok, err = pcall(Flow.tickPot)
				if not ok then
					state.status = tostring(err)
				end
				task.wait(0.45)
			else
				Flow.buyName = nil
				task.wait(0.3)
			end
		end
	end)

	task.spawn(function()
		while stillMine() do
			if state.sellOn then
				local ok, err = pcall(Flow.tickSell)
				if not ok then
					state.status = tostring(err)
				end
				task.wait(0.7)
			else
				Flow.sellFly = nil
				task.wait(0.35)
			end
		end
	end)

	task.spawn(function()
		while stillMine() do
			local mineSwing = state.mineOn and state.atkOn
			local huntSwing = state.huntOn and Flow.aliveHunt(Flow.huntTarget) and Flow.atHuntStand(Flow.huntTarget)
			if (mineSwing or huntSwing) and not Flow.swingBusy then
				Flow.swingBusy = true
				task.spawn(function()
					pcall(Flow.swingWeapon)
					Flow.swingBusy = false
				end)
			end
			task.wait(0.35)
		end
	end)

	hook(player.CharacterAdded:Connect(function()
		Flow.hoverOn = false
		Flow.clipSaved = nil
		Flow.target = nil
		Flow.huntTarget = nil
		Flow.arriveAt = 0
	end))
end

local function bindUi()
	local function corner(p, n)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, n or 6)
		c.Parent = p
	end

	local function paintOn(btn, on, label)
		btn.BackgroundColor3 = on and C.on or C.off
		btn.Text = (on and "开    " or "关    ") .. label
	end

	local window = Instance.new("Frame")
	window.BackgroundColor3 = C.bg
	window.BorderSizePixel = 0
	window.Position = UDim2.fromOffset(state.winX or 22, state.winY or 88)
	window.Size = UDim2.fromOffset(state.winW or 920, state.winH or 400)
	Flow.window = window
	window.ClipsDescendants = true
	window.ZIndex = 50
	window.Parent = screenGui
	corner(window, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.line
	stroke.Thickness = 1
	stroke.Parent = window

	local title = Instance.new("TextButton")
	title.BackgroundColor3 = C.panel
	title.BorderSizePixel = 0
	title.ZIndex = 51
	title.Size = UDim2.new(1, 0, 0, 34)
	title.Font = Enum.Font.GothamBold
	title.Text = "锻造菜单  v" .. FORGE_VERSION .. "    T"
	title.TextColor3 = C.text
	title.TextSize = 13
	title.AutoButtonColor = false
	title.Parent = window
	corner(title, 8)

	local dragging = false
	local resizing = false
	local resizeMode = "both"
	local dragStart = nil
	local startPos = nil
	local startSize = nil
	local function clampWin(w, h)
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
		return math.clamp(math.floor(w + 0.5), 640, math.max(640, vp.X - 16)), math.clamp(math.floor(h + 0.5), 280, math.max(280, vp.Y - 16))
	end
	title.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			resizing = false
			dragStart = input.Position
			startPos = window.Position
		end
	end)
	title.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
	table.insert(Flow.conns, UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		if resizing and dragStart and startSize then
			local d = input.Position - dragStart
			local w = startSize.X
			local h = startSize.Y
			if resizeMode ~= "y" then
				w = w + d.X
			end
			if resizeMode ~= "x" then
				h = h + d.Y
			end
			w, h = clampWin(w, h)
			window.Size = UDim2.fromOffset(w, h)
		elseif dragging and dragStart and startPos then
			local d = input.Position - dragStart
			window.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
	table.insert(Flow.conns, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
			resizing = false
		end
	end))

	local statusLab = Instance.new("TextLabel")
	statusLab.BackgroundColor3 = Color3.fromRGB(10, 18, 26)
	statusLab.BorderSizePixel = 0
	statusLab.ZIndex = 51
	statusLab.Position = UDim2.fromOffset(0, 34)
	statusLab.Size = UDim2.new(1, 0, 0, 22)
	statusLab.Font = Enum.Font.Gotham
	statusLab.Text = "待机"
	statusLab.TextColor3 = Color3.fromRGB(120, 210, 160)
	statusLab.TextSize = 12
	statusLab.Parent = window

	local left = Instance.new("ScrollingFrame")
	left.BackgroundTransparency = 1
	left.BorderSizePixel = 0
	left.ZIndex = 51
	left.Position = UDim2.fromOffset(8, 64)
	left.Size = UDim2.new(0, 92, 1, -20)
	left.CanvasSize = UDim2.new(0, 0, 0, 0)
	left.AutomaticCanvasSize = Enum.AutomaticSize.Y
	left.ScrollBarThickness = 2
	left.ScrollBarImageColor3 = C.line
	left.Parent = window
	local leftList = Instance.new("UIListLayout")
	leftList.Padding = UDim.new(0, 6)
	leftList.SortOrder = Enum.SortOrder.LayoutOrder
	leftList.Parent = left

	local function mkCat(text, order)
		local b = Instance.new("TextButton")
		b.BackgroundColor3 = C.tab
		b.BorderSizePixel = 0
		b.Font = Enum.Font.GothamBold
		b.Text = text
		b.TextColor3 = C.text
		b.TextSize = 12
		b.Size = UDim2.new(1, -4, 0, 28)
		b.LayoutOrder = order
		b.AutoButtonColor = true
		b.Parent = left
		corner(b, 4)
		return b
	end
	local catAuto = mkCat("自动化", 1)
	local catHunt = mkCat("打怪", 2)
	local catPot = mkCat("药水", 3)
	local catSell = mkCat("出售", 4)
	local catGuide = mkCat("锻造指南", 5)
	local catOther = mkCat("其他", 6)

	local right = Instance.new("Frame")
	right.BackgroundTransparency = 1
	right.ZIndex = 51
	right.Position = UDim2.fromOffset(108, 64)
	right.Size = UDim2.new(1, -116, 1, -20)
	right.Parent = window

	local function mkPage()
		local page = Instance.new("ScrollingFrame")
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.ZIndex = 51
		page.Size = UDim2.fromScale(1, 1)
		page.CanvasSize = UDim2.new(0, 0, 0, 0)
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		page.ScrollBarThickness = 4
		page.ScrollBarImageColor3 = C.line
		page.Parent = right
		local pageList = Instance.new("UIListLayout")
		pageList.Padding = UDim.new(0, 6)
		pageList.SortOrder = Enum.SortOrder.LayoutOrder
		pageList.Parent = page
		return page
	end
	local scroll = mkPage()
	local huntPage = mkPage()
	local potPage = mkPage()
	local sellPage = mkPage()
	local guidePage = mkPage()
	local otherPage = mkPage()
	huntPage.Visible = false
	potPage.Visible = false
	sellPage.Visible = false
	guidePage.Visible = false
	otherPage.Visible = false

	local function showPage(name)
		state.page = name
		scroll.Visible = name == "auto"
		huntPage.Visible = name == "hunt"
		potPage.Visible = name == "pot"
		sellPage.Visible = name == "sell"
		guidePage.Visible = name == "guide"
		otherPage.Visible = name == "other"
		catAuto.BackgroundColor3 = name == "auto" and C.tab or C.btn
		catHunt.BackgroundColor3 = name == "hunt" and C.tab or C.btn
		catPot.BackgroundColor3 = name == "pot" and C.tab or C.btn
		catSell.BackgroundColor3 = name == "sell" and C.tab or C.btn
		catGuide.BackgroundColor3 = name == "guide" and C.tab or C.btn
		catOther.BackgroundColor3 = name == "other" and C.tab or C.btn
		if name == "pot" then
			Flow.refreshPotChecks()
		end
		if name == "sell" then
			Flow.refreshSellList()
		end
		if name == "guide" and Flow.ensureGuideIcons then
			Flow.ensureGuideIcons()
		elseif name ~= "guide" and Flow.hideGuideOverlay then
			Flow.hideGuideOverlay()
		end
	end
	showPage("auto")
	catAuto.MouseButton1Click:Connect(function()
		showPage("auto")
	end)
	catHunt.MouseButton1Click:Connect(function()
		showPage("hunt")
	end)
	catPot.MouseButton1Click:Connect(function()
		showPage("pot")
	end)
	catSell.MouseButton1Click:Connect(function()
		showPage("sell")
	end)
	catGuide.MouseButton1Click:Connect(function()
		showPage("guide")
	end)
	catOther.MouseButton1Click:Connect(function()
		showPage("other")
	end)

	local function mkBtn(parent, text, order, h)
		local b = Instance.new("TextButton")
		b.BackgroundColor3 = C.btn
		b.BorderSizePixel = 0
		b.Font = Enum.Font.Gotham
		b.Text = "关    " .. text
		b.TextColor3 = C.text
		b.TextSize = 13
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.Size = UDim2.new(1, 0, 0, h or 28)
		b.LayoutOrder = order or 0
		b.AutoButtonColor = true
		b.Parent = parent
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.Parent = b
		corner(b, 4)
		return b
	end

	local function findAsset(kind, name)
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		if not assets then
			return nil
		end
		if kind == "Mob" then
			local folder = assets:FindFirstChild("Mobs")
			local alias = Flow.mobAsset[name]
			return folder and (folder:FindFirstChild(alias or name) or folder:FindFirstChild(name) or folder:FindFirstChild((string.gsub(name, " ", ""))))
		end
		if kind == "Potion" then
			local extras = assets:FindFirstChild("Extras")
			local folder = extras and extras:FindFirstChild("Potion")
			return folder and (folder:FindFirstChild(name) or folder:FindFirstChild(name .. "2"))
		end
		if kind == "Ore" then
			local folder = assets:FindFirstChild("Ores")
			return folder and folder:FindFirstChild(name, true)
		end
		if kind == "Material" then
			local extras = assets:FindFirstChild("Extras")
			local folders = {
				assets:FindFirstChild("Materials"),
				extras and extras:FindFirstChild("Material"),
				extras and extras:FindFirstChild("Essence"),
				extras and extras:FindFirstChild("Materials"),
			}
			for _, folder in ipairs(folders) do
				if folder then
					local found = folder:FindFirstChild(name, true) or folder:FindFirstChild((string.gsub(name, " ", "")), true)
					if found then
						return found
					end
				end
			end
			return nil
		end
		if kind == "Rune" then
			local extras = assets:FindFirstChild("Extras")
			local folders = {
				assets:FindFirstChild("Runes"),
				extras and extras:FindFirstChild("Rune"),
				extras and extras:FindFirstChild("Runes"),
			}
			local short = string.match(name, "^(.-)_T%d+$") or name
			for _, folder in ipairs(folders) do
				if folder then
					local found = folder:FindFirstChild(name, true) or folder:FindFirstChild(short, true)
					if found then
						return found
					end
				end
			end
			return nil
		end
		local folder = assets:FindFirstChild("Rocks")
		return folder and folder:FindFirstChild(name)
	end

	local function aimViewport(vf, model)
		local cam = vf and vf.CurrentCamera
		if not (cam and model and model.Parent) then
			return
		end
		local ok, cf, size = pcall(function()
			return model:GetBoundingBox()
		end)
		if not (ok and cf and size) then
			return
		end
		local abs = vf.AbsoluteSize
		local aspect = (abs.X > 2 and abs.Y > 2) and (abs.X / abs.Y) or 1
		cam.FieldOfView = 1
		local yFov2 = math.rad(cam.FieldOfView / 2)
		local tany = math.tan(yFov2)
		local cFov2 = math.atan(tany * math.min(1, aspect))
		local dist = (size.Magnitude / 2) / math.max(math.sin(cFov2), 1e-6)
		cam.CFrame = CFrame.new(cf.Position) * CFrame.fromEulerAnglesYXZ(math.rad(-20), 0, math.rad(10)) * CFrame.new(0, 0, dist)
	end

	local function fillRockIcon(vf, rockName, kind)
		local src = findAsset(kind or "Rock", rockName)
		if not (vf and src) then
			return
		end
		for _, child in ipairs(vf:GetChildren()) do
			if child:IsA("WorldModel") or child:IsA("Camera") or child:IsA("Model") or child:IsA("ImageLabel") then
				child:Destroy()
			end
		end
		local model
		if src:IsA("Model") then
			model = src:Clone()
		else
			model = Instance.new("Model")
			local part = src:Clone()
			part.Parent = model
			model.PrimaryPart = part:IsA("BasePart") and part or nil
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		local usedGame = false
		pcall(function()
			local knit = require(ReplicatedStorage.Shared.Packages.Knit)
			local vp = knit.GetController("UIController").Modules.Viewport
			if vp and vp.new then
				vp.new(vf, model)
				usedGame = true
			end
		end)
		if usedGame then
			task.defer(aimViewport, vf, model)
			return
		end
		model.Parent = vf
		local cam = Instance.new("Camera")
		cam.FieldOfView = 1
		cam.Parent = vf
		vf.CurrentCamera = cam
		aimViewport(vf, model)
		task.defer(aimViewport, vf, model)
	end

	local function fillGearIcon(vf, gearType, oreName)
		if not (vf and type(gearType) == "string") then
			return
		end
		local model
		pcall(function()
			local Equipments = require(ReplicatedStorage.Shared.Data.Equipments)
			if Equipments and Equipments.GetItemModel then
				model = Equipments:GetItemModel({
					Type = gearType,
					Name = gearType,
					Ore = oreName,
					Quality = 80,
				})
			end
		end)
		if not model then
			fillRockIcon(vf, oreName, "Ore")
			return
		end
		for _, child in ipairs(vf:GetChildren()) do
			if child:IsA("WorldModel") or child:IsA("Camera") or child:IsA("Model") or child:IsA("ImageLabel") then
				child:Destroy()
			end
		end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") then
				d:Destroy()
			elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
				d.Enabled = false
			elseif d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		local usedGame = false
		pcall(function()
			local knit = require(ReplicatedStorage.Shared.Packages.Knit)
			local vp = knit.GetController("UIController").Modules.Viewport
			if vp and vp.new then
				vp.new(vf, model, nil, {
					Fit = true,
					Z = 55,
				})
				usedGame = true
			end
		end)
		if usedGame then
			task.defer(aimViewport, vf, model)
			return
		end
		model.Parent = vf
		local cam = Instance.new("Camera")
		cam.FieldOfView = 1
		cam.Parent = vf
		vf.CurrentCamera = cam
		aimViewport(vf, model)
		task.defer(aimViewport, vf, model)
	end

	local function fillSellIcon(vf, info)
		if not (vf and info) or vf:GetAttribute("Filled") then
			return
		end
		vf:SetAttribute("Filled", true)
		local kind = info.kind == "ore" and "Ore" or (info.kind == "mat" and "Material" or "Rune")
		fillRockIcon(vf, info.id, kind)
		if vf.CurrentCamera or vf:FindFirstChildOfClass("Model") or vf:FindFirstChildOfClass("WorldModel") then
			return
		end
		if type(info.icon) == "string" and info.icon ~= "" then
			local img = Instance.new("ImageLabel")
			img.BackgroundTransparency = 1
			img.BorderSizePixel = 0
			img.Image = info.icon
			img.ScaleType = Enum.ScaleType.Fit
			img.Size = UDim2.fromScale(1, 1)
			img.Parent = vf
		end
	end

	local function ensureSellIcons(body)
		if not body then
			return
		end
		for _, child in ipairs(body:GetChildren()) do
			if child:IsA("GuiButton") and child.Visible then
				local vf = child:FindFirstChildOfClass("ViewportFrame")
				local id = child:GetAttribute("SellId")
				if vf and id then
					for _, info in ipairs(Flow.sellItems) do
						if info.id == id then
							fillSellIcon(vf, info)
							break
						end
					end
				end
			end
		end
	end
	Flow.ensureSellIcons = ensureSellIcons

	local function mkRock(parent, rockName, order)
		local b = Instance.new("TextButton")
		b.BackgroundColor3 = C.off
		b.BorderSizePixel = 0
		b.Text = ""
		b.AutoButtonColor = true
		b.Size = UDim2.fromOffset(104, 128)
		b.LayoutOrder = order or 0
		b.Parent = parent
		corner(b, 6)
		local icon = Instance.new("ViewportFrame")
		icon.BackgroundColor3 = Color3.fromRGB(14, 22, 32)
		icon.BorderSizePixel = 0
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 6)
		icon.Size = UDim2.fromOffset(88, 88)
		icon.LightColor = Color3.fromRGB(255, 255, 255)
		icon.Ambient = Color3.fromRGB(170, 170, 170)
		icon.LightDirection = Vector3.new(-1, -1, -1)
		icon.Parent = b
		corner(icon, 6)
		fillRockIcon(icon, rockName, "Rock")
		local lab = Instance.new("TextLabel")
		lab.Name = "NameLab"
		lab.BackgroundTransparency = 1
		lab.Font = Enum.Font.Gotham
		lab.Text = "关  " .. Flow.rockLabel(rockName)
		lab.TextColor3 = C.text
		lab.TextSize = 11
		lab.TextWrapped = true
		lab.TextXAlignment = Enum.TextXAlignment.Center
		lab.TextYAlignment = Enum.TextYAlignment.Top
		lab.Position = UDim2.fromOffset(4, 96)
		lab.Size = UDim2.new(1, -8, 0, 28)
		lab.Parent = b
		return b
	end

	local function mkCard(parent, key, label, kind, order)
		local b = Instance.new("TextButton")
		b.BackgroundColor3 = C.off
		b.BorderSizePixel = 0
		b.Text = ""
		b.AutoButtonColor = true
		b.Size = UDim2.fromOffset(104, 128)
		b.LayoutOrder = order or 0
		b.Parent = parent
		corner(b, 6)
		local icon = Instance.new("ViewportFrame")
		icon.BackgroundColor3 = Color3.fromRGB(14, 22, 32)
		icon.BorderSizePixel = 0
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 6)
		icon.Size = UDim2.fromOffset(88, 88)
		icon.LightColor = Color3.fromRGB(255, 255, 255)
		icon.Ambient = Color3.fromRGB(170, 170, 170)
		icon.LightDirection = Vector3.new(-1, -1, -1)
		icon.Parent = b
		corner(icon, 6)
		fillRockIcon(icon, key, kind)
		local lab = Instance.new("TextLabel")
		lab.Name = "NameLab"
		lab.BackgroundTransparency = 1
		lab.Font = Enum.Font.Gotham
		lab.Text = "关  " .. label
		lab.TextColor3 = C.text
		lab.TextSize = 11
		lab.TextWrapped = true
		lab.TextXAlignment = Enum.TextXAlignment.Center
		lab.TextYAlignment = Enum.TextYAlignment.Top
		lab.Position = UDim2.fromOffset(4, 96)
		lab.Size = UDim2.new(1, -8, 0, 28)
		lab.Parent = b
		return b
	end

	local function mkSellCard(parent, info, order)
		local kind = info.kind == "ore" and "Ore" or (info.kind == "mat" and "Material" or "Rune")
		local b = mkCard(parent, info.id, info.label, kind, order)
		b.Size = UDim2.fromOffset(104, 142)
		b:SetAttribute("SellId", info.id)
		b:SetAttribute("SellKind", info.kind)
		local lab = b:FindFirstChild("NameLab")
		if lab then
			lab.Position = UDim2.fromOffset(4, 94)
			lab.Size = UDim2.new(1, -8, 0, 22)
		end
		local meta = Instance.new("TextLabel")
		meta.Name = "MetaLab"
		meta.BackgroundTransparency = 1
		meta.Font = Enum.Font.Gotham
		meta.Text = ""
		meta.TextColor3 = C.dim
		meta.TextSize = 11
		meta.TextXAlignment = Enum.TextXAlignment.Center
		meta.Position = UDim2.fromOffset(4, 116)
		meta.Size = UDim2.new(1, -8, 0, 22)
		meta.Parent = b
		local vf = b:FindFirstChildOfClass("ViewportFrame")
		if vf then
			vf:SetAttribute("Filled", false)
			for _, child in ipairs(vf:GetChildren()) do
				child:Destroy()
			end
			vf.CurrentCamera = nil
		end
		return b
	end

	local function mkRow(parent, titleText, value, order, size)
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = size or UDim2.new(1, 0, 0, 40)
		row.LayoutOrder = order or 0
		row.Parent = parent
		local lab = Instance.new("TextLabel")
		lab.BackgroundTransparency = 1
		lab.Font = Enum.Font.Gotham
		lab.Text = titleText
		lab.TextColor3 = C.dim
		lab.TextSize = 11
		lab.TextXAlignment = Enum.TextXAlignment.Left
		lab.Size = UDim2.new(1, 0, 0, 13)
		lab.Parent = row
		local minus = Instance.new("TextButton")
		minus.BackgroundColor3 = C.btn
		minus.BorderSizePixel = 0
		minus.Font = Enum.Font.GothamBold
		minus.Text = "-"
		minus.TextColor3 = C.text
		minus.TextSize = 14
		minus.Position = UDim2.fromOffset(0, 14)
		minus.Size = UDim2.fromOffset(28, 24)
		minus.Parent = row
		corner(minus, 4)
		local box = Instance.new("TextBox")
		box.BackgroundColor3 = Color3.fromRGB(14, 22, 32)
		box.BorderSizePixel = 0
		box.Font = Enum.Font.Gotham
		box.Text = value
		box.TextColor3 = C.text
		box.TextSize = 13
		box.Position = UDim2.fromOffset(32, 14)
		box.Size = UDim2.new(1, -64, 0, 24)
		box.ClearTextOnFocus = false
		box.Parent = row
		corner(box, 4)
		local plus = Instance.new("TextButton")
		plus.BackgroundColor3 = C.btn
		plus.BorderSizePixel = 0
		plus.Font = Enum.Font.GothamBold
		plus.Text = "+"
		plus.TextColor3 = C.text
		plus.TextSize = 14
		plus.AnchorPoint = Vector2.new(1, 0)
		plus.Position = UDim2.new(1, 0, 0, 14)
		plus.Size = UDim2.fromOffset(28, 24)
		plus.Parent = row
		corner(plus, 4)
		return { box = box, minus = minus, plus = plus, frame = row }
	end

	local function bindNum(row, getv, setv, step, lo, hi)
		local function apply(n)
			n = math.clamp(tonumber(n) or getv(), lo, hi)
			setv(n)
			row.box.Text = tostring(n)
		end
		row.minus.MouseButton1Click:Connect(function()
			apply(getv() - step)
		end)
		row.plus.MouseButton1Click:Connect(function()
			apply(getv() + step)
		end)
		row.box.FocusLost:Connect(function()
			apply(row.box.Text)
		end)
	end

	local mineBtn = mkBtn(scroll, "自动挖矿", 1)
	local atkBtn = mkBtn(scroll, "打怪", 2)
	paintOn(atkBtn, state.atkOn, "打怪")
	local atkHint = Instance.new("TextLabel")
	atkHint.BackgroundTransparency = 1
	atkHint.Font = Enum.Font.Gotham
	atkHint.Text = "和自动挖矿绑在一起：边挖边挥刀，不换镐。没开挖矿不会挥。"
	atkHint.TextColor3 = C.dim
	atkHint.TextSize = 11
	atkHint.TextXAlignment = Enum.TextXAlignment.Left
	atkHint.TextWrapped = true
	atkHint.Size = UDim2.new(1, 0, 0, 18)
	atkHint.LayoutOrder = 3
	atkHint.Parent = scroll
	local nums = Instance.new("Frame")
	nums.BackgroundTransparency = 1
	nums.Size = UDim2.new(1, 0, 0, 40)
	nums.LayoutOrder = 4
	nums.Parent = scroll
	local speedRow = mkRow(nums, "飞行速度", tostring(state.flySpeed), 1, UDim2.new(0.32, 0, 1, 0))
	local distRow = mkRow(nums, "站位距离", tostring(state.standDist), 2, UDim2.new(0.32, 0, 1, 0))
	local yawRow = mkRow(nums, "上下朝向  +空中 / -地下", tostring(state.standPitch), 3, UDim2.new(0.32, 0, 1, 0))
	speedRow.frame.Position = UDim2.fromScale(0, 0)
	distRow.frame.Position = UDim2.fromScale(0.34, 0)
	yawRow.frame.Position = UDim2.fromScale(0.68, 0)
	bindNum(speedRow, function()
		return state.flySpeed
	end, function(v)
		state.flySpeed = v
	end, 5, 8, 160)
	bindNum(distRow, function()
		return state.standDist
	end, function(v)
		state.standDist = v
	end, 0.5, 2, 24)
	bindNum(yawRow, function()
		return state.standPitch
	end, function(v)
		state.standPitch = v
	end, 15, -90, 90)

	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.Gotham
	hint.Text = "上下朝向：正数在空中往下挖，负数在地下往上挖。"
	hint.TextColor3 = C.dim
	hint.TextSize = 11
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.TextWrapped = true
	hint.Size = UDim2.new(1, 0, 0, 28)
	hint.LayoutOrder = 5
	hint.Parent = scroll

	local function selectedCount(map)
		local n = 0
		for _, name in ipairs(map.rocks) do
			if state.selected[name] then
				n = n + 1
			end
		end
		return n
	end

	local here = Flow.placeMap[game.PlaceId] or 3
	state.openMap = here

	for i, map in ipairs(Flow.maps) do
		local wrap = Instance.new("Frame")
		wrap.BackgroundTransparency = 1
		wrap.AutomaticSize = Enum.AutomaticSize.Y
		wrap.Size = UDim2.new(1, 0, 0, 32)
		wrap.LayoutOrder = 10 + i
		wrap.Parent = scroll
		local wrapList = Instance.new("UIListLayout")
		wrapList.Padding = UDim.new(0, 4)
		wrapList.SortOrder = Enum.SortOrder.LayoutOrder
		wrapList.Parent = wrap

		local head = Instance.new("TextButton")
		head.BackgroundColor3 = C.panel
		head.BorderSizePixel = 0
		head.Font = Enum.Font.GothamBold
		head.TextColor3 = C.text
		head.TextSize = 13
		head.TextXAlignment = Enum.TextXAlignment.Left
		head.Size = UDim2.new(1, 0, 0, 32)
		head.LayoutOrder = 1
		head.AutoButtonColor = true
		head.Parent = wrap
		local hpad = Instance.new("UIPadding")
		hpad.PaddingLeft = UDim.new(0, 10)
		hpad.Parent = head
		corner(head, 4)

		local body = Instance.new("Frame")
		body.BackgroundTransparency = 1
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.Size = UDim2.new(1, 0, 0, 0)
		body.LayoutOrder = 2
		body.Visible = state.openMap == map.id
		body.Parent = wrap
		local bodyList = Instance.new("UIListLayout")
		bodyList.Padding = UDim.new(0, 4)
		bodyList.SortOrder = Enum.SortOrder.LayoutOrder
		bodyList.Parent = body

		local act = Instance.new("Frame")
		act.BackgroundTransparency = 1
		act.Size = UDim2.new(1, 0, 0, 26)
		act.LayoutOrder = 1
		act.Parent = body
		local allBtn = Instance.new("TextButton")
		allBtn.BackgroundColor3 = C.btn
		allBtn.BorderSizePixel = 0
		allBtn.Font = Enum.Font.Gotham
		allBtn.Text = "全选本图"
		allBtn.TextColor3 = C.text
		allBtn.TextSize = 12
		allBtn.Size = UDim2.new(0.5, -3, 1, 0)
		allBtn.Parent = act
		corner(allBtn, 4)
		local noneBtn = Instance.new("TextButton")
		noneBtn.BackgroundColor3 = C.btn
		noneBtn.BorderSizePixel = 0
		noneBtn.Font = Enum.Font.Gotham
		noneBtn.Text = "清空本图"
		noneBtn.TextColor3 = C.text
		noneBtn.TextSize = 12
		noneBtn.Position = UDim2.new(0.5, 3, 0, 0)
		noneBtn.Size = UDim2.new(0.5, -3, 1, 0)
		noneBtn.Parent = act
		corner(noneBtn, 4)

		local grid = Instance.new("Frame")
		grid.BackgroundTransparency = 1
		grid.AutomaticSize = Enum.AutomaticSize.Y
		grid.Size = UDim2.new(1, 0, 0, 0)
		grid.LayoutOrder = 2
		grid.Parent = body
		local gridLay = Instance.new("UIGridLayout")
		gridLay.CellPadding = UDim2.fromOffset(6, 6)
		gridLay.CellSize = UDim2.fromOffset(104, 128)
		gridLay.FillDirection = Enum.FillDirection.Horizontal
		gridLay.HorizontalAlignment = Enum.HorizontalAlignment.Left
		gridLay.SortOrder = Enum.SortOrder.LayoutOrder
		gridLay.Parent = grid

		for ri, rockName in ipairs(map.rocks) do
			local cb = mkRock(grid, rockName, 10 + ri)
			Flow.checks[rockName] = cb
			cb.MouseButton1Click:Connect(function()
				state.selected[rockName] = not state.selected[rockName]
				Flow.refreshChecks()
			end)
		end

		local function updateHead()
			local n = selectedCount(map)
			local mark = body.Visible and "▾" or "▸"
			head.Text = mark .. "  " .. map.title .. "    " .. n .. "/" .. #map.rocks
		end
		Flow.mapHeads[map.id] = { update = updateHead, body = body }
		updateHead()

		head.MouseButton1Click:Connect(function()
			if state.openMap == map.id then
				state.openMap = nil
				body.Visible = false
			else
				state.openMap = map.id
				for id, pack in pairs(Flow.mapHeads) do
					if pack.body then
						pack.body.Visible = id == map.id
					end
					if pack.update then
						pack.update()
					end
				end
				return
			end
			updateHead()
		end)
		allBtn.MouseButton1Click:Connect(function()
			for _, name in ipairs(map.rocks) do
				state.selected[name] = true
			end
			Flow.refreshChecks()
		end)
		noneBtn.MouseButton1Click:Connect(function()
			for _, name in ipairs(map.rocks) do
				state.selected[name] = nil
			end
			Flow.refreshChecks()
		end)
	end

	local openPack = Flow.mapHeads[here]
	if openPack and openPack.body then
		openPack.body.Visible = true
		if openPack.update then
			openPack.update()
		end
	end

	local function mkPlain(parent, text, order, color)
		local b = Instance.new("TextButton")
		b.BackgroundColor3 = color or C.btn
		b.BorderSizePixel = 0
		b.Font = Enum.Font.GothamBold
		b.Text = text
		b.TextColor3 = C.text
		b.TextSize = 13
		b.Size = UDim2.new(1, 0, 0, 32)
		b.LayoutOrder = order
		b.AutoButtonColor = true
		b.Parent = parent
		corner(b, 4)
		return b
	end

	local function mkAct(parent, order)
		local act = Instance.new("Frame")
		act.BackgroundTransparency = 1
		act.Size = UDim2.new(1, 0, 0, 26)
		act.LayoutOrder = order
		act.Parent = parent
		return act
	end

	local huntBtn = mkBtn(huntPage, "自动打怪", 1)
	paintOn(huntBtn, state.huntOn, "自动打怪")
	local huntHint = Instance.new("TextLabel")
	huntHint.BackgroundTransparency = 1
	huntHint.Font = Enum.Font.Gotham
	huntHint.Text = "站在怪正上方挥刀，高度拉开躲开近战。可多选或单选本岛怪物。"
	huntHint.TextColor3 = C.dim
	huntHint.TextSize = 11
	huntHint.TextXAlignment = Enum.TextXAlignment.Left
	huntHint.TextWrapped = true
	huntHint.Size = UDim2.new(1, 0, 0, 28)
	huntHint.LayoutOrder = 2
	huntHint.Parent = huntPage
	local huntNums = Instance.new("Frame")
	huntNums.BackgroundTransparency = 1
	huntNums.Size = UDim2.new(1, 0, 0, 40)
	huntNums.LayoutOrder = 3
	huntNums.Parent = huntPage
	local heightRow = mkRow(huntNums, "头顶高度", tostring(state.huntHeight), 1, UDim2.new(0.48, 0, 1, 0))
	bindNum(heightRow, function()
		return state.huntHeight
	end, function(v)
		state.huntHeight = v
	end, 1, 8, 28)
	local huntAct = mkAct(huntPage, 4)
	local huntAll = mkPlain(huntAct, "全选本岛", 1, C.btn)
	huntAll.Size = UDim2.new(0.33, -4, 1, 0)
	local huntNone = mkPlain(huntAct, "清空", 2, C.btn)
	huntNone.Size = UDim2.new(0.33, -4, 1, 0)
	huntNone.Position = UDim2.new(0.33, 2, 0, 0)
	local modeBtn = mkPlain(huntAct, state.huntSingle and "单选" or "多选", 3, C.tab)
	modeBtn.Size = UDim2.new(0.34, -4, 1, 0)
	modeBtn.Position = UDim2.new(0.66, 4, 0, 0)
	local huntGrid = Instance.new("Frame")
	huntGrid.BackgroundTransparency = 1
	huntGrid.AutomaticSize = Enum.AutomaticSize.Y
	huntGrid.Size = UDim2.new(1, 0, 0, 0)
	huntGrid.LayoutOrder = 5
	huntGrid.Parent = huntPage
	local huntLay = Instance.new("UIGridLayout")
	huntLay.CellPadding = UDim2.fromOffset(6, 6)
	huntLay.CellSize = UDim2.fromOffset(104, 128)
	huntLay.FillDirection = Enum.FillDirection.Horizontal
	huntLay.SortOrder = Enum.SortOrder.LayoutOrder
	huntLay.Parent = huntGrid
	local islandMobs = Flow.mobsByMap[here] or Flow.mobsByMap[3]
	for i, mobName in ipairs(islandMobs) do
		local cb = mkCard(huntGrid, mobName, Flow.mobLabel(mobName), "Mob", i)
		Flow.huntChecks[mobName] = cb
		cb.MouseButton1Click:Connect(function()
			if state.huntSingle then
				local on = state.huntSel[mobName] ~= true
				state.huntSel = {}
				if on then
					state.huntSel[mobName] = true
				end
			else
				state.huntSel[mobName] = not state.huntSel[mobName]
			end
			Flow.refreshHuntChecks()
		end)
	end
	Flow.refreshHuntChecks()
	huntAll.MouseButton1Click:Connect(function()
		state.huntSingle = false
		modeBtn.Text = "多选"
		for _, name in ipairs(islandMobs) do
			state.huntSel[name] = true
		end
		Flow.refreshHuntChecks()
	end)
	huntNone.MouseButton1Click:Connect(function()
		state.huntSel = {}
		Flow.refreshHuntChecks()
	end)
	modeBtn.MouseButton1Click:Connect(function()
		state.huntSingle = not state.huntSingle
		modeBtn.Text = state.huntSingle and "单选" or "多选"
		if state.huntSingle then
			local keep = nil
			for _, name in ipairs(islandMobs) do
				if state.huntSel[name] then
					keep = name
					break
				end
			end
			state.huntSel = {}
			if keep then
				state.huntSel[keep] = true
			end
			Flow.refreshHuntChecks()
		end
	end)

	local potBtn = mkBtn(potPage, "自动喝药", 1)
	paintOn(potBtn, state.potOn, "自动喝药")
	local potHint = Instance.new("TextLabel")
	potHint.BackgroundTransparency = 1
	potHint.Font = Enum.Font.Gotham
	potHint.Text = "选中的药水会自动喝。生命药水只在血量低于 82% 时喝。喝完飞去本岛商店买。"
	potHint.TextColor3 = C.dim
	potHint.TextSize = 11
	potHint.TextXAlignment = Enum.TextXAlignment.Left
	potHint.TextWrapped = true
	potHint.Size = UDim2.new(1, 0, 0, 28)
	potHint.LayoutOrder = 2
	potHint.Parent = potPage
	local potAct = mkAct(potPage, 3)
	local potAll = mkPlain(potAct, "全选", 1, C.btn)
	potAll.Size = UDim2.new(0.5, -3, 1, 0)
	local potNone = mkPlain(potAct, "清空", 2, C.btn)
	potNone.Size = UDim2.new(0.5, -3, 1, 0)
	potNone.Position = UDim2.new(0.5, 3, 0, 0)
	local potGrid = Instance.new("Frame")
	potGrid.BackgroundTransparency = 1
	potGrid.AutomaticSize = Enum.AutomaticSize.Y
	potGrid.Size = UDim2.new(1, 0, 0, 0)
	potGrid.LayoutOrder = 4
	potGrid.Parent = potPage
	local potLay = Instance.new("UIGridLayout")
	potLay.CellPadding = UDim2.fromOffset(6, 6)
	potLay.CellSize = UDim2.fromOffset(104, 128)
	potLay.FillDirection = Enum.FillDirection.Horizontal
	potLay.SortOrder = Enum.SortOrder.LayoutOrder
	potLay.Parent = potGrid
	for i, info in ipairs(Flow.potions) do
		local qty = Flow.potionQty(info.id)
		local cb = mkCard(potGrid, info.id, Flow.potLabel(info.id) .. "  x" .. tostring(qty), "Potion", i)
		Flow.potChecks[info.id] = cb
		cb.MouseButton1Click:Connect(function()
			state.potSel[info.id] = not state.potSel[info.id]
			Flow.refreshPotChecks()
		end)
	end
	Flow.refreshPotChecks()
	potAll.MouseButton1Click:Connect(function()
		for _, info in ipairs(Flow.potions) do
			state.potSel[info.id] = true
		end
		Flow.refreshPotChecks()
	end)
	potNone.MouseButton1Click:Connect(function()
		state.potSel = {}
		Flow.refreshPotChecks()
	end)

	local sellBtn = mkBtn(sellPage, "自动出售", 1)
	paintOn(sellBtn, state.sellOn, "自动出售")
	local sellHint = Instance.new("TextLabel")
	sellHint.BackgroundTransparency = 1
	sellHint.Font = Enum.Font.Gotham
	sellHint.Text = "勾好要卖的。挖矿或打怪时按间隔飞去商人卖一次，收藏的不卖。"
	sellHint.TextColor3 = C.dim
	sellHint.TextSize = 11
	sellHint.TextXAlignment = Enum.TextXAlignment.Left
	sellHint.TextWrapped = true
	sellHint.Size = UDim2.new(1, 0, 0, 28)
	sellHint.LayoutOrder = 2
	sellHint.Parent = sellPage
	local sellNums = Instance.new("Frame")
	sellNums.BackgroundTransparency = 1
	sellNums.Size = UDim2.new(1, 0, 0, 40)
	sellNums.LayoutOrder = 3
	sellNums.Parent = sellPage
	local waitRow = mkRow(sellNums, "出售间隔(秒)", tostring(state.sellWait), 1, UDim2.new(0.48, 0, 1, 0))
	bindNum(waitRow, function()
		return Flow.sellInterval()
	end, function(v)
		state.sellWait = v
		if state.sellOn and Flow.farmOn() and not Flow.sellFly then
			Flow.nextSellAt = os.clock() + v
		end
	end, 10, 10, 600)
	local sellAct = mkAct(sellPage, 4)
	local sortBtn = mkPlain(sellAct, state.sellDesc and "排序 高→低" or "排序 低→高", 1, C.tab)
	sortBtn.Size = UDim2.new(0.34, -3, 1, 0)
	local ownedBtn = mkPlain(sellAct, state.sellOwned and "只看身上" or "显示全部", 2, C.btn)
	ownedBtn.Size = UDim2.new(0.33, -2, 1, 0)
	ownedBtn.Position = UDim2.new(0.34, 1, 0, 0)
	local sellAll = mkPlain(sellAct, "全选", 3, C.btn)
	sellAll.Size = UDim2.new(0.165, -2, 1, 0)
	sellAll.Position = UDim2.new(0.67, 2, 0, 0)
	local sellNone = mkPlain(sellAct, "清空", 4, C.btn)
	sellNone.Size = UDim2.new(0.165, -2, 1, 0)
	sellNone.Position = UDim2.new(0.835, 2, 0, 0)

	local sellCats = {
		{ id = "ore", title = "矿石", order = 5 },
		{ id = "mat", title = "材料", order = 6 },
		{ id = "rune", title = "符文", order = 7 },
	}
	for _, cat in ipairs(sellCats) do
		local wrap = Instance.new("Frame")
		wrap.BackgroundTransparency = 1
		wrap.AutomaticSize = Enum.AutomaticSize.Y
		wrap.Size = UDim2.new(1, 0, 0, 32)
		wrap.LayoutOrder = cat.order
		wrap.Parent = sellPage
		local wrapList = Instance.new("UIListLayout")
		wrapList.Padding = UDim.new(0, 4)
		wrapList.SortOrder = Enum.SortOrder.LayoutOrder
		wrapList.Parent = wrap
		local head = Instance.new("TextButton")
		head.BackgroundColor3 = C.panel
		head.BorderSizePixel = 0
		head.Font = Enum.Font.GothamBold
		head.TextColor3 = C.text
		head.TextSize = 13
		head.TextXAlignment = Enum.TextXAlignment.Left
		head.Size = UDim2.new(1, 0, 0, 32)
		head.LayoutOrder = 1
		head.AutoButtonColor = true
		head.Parent = wrap
		local hpad = Instance.new("UIPadding")
		hpad.PaddingLeft = UDim.new(0, 10)
		hpad.Parent = head
		corner(head, 4)
		local body = Instance.new("Frame")
		body.BackgroundTransparency = 1
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.Size = UDim2.new(1, 0, 0, 0)
		body.LayoutOrder = 2
		body.Visible = state.openSell == cat.id
		body.Parent = wrap
		local gridLay = Instance.new("UIGridLayout")
		gridLay.CellPadding = UDim2.fromOffset(6, 6)
		gridLay.CellSize = UDim2.fromOffset(104, 142)
		gridLay.FillDirection = Enum.FillDirection.Horizontal
		gridLay.SortOrder = Enum.SortOrder.LayoutOrder
		gridLay.Parent = body
		local catId = cat.id
		local function countKind()
			local n = 0
			local total = 0
			for _, info in ipairs(Flow.sellItems) do
				if info.kind == catId then
					total = total + 1
					if state.sellSel[info.id] then
						n = n + 1
					end
				end
			end
			return n, total
		end
		local function updateHead(visibleCount)
			local n, total = countKind()
			local mark = body.Visible and "▾" or "▸"
			local extra = visibleCount and ("  显示" .. tostring(visibleCount)) or ""
			head.Text = mark .. "  " .. cat.title .. "    " .. n .. "/" .. total .. extra
		end
		Flow.sellHeads[cat.id] = { update = updateHead, body = body }
		updateHead()
		head.MouseButton1Click:Connect(function()
			if state.openSell == cat.id then
				state.openSell = nil
				body.Visible = false
			else
				state.openSell = cat.id
				for id, pack in pairs(Flow.sellHeads) do
					if pack.body then
						pack.body.Visible = id == cat.id
					end
					if pack.update then
						pack.update()
					end
				end
				task.defer(ensureSellIcons, body)
				return
			end
			updateHead()
		end)
		for _, info in ipairs(Flow.sellItems) do
			if info.kind == cat.id then
				local card = mkSellCard(body, info, 1)
				Flow.sellChecks[info.id] = card
				local itemId = info.id
				card.MouseButton1Click:Connect(function()
					state.sellSel[itemId] = not state.sellSel[itemId]
					Flow.refreshSellList()
				end)
			end
		end
	end
	sortBtn.MouseButton1Click:Connect(function()
		state.sellDesc = not state.sellDesc
		sortBtn.Text = state.sellDesc and "排序 高→低" or "排序 低→高"
		Flow.refreshSellList()
	end)
	ownedBtn.MouseButton1Click:Connect(function()
		state.sellOwned = not state.sellOwned
		ownedBtn.Text = state.sellOwned and "只看身上" or "显示全部"
		Flow.refreshSellList()
	end)
	sellAll.MouseButton1Click:Connect(function()
		local kind = state.openSell
		if not kind then
			return
		end
		for _, info in ipairs(Flow.sellItems) do
			if info.kind == kind then
				local qty = Flow.sellQty(info)
				if (not state.sellOwned) or qty > 0 then
					state.sellSel[info.id] = true
				end
			end
		end
		Flow.refreshSellList()
	end)
	sellNone.MouseButton1Click:Connect(function()
		state.sellSel = {}
		Flow.refreshSellList()
	end)
	Flow.refreshSellList()

	local function mkGuideVf(parent, size, pos)
		local vf = Instance.new("ViewportFrame")
		vf.BackgroundColor3 = Color3.fromRGB(14, 22, 32)
		vf.BorderSizePixel = 0
		vf.Active = false
		vf.Size = size
		vf.Position = pos or UDim2.fromOffset(0, 0)
		vf.LightColor = Color3.fromRGB(255, 255, 255)
		vf.Ambient = Color3.fromRGB(170, 170, 170)
		vf.LightDirection = Vector3.new(-1, -1, -1)
		vf.Parent = parent
		corner(vf, 6)
		return vf
	end

	local function fillGuideTree(root)
		if not root then
			return
		end
		for _, vf in ipairs(root:GetDescendants()) do
			if vf:IsA("ViewportFrame") then
				local kind = vf:GetAttribute("GuideKind")
				local name = vf:GetAttribute("GuideName")
				if kind and name and not vf:GetAttribute("Filled") then
					local vis = true
					local walk = vf.Parent
					while walk and walk ~= root do
						if walk:IsA("GuiObject") and not walk.Visible then
							vis = false
							break
						end
						walk = walk.Parent
					end
					if vis then
						vf:SetAttribute("Filled", true)
						if kind == "Gear" then
							fillGearIcon(vf, name, vf:GetAttribute("GuideOre"))
						else
							fillRockIcon(vf, name, kind)
						end
					end
				end
			end
		end
	end

	local function mkGuideCell(parent, kind, name, caption, order, extra, click)
		local cell
		if click then
			cell = Instance.new("TextButton")
			cell.Text = ""
			cell.AutoButtonColor = true
			cell.BackgroundColor3 = C.off
			cell.BackgroundTransparency = 0
			cell.MouseButton1Click:Connect(click)
		else
			cell = Instance.new("Frame")
			cell.BackgroundTransparency = 1
		end
		cell.BorderSizePixel = 0
		cell.Size = UDim2.fromOffset(72, 94)
		cell.LayoutOrder = order or 0
		cell.Parent = parent
		if click then
			corner(cell, 6)
		end
		local vf = mkGuideVf(cell, UDim2.fromOffset(68, 68), UDim2.fromOffset(2, 2))
		vf:SetAttribute("GuideKind", kind)
		vf:SetAttribute("GuideName", name)
		if extra then
			vf:SetAttribute("GuideOre", extra)
		end
		local lab = Instance.new("TextLabel")
		lab.BackgroundTransparency = 1
		lab.Font = Enum.Font.Gotham
		lab.Text = caption or ""
		lab.TextColor3 = C.text
		lab.TextSize = 10
		lab.TextWrapped = true
		lab.TextXAlignment = Enum.TextXAlignment.Center
		lab.TextYAlignment = Enum.TextYAlignment.Top
		lab.Position = UDim2.fromOffset(0, 70)
		lab.Size = UDim2.new(1, 0, 0, 24)
		lab.Parent = cell
		return cell
	end

	local guideOverlay = Instance.new("ScrollingFrame")
	guideOverlay.Name = "GuideOverlay"
	guideOverlay.BackgroundColor3 = C.bg
	guideOverlay.BorderSizePixel = 0
	guideOverlay.Visible = false
	guideOverlay.ZIndex = 70
	guideOverlay.Size = UDim2.fromScale(1, 1)
	guideOverlay.CanvasSize = UDim2.new(0, 0, 0, 0)
	guideOverlay.AutomaticCanvasSize = Enum.AutomaticSize.Y
	guideOverlay.ScrollBarThickness = 4
	guideOverlay.ScrollBarImageColor3 = C.line
	guideOverlay.Parent = right
	local overList = Instance.new("UIListLayout")
	overList.Padding = UDim.new(0, 6)
	overList.SortOrder = Enum.SortOrder.LayoutOrder
	overList.Parent = guideOverlay
	local overPad = Instance.new("UIPadding")
	overPad.PaddingTop = UDim.new(0, 4)
	overPad.PaddingBottom = UDim.new(0, 8)
	overPad.Parent = guideOverlay

	function Flow.hideGuideOverlay()
		guideOverlay.Visible = false
	end

	local function ensureGuideIcons()
		if guidePage.Visible then
			fillGuideTree(guidePage)
		end
		if guideOverlay.Visible then
			fillGuideTree(guideOverlay)
		end
	end
	Flow.ensureGuideIcons = ensureGuideIcons

	local function clearOverlay()
		for _, child in ipairs(guideOverlay:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end

	local function addOverlayLabel(text, order, bold, h)
		local lab = Instance.new("TextLabel")
		lab.BackgroundTransparency = 1
		lab.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
		lab.Text = text or ""
		lab.TextColor3 = bold and C.text or C.dim
		lab.TextSize = bold and 14 or 12
		lab.TextWrapped = true
		lab.TextXAlignment = Enum.TextXAlignment.Left
		lab.AutomaticSize = Enum.AutomaticSize.Y
		lab.Size = UDim2.new(1, -8, 0, h or 16)
		lab.LayoutOrder = order
		lab.Parent = guideOverlay
		return lab
	end

	local function addOverlayRow(order)
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.AutomaticSize = Enum.AutomaticSize.Y
		row.Size = UDim2.new(1, 0, 0, 0)
		row.LayoutOrder = order
		row.Parent = guideOverlay
		local lay = Instance.new("UIListLayout")
		lay.FillDirection = Enum.FillDirection.Horizontal
		lay.Padding = UDim.new(0, 6)
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Parent = row
		return row
	end

	local function addCraftBlock(craft, order)
		if not craft then
			return order
		end
		addOverlayLabel(
			"先合成 "
				.. Flow.sellLabel(craft.dest)
				.. (craft.station and (" · " .. craft.station) or "")
				.. (craft.gold and (" · 另外要 " .. tostring(craft.gold) .. " 金") or ""),
			order,
			false
		)
		local row = addOverlayRow(order + 1)
		mkGuideCell(row, "Ore", craft.dest, Flow.sellLabel(craft.dest), 1)
		for i, part in ipairs(craft.parts or {}) do
			mkGuideCell(row, "Ore", part[1], Flow.sellLabel(part[1]) .. " " .. tostring(part[2]) .. "颗", i + 1)
		end
		return order + 2
	end

	local function openGuideDetail(spec)
		clearOverlay()
		local back = Instance.new("TextButton")
		back.BackgroundColor3 = C.tab
		back.BorderSizePixel = 0
		back.Font = Enum.Font.GothamBold
		back.Text = "返回指南"
		back.TextColor3 = C.text
		back.TextSize = 13
		back.Size = UDim2.new(1, 0, 0, 30)
		back.LayoutOrder = 1
		back.AutoButtonColor = true
		back.Parent = guideOverlay
		corner(back, 4)
		back.MouseButton1Click:Connect(function()
			guideOverlay.Visible = false
		end)
		addOverlayLabel(spec.title or "", 2, true, 20)
		addOverlayLabel(spec.body or "", 3, false, 18)
		if spec.counts and #spec.counts > 0 then
			addOverlayLabel("这一炉矿石", 4, true)
			local row = addOverlayRow(5)
			local look = spec.lookOre or (spec.counts[1] and spec.counts[1][1])
			for i, part in ipairs(spec.counts) do
				mkGuideCell(row, "Ore", part[1], Flow.sellLabel(part[1]) .. " " .. tostring(part[2]) .. "颗", i, look)
			end
		end
		if spec.gears and #spec.gears > 0 then
			addOverlayLabel("成品样子", 6, true)
			local row = addOverlayRow(7)
			for i, gear in ipairs(spec.gears) do
				mkGuideCell(row, "Gear", gear[1], Flow.gearLabel(gear[1]), i, gear[2] or spec.lookOre)
			end
		end
		if spec.lines then
			local nextOrder = 8
			for _, line in ipairs(spec.lines) do
				addOverlayLabel(line.text, nextOrder, false)
				local row = addOverlayRow(nextOrder + 1)
				local look = line.counts and line.counts[1] and line.counts[1][1]
				for i, part in ipairs(line.counts or {}) do
					mkGuideCell(row, "Ore", part[1], Flow.sellLabel(part[1]) .. " " .. tostring(part[2]) .. "颗", i, look)
				end
				if line.gear then
					mkGuideCell(row, "Gear", line.gear, Flow.gearLabel(line.gear), 20, look)
				end
				nextOrder = nextOrder + 2
			end
			addCraftBlock(spec.craft, nextOrder)
			addCraftBlock(spec.craft2, nextOrder + 2)
		else
			addCraftBlock(spec.craft, 8)
			addCraftBlock(spec.craft2, 10)
		end
		guideOverlay.Visible = true
		guideOverlay.CanvasPosition = Vector2.new(0, 0)
		task.defer(ensureGuideIcons)
	end

	local function clickWeapon(area, weaponName)
		local cls = Flow.gearClass[weaponName] or "StraightSword"
		local lock = Flow.classLock[cls] or 9
		local total = Flow.forgeTotal(lock)
		local counts = Flow.mixCounts(area.mix, total)
		local look = counts[1] and counts[1][1]
		local clsName = Flow.classZh[cls] or cls
		local body = table.concat({
			"点的是 " .. Flow.gearLabel(weaponName) .. "，属于" .. clsName .. "。",
			"游戏按颗数进炉。锁定" .. clsName .. "至少要 " .. tostring(lock) .. " 颗，这一套按 " .. tostring(total) .. " 颗扔。",
			"配法：" .. Flow.mixLine(counts) .. "，一共 " .. tostring(total) .. " 颗。",
			"词条矿至少要占三成才会满，所以带词条的那种不要少扔。",
			area.note or "",
		}, "\n")
		openGuideDetail({
			title = Flow.gearLabel(weaponName) .. " · " .. clsName,
			body = body,
			counts = counts,
			lookOre = look,
			gears = { { weaponName, look } },
			craft = area.craft,
			craft2 = area.craft2,
		})
	end

	local function clickArmorSet(area, set)
		local mix = area.armorMix or area.mix
		local lines = {}
		local gears = {}
		local bag = {}
		local look
		for _, item in ipairs(set.items or {}) do
			local cls = Flow.gearClass[item] or "HeavyChestplate"
			local lock = Flow.classLock[cls] or 52
			local total = Flow.forgeTotal(lock)
			local counts = Flow.mixCounts(mix, total)
			look = look or (counts[1] and counts[1][1])
			gears[#gears + 1] = { item, look }
			for _, part in ipairs(counts) do
				bag[part[1]] = (bag[part[1]] or 0) + part[2]
			end
			lines[#lines + 1] = {
				text = Flow.gearLabel(item)
					.. "（"
					.. (Flow.classZh[cls] or cls)
					.. "，锁定 "
					.. tostring(lock)
					.. " 颗）这一炉 "
					.. tostring(total)
					.. " 颗："
					.. Flow.mixLine(counts),
				counts = counts,
				gear = item,
			}
		end
		local sumBits = {}
		local sum = 0
		for name, qty in pairs(bag) do
			sumBits[#sumBits + 1] = { name, qty }
			sum = sum + qty
		end
		table.sort(sumBits, function(a, b)
			return a[2] > b[2]
		end)
		local body = table.concat({
			(set.title or "护甲一套") .. "要分开锻 3 次，头、甲、腿各进一炉。",
			"三件合计 " .. tostring(sum) .. " 颗：" .. Flow.mixLine(sumBits) .. "。",
			area.armorNote or area.note or "",
		}, "\n")
		openGuideDetail({
			title = set.title or "护甲一套",
			body = body,
			lookOre = look,
			gears = gears,
			lines = lines,
			craft = area.craft,
			craft2 = area.craft2,
		})
	end

	local guideHint = Instance.new("TextLabel")
	guideHint.BackgroundTransparency = 1
	guideHint.Font = Enum.Font.Gotham
	guideHint.Text = "点武器或整套护甲，看这一炉要几颗配几颗。词条矿至少占三成才满。当前地图已展开。"
	guideHint.TextColor3 = C.dim
	guideHint.TextSize = 11
	guideHint.TextXAlignment = Enum.TextXAlignment.Left
	guideHint.TextWrapped = true
	guideHint.Size = UDim2.new(1, 0, 0, 28)
	guideHint.LayoutOrder = 1
	guideHint.Parent = guidePage

	local stageBar = Instance.new("Frame")
	stageBar.BackgroundTransparency = 1
	stageBar.Size = UDim2.new(1, 0, 0, 26)
	stageBar.LayoutOrder = 2
	stageBar.Parent = guidePage
	local stageBtns = {}
	local stageDefs = {
		{ id = "all", text = "全部" },
		{ id = "early", text = "前期" },
		{ id = "mid", text = "中期" },
		{ id = "late", text = "后期" },
	}
	local function paintStage()
		for _, def in ipairs(stageDefs) do
			local b = stageBtns[def.id]
			if b then
				b.BackgroundColor3 = state.guideStage == def.id and C.tab or C.btn
			end
		end
	end
	for i, def in ipairs(stageDefs) do
		local b = Instance.new("TextButton")
		b.BackgroundColor3 = C.btn
		b.BorderSizePixel = 0
		b.Font = Enum.Font.GothamBold
		b.Text = def.text
		b.TextColor3 = C.text
		b.TextSize = 12
		b.Size = UDim2.new(0.25, -4, 1, 0)
		b.Position = UDim2.new((i - 1) * 0.25, 2, 0, 0)
		b.AutoButtonColor = true
		b.Parent = stageBar
		corner(b, 4)
		stageBtns[def.id] = b
		b.MouseButton1Click:Connect(function()
			state.guideStage = def.id
			paintStage()
			if Flow.refreshGuideFilter then
				Flow.refreshGuideFilter()
			end
			ensureGuideIcons()
		end)
	end
	paintStage()

	local guideHeads = {}
	state.openGuide = Flow.placeMap[game.PlaceId] or 3

	local function mkGuideArea(parent, area, order)
		local card = Instance.new("Frame")
		card.BackgroundColor3 = C.panel
		card.BorderSizePixel = 0
		card.AutomaticSize = Enum.AutomaticSize.Y
		card.Size = UDim2.new(1, 0, 0, 0)
		card.LayoutOrder = order
		card.Parent = parent
		card:SetAttribute("GuideStage", area.stage)
		corner(card, 6)
		local pad = Instance.new("UIPadding")
		pad.PaddingTop = UDim.new(0, 8)
		pad.PaddingBottom = UDim.new(0, 8)
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.Parent = card
		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, 6)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = card

		local head = Instance.new("TextLabel")
		head.BackgroundTransparency = 1
		head.Font = Enum.Font.GothamBold
		head.Text = area.stageName .. "  " .. area.area
		head.TextColor3 = C.text
		head.TextSize = 13
		head.TextXAlignment = Enum.TextXAlignment.Left
		head.Size = UDim2.new(1, 0, 0, 18)
		head.LayoutOrder = 1
		head.Parent = card

		local tip = Instance.new("TextLabel")
		tip.BackgroundTransparency = 1
		tip.Font = Enum.Font.Gotham
		tip.Text = area.tip or ""
		tip.TextColor3 = C.dim
		tip.TextSize = 11
		tip.TextWrapped = true
		tip.TextXAlignment = Enum.TextXAlignment.Left
		tip.AutomaticSize = Enum.AutomaticSize.Y
		tip.Size = UDim2.new(1, 0, 0, 16)
		tip.LayoutOrder = 2
		tip.Parent = card

		local rockLab = Instance.new("TextLabel")
		rockLab.BackgroundTransparency = 1
		rockLab.Font = Enum.Font.Gotham
		rockLab.Text = "矿区"
		rockLab.TextColor3 = C.dim
		rockLab.TextSize = 11
		rockLab.TextXAlignment = Enum.TextXAlignment.Left
		rockLab.Size = UDim2.new(1, 0, 0, 14)
		rockLab.LayoutOrder = 3
		rockLab.Parent = card
		local rockRow = Instance.new("Frame")
		rockRow.BackgroundTransparency = 1
		rockRow.AutomaticSize = Enum.AutomaticSize.Y
		rockRow.Size = UDim2.new(1, 0, 0, 0)
		rockRow.LayoutOrder = 4
		rockRow.Parent = card
		local rockLay = Instance.new("UIListLayout")
		rockLay.FillDirection = Enum.FillDirection.Horizontal
		rockLay.Padding = UDim.new(0, 6)
		rockLay.SortOrder = Enum.SortOrder.LayoutOrder
		rockLay.Parent = rockRow
		for i, rockName in ipairs(area.rocks or {}) do
			mkGuideCell(rockRow, "Rock", rockName, Flow.rockLabel(rockName), i)
		end

		local lookOre = area.mix and area.mix[1] and area.mix[1][1]
		local wepLab = Instance.new("TextLabel")
		wepLab.BackgroundTransparency = 1
		wepLab.Font = Enum.Font.Gotham
		wepLab.Text = "武器（点进去看几颗配几颗）"
		wepLab.TextColor3 = C.dim
		wepLab.TextSize = 11
		wepLab.TextXAlignment = Enum.TextXAlignment.Left
		wepLab.Size = UDim2.new(1, 0, 0, 14)
		wepLab.LayoutOrder = 5
		wepLab.Parent = card
		local wepRow = Instance.new("Frame")
		wepRow.BackgroundTransparency = 1
		wepRow.AutomaticSize = Enum.AutomaticSize.Y
		wepRow.Size = UDim2.new(1, 0, 0, 0)
		wepRow.LayoutOrder = 6
		wepRow.Parent = card
		local wepLay = Instance.new("UIListLayout")
		wepLay.FillDirection = Enum.FillDirection.Horizontal
		wepLay.Padding = UDim.new(0, 6)
		wepLay.SortOrder = Enum.SortOrder.LayoutOrder
		wepLay.Parent = wepRow
		for i, weaponName in ipairs(area.weapons or {}) do
			mkGuideCell(wepRow, "Gear", weaponName, Flow.gearLabel(weaponName), i, lookOre, function()
				clickWeapon(area, weaponName)
			end)
		end

		local armLab = Instance.new("TextLabel")
		armLab.BackgroundTransparency = 1
		armLab.Font = Enum.Font.Gotham
		armLab.Text = "护甲整套（点一套看头甲腿各要几颗）"
		armLab.TextColor3 = C.dim
		armLab.TextSize = 11
		armLab.TextXAlignment = Enum.TextXAlignment.Left
		armLab.Size = UDim2.new(1, 0, 0, 14)
		armLab.LayoutOrder = 7
		armLab.Parent = card

		for si, set in ipairs(area.armorSets or {}) do
			local setBtn = Instance.new("TextButton")
			setBtn.BackgroundColor3 = C.off
			setBtn.BorderSizePixel = 0
			setBtn.Text = ""
			setBtn.AutoButtonColor = true
			setBtn.AutomaticSize = Enum.AutomaticSize.Y
			setBtn.Size = UDim2.new(1, 0, 0, 0)
			setBtn.LayoutOrder = 8 + si
			setBtn.Parent = card
			corner(setBtn, 6)
			local setPad = Instance.new("UIPadding")
			setPad.PaddingTop = UDim.new(0, 6)
			setPad.PaddingBottom = UDim.new(0, 6)
			setPad.PaddingLeft = UDim.new(0, 6)
			setPad.PaddingRight = UDim.new(0, 6)
			setPad.Parent = setBtn
			local setList = Instance.new("UIListLayout")
			setList.Padding = UDim.new(0, 4)
			setList.SortOrder = Enum.SortOrder.LayoutOrder
			setList.Parent = setBtn
			local setTitle = Instance.new("TextLabel")
			setTitle.BackgroundTransparency = 1
			setTitle.Font = Enum.Font.GothamBold
			setTitle.Text = set.title or "护甲一套"
			setTitle.TextColor3 = C.text
			setTitle.TextSize = 12
			setTitle.TextXAlignment = Enum.TextXAlignment.Left
			setTitle.Size = UDim2.new(1, 0, 0, 16)
			setTitle.LayoutOrder = 1
			setTitle.Parent = setBtn
			local setRow = Instance.new("Frame")
			setRow.BackgroundTransparency = 1
			setRow.AutomaticSize = Enum.AutomaticSize.Y
			setRow.Size = UDim2.new(1, 0, 0, 0)
			setRow.LayoutOrder = 2
			setRow.Parent = setBtn
			local setLay = Instance.new("UIListLayout")
			setLay.FillDirection = Enum.FillDirection.Horizontal
			setLay.Padding = UDim.new(0, 6)
			setLay.SortOrder = Enum.SortOrder.LayoutOrder
			setLay.Parent = setRow
			local armorLook = (area.armorMix and area.armorMix[1] and area.armorMix[1][1]) or lookOre
			for pi, item in ipairs(set.items or {}) do
				mkGuideCell(setRow, "Gear", item, Flow.gearLabel(item), pi, armorLook)
			end
			setBtn.MouseButton1Click:Connect(function()
				clickArmorSet(area, set)
			end)
		end
		return card
	end

	for i, map in ipairs(Flow.guideMaps) do
		local wrap = Instance.new("Frame")
		wrap.BackgroundTransparency = 1
		wrap.AutomaticSize = Enum.AutomaticSize.Y
		wrap.Size = UDim2.new(1, 0, 0, 32)
		wrap.LayoutOrder = 10 + i
		wrap.Parent = guidePage
		local wrapList = Instance.new("UIListLayout")
		wrapList.Padding = UDim.new(0, 4)
		wrapList.SortOrder = Enum.SortOrder.LayoutOrder
		wrapList.Parent = wrap

		local head = Instance.new("TextButton")
		head.BackgroundColor3 = C.panel
		head.BorderSizePixel = 0
		head.Font = Enum.Font.GothamBold
		head.TextColor3 = C.text
		head.TextSize = 13
		head.TextXAlignment = Enum.TextXAlignment.Left
		head.Size = UDim2.new(1, 0, 0, 32)
		head.LayoutOrder = 1
		head.AutoButtonColor = true
		head.Parent = wrap
		local hpad = Instance.new("UIPadding")
		hpad.PaddingLeft = UDim.new(0, 10)
		hpad.Parent = head
		corner(head, 4)

		local body = Instance.new("Frame")
		body.BackgroundTransparency = 1
		body.AutomaticSize = Enum.AutomaticSize.Y
		body.Size = UDim2.new(1, 0, 0, 0)
		body.LayoutOrder = 2
		body.Visible = state.openGuide == map.id
		body.Parent = wrap
		local bodyList = Instance.new("UIListLayout")
		bodyList.Padding = UDim.new(0, 6)
		bodyList.SortOrder = Enum.SortOrder.LayoutOrder
		bodyList.Parent = body

		local cards = {}
		for ai, area in ipairs(map.areas) do
			cards[#cards + 1] = mkGuideArea(body, area, ai)
		end

		local function updateHead()
			local mark = body.Visible and "▾" or "▸"
			local here = (Flow.placeMap[game.PlaceId] or 0) == map.id
			head.Text = mark .. "  " .. map.title .. (here and "    当前地图" or "")
		end
		guideHeads[map.id] = { update = updateHead, body = body, cards = cards }
		updateHead()

		head.MouseButton1Click:Connect(function()
			if state.openGuide == map.id then
				state.openGuide = nil
				body.Visible = false
			else
				state.openGuide = map.id
				for id, pack in pairs(guideHeads) do
					if pack.body then
						pack.body.Visible = id == map.id
					end
					if pack.update then
						pack.update()
					end
				end
				ensureGuideIcons()
				return
			end
			updateHead()
		end)
	end

	function Flow.refreshGuideFilter()
		for _, pack in pairs(guideHeads) do
			for _, card in ipairs(pack.cards or {}) do
				local st = card:GetAttribute("GuideStage")
				card.Visible = state.guideStage == "all" or st == state.guideStage
			end
		end
	end
	Flow.refreshGuideFilter()

	local openGuide = guideHeads[state.openGuide]
	if openGuide and openGuide.body then
		openGuide.body.Visible = true
		if openGuide.update then
			openGuide.update()
		end
	end

	local otherHint = Instance.new("TextLabel")
	otherHint.BackgroundTransparency = 1
	otherHint.Font = Enum.Font.Gotham
	otherHint.Text = "保存矿石、怪物、药水、出售选择和窗口大小。版本 " .. FORGE_VERSION
	otherHint.TextColor3 = C.dim
	otherHint.TextSize = 11
	otherHint.TextXAlignment = Enum.TextXAlignment.Left
	otherHint.TextWrapped = true
	otherHint.Size = UDim2.new(1, 0, 0, 28)
	otherHint.LayoutOrder = 1
	otherHint.Parent = otherPage
	local saveBtn = mkPlain(otherPage, "保存配置", 2, C.tab)
	local updateBtn = mkPlain(otherPage, env._ForgeScriptUrl and "拉取远程更新" or "当前是本地脚本", 3, C.tab)
	local exitBtn = mkPlain(otherPage, "退出并清理", 4, C.exit)

	local function mkGrip(size, pos, mode, mark)
		local g = Instance.new("TextButton")
		g.BackgroundTransparency = 1
		g.BorderSizePixel = 0
		g.Text = mark or ""
		g.TextColor3 = C.dim
		g.TextSize = 12
		g.Font = Enum.Font.GothamBold
		g.AutoButtonColor = false
		g.Size = size
		g.Position = pos
		g.ZIndex = 80
		g.Parent = window
		g.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				resizing = true
				dragging = false
				resizeMode = mode
				dragStart = input.Position
				startSize = window.AbsoluteSize
			end
		end)
		return g
	end
	mkGrip(UDim2.new(0, 8, 1, -18), UDim2.new(1, -8, 0, 0), "x")
	mkGrip(UDim2.new(1, -18, 0, 8), UDim2.new(0, 0, 1, -8), "y")
	mkGrip(UDim2.fromOffset(18, 18), UDim2.new(1, -18, 1, -18), "both", "◢")

	mineBtn.MouseButton1Click:Connect(function()
		state.mineOn = not state.mineOn
		paintOn(mineBtn, state.mineOn, "自动挖矿")
		if not state.mineOn then
			Flow.stopHold()
			Flow.target = nil
			Flow.arriveAt = 0
			if not (state.huntOn or state.potOn or state.sellOn) then
				Flow.setFlyBody(false)
				state.status = "待机"
			end
		else
			Flow.armSellClock()
		end
	end)
	atkBtn.MouseButton1Click:Connect(function()
		state.atkOn = not state.atkOn
		paintOn(atkBtn, state.atkOn, "打怪")
	end)
	huntBtn.MouseButton1Click:Connect(function()
		state.huntOn = not state.huntOn
		paintOn(huntBtn, state.huntOn, "自动打怪")
		if not state.huntOn then
			Flow.huntTarget = nil
			if not (state.mineOn or state.potOn) then
				state.status = "待机"
			end
		else
			Flow.armSellClock()
		end
	end)
	potBtn.MouseButton1Click:Connect(function()
		state.potOn = not state.potOn
		paintOn(potBtn, state.potOn, "自动喝药")
		if not state.potOn then
			Flow.buyName = nil
			if not (state.mineOn or state.huntOn or state.sellOn) then
				state.status = "待机"
			end
		end
	end)
	sellBtn.MouseButton1Click:Connect(function()
		state.sellOn = not state.sellOn
		paintOn(sellBtn, state.sellOn, "自动出售")
		if not state.sellOn then
			Flow.clearSellTrip()
			Flow.nextSellAt = 0
			if not (state.mineOn or state.huntOn or state.potOn) then
				state.status = "待机"
			end
		elseif not Flow.hasAnySellSel() then
			state.status = "先勾要卖的"
		else
			Flow.armSellClock()
		end
	end)
	saveBtn.MouseButton1Click:Connect(function()
		local ok, err = Flow.saveCfg()
		if ok then
			saveBtn.Text = "已保存"
			saveBtn.BackgroundColor3 = C.on
			task.delay(1.2, function()
				if saveBtn and saveBtn.Parent then
					saveBtn.Text = "保存配置"
					saveBtn.BackgroundColor3 = C.tab
				end
			end)
		else
			saveBtn.Text = tostring(err or "保存失败")
			task.delay(1.6, function()
				if saveBtn and saveBtn.Parent then
					saveBtn.Text = "保存配置"
				end
			end)
		end
	end)
	updateBtn.MouseButton1Click:Connect(function()
		local ok, err = Flow.reloadRemote()
		if ok then
			updateBtn.Text = "正在更新…"
		else
			updateBtn.Text = tostring(err or "更新失败")
			task.delay(1.8, function()
				if updateBtn and updateBtn.Parent then
					updateBtn.Text = env._ForgeScriptUrl and "拉取远程更新" or "当前是本地脚本"
				end
			end)
		end
	end)

	local function shutdown()
		alive = false
		env._ForgeFarmGen = (tonumber(env._ForgeFarmGen) or myGen) + 1
		state.mineOn = false
		state.atkOn = false
		state.huntOn = false
		state.potOn = false
		state.sellOn = false
		Flow.buyName = nil
		Flow.sellFly = nil
		Flow.sellTalk = false
		Flow.nextSellAt = 0
		Flow.huntTarget = nil
		pcall(function()
			Flow.stopHold()
		end)
		pcall(function()
			Flow.setFlyBody(false)
		end)
		pcall(function()
			Flow.restoreCamOcclusion()
		end)
		pcall(function()
			RunService:UnbindFromRenderStep("ForgeFly")
		end)
		pcall(function()
			RunService:UnbindFromRenderStep("ForgeCam")
		end)
		for _, conn in ipairs(Flow.conns) do
			pcall(function()
				conn:Disconnect()
			end)
		end
		Flow.conns = {}
		if screenGui then
			pcall(function()
				screenGui:Destroy()
			end)
		end
		env._ForgeShutdown = nil
		print("[Forge] cleaned")
	end
	env._ForgeShutdown = shutdown

	exitBtn.MouseButton1Click:Connect(shutdown)

	table.insert(Flow.conns, UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or not stillMine() then
			return
		end
		if input.KeyCode == Enum.KeyCode.T then
			state.uiOn = not state.uiOn
			window.Visible = state.uiOn
		end
	end))

	task.spawn(function()
		while stillMine() do
			if statusLab and statusLab.Parent then
				local extra = ""
				if state.mineOn then
					extra = extra .. "  矿" .. tostring(Flow.countReady and Flow.countReady() or 0)
				end
				if state.huntOn then
					extra = extra .. "  怪"
				end
				if potPage.Visible then
					pcall(Flow.refreshPotChecks)
				end
				if sellPage.Visible then
					pcall(Flow.refreshSellList)
				end
				if state.sellOn then
					if Flow.sellFly or Flow.sellTalk then
						extra = extra .. "  卖"
					elseif Flow.farmOn() and Flow.nextSellAt and Flow.nextSellAt > 0 then
						extra = extra .. "  卖" .. tostring(math.max(0, math.ceil(Flow.nextSellAt - os.clock()))) .. "s"
					else
						extra = extra .. "  卖"
					end
				end
				statusLab.Text = (state.status or "待机") .. extra
			end
			task.wait(0.2)
		end
	end)

	Flow.refreshChecks()
end

pcall(Flow.loadCfg)
bindFarm()
bindUi()
print("[Forge] ready " .. FORGE_VERSION)
