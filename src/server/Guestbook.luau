--!nonstrict
-- «Пока тебя не было» (DD-089). A home is seen even when its owner is away: survivors in other groves
-- walk round it (it stands on their free plot) and may leave a ♥. Each grove server gathers what its
-- people did to absent owners and writes it to the owner's guestbook now and then (one DataStore key
-- per owner); the owner's next server reads and empties it, adds the ♥ to the profile and tells them.
-- Without DataStore (Studio) nothing is written; the demo homes have negative ids and are skipped.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Guestbook = {}

local FLUSH = 30
local NAMES = 6
local store = nil
pcall(function()
	store = DataStoreService:GetDataStore("TLG_Guestbook_v1")
end)
local online = store ~= nil and not RunService:IsStudio()

local pending: { [number]: { likes: number, visits: number, names: { string } } } = {}
local counted: { [string]: boolean } = {} -- "visitor:owner": one visit per pair per server

local function entry(owner: number)
	local e = pending[owner]
	if not e then
		e = { likes = 0, visits = 0, names = {} }
		pending[owner] = e
	end
	return e
end

local function addName(e, name: string)
	if not table.find(e.names, name) and #e.names < NAMES then
		table.insert(e.names, name)
	end
end

function Guestbook.like(owner: number, from: string)
	if owner <= 0 then
		return
	end
	local e = entry(owner)
	e.likes += 1
	addName(e, from)
end

-- A survivor stood in an absent owner's yard: counted once per pair while this server lives.
function Guestbook.visit(owner: number, visitor: number, from: string)
	local key = visitor .. ":" .. owner
	if owner <= 0 or counted[key] then
		return
	end
	counted[key] = true
	local e = entry(owner)
	e.visits += 1
	addName(e, from)
end

function Guestbook.flush()
	if not online or next(pending) == nil then
		table.clear(pending)
		return
	end
	local batch = pending
	pending = {}
	for owner, e in batch do
		task.spawn(function()
			pcall(store.UpdateAsync, store, tostring(owner), function(old)
				old = if type(old) == "table" then old else { likes = 0, visits = 0, names = {} }
				old.likes = (old.likes or 0) + e.likes
				old.visits = (old.visits or 0) + e.visits
				old.names = if type(old.names) == "table" then old.names else {}
				for _, n in e.names do
					addName(old, n)
				end
				return old
			end)
		end)
	end
end

-- The owner came in: what waited for them (and the book is emptied). nil when there is nothing.
function Guestbook.claim(owner: number)
	if not online then
		return nil
	end
	local got = nil
	pcall(store.UpdateAsync, store, tostring(owner), function(old)
		if type(old) == "table" and ((old.likes or 0) > 0 or (old.visits or 0) > 0) then
			got = old
		end
		return nil
	end)
	return got
end

task.spawn(function()
	while true do
		task.wait(FLUSH)
		Guestbook.flush()
	end
end)
game:BindToClose(function()
	Guestbook.flush()
end)

return Guestbook
