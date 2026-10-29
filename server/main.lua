local xsound = exports["xsound"]

local sounds = {}
local boomboxes = {}
local concerts = {}
local identifiers = {}
local soundKeys = {}
local lastKey = 0
local ready = {}

local OWNER_KEY = "zyrnex_music:owner"

local function identifierOf(playerId)
    local identifier = identifiers[playerId]

    if not identifier then
        identifier = GetPlayerIdentifierByType(playerId, "license") or ("player:%s"):format(playerId)
        identifiers[playerId] = identifier
    end

    return identifier
end

local function soundId(identifier, soundType)
    local key = soundKeys[identifier]

    if not key then
        lastKey = lastKey + 1
        key = lastKey
        soundKeys[identifier] = key
    end

    return ("zyrnex_music:%s:%s"):format(key, soundType)
end

local function notify(playerId, message)
    TriggerClientEvent("ox_lib:notify", playerId, { description = message, type = "error" })
end

local function validUrl(url)
    if type(url) ~= "string" then
        return
    end

    url = url:gsub("^%s+", ""):gsub("%s+$", "")

    if #url < 8 or #url > 512 or not url:find("^https?://") then
        return
    end

    return url
end

local function validVolume(volume)
    volume = tonumber(volume)

    if not volume then
        return Config.DefaultVolume
    end

    if volume < 0.0 then
        return 0.0
    end

    if volume > Config.MaxVolume then
        return Config.MaxVolume
    end

    return volume
end

local function validRadius(radius)
    radius = math.floor(tonumber(radius) or Config.DefaultConcertRadius)

    if radius < 1 then
        return 1
    end

    if radius > Config.MaxConcertRadius then
        return Config.MaxConcertRadius
    end

    return radius
end

local function validType(soundType)
    return soundType == "car" or soundType == "radio" or soundType == "concert"
end

local function elapsed(sound)
    return (sound.paused and sound.pausedAt or os.time()) - sound.startedAt
end

local function soundState(sound)
    if not sound then
        return nil
    end

    return {
        id = sound.id,
        type = sound.type,
        url = sound.url,
        volume = sound.volume,
        paused = sound.paused,
        radius = sound.distance,
    }
end

local function pushState(playerId, soundType, sound)
    TriggerClientEvent("zyrnex_music:state", playerId, soundType, soundState(sound))
end

local function stopSound(identifier, soundType)
    local id = soundId(identifier, soundType)
    local sound = sounds[id]

    if not sound then
        return false
    end

    sounds[id] = nil
    xsound:Destroy(-1, id)
    pushState(sound.source, soundType, nil)

    return true
end

local function startSound(identifier, soundType, playerId, url, volume, coords, distance)
    local id = soundId(identifier, soundType)

    if sounds[id] then
        xsound:Destroy(-1, id)
    end

    local sound = {
        id = id,
        type = soundType,
        source = playerId,
        identifier = identifier,
        url = url,
        volume = volume,
        coords = coords,
        distance = distance,
        paused = false,
        startedAt = os.time(),
    }

    sounds[id] = sound
    xsound:PlayUrlPos(-1, id, url, volume, coords, true)

    if distance then
        xsound:Distance(-1, id, distance)
    end

    pushState(playerId, soundType, sound)

    return sound
end

local function ownSound(playerId, soundType)
    if not validType(soundType) then
        return
    end

    local identifier = identifierOf(playerId)

    return sounds[soundId(identifier, soundType)], identifier
end

local function getBoombox(identifier, coords)
    for i = 1, #boomboxes do
        local boombox = boomboxes[i]

        if boombox.identifier == identifier and DoesEntityExist(boombox.entity) then
            if #(GetEntityCoords(boombox.entity) - coords) <= Config.RadioDistance then
                return boombox, i
            end
        end
    end
end

local function countBoomboxes(identifier)
    local count = 0

    for i = 1, #boomboxes do
        if boomboxes[i].identifier == identifier then
            count = count + 1
        end
    end

    return count
end

