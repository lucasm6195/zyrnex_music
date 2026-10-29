local xsound = exports["xsound"]

local model = joaat(Config.BoomboxProp)

local OWNER_KEY = "zyrnex_music:owner"

local player = { open = false, type = nil, state = nil, reported = nil }

local function isOwner(entity)
    return Entity(entity).state[OWNER_KEY] == GetPlayerServerId(PlayerId())
end

local function closePlayer()
    if not player.open then
        return
    end

    player.open = false
    player.type = nil
    SendNUIMessage({ action = "close" })
    SetNuiFocus(false, false)
end

local function progressLoop()
    CreateThread(function()
        while player.open do
            local state = player.state
            local id = state and state.id

            if id and xsound:soundExists(id) then
                local duration = xsound:getMaxDuration(id)

                SendNUIMessage({
                    action = "progress",
                    time = xsound:getTimeStamp(id),
                    duration = duration,
                })

                if duration and duration > 0 and player.reported ~= id then
                    player.reported = id
                    TriggerServerEvent("zyrnex_music:duration", player.type, duration)
                end
            end

            Wait(500)
        end
    end)
end

local function openPlayer(soundType)
    if player.open then
        return
    end

    lib.callback("zyrnex_music:open", false, function(allowed, data)
        if not allowed then
            if data then
                lib.notify({ description = data, type = "error" })
            end
            return
        end

        player.open = true
        player.type = soundType
        player.state = data.state

        SendNUIMessage({
            action = "open",
            type = soundType,
            strings = UiStrings(),
            state = data.state,
            radius = data.radius,
            maxRadius = data.maxRadius,
            maxVolume = data.maxVolume,
            defaultVolume = data.defaultVolume,
        })
        SetNuiFocus(true, true)
        progressLoop()
    end, soundType)
end

exports.ox_target:addModel(model, {
    {
        name = "zyrnex_music:control",
        icon = "fa-solid fa-music",
        label = L("targetControl"),
        distance = Config.RadioDistance,
        canInteract = function(entity)
            return isOwner(entity)
        end,
        onSelect = function()
            openPlayer("radio")
        end,
    },
    {
        name = "zyrnex_music:pick",
        icon = "fa-solid fa-hand",
        label = L("targetPick"),
        distance = Config.RadioDistance,
        canInteract = function(entity)
            return isOwner(entity)
        end,
        onSelect = function()
            TriggerServerEvent("zyrnex_music:pick")
        end,
    },
})

RegisterCommand(Config.Commands.carRadio, function()
    if player.open then
        return closePlayer()
    end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
        openPlayer("car")
    end
end, false)

RegisterNetEvent("zyrnex_music:openConcert", function()
    openPlayer("concert")
end)

RegisterNetEvent("zyrnex_music:state", function(soundType, state)
    if player.type ~= soundType then
        return
    end

    player.state = state
    SendNUIMessage({ action = "state", state = state })
end)

RegisterNetEvent("zyrnex_music:closed", closePlayer)

RegisterNetEvent("zyrnex_music:sync", function(list)
    for i = 1, #list do
        local sound = list[i]
        local id = sound.id

        xsound:PlayUrlPos(id, sound.url, sound.volume, sound.coords, true, {
            onPlayStart = function()
                if sound.time > 0 then
                    xsound:setTimeStamp(id, sound.time)
                end

                if sound.paused then
                    xsound:Pause(id)
                end
            end,
        })

        if sound.distance then
            xsound:Distance(id, sound.distance)
        end
    end
end)

RegisterNUICallback("close", function(_, cb)
    closePlayer()
    cb(true)
end)

RegisterNUICallback("play", function(info, cb)
    TriggerServerEvent("zyrnex_music:playSong", info.song, player.type, info.volume, info.radius)
    cb(true)
end)

RegisterNUICallback("volume", function(info, cb)
    TriggerServerEvent("zyrnex_music:changeVolume", player.type, info.volume)
    cb(true)
end)

RegisterNUICallback("pause", function(_, cb)
    TriggerServerEvent("zyrnex_music:togglePause", player.type)
    cb(true)
end)

RegisterNUICallback("seek", function(info, cb)
    TriggerServerEvent("zyrnex_music:seek", player.type, info.time)
    cb(true)
end)

RegisterNUICallback("radius", function(info, cb)
    if player.type == "concert" then
        TriggerServerEvent("zyrnex_music:setRadius", info.radius)
    end
    cb(true)
end)

RegisterNUICallback("stop", function(_, cb)
    TriggerServerEvent("zyrnex_music:stopMusic", player.type)
    cb(true)
end)

RegisterNUICallback("pick", function(_, cb)
    if player.type == "radio" then
        TriggerServerEvent("zyrnex_music:pick")
    end
    cb(true)
end)

AddEventHandler("onResourceStop", function(resource)
    if resource ~= GetCurrentResourceName() then
        return
    end

    if player.open then
        SetNuiFocus(false, false)
    end
end)

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do
        Wait(500)
    end

    TriggerServerEvent("zyrnex_music:ready")
end)
