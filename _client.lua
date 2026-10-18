if SERVER == nil and CLIENT == nil then
    SERVER = IsDuplicityVersion()
    CLIENT = not SERVER
end

if type(module) ~= 'function' then
    local code = LoadResourceFile('vrp', 'lib/utils.lua') or LoadResourceFile('vRP', 'lib/utils.lua')
    assert(code, 'combo_lategame: vrp/lib/utils.lua nao encontrado (o resource vrp esta iniciado?)')
    load(code, '@@vrp/lib/utils.lua')()
end

function import(path)
    return module('vrp', path)
end

local Tunnel = import('lib/Tunnel')

local function comboRequireLocal(path)
    local resource = GetCurrentResourceName()
    local code = LoadResourceFile(resource, path) or LoadResourceFile(resource, path .. '.lua')
    if not code then
        error(('combo_lategame: arquivo nao encontrado: %s'):format(path))
    end
    local chunk, err = load(code, ('@@%s/%s'):format(resource, path))
    if not chunk then error(err) end
    return chunk()
end

local config = comboRequireLocal('config/config.lua')
local clientConfig = comboRequireLocal('config/client/functions.lua')

local apiClient = {}
Tunnel.bindInterface('combo_lategame', apiClient)
local apiServer = Tunnel.getInterface('combo_lategame')

local PlayerPedId = PlayerPedId
local GetEntityCoords = GetEntityCoords
local GetEntityHeading = GetEntityHeading
local GetEntityHealth = GetEntityHealth
local GetGameTimer = GetGameTimer
local GetHashKey = GetHashKey
local GiveWeaponToPed = GiveWeaponToPed
local IsPedDeadOrDying = IsPedDeadOrDying
local NetworkResurrectLocalPlayer = NetworkResurrectLocalPlayer
local SetEntityCoordsNoOffset = SetEntityCoordsNoOffset
local SetEntityHeading = SetEntityHeading
local SendNUIMessage = SendNUIMessage
local SetNuiFocus = SetNuiFocus
local TriggerServerEvent = TriggerServerEvent
local LoadResourceFile = LoadResourceFile
local GetCurrentResourceName = GetCurrentResourceName
local Wait = Citizen.Wait
local CreateThread = Citizen.CreateThread
local SetTimeout = Citizen.SetTimeout
local SetEntityCoords = SetEntityCoords
local DrawMarker = DrawMarker
local floor = math.floor
local ceil = math.ceil
local cos = math.cos
local sin = math.sin
local pi = math.pi
local sqrt = math.sqrt

local IMG_FALLBACK_SVG = 'data:image/svg+xml;charset=utf-8,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 width=%22320%22 height=%22180%22%3E%3Crect fill=%22%23242424%22 width=%22320%22 height=%22180%22/%3E%3Ctext x=%22160%22 y=%2295%22 fill=%22%23888%22 font-size=%2214%22 font-family=%22sans-serif%22 text-anchor=%22middle%22%3ELate Game%3C/text%3E%3C/svg%3E'
local IMG_PREFIXES = { 'web/images/', 'images/', 'web/lategame/' }

local isInMatch = false
local isSpectating = false
local spectatingPlayer = nil
local pendingInviteChallengeId = nil
local lgDeathSent = false
local lgProtectedUntil = 0
local lgSpawnCenter = nil
local lgBarrierRadius = 10.0
local lgSpawnGen = 0
local statisticOpen = false

local function vrpResourceName()
    if GetResourceState('vrp') == 'started' then return 'vrp' end
    if GetResourceState('vRP') == 'started' then return 'vRP' end
    return 'vrp'
end

local function nuiFileUrl(resourceName, relPath)
    relPath = tostring(relPath or ''):gsub('\\', '/'):gsub('^/+', '')
    return ('https://cfx-nui-%s/%s'):format(resourceName, relPath)
end

local function splitNuiAssetUrl(url)
    if type(url) ~= 'string' then return nil, nil end
    local res, rel = url:match('^nui://([^/]+)/(.+)$')
    if res and rel then return res, rel end
    return url:match('^https://cfx%-nui%-([^/]+)/(.+)$')