CreateThread(function()
    while true do
        Wait(200)

        for id, sound in pairs(sounds) do
            if sound.type == "car" then
                local ped = GetPlayerPed(sound.source)

                if ped == 0 or GetVehiclePedIsIn(ped, false) == 0 then
                    sounds[id] = nil
                    xsound:Destroy(-1, id)
                    pushState(sound.source, "car", nil)
                else
                    sound.coords = GetEntityCoords(ped)
                    xsound:Position(-1, id, sound.coords)
                end
            end
        end
    end
end)

RegisterNetEvent("zyrnex_music:playSong", function(song, soundType, volume, radius)
    local playerId = source

    if not validType(soundType) then
        return
    end

    local url = validUrl(song)

    if not url then
        return notify(playerId, L("invalidUrl"))
    end

    local identifier = identifierOf(playerId)
    local ped = GetPlayerPed(playerId)
    local coords = GetEntityCoords(ped)
    local distance

    if soundType == "car" then
        if GetVehiclePedIsIn(ped, false) == 0 then
            return
        end
    elseif soundType == "radio" then
        local boombox = getBoombox(identifier, coords)

        if not boombox then
            return notify(playerId, L("notYours"))
        end

        coords = GetEntityCoords(boombox.entity)
    else
        if not concerts[identifier] then
            return notify(playerId, L("noPermission"))
        end

        distance = validRadius(radius)
        concerts[identifier] = distance
    end

    startSound(identifier, soundType, playerId, url, validVolume(volume), coords, distance)
end)

RegisterNetEvent("zyrnex_music:changeVolume", function(soundType, volume)
    local sound = ownSound(source, soundType)

    if not sound then
        return
    end

    sound.volume = validVolume(volume)
    xsound:setVolume(-1, sound.id, sound.volume)
end)

RegisterNetEvent("zyrnex_music:togglePause", function(soundType)
    local playerId = source
    local sound = ownSound(playerId, soundType)

    if not sound then
        return
    end

    if sound.paused then
        sound.startedAt = sound.startedAt + (os.time() - sound.pausedAt)
        sound.paused = false
        sound.pausedAt = nil
        xsound:Resume(-1, sound.id)
    else
        sound.paused = true
        sound.pausedAt = os.time()
        xsound:Pause(-1, sound.id)
    end

    pushState(playerId, soundType, sound)
end)

RegisterNetEvent("zyrnex_music:seek", function(soundType, time)
    local sound = ownSound(source, soundType)
    time = math.floor(tonumber(time) or -1)

    if not sound or time < 0 or (sound.duration and time > sound.duration) then
        return
    end

    sound.startedAt = (sound.paused and sound.pausedAt or os.time()) - time
    xsound:setTimeStamp(-1, sound.id, time)
end)

RegisterNetEvent("zyrnex_music:setRadius", function(radius)
    local sound, identifier = ownSound(source, "concert")

    if not concerts[identifier] then
        return
    end

    radius = validRadius(radius)
    concerts[identifier] = radius

    if sound then
        sound.distance = radius
        xsound:Distance(-1, sound.id, radius)
    end
end)

RegisterNetEvent("zyrnex_music:duration", function(soundType, duration)
    local sound = ownSound(source, soundType)
    duration = tonumber(duration)

    if sound and duration and duration > 0 and duration < 86400 then
        sound.duration = math.floor(duration)
    end
end)

RegisterNetEvent("zyrnex_music:stopMusic", function(soundType)
    if not validType(soundType) then
        return
    end

    stopSound(identifierOf(source), soundType)
end)

RegisterNetEvent("zyrnex_music:pick", function()
    local playerId = source
    local identifier = identifierOf(playerId)
    local boombox, index = getBoombox(identifier, GetEntityCoords(GetPlayerPed(playerId)))

    if not boombox then
        return notify(playerId, L("notYours"))
    end

    if not exports.ox_inventory:CanCarryItem(playerId, Config.BoomboxItem, 1) then
        return notify(playerId, L("cantCarry"))
    end

    stopSound(identifier, "radio")
    DeleteEntity(boombox.entity)
    table.remove(boomboxes, index)
    exports.ox_inventory:AddItem(playerId, Config.BoomboxItem, 1)
    TriggerClientEvent("zyrnex_music:closed", playerId)
end)

