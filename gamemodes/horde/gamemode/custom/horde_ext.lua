CONFIG.name = "horde_ext"

-- Sound registration helpers used by TFA/ArcCW weapon definitions at file scope.
-- Defined here (early, and on both server & client) so they are always available
-- before any weapon SWEP file is loaded lazily on spawn.
local SoundChannels = {
	["shoot"] = CHAN_WEAPON,
	["shootwrap"] = CHAN_STATIC,
	["misc"] = CHAN_AUTO
}

local SoundChars = {
	["*"] = "STREAM",
	["#"] = "DRYMIX",
	["@"] = "OMNI",
	[">"] = "DOPPLER",
	["<"] = "DIRECTIONAL",
	["^"] = "DISTVARIANT",
	["("] = "SPATIALSTEREO_LOOP",
	[")"] = "SPATIALSTEREO",
	["}"] = "FASTPITCH",
	["$"] = "CRITICAL",
	["!"] = "SENTENCE",
	["?"] = "USERVOX"
}
local DefaultSoundChar = ")"

function HORDE:Sound_PatchSound( path, kind )
	local pathv
	local c = string.sub(path,1,1)

	if SoundChars[c] then
		pathv = string.sub( path, 2, string.len(path) )
	else
		pathv = path
	end

	local kindstr = kind
	if not kindstr then
		kindstr = DefaultSoundChar
	end
	if string.len(kindstr) > 1 then
		local found = false
		for k,v in pairs( SoundChars ) do
			if v == kind then
				kindstr = k
				found = true
				break
			end
		end
		if not found then
			kindstr = DefaultSoundChar
		end
	end

	return kindstr .. pathv
end

function HORDE:Sound_AddSound( name, channel, volume, level, pitch, wave, char )
	char = char or ""

	local SoundData = {
		name = name,
		channel = channel or CHAN_AUTO,
		volume = volume or 1,
		level = level or 75,
		pitch = pitch or 100
	}

	if char ~= "" then
		if type(wave) == "string" then
			wave = HORDE:Sound_PatchSound(wave, char)
		elseif type(wave) == "table" then
			local patchWave = table.Copy(wave)

			for k, v in pairs(patchWave) do
				patchWave[k] = HORDE:Sound_PatchSound(v, char)
			end

			wave = patchWave
		end
	end

	SoundData.sound = wave

	sound.Add(SoundData)
end

function HORDE:Sound_AddFireSound( id, path, wrap, kindv )
	kindv = kindv or ")"

	HORDE:Sound_AddSound(id, wrap and SoundChannels.shootwrap or SoundChannels.shoot, 1, 120, {97, 103}, path, kindv)
end

function HORDE:Sound_AddWeaponSound( id, path, kindv )
	kindv = kindv or ")"

	HORDE:Sound_AddSound(id, SoundChannels.misc, 1, 80, {97, 103}, path, kindv)
end

if SERVER then
	function HORDE:MakeExplosionEffect(pos, ent)
		if CreateGrenadeExplosion then
			CreateGrenadeExplosion(pos)
			if ent then HORDE:EmitExplosionSound(ent, 125) end
		else
			local effectdata = EffectData()
			effectdata:SetOrigin(pos)
			util.Effect("Explosion", effectdata)
		end
	end
	
	function HORDE:EmitExplosionSound(ent, soundlevel, pitch) 
		ent:EmitSound("weapons/explode" .. math.random(3, 5) .. ".wav", soundlevel, pitch)
	end
end

local blacklist = {["horde_ext.lua"] = true}
local blacklist_folders = {
	["post_init"] = true, ["arccw"] = true, ["subclasses"] = true, ["perks"] = true, ["gadgets"] = true, ["mutations"] = true,
	--["gui"] = true, ["status"] = true
}
local function NEW_AddCSLuaFile(name)
	blacklist[name] = true
	AddCSLuaFile(name)
end
local function NEW_include(name)
	blacklist[name] = true
	include(name)
end

local function ExtInclude(name, dir)

	local sep = string.Split(name, "_")
	name = dir .. name

	-- Determine where to load the files72dfgh
	if sep[1] == "sv" then
		if SERVER then
			NEW_include(name)
		end
	elseif sep[1] == "cl" then
		if SERVER then
			NEW_AddCSLuaFile(name)
		else
			NEW_include(name)
		end
	elseif sep[1] == "sh" then
		if SERVER then
			NEW_AddCSLuaFile(name)
		end
		NEW_include(name)
	end
end

-- Run this on both client and server
function AnalyzeDirection(direction, all_shared, pre_callback, post_callback, not_in_custom, dont_analyze_folders)
    local files, dirs = file.Find( "horde/gamemode/" .. (not_in_custom and "" or "custom/") .. direction .. "*", "LUA" )
	for k,v in pairs(files) do
        if !blacklist[direction .. v] then
			if all_shared then
				local name = (not_in_custom and "horde/gamemode/" or "horde/gamemode/custom/") .. direction .. v
				if pre_callback and pre_callback(direction, v) then continue end
				if SERVER then
					NEW_AddCSLuaFile(name)
				end
				NEW_include(name)
				if post_callback then post_callback(direction, v) end
			else
        		ExtInclude(v, (not_in_custom and "horde/gamemode/" or "horde/gamemode/custom/") .. direction)
			end
		end
    end
	if !dont_analyze_folders then
		for k, dirname in pairs(dirs) do
			if !blacklist_folders[dirname] then
				AnalyzeDirection(direction .. dirname .. "/", all_shared, pre_callback, post_callback, not_in_custom)
			end
		end
	end
end


AnalyzeDirection("arccw/attachments/", true, function(dir, name)
	if !ArcCWInstalled then
		blacklist[dir .. name] = true
		return true
	end

	att = {}
	
end, function(dir, name)
	if att and att.Slot  then
		ArcCW.LoadAttachmentType( att, string.Split(name, ".")[1] )
	end
	att = nil
end)
AnalyzeDirection("gadgets/", true, function(dir, name)
	GADGET = {}
end, function(dir, name)
	if GADGET.Ignore then return end
	GADGET.ClassName = string.lower(GADGET.ClassName or string.Explode(".", name)[1])
	GADGET.SortOrder = GADGET.SortOrder or 0

	hook.Run("Horde_OnLoadGadget", GADGET)

	HORDE.gadgets[GADGET.ClassName] = GADGET

	for k, v in pairs(GADGET.Hooks or {}) do
		hook.Add(k, "horde_gadget_" .. GADGET.ClassName, v)
	end

	GADGET = nil
end)
AnalyzeDirection("tfa/", true, nil, nil, true)
AnalyzeDirection("")

hook.Add( "InitPostEntity", "HORDE_EXT", function()
	AnalyzeDirection("post_init/")
	if CLIENT then

		local function initsync()
			local class = MySelf:Horde_GetClass()
			if !class then
				net.Start("Horde_InitClass")
				net.WriteString(HORDE.Class_Survivor)
				net.SendToServer()
			end
	
			net.Start("Horde_PlayerInit")
			net.SendToServer()
		end
	
		timer.Create("Horde_ClientPlayerFix", .5, 5, function()
			if !IsValid(MySelf) and IsValid(LocalPlayer()) then
				MySelf = LocalPlayer()
				initsync()
			end
		end)
	end
end )