end

local function resolveVrpConfigPng(keys)
    local vrpRes = vrpResourceName()
    for _, key in ipairs(keys) do
        if type(key) == 'string' and key ~= '' then
            local rels = {
                ('config/inventory/%s.png'):format(key),
                ('config/%s.png'):format(key),
            }
            for _, rel in ipairs(rels) do
                local raw = LoadResourceFile(vrpRes, rel)
                if type(raw) == 'string' and #raw > 0 then
                    return nuiFileUrl(vrpRes, rel)
                end
            end
        end
    end
    return IMG_FALLBACK_SVG
end

local function weaponInventoryImageUrl(weaponSpawn)
    if type(weaponSpawn) ~= 'string' or weaponSpawn == '' then return nil end

    local imageKey = weaponSpawn
    if type(itemIndex) == 'function' then
        local ok, idx = pcall(itemIndex, weaponSpawn)
        if ok and type(idx) == 'string' and idx ~= '' then
            imageKey = idx
        end
    end

    local res = GetCurrentResourceName()
    local keys = { imageKey }
    if weaponSpawn ~= imageKey then keys[#keys + 1] = weaponSpawn end

    for _, key in ipairs(keys) do
        for _, prefix in ipairs(IMG_PREFIXES) do
            local rel = prefix .. key .. '.png'
            local raw = LoadResourceFile(res, rel)
            if type(raw) == 'string' and #raw > 0 then
                return nuiFileUrl(res, rel)
            end
        end
    end

    return resolveVrpConfigPng(keys)
end

local function resolveBannerUrlOnce(cfg)
    local res = GetCurrentResourceName()
    local tryPaths = {}
    local relForVrp = nil

    if type(cfg) == 'table' and type(cfg.Banner) == 'string' then
        local rawBanner = cfg.Banner:gsub('^%s+', ''):gsub('%s+$', '')

        if rawBanner:sub(1, 7) == 'WEAPON_' then
            local u = weaponInventoryImageUrl(rawBanner)
            if type(u) == 'string' and u ~= '' then return u end
            return IMG_FALLBACK_SVG
        end

        if rawBanner:match('^nui://') or rawBanner:match('^https://cfx%-nui%-') then
            local _, rel = splitNuiAssetUrl(rawBanner)
            if type(rel) == 'string' and rel ~= '' then
                local vrpRes = vrpResourceName()
                local raw = LoadResourceFile(vrpRes, rel)
                if type(raw) == 'string' and #raw > 0 then
                    return nuiFileUrl(vrpRes, rel)
                end
                local fname = rel:match('([^/]+)$')
                local base = fname and (fname:match('^(.+)%.[^.]+$') or fname)
                if type(base) == 'string' and base ~= '' then
                    local u = resolveVrpConfigPng({ base })
                    if type(u) == 'string' and u ~= '' and u ~= IMG_FALLBACK_SVG then
                        return u
                    end
                end
            end
        end

        local b = rawBanner:gsub('^%.%./', ''):gsub('^%./', ''):gsub('\\', '/'):gsub('^/+', '')
        relForVrp = b
        if b ~= '' then
            tryPaths[#tryPaths + 1] = b
            if not b:match('^web/') then
                tryPaths[#tryPaths + 1] = 'web/' .. b
            end
        end
    end
    tryPaths[#tryPaths + 1] = 'web/dist/assets/verified.5b3afc32.svg'

    for _, path in ipairs(tryPaths) do
        path = path:gsub('\\', '/')
        local raw = LoadResourceFile(res, path)
        if raw and #raw > 0 then
            return nuiFileUrl(res, path)
        end
    end

    if type(relForVrp) == 'string' and relForVrp ~= '' then
        local fname = relForVrp:match('([^/]+)$') or relForVrp
        local base = fname:match('^(.+)%.[^.]+$') or fname
        if base ~= '' then
            return resolveVrpConfigPng({ base })
        end
    end

    return IMG_FALLBACK_SVG
end

local function buildSortedList(source)
    local list = {}
    for key, data in pairs(source or {}) do
        if type(key) == 'string' and type(data) == 'table' and data.Name then
            list[#list + 1] = {
                id = key,
                name = data.Name,
                bannerURL = resolveBannerUrlOnce(data),
            }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local CACHED_GAME_MAPS = buildSortedList(config.Maps)
local CACHED_GAME_MODES = buildSortedList(config.Modes)

local function sendScoreboardNui(show, teams)
    pcall(function()
        SendNUIMessage({
            action = 'scoreboard',
            toggle = show and true or false,
            teams = teams or {},
        })
    end)
end

local function sendStatisticNui(show, data)
    pcall(function()
        SendNUIMessage({
            action = 'statistic',
            toggle = show and true or false,
            statistic = data,
        })
    end)
end

local function closeStatistic()
    if not statisticOpen then return end
    statisticOpen = false
    sendStatisticNui(false)
    if apiServer and apiServer.closeMatchStatistic then
        apiServer.closeMatchStatistic()
    end
end

local function toggleStatistic()
    if statisticOpen then
        closeStatistic()
        return
    end
    if not isInMatch then return end
    local data = apiServer and apiServer.openMatchStatistic and apiServer.openMatchStatistic()
    if type(data) == 'table' then
        statisticOpen = true
        sendStatisticNui(true, data)
    end
end

local function setWeaponDropOnDeath(ped, allowDrop)
    ped = ped or PlayerPedId()
    if ped and ped ~= 0 then
        SetPedDropsWeaponsWhenDead(ped, allowDrop and true or false)
    end
end

local function drawCountdownText(text, scale)
    SetTextFont(1)
    SetTextScale(scale, scale)
    SetTextColour(255, 255, 255, 255)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.5, 0.42)
end

local function drawSpawnBarrier(center, radius)
    local segments = 40
    local step = (2.0 * pi) / segments
    local width = radius * step * 1.6
    for i = 0, segments - 1 do
        local angle = i * step
        DrawMarker(1,
            center.x + cos(angle) * radius, center.y + sin(angle) * radius, center.z - 1.0,
            0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
            width, width, 3.0,
            200, 30, 30, 110,
            false, false, 2, false, nil, nil, false)
    end
end

local function clampInsideBarrier(center, radius)
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local dx, dy = pos.x - center.x, pos.y - center.y
    local dist = sqrt(dx * dx + dy * dy)
    if dist > radius then
        SetEntityCoords(ped, center.x + (dx / dist) * radius, center.y + (dy / dist) * radius, pos.z, false, false, false, false)
    end
end

local function killerServerIdFromEntity(entity)
    if not entity or entity == 0 then return nil end
    if not DoesEntityExist(entity) or not IsPedAPlayer(entity) then return nil end
    local idx = NetworkGetPlayerIndexFromPed(entity)
    if idx <= -1 then return nil end
    return GetPlayerServerId(idx)
end

local function enterMatchInternal(matchData)
    if type(matchData) ~= 'table' then return end

    lgSpawnGen = lgSpawnGen + 1
    local gen = lgSpawnGen
    lgDeathSent = true
    lgProtectedUntil = 0
    lgSpawnCenter = nil

    CreateThread(function()
        isInMatch = true

        local ped = PlayerPedId()
        clientConfig.setPedMaxHealth(ped)
        clientConfig.setEntityInvincible(ped, false)
        clientConfig.freezeEntityPosition(ped, false)

        local spawn = matchData.spawnPosition
        if spawn then
            local x = spawn.x + 0.0
            local y = spawn.y + 0.0
            local z = spawn.z + 0.0
            local heading = GetEntityHeading(ped) + 0.0

            NetworkResurrectLocalPlayer(x, y, z, heading, true, true, false)
            ped = PlayerPedId()
            ClearPedBloodDamage(ped)
            ClearPedTasksImmediately(ped)
            SetPedCanRagdoll(ped, true)
            clientConfig.setPedMaxHealth(ped)

            DoScreenFadeOut(200)
            while not IsScreenFadedOut() do Wait(0) end

            RequestCollisionAtCoord(x, y, z)
            SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
            SetEntityHeading(ped, heading)

            local deadline = GetGameTimer() + 5000
            while GetGameTimer() < deadline do
                if HasCollisionLoadedAroundEntity(ped) then break end
                Wait(0)
            end

            Wait(200)
            DoScreenFadeIn(300)

            ped = PlayerPedId()
            if IsPedDeadOrDying(ped, true) or GetEntityHealth(ped) <= 101 then
                NetworkResurrectLocalPlayer(x, y, z, heading, true, true, false)
                ped = PlayerPedId()
                ClearPedBloodDamage(ped)
                ClearPedTasksImmediately(ped)
                SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
                SetEntityHeading(ped, heading)
                clientConfig.setPedMaxHealth(ped)
            end
        end

        local weapons = matchData.weapons
        if type(weapons) == 'table' then
            clientConfig.removeAllPedWeapons(ped)
            local firstHash = nil
            for i = 1, #weapons do
                local weaponName = weapons[i]
                if type(weaponName) == 'string' and weaponName ~= '' then
                    local wh = GetHashKey(weaponName)
                    if wh ~= 0 then
                        GiveWeaponToPed(ped, wh, 250, false, true)
                        if not firstHash then firstHash = wh end
                    end
                end
            end
            if firstHash then
                SetCurrentPedWeapon(ped, firstHash, true)
            end
        end

        if type(matchData.scoreboard) == 'table' then
            Wait(150)
            sendScoreboardNui(true, matchData.scoreboard)
            Wait(400)
            sendScoreboardNui(true, matchData.scoreboard)
        end

        ped = PlayerPedId()
        if type(spawn) == 'table' then
            if IsPedDeadOrDying(ped, true) or GetEntityHealth(ped) <= 101 then
                local sx = spawn.x + 0.0
                local sy = spawn.y + 0.0
                local sz = spawn.z + 0.0
                local sh = GetEntityHeading(ped) + 0.0
                NetworkResurrectLocalPlayer(sx, sy, sz, sh, true, true, false)
                ped = PlayerPedId()
                ClearPedBloodDamage(ped)
                ClearPedTasksImmediately(ped)
                SetEntityCoordsNoOffset(ped, sx, sy, sz, false, false, false)
                SetEntityHeading(ped, sh)
            end
            clientConfig.setPedMaxHealth(ped)
        elseif not IsPedDeadOrDying(ped, true) and GetEntityHealth(ped) > 101 then
            clientConfig.setPedMaxHealth(ped)
        end

        setWeaponDropOnDeath(ped, false)

        local protectSec = tonumber(matchData.spawnProtect)
        local barrierCenter = matchData.sideCenter or matchData.spawnPosition
        if protectSec and protectSec > 0 and barrierCenter and gen == lgSpawnGen then
            local serverR = tonumber(matchData.barrierRadius) or 10.0
            local radius = tonumber(config.SpawnBarrierRadius) or serverR
            if radius < serverR * 0.7 then radius = serverR * 0.7 end

            lgProtectedUntil = GetGameTimer() + floor(protectSec * 1000)
            lgBarrierRadius = radius
            lgSpawnCenter = {
                x = barrierCenter.x + 0.0,
                y = barrierCenter.y + 0.0,
                z = barrierCenter.z + 0.0,
            }
            clientConfig.setEntityInvincible(ped, true)
            SetTimeout(floor(protectSec * 1000), function()
                if gen ~= lgSpawnGen then return end
                lgSpawnCenter = nil
                if isInMatch then
                    clientConfig.setEntityInvincible(PlayerPedId(), false)
                end
            end)
        end

        Wait(100)
        if gen == lgSpawnGen then
            lgDeathSent = false
        end
    end)
end

local function openComboLategamePanel()
    if isInMatch then
        pcall(function()
            config.notify(1, config.Language.CannotOpenPanel, 5000)
        end)
        return
    end
    pcall(function() SendNUIMessage({ action = 'painel' }) end)
    pcall(function() SetNuiFocus(true, true) end)
end

function apiClient.enterMatch(matchData)
    enterMatchInternal(matchData)
end

function apiClient.exitMatch(serverRestore)
    isInMatch = false
    lgDeathSent = false
    lgProtectedUntil = 0
    closeStatistic()
    sendScoreboardNui(false, {})
    TriggerServerEvent('combo_lategame:clearMatchState')

    lgSpawnCenter = nil
    local ped = PlayerPedId()
    clientConfig.removeAllPedWeapons(ped)
    clientConfig.setEntityInvincible(ped, false)
    setWeaponDropOnDeath(ped, true)

    if not serverRestore then
        pcall(function() SetPedArmour(ped, 0) end)
        clientConfig.setPedMaxHealth(ped)
    end
end

function apiClient.enterSpectatorMode(targetPlayer, targetName)
    isSpectating = true
    spectatingPlayer = targetPlayer

    local targetPed = GetPlayerPed(GetPlayerFromServerId(targetPlayer))
    clientConfig.setPlayerInSpectatorMode(true, targetPed)

    config.notify(3, config.Language.SpectatingPlayer .. (targetName or targetPlayer), 5000)
end

function apiClient.exitSpectatorMode()
    isSpectating = false
    clientConfig.setPlayerInSpectatorMode(false)
    spectatingPlayer = nil
end

function apiClient.setPlayerHealth(health)
    clientConfig.setEntityHealth(PlayerPedId(), health)
end

function apiClient.respawnPlayer()
    clientConfig.respawnPed(PlayerPedId())
end

RegisterNetEvent('combo_lategame:applyWeapons', function(weapons)
    if type(weapons) ~= 'table' then return end
    local ped = PlayerPedId()
    for k, v in pairs(weapons) do
        local weaponName, ammo = nil, 250
        if type(k) == 'number' and type(v) == 'string' then
            weaponName = v
        elseif type(k) == 'string' then
            weaponName = k
            if type(v) == 'table' and v.ammo ~= nil then
                ammo = tonumber(v.ammo) or ammo
            end
        end
        if weaponName and weaponName ~= '' then
            GiveWeaponToPed(ped, GetHashKey(weaponName), ammo, false, true)
        end
    end
end)

RegisterNetEvent('combo_lategame:receiveWeapon', function(weaponName, ammo)
    if type(weaponName) ~= 'string' then return end
    GiveWeaponToPed(PlayerPedId(), GetHashKey(weaponName), tonumber(ammo) or 250, false, true)
end)

RegisterNetEvent('combo_lategame:challengeInvite', function(challengeId, message)
    CreateThread(function()
        local cid = tonumber(challengeId)
        if not cid or type(message) ~= 'string' then return end

        if GetResourceState('ox_lib') == 'started' then
            local ok, result = pcall(function()
                return exports.ox_lib:alertDialog({
                    header = 'Late Game — Desafio',
                    content = message,
                    centered = true,
                    cancel = true,
                    labels = { cancel = 'Recusar', confirm = 'Aceitar' }
                })
            end)
            if ok then
                if result == 'confirm' then
                    apiServer.acceptChallenge(cid)
                    return
                end
                if result == 'cancel' then
                    TriggerServerEvent('combo_lategame:rejectChallenge', cid)
                    return
                end
            end
        end

        pendingInviteChallengeId = cid
        pcall(function()
            config.notify(3, message .. '\n~w~Digite ~y~/aceitarlg~w~ para aceitar.', 20000)
        end)
    end)
end)

RegisterNetEvent('combo_lategame:votationPhase', function(phase)
    if phase ~= 'mode' and phase ~= 'map' then return end
    CreateThread(function()
        Wait(0)
        SendNUIMessage({ action = 'updateVoteStatus', status = true })
        SetNuiFocus(true, true)
        if phase == 'mode' then
            SendNUIMessage({ action = 'voteMode', toggle = true })
        else
            SendNUIMessage({ action = 'voteMode', toggle = false })
            Wait(150)
            SendNUIMessage({ action = 'voteMap', toggle = true })
        end
    end)
end)

RegisterNetEvent('combo_lategame:votationClosed', function()
    SendNUIMessage({ action = 'voteMap', toggle = false })
    SendNUIMessage({ action = 'voteMode', toggle = false })
    SendNUIMessage({ action = 'updateVoteStatus', status = false })
    SetNuiFocus(false, false)
end)

RegisterNetEvent('combo_lategame:setScoreboard', function(show, teams)
    sendScoreboardNui(show, teams)
end)

RegisterNetEvent('combo_lategame:requestStashReturnCoords', function()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    TriggerServerEvent('combo_lategame:stashReturnCoords', c.x, c.y, c.z, GetEntityHeading(ped))
end)

RegisterNetEvent('combo_lategame:matchSeriesEnd', function(coords, serverRestore)
    CreateThread(function()
        local ped = PlayerPedId()
        if coords and type(coords.x) == 'number' and type(coords.y) == 'number' and type(coords.z) == 'number' then
            local x, y, z = coords.x + 0.0, coords.y + 0.0, coords.z + 0.0
            local heading = (coords.h ~= nil and coords.h + 0.0) or GetEntityHeading(ped)
            DoScreenFadeOut(200)
            while not IsScreenFadedOut() do Wait(0) end
            RequestCollisionAtCoord(x, y, z)
            NetworkResurrectLocalPlayer(x, y, z, heading, true, true, false)
            ped = PlayerPedId()
            SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
            SetEntityHeading(ped, heading)
            local deadline = GetGameTimer() + 5000
            while GetGameTimer() < deadline do
                if HasCollisionLoadedAroundEntity(ped) then break end
                Wait(0)
            end
            Wait(150)
            DoScreenFadeIn(300)
        end
        apiClient.exitMatch(serverRestore)
    end)
end)

RegisterNetEvent('combo_lategame:startSpectateTarget', function(targetServerId, targetName)
    targetServerId = tonumber(targetServerId)
    if not targetServerId then return end
    if isInMatch then
        pcall(function()
            config.notify(1, config.Language.CannotOpenPanel, 4000)
        end)
        return
    end
    SetNuiFocus(false, false)
    apiClient.enterSpectatorMode(targetServerId, targetName)
end)

RegisterNetEvent('combo_lategame:chatMessage', function(message)
    if type(message) ~= 'table' then return end
    pcall(function()
        SendNUIMessage({ action = 'updateChat', message = message })
    end)
end)

RegisterNetEvent('combo_lategame:updateStatistic', function(data)
    if statisticOpen and type(data) == 'table' then
        sendStatisticNui(true, data)
    end
end)

RegisterNetEvent('combo_lategame:killFeed', function(feed)
    if type(feed) ~= 'table' then return end
    pcall(function()
        SendNUIMessage({ action = 'killfeed', notify = feed })
    end)
end)

RegisterCommand('activeStatistic', toggleStatistic, false)

RegisterCommand('aceitarlg', function()
    if not pendingInviteChallengeId then return end
    local cid = pendingInviteChallengeId
    pendingInviteChallengeId = nil
    apiServer.acceptChallenge(cid)
end)

RegisterCommand('recusarlg', function()
    if pendingInviteChallengeId then
        TriggerServerEvent('combo_lategame:rejectChallenge', pendingInviteChallengeId)
    end
    pendingInviteChallengeId = nil
    pcall(function() config.notify(1, 'Desafio ignorado.', 4000) end)
end)

RegisterNUICallback('closeUi', function(_, cb)
    SetNuiFocus(false, false)
    cb({ status = true })
end)

RegisterNUICallback('closeStatistic', function(_, cb)
    closeStatistic()
    cb({ ok = true })
end)

RegisterNUICallback('painelCategories', function(_, cb)
    cb({
        data = {
            { id = 'teams', label = config.Language.Teams, placeHolder = true },
            { id = 'monitor', label = config.Language.Monitor },
            { id = 'spectate', label = config.Language.Spectate },
            { id = 'challenges', label = config.Language.Challenges }
        }
    })
end)

RegisterNUICallback('limitMembers', function(_, cb)
    cb({ limit = config.MaximumRoomMembers or 15 })
end)

RegisterNUICallback('availableGameMaps', function(_, cb)
    cb({ data = CACHED_GAME_MAPS })
end)

RegisterNUICallback('availableGameModes', function(_, cb)
    cb({ data = CACHED_GAME_MODES })
end)

RegisterNUICallback('voteGameMode', function(data, cb)
    cb({ status = apiServer.voteGameMode(data and data.mode) and true or false })
end)

RegisterNUICallback('voteGameMap', function(data, cb)
    local mapKey = data and (data.map or data.mode)
    cb({ status = apiServer.voteGameMap(mapKey) and true or false })
end)

RegisterNUICallback('sendMessage', function(data, cb)
    local content = data and data.content
    if type(content) ~= 'string' then cb({ ok = false }) return end
    content = content:gsub('^%s+', ''):gsub('%s+$', '')
    if content == '' then cb({ ok = false }) return end
    if #content > 255 then content = content:sub(1, 255) end
    if apiServer and apiServer.sendChatMessage then
        apiServer.sendChatMessage(content)
    end
    cb({ ok = true })
end)

RegisterNUICallback('availableTeamsToJoin', function(_, cb)
    cb({ data = apiServer.getRooms() or {} })
end)

RegisterNUICallback('tryCreateTeam', function(_, cb)
    cb({ hasVip = true, defaultName = '' })
end)

RegisterNUICallback('createTeam', function(data, cb)
    local success = false
    local name = data and data.name
    if name and name ~= '' then
        success = apiServer.createRoom(name)
    end
    cb({ status = success and true or false })
end)

RegisterNUICallback('joinTeam', function(data, cb)
    local teamId = data and tonumber(data.team)
    if not teamId then cb({ status = false }) return end
    cb({ status = apiServer.joinRoom(teamId) and true or false })
end)

RegisterNUICallback('currentTeam', function(_, cb)
    cb({ data = apiServer.getCurrentRoom() })
end)

RegisterNUICallback('availableTeamsToChallenge', function(_, cb)
    local myRoomId = apiServer.getPlayerRoomId()
    local rooms = apiServer.getRooms() or {}
    local result = {}
    for i = 1, #rooms do
        local room = rooms[i]
        if myRoomId == nil or room.id ~= myRoomId then
            result[#result + 1] = room
        end
    end
    cb({ data = result })
end)

RegisterNUICallback('challengeTeam', function(data, cb)
    local teamId = data and tonumber(data.team)
    if not teamId then cb({ status = false }) return end
    cb({ status = apiServer.sendChallenge(teamId) and true or false })
end)

RegisterNUICallback('deleteTeam', function(data, cb)
    local teamId = data and tonumber(data.team)
    if not teamId then cb({ status = false }) return end
    cb({ status = apiServer.deleteRoom(teamId) and true or false })
end)

RegisterNUICallback('leftTeam', function(data, cb)
    local teamId = data and tonumber(data.team)
    if not teamId then cb({ status = false }) return end
    cb({ status = apiServer.leaveRoom(teamId) and true or false })
end)

RegisterNUICallback('kickMember', function(data, cb)
    local id = data and tonumber(data.id)
    if not id then cb({ status = false }) return end
    cb({ status = apiServer.kickFromMyRoom(id) and true or false })
end)

RegisterNUICallback('availableGamesToMonitor', function(_, cb)
    local list = {}
    if apiServer and apiServer.getActiveMatchCards then
        list = apiServer.getActiveMatchCards() or {}
    end
    cb({ data = list })
end)

RegisterNUICallback('monitorGame', function(data, cb)
    local gid = data and tonumber(data.game)
    local ok = false
    if gid and apiServer and apiServer.monitorRunningMatch then
        ok = apiServer.monitorRunningMatch(gid) and true or false
    end
    cb({ status = ok })
end)

RegisterNUICallback('availableGamesToSpectate', function(_, cb)
    local list = {}
    if apiServer and apiServer.getActiveMatchCards then
        list = apiServer.getActiveMatchCards() or {}
    end
    cb({ data = list })
end)

RegisterNUICallback('spectateGame', function(data, cb)
    local gid = data and tonumber(data.game)
    local ok = false
    if gid and apiServer and apiServer.spectateRunningMatch then
        ok = apiServer.spectateRunningMatch(gid) and true or false
    end
    cb({ status = ok })
end)

RegisterNetEvent('combo_lategame:enterMatch', enterMatchInternal)
RegisterNetEvent('combo_lategame:newRound', enterMatchInternal)

clientConfig.openHandler(openComboLategamePanel)
clientConfig.openHandlerSpectator(function()
    if isSpectating then
        apiClient.exitSpectatorMode()
        pcall(function() config.notify(2, 'Modo espectador encerrado.', 4000) end)
    end
end)

CreateThread(function()
    RegisterKeyMapping('lategame', 'Late Game - Abrir painel', 'keyboard', 'F9')
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    sendScoreboardNui(false, {})
    setWeaponDropOnDeath(PlayerPedId(), true)
end)

CreateThread(function()
    while true do
        if isInMatch then
            clientConfig.disableControls()
            Wait(0)
        else
            Wait(1000)
        end
    end
end)

CreateThread(function()
    while true do
        if isSpectating then
            if spectatingPlayer then
                local targetPed = GetPlayerPed(GetPlayerFromServerId(spectatingPlayer))
                if targetPed and targetPed ~= 0 then
                    clientConfig.setPlayerInSpectatorMode(true, targetPed)
                end
            end
            Wait(0)
        else
            Wait(1000)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(200)
        if isInMatch and LocalPlayer.state.combo_lategame_match then
            local ped = PlayerPedId()
            setWeaponDropOnDeath(ped, false)
            if GetGameTimer() >= lgProtectedUntil then
                if IsPedDeadOrDying(ped, true) or GetEntityHealth(ped) <= 101 then
                    if not lgDeathSent then
                        lgDeathSent = true
                        TriggerServerEvent('combo_lategame:roundPlayerDown', killerServerIdFromEntity(GetPedSourceOfDeath(ped)))
                    end
                elseif lgDeathSent then
                    lgDeathSent = false
                end
            end
        elseif not isInMatch then
            lgDeathSent = false
        end
    end
end)

CreateThread(function()
    while true do
        if isInMatch or LocalPlayer.state.combo_lategame_match then
            setWeaponDropOnDeath(PlayerPedId(), false)
            Wait(150)
        else
            Wait(800)
        end
    end
end)

AddEventHandler('gameEventTriggered', function(event, args)
    if event ~= 'CEventNetworkEntityDamage' then return end
    if not isInMatch or lgDeathSent then return end
    if GetGameTimer() < lgProtectedUntil then return end
    local victim = args[1]
    if victim ~= PlayerPedId() then return end
    if GetEntityHealth(victim) > 101 then return end
    lgDeathSent = true
    TriggerServerEvent('combo_lategame:roundPlayerDown', killerServerIdFromEntity(args[2]))
end)

CreateThread(function()
    while true do
        if isInMatch and lgProtectedUntil > 0 then
            local remaining = lgProtectedUntil - GetGameTimer()
            if remaining > 0 then
                drawCountdownText(tostring(ceil(remaining / 1000)), 2.2)
                if lgSpawnCenter then
                    drawSpawnBarrier(lgSpawnCenter, lgBarrierRadius)
                    clampInsideBarrier(lgSpawnCenter, lgBarrierRadius)
                end
                Wait(0)
            elseif remaining > -1200 then
                drawCountdownText('GO!', 2.6)
                Wait(0)
            else
                Wait(250)
            end
        else
            Wait(300)
        end
    end
end)

return apiClient