RegisterNetEvent("zyrnex_music:ready", function()
    local playerId = source

    if ready[playerId] then
        return
    end

    ready[playerId] = true

    local identifier = identifierOf(playerId)

    for i = 1, #boomboxes do
        local boombox = boomboxes[i]

        if boombox.identifier == identifier and DoesEntityExist(boombox.entity) then
            Entity(boombox.entity).state:set(OWNER_KEY, playerId, true)
        end
    end

    local list = {}

    for _, sound in pairs(sounds) do
        local time = elapsed(sound)

        if sound.duration then
            time = time % sound.duration
        end

        list[#list + 1] = {
            id = sound.id,
            url = sound.url,
            volume = sound.volume,
            coords = sound.coords,
            distance = sound.distance,
            paused = sound.paused,
            time = time,
        }
    end

    if #list > 0 then
        TriggerClientEvent("zyrnex_music:sync", playerId, list)
    end
end)

lib.callback.register("zyrnex_music:open", function(playerId, soundType)
    if not validType(soundType) then
        return false
    end

    local identifier = identifierOf(playerId)
    local ped = GetPlayerPed(playerId)

    if soundType == "radio" then
        if not getBoombox(identifier, GetEntityCoords(ped)) then
            return false, L("notYours")
        end
    elseif soundType == "car" then
        local vehicle = GetVehiclePedIsIn(ped, false)

        if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then
            return false
        end
    elseif not concerts[identifier] then
        return false, L("noPermission")
    end

    return true, {
        state = soundState(sounds[soundId(identifier, soundType)]),
        radius = concerts[identifier],
        maxRadius = Config.MaxConcertRadius,
        maxVolume = Config.MaxVolume,
        defaultVolume = Config.DefaultVolume,
    }
end)

exports("boombox", function(event, _, inventory)
    local playerId = inventory.id
    local identifier = identifierOf(playerId)

    if event == "usingItem" then
        if countBoomboxes(identifier) >= Config.MaxBoomboxes then
            notify(playerId, L("tooManyRadios"))
            return false
        end

        return
    end

    if event ~= "usedItem" then
        return
    end

    local coords = GetEntityCoords(GetPlayerPed(playerId))
    local entity = CreateObject(joaat(Config.BoomboxProp), coords.x + 0.5, coords.y + 0.5, coords.z - 1.0, true, false,
        false)

    if not DoesEntityExist(entity) then
        exports.ox_inventory:AddItem(playerId, Config.BoomboxItem, 1)
        return
    end

    FreezeEntityPosition(entity, true)
    Entity(entity).state:set(OWNER_KEY, playerId, true)
    boomboxes[#boomboxes + 1] = { entity = entity, identifier = identifier }
end)

RegisterCommand(Config.Commands.concert, function(playerId, args)
    if playerId == 0 then
        return
    end

    if not IsPlayerAceAllowed(playerId, Config.ConcertAce) then
        return notify(playerId, L("noPermission"))
    end

    concerts[identifierOf(playerId)] = validRadius(args[1])
    TriggerClientEvent("zyrnex_music:openConcert", playerId)
end, false)

AddEventHandler("playerDropped", function()
    local playerId = source
    local identifier = identifiers[playerId]

    ready[playerId] = nil
    identifiers[playerId] = nil

    if not identifier then
        return
    end

    concerts[identifier] = nil
    stopSound(identifier, "car")
    stopSound(identifier, "radio")
    stopSound(identifier, "concert")
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    for id in pairs(sounds) do
        xsound:Destroy(-1, id)
    end

    for i = 1, #boomboxes do
        local entity = boomboxes[i].entity

        if DoesEntityExist(entity) then
            DeleteEntity(entity)
        end
    end
end)
