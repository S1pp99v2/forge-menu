--!nocheck
--!nolint
local FORGE_VERSION = "1.1.1"
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
	uiOn = true,
	page = "auto",
	flySpeed = 70,
	standDist = 4.5,
	standPitch = 0,
	huntHeight = 12,
	huntSingle = false,
	selected = {},
	huntSel = {},
	potSel = {},
	openMap = nil,
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
	mapHeads = {},
	swingBusy = false,
	window = nil,
	huntTarget = nil,
	buyName = nil,
	lastDrink = {},
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

	function Flow.drinkPotion(id)
		local rf = Flow.equipRF()
		if not rf then
			return false
		end
		local ok = pcall(function()
			rf:InvokeServer(id)
		end)
		Flow.lastDrink[id] = os.clock()
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

	function Flow.needPotion(id)
		local info = Flow.potInfo(id)
		if not info then
			return nil
		end
		if Flow.potionQty(id) <= 0 then
			return "buy"
		end
		local last = Flow.lastDrink[id] or 0
		if os.clock() - last < 1.4 then
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
		local dest, look = Flow.flyJob()
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
		if state.huntOn or Flow.buyName then
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
		state.status = "挖掘 " .. Flow.rockLabel(Flow.target.Name)
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
		if Flow.buyName then
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
					if not pos then
						state.status = "这图不能买 " .. Flow.potLabel(info.id)
						return
					end
					if info.price > 0 and Flow.gold() < info.price then
						state.status = "金币不够买 " .. Flow.potLabel(info.id)
						return
					end
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
		if not picked then
			state.status = state.status
			if not (state.mineOn or state.huntOn) then
				state.status = "先选药水"
			end
			Flow.buyName = nil
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

	function Flow.restoreCamOcclusion()
		if Flow.occlusionOn then
			pcall(function()
				player.DevCameraOcclusionMode = Flow.savedOcclusion or Enum.DevCameraOcclusionMode.Zoom
			end)
			Flow.occlusionOn = false
		end
	end

	function Flow.applyFreeCam()
		if not (state.mineOn or state.huntOn or Flow.buyName) then
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
			local huntSwing = state.huntOn and Flow.aliveHunt(Flow.huntTarget) and Flow.atHuntStand(Flow.huntTarget)
			if (state.atkOn or huntSwing) and not Flow.swingBusy then
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

	local left = Instance.new("Frame")
	left.BackgroundTransparency = 1
	left.ZIndex = 51
	left.Position = UDim2.fromOffset(8, 64)
	left.Size = UDim2.new(0, 88, 1, -20)
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
		b.TextSize = 13
		b.Size = UDim2.new(1, 0, 0, 32)
		b.LayoutOrder = order
		b.AutoButtonColor = true
		b.Parent = left
		corner(b, 4)
		return b
	end
	local catAuto = mkCat("自动化", 1)
	local catHunt = mkCat("打怪", 2)
	local catPot = mkCat("药水", 3)
	local catOther = mkCat("其他", 4)

	local right = Instance.new("Frame")
	right.BackgroundTransparency = 1
	right.ZIndex = 51
	right.Position = UDim2.fromOffset(104, 64)
	right.Size = UDim2.new(1, -112, 1, -20)
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
	local otherPage = mkPage()
	huntPage.Visible = false
	potPage.Visible = false
	otherPage.Visible = false

	local function showPage(name)
		state.page = name
		scroll.Visible = name == "auto"
		huntPage.Visible = name == "hunt"
		potPage.Visible = name == "pot"
		otherPage.Visible = name == "other"
		catAuto.BackgroundColor3 = name == "auto" and C.tab or C.btn
		catHunt.BackgroundColor3 = name == "hunt" and C.tab or C.btn
		catPot.BackgroundColor3 = name == "pot" and C.tab or C.btn
		catOther.BackgroundColor3 = name == "other" and C.tab or C.btn
		if name == "pot" then
			Flow.refreshPotChecks()
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
		local folder = assets:FindFirstChild("Rocks")
		return folder and folder:FindFirstChild(name)
	end

	local function fillRockIcon(vf, rockName, kind)
		local src = findAsset(kind or "Rock", rockName)
		if not src then
			return
		end
		local world = Instance.new("WorldModel")
		world.Parent = vf
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
			end
		end
		pcall(function()
			model:PivotTo(CFrame.new())
		end)
		model.Parent = world
		local cam = Instance.new("Camera")
		cam.Parent = vf
		vf.CurrentCamera = cam
		local ok, cf, size = pcall(function()
			return model:GetBoundingBox()
		end)
		if ok and cf and size then
			local m = math.max(size.X, size.Y, size.Z, 1)
			cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(m, m * 0.42, m) * 0.95, cf.Position)
		end
	end

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
	atkHint.Text = "被动防御：没怪也挥刀。挖矿时不换镐，和打怪页的自动寻怪无关。"
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
	potHint.Text = "选中的药水会自动喝。喝完飞去本岛商店买，买完继续喝。"
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

	local otherHint = Instance.new("TextLabel")
	otherHint.BackgroundTransparency = 1
	otherHint.Font = Enum.Font.Gotham
	otherHint.Text = "保存矿石、怪物、药水选择和窗口大小。版本 " .. FORGE_VERSION
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
			if not (state.huntOn or state.potOn) then
				Flow.setFlyBody(false)
				state.status = "待机"
			end
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
		end
	end)
	potBtn.MouseButton1Click:Connect(function()
		state.potOn = not state.potOn
		paintOn(potBtn, state.potOn, "自动喝药")
		if not state.potOn then
			Flow.buyName = nil
			if not (state.mineOn or state.huntOn) then
				state.status = "待机"
			end
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
		Flow.buyName = nil
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
