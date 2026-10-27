--!nonstrict
-- The grove's weekly boards (DD-088): the best drill defence held, research stages raised, help given
-- (allies raised, fights won together with a newcomer). Every survivor's own values live in their profile
-- (`week`, reset each Monday 00:00 UTC); after a fight they are mirrored into one OrderedDataStore per
-- board and week, and the boards read the top of those. Last week's top three earn a laurel (a title
-- and a line in the chronicle). Without DataStore (Studio) the boards are made of the survivors present.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserService = game:GetService("UserService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Meta = require(Shared:WaitForChild("Meta"))
local Profile = require(script.Parent.Profile)

local Weekly = {}

local TOP = 5
local REFRESH = 60
local online = not RunService:IsStudio()
local stores = {} -- "board:week" -> OrderedDataStore
local names: { [number]: string } = {}
local cache = { week = -1, at = -1e9, top = {} } -- top[board] = { { uid, value } }
local lastWeek = { week = -1, top = nil } -- last week's top three per board (laurels)

local function store(board: string, week: number)
	local key = board .. ":" .. week
	if stores[key] == nil then
		local ok, s = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, "TLG_Week_" .. board .. "_" .. week)
		stores[key] = if ok then s else false
		if not ok then
			online = false
		end
	end
	return stores[key] or nil
end

local function nameOf(uid: number): string
	if names[uid] then
		return names[uid]
	end
	local p = Players:GetPlayerByUserId(uid)
	if p then
		names[uid] = p.DisplayName
		return p.DisplayName
	end
	return "Выживший"
end

local function fetchNames(uids: { number })
	local want = {}
	for _, uid in uids do
		if not names[uid] and uid > 0 then
			table.insert(want, uid)
		end
	end
	if #want == 0 then
		return
	end
	local ok, infos = pcall(UserService.GetUserInfosByUserIdsAsync, UserService, want)
	if ok and type(infos) == "table" then
		for _, info in infos do
			names[info.Id] = info.DisplayName
		end
	end
end

local function readTop(board: string, week: number, n: number)
	local s = store(board, week)
	if not s then
		return nil
	end
	local ok, pages = pcall(s.GetSortedAsync, s, false, n)
	if not ok then
		return nil
	end
	local out = {}
	for _, row in pages:GetCurrentPage() do
		local uid = tonumber(row.key)
		if uid and row.value > 0 then
			table.insert(out, { uid = uid, value = row.value })
		end
	end
	return out
end

-- After a fight: this survivor's week goes to the boards (only what is above zero).
function Weekly.push(player: Player)
	local d = Profile.get(player)
	if not online or not d then
		return
	end
	local week = Profile.thisWeek(d)
	local uid = player.UserId
	names[uid] = player.DisplayName
	task.spawn(function()
		for _, board in Meta.WeeklyBoards do
			local v = week[board] or 0
			local s = v > 0 and store(board, week.n)
			if s then
				pcall(s.SetAsync, s, tostring(uid), v)
			end
		end
	end)
end

local function refresh(week: number)
	if os.clock() - cache.at < REFRESH and cache.week == week then
		return
	end
	cache.at = os.clock()
	cache.week = week
	if not online then
		return
	end
	task.spawn(function()
		local top = {}
		local uids = {}
		for _, board in Meta.WeeklyBoards do
			top[board] = readTop(board, week, TOP) or {}
			for _, row in top[board] do
				table.insert(uids, row.uid)
			end
		end
		fetchNames(uids)
		cache.top = top
	end)
end

-- The boards for the camp state: { week, endsIn, [board] = { { name, value, uid } } } — the stored top
-- with the survivors present merged in (their own values are always fresh).
function Weekly.boards()
	local now = os.time()
	local week = Meta.weekIndex(now)
	refresh(week)
	local out = { week = week, endsIn = Meta.weekEndsIn(now) }
	for _, board in Meta.WeeklyBoards do
		local rows = {}
		local seen = {}
		for _, player in Players:GetPlayers() do
			local d = Profile.get(player)
			local v = d and Profile.thisWeek(d)[board] or 0
			if v > 0 then
				rows[player.UserId] = v
				seen[player.UserId] = true
			end
		end
		for _, row in (if cache.week == week then cache.top[board] else nil) or {} do
			if not seen[row.uid] then
				rows[row.uid] = row.value
			end
		end
		local list = {}
		for uid, v in rows do
			table.insert(list, { uid = uid, name = nameOf(uid), value = v })
		end
		table.sort(list, function(a, b)
			if a.value ~= b.value then
				return a.value > b.value
			end
			return a.uid < b.uid
		end)
		while #list > TOP do
			table.remove(list)
		end
		out[board] = list
	end
	return out
end

-- Last week's top three (read once per server): laurels for whoever of them is here.
-- Returns the boards this survivor newly earned a laurel on.
function Weekly.laurels(player: Player): { string }
	local earned = {}
	if not online then
		return earned
	end
	local prev = Meta.weekIndex(os.time()) - 1
	if lastWeek.week ~= prev then
		lastWeek.week = prev
		lastWeek.top = {}
		for _, board in Meta.WeeklyBoards do
			lastWeek.top[board] = readTop(board, prev, 3) or {}
		end
	end
	for _, board in Meta.WeeklyBoards do
		for _, row in lastWeek.top[board] or {} do
			if row.uid == player.UserId and Profile.addLaurel(player, board, prev) then
				table.insert(earned, board)
			end
		end
	end
	return earned
end

return Weekly
