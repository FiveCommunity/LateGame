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
local serverConfig = comboRequireLocal('config/server/functions.lua')

local TriggerClientEvent = TriggerClientEvent
local GetPlayerName = GetPlayerName
local osTime = os.time
local osDate = os.date
local floor = math.floor
local min = math.min
local max = math.max
local cos = math.cos
local sin = math.sin
local pi = math.pi
local tsort = table.sort
local tinsert = table.insert
local tremove = table.remove

local LG_BUCKET_BASE = 1000

local VOTE_MODE_SECONDS = tonumber(GetConvar('combo_lategame_vote_mode_sec', '120')) or 120
local VOTE_MAP_SECONDS = tonumber(GetConvar('combo_lategame_vote_map_sec', '120')) or 120

local rooms = {}
local nextRoomId = 0
local nextLgMatchId = 0
local lgMatches = {}
local lgReturnCoords = {}
local pendingChallenges = {}
local nextChallengeId = 0
local activeVotation = nil
local lastChatAt = {}

local apiServer = {}
Tunnel.bindInterface('combo_lategame', apiServer)

local function lgUseDimensions()
    return not config.DisableDimensionsVerify and serverConfig ~= nil
end

local function getUserId(src)
    if not serverConfig or not serverConfig.getUserId then return nil end
    local ok, id = pcall(serverConfig.getUserId, src)
    if ok then return id end
    return nil
end

local function getUserSource(userId)
    if not serverConfig or not serverConfig.getUserSource then return nil end
    local ok, src = pcall(serverConfig.getUserSource, userId)
    if ok then return src end
    return nil
end

local function getUserName(src)
    if not serverConfig or not serverConfig.getUserName then return nil end
    local ok, name = pcall(serverConfig.getUserName, src)
    if ok and type(name) == 'string' then return name end
    return nil
end

local function getPlayerInfo(source)
    local name = getUserName(source)
    if type(name) == 'string' then
        name = name:gsub('^%s+', ''):gsub('%s+$', '')
    end
    if not name or name == '' then
        name = GetPlayerName(source) or 'Desconhecido'
    end
    return { source = source, user_id = getUserId(source), name = name }
end

local function allocRoomId()
    nextRoomId = nextRoomId + 1
    return nextRoomId
end

local function pluralityAmongVotes(votes)
    if type(votes) ~= 'table' then return nil end
    local counts = {}
    for _, choice in pairs(votes) do
        if choice ~= nil then
            counts[choice] = (counts[choice] or 0) + 1
        end
    end
    local ranked = {}
    for choice, cnt in pairs(counts) do
        ranked[#ranked + 1] = { choice = choice, cnt = cnt }
    end
    tsort(ranked, function(a, b)
        if a.cnt ~= b.cnt then return a.cnt > b.cnt end
        return tostring(a.choice) < tostring(b.choice)
    end)
    return ranked[1] and ranked[1].choice or nil
end

local function voteMajorityWinner(votes, participants)
    if not votes or not participants or #participants == 0 then return nil end
    local need = floor(#participants / 2) + 1
    local counts = {}
    for i = 1, #participants do
        local choice = votes[participants[i]]
        if choice then
            counts[choice] = (counts[choice] or 0) + 1
        end
    end
    for choice, cnt in pairs(counts) do
        if cnt >= need then return choice end
    end
    return nil
end

local function resolveVoteWinner(votes, participants)
    local maj = voteMajorityWinner(votes, participants)
    if maj then return maj end
    if not votes or not participants then return nil end
    for i = 1, #participants do
        if not votes[participants[i]] then return nil end
    end
    local counts = {}
    for i = 1, #participants do
        local c = votes[participants[i]]
        counts[c] = (counts[c] or 0) + 1
    end
    local ranked = {}
    for choice, cnt in pairs(counts) do
        ranked[#ranked + 1] = { choice = choice, cnt = cnt }
    end
    tsort(ranked, function(a, b)
        if a.cnt ~= b.cnt then return a.cnt > b.cnt end
        return tostring(a.choice) < tostring(b.choice)
    end)
    return ranked[1] and ranked[1].choice or nil
end

local function defaultModeKey()
    if config.Modes and config.Modes.Pistols then return 'Pistols' end
    if config.Modes then
        for k in pairs(config.Modes) do return k end
    end
    return 'Pistols'
end

local function defaultMapKey()
    if config.Maps then
        local keys = {}
        for k in pairs(config.Maps) do keys[#keys + 1] = k end
        tsort(keys)
        return keys[1]
    end
    return nil
end

local function mergeRoomMembers(roomA, roomB)
    local seen = {}
    local out = {}
    local source = { roomA, roomB }
    for r = 1, #source do
        local room = source[r]
        if room and room.members then
            for i = 1, #room.members do
                local src = room.members[i]
                if not seen[src] then
                    seen[src] = true
                    out[#out + 1] = src
                end
            end
        end
    end
    return out
end

local function isVotationParticipant(src)
    if not activeVotation then return false end
    local participants = activeVotation.participants
    for i = 1, #participants do
        if participants[i] == src then return true end
    end
    return false
end

local function chatNowString()
    local t = osDate('*t')
    return string.format('%02d:%02d', t.hour, t.min)
end

local function chatAuthorName(src)
    local info = getPlayerInfo(src)
    if type(info) == 'table' and type(info.name) == 'string' and info.name ~= '' then
        return info.name
    end
    return GetPlayerName(src) or ('Jogador ' .. tostring(src))
end

local function broadcastVotationTextChat(authorSrc, content)
    local v = activeVotation
    if not v or (v.phase ~= 'mode' and v.phase ~= 'map') then return end
    if not isVotationParticipant(authorSrc) then return end

    local now = GetGameTimer()
    if lastChatAt[authorSrc] and (now - lastChatAt[authorSrc]) < 600 then return end
    lastChatAt[authorSrc] = now

    local author = chatAuthorName(authorSrc)
    local date = chatNowString()
    for i = 1, #v.participants do
        local p = v.participants[i]
        TriggerClientEvent('combo_lategame:chatMessage', p, {
            type = 'text',
            authorIsMyself = (p == authorSrc),
            author = author,
            content = content,
            date = date,
        })
    end
end

local function broadcastVotationVoteChat(authorSrc, modeOrMapName)
    local v = activeVotation
    if not v then return end
    if not isVotationParticipant(authorSrc) then return end

    local author = chatAuthorName(authorSrc)
    for i = 1, #v.participants do
        TriggerClientEvent('combo_lategame:chatMessage', v.participants[i], {
            type = 'vote',
            author = author,
            mode = tostring(modeOrMapName),
        })
    end
end

local function broadcastVotationPhase(phase)
    if not activeVotation then return end
    local participants = activeVotation.participants
    for i = 1, #participants do
        local src = participants[i]
        TriggerClientEvent('combo_lategame:votationPhase', src, phase)
        TriggerClientEvent('combo_lategame:requestStashReturnCoords', src)
    end
end

local function spawnCoords(vec)
    if not vec then return nil end
    local x = vec.x or vec[1]
    local y = vec.y or vec[2]
    local z = vec.z or vec[3]
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return nil end
    return x, y, z
end

local function lgAllSources(m)
    local t = {}
    for i = 1, #m.teamA do t[#t + 1] = m.teamA[i] end
    for i = 1, #m.teamB do t[#t + 1] = m.teamB[i] end
    return t
end

local function lgTeamStillAlive(m, teamList)
    for i = 1, #teamList do
        if m.alive[teamList[i]] then return true end
    end
    return false
end

local function lgScoreboardTeams(m)
    local function players(teamList)
        local list = {}
        for i = 1, #teamList do
            list[i] = { isAlive = m.alive[teamList[i]] and true or false }
        end
        return list
    end
    return {
        teamLeft = { wins = m.winsA, players = players(m.teamA) },
        teamRight = { wins = m.winsB, players = players(m.teamB) },
    }
end

local function lgBuildWeapons(modeKey, roundIdx)
    local roundsCfg = config.Rounds and config.Rounds[modeKey]
    local idx = min(max(tonumber(roundIdx) or 1, 1), 30)
    local pool = roundsCfg and (roundsCfg[idx] or roundsCfg[1])
    local weapons = {}
    if type(pool) == 'table' then
        for i = 1, #pool do weapons[i] = pool[i] end
    end
    if #weapons == 0 then
        local fb = config.Rounds and config.Rounds.Pistols and config.Rounds.Pistols[1]
        if type(fb) == 'table' then
            for i = 1, #fb do weapons[i] = fb[i] end
        end
    end
    return weapons
end

local function lgSpawnPosForMember(members, sideCfg, memberIndex, dist)
    local bx, by, bz = spawnCoords(sideCfg and sideCfg[1])
    if not bx then return nil end
    local n = #members
    local ox, oy = 0.0, 0.0
    if n > 1 then
        local angle = (memberIndex - 1) * (2 * pi / n)
        ox = cos(angle) * dist * 0.6
        oy = sin(angle) * dist * 0.6
    end
    return { x = bx + ox, y = by + oy, z = bz }
end

local function clearPlayerLgStates(src)
    pcall(function()
        Player(src).state:set('combo_lategame_match', false, true)
        Player(src).state:set('combo_lategame_mid', nil, true)
        Player(src).state:set('combo_lategame_team', nil, true)
        Player(src).state:set('inPvp', false, true)
    end)
end

local function lgSeriesMaxWins()
    return max(1, tonumber(config.MaxRoundWins) or 10)
end

local function lgRoundDelayMs()
    return max(1500, tonumber(config.RoundResetDelayMs) or 4000)
end

local function lgNotifyAll(m, kind, msg, timeMs)
    local all = lgAllSources(m)
    for i = 1, #all do
        config.notify(all[i], kind or 2, msg, timeMs or 6000)
    end
end

local function lgBroadcastScoreboard(m)
    local teams = lgScoreboardTeams(m)
    local all = lgAllSources(m)
    for i = 1, #all do
        TriggerClientEvent('combo_lategame:setScoreboard', all[i], true, teams)
    end
end

local function lgStatMembers(m, teamList)
    local members = {}
    for i = 1, #teamList do
        local st = m.stats and m.stats[teamList[i]]
        members[i] = {
            name = (st and st.name) or ('Jogador ' .. tostring(teamList[i])),
            kills = (st and st.kills) or 0,
            deaths = (st and st.deaths) or 0,
        }
    end
    return members
end

local function lgBuildStatistic(m)
    return {
        teamBottom = { name = m.labelA, wins = m.winsA, members = lgStatMembers(m, m.teamA) },
        teamTop = { name = m.labelB, wins = m.winsB, members = lgStatMembers(m, m.teamB) },
    }
end

local function lgPushStatistic(m)
    if not m.watchers then return end
    local data = lgBuildStatistic(m)
    for watcher in pairs(m.watchers) do
        TriggerClientEvent('combo_lategame:updateStatistic', watcher, data)
    end
end

local lgKillFeedId = 0

local function lgEmitKillFeed(m, killerName, victimName)
    lgKillFeedId = lgKillFeedId + 1
    local feed = { id = lgKillFeedId, killer = killerName, victim = victimName }
    local all = lgAllSources(m)
    for i = 1, #all do
        TriggerClientEvent('combo_lategame:killFeed', all[i], feed)
    end
end

local function lgRegisterDeath(m, victim, killerSrc)
    if m.alive[victim] == false then return false end
    m.alive[victim] = false

    local vStat = m.stats and m.stats[victim]
    if vStat then vStat.deaths = vStat.deaths + 1 end

    killerSrc = tonumber(killerSrc)
    if killerSrc and killerSrc ~= victim and m.stats then
        local kStat = m.stats[killerSrc]
        if kStat and (not vStat or kStat.team ~= vStat.team) then
            kStat.kills = kStat.kills + 1
            lgEmitKillFeed(m, kStat.name, (vStat and vStat.name) or (GetPlayerName(victim) or 'Jogador'))
        end
    end

    lgPushStatistic(m)
    return true
end

local function lgPickSpectateTargetSource(m)
    if not m or type(m.alive) ~= 'table' then return nil end
    local teamA, teamB = m.teamA or {}, m.teamB or {}
    for i = 1, #teamA do
        if m.alive[teamA[i]] then return teamA[i] end
    end
    for i = 1, #teamB do
        if m.alive[teamB[i]] then return teamB[i] end
    end
    if teamA[1] then return teamA[1] end
    if teamB[1] then return teamB[1] end
    return nil
end

local function lgFinishSeries(mid, reason, winnerLabel, looserLabel)
    local m = lgMatches[mid]
    if not m then return end

    local serverRestore = m.usedDimensions and true or false
    local all = lgAllSources(m)

    for i = 1, #all do
        local src = all[i]
        if serverRestore then
            TriggerClientEvent('combo_lategame:matchSeriesEnd', src, nil, true)
        else
            TriggerClientEvent('combo_lategame:matchSeriesEnd', src, lgReturnCoords[src], false)
        end
    end

    for i = 1, #all do
        local src = all[i]
        if serverRestore then
            pcall(serverConfig.setPlayerInfos, src)
        end
        clearPlayerLgStates(src)
        lgReturnCoords[src] = nil
    end

    lgMatches[mid] = nil

    if winnerLabel and serverConfig and serverConfig.sendWebhookWinner then
        pcall(serverConfig.sendWebhookWinner, winnerLabel, looserLabel, m.mapKey, m.modeKey)
    end
end

local function lgDisconnectSeries(mid, droppedSrc)
    if not lgMatches[mid] then return end
    local name = GetPlayerName(droppedSrc) or 'Jogador'
    lgNotifyAll(lgMatches[mid], 1, ('Partida encerrada: %s desconectou.'):format(name), 8000)
    lgFinishSeries(mid, 'disconnect')
end

local function lgSendRoundPayload(mid, useEnterMatchEvent)
    local m = lgMatches[mid]
    if not m then return end

    local dist = m.dist
    local weapons = lgBuildWeapons(m.modeKey, m.round)
    local teams = lgScoreboardTeams(m)
    local mapCfg = m.mapCfg
    local ev = useEnterMatchEvent and 'combo_lategame:enterMatch' or 'combo_lategame:newRound'

    local spawnProtect = 0
    if type(config.SpawnTimes) == 'table' then
        if (m.round or 1) <= 1 then
            spawnProtect = tonumber(config.SpawnTimes.FirstRound) or 0
        else
            spawnProtect = tonumber(config.SpawnTimes.OthersRounds) or 0
        end
    end

    local function spawnSide(members, sideCfg, teamLetter)
        local bx, by, bz = spawnCoords(sideCfg and sideCfg[1])
        local sideCenter = bx and { x = bx, y = by, z = bz } or nil
        for i = 1, #members do
            local src = members[i]
            local pos = lgSpawnPosForMember(members, sideCfg, i, dist)
            if not pos then return end
            pcall(function()
                Player(src).state:set('combo_lategame_match', true, true)
                Player(src).state:set('combo_lategame_mid', mid, true)
                Player(src).state:set('inPvp', true, true)
                Player(src).state:set('combo_lategame_team', teamLetter, true)
            end)
            TriggerClientEvent(ev, src, {
                spawnPosition = pos,
                sideCenter = sideCenter,
                barrierRadius = dist,
                weapons = weapons,
                scoreboard = teams,
                spawnProtect = spawnProtect,
            })
        end
    end

    local sideA, sideB = mapCfg.SideOne, mapCfg.SideTwo
    if config.ChangeSideByRound and ((m.round or 1) % 2 == 0) then
        sideA, sideB = mapCfg.SideTwo, mapCfg.SideOne
    end

    spawnSide(m.teamA, sideA, 'A')
    spawnSide(m.teamB, sideB, 'B')
end

local function advanceModeToMapPhase(v, winner)
    if not v or not winner then return end
    if not config.Modes or not config.Modes[winner] then return end
    v.lockedMode = winner
    v.phase = 'map'
    v.mapDeadline = osTime() + VOTE_MAP_SECONDS
    for i = 1, #v.participants do
        config.notify(v.participants[i], 3, config.Language.WeaponVoteCompleted, 8000)
    end
    broadcastVotationPhase('map')
end

local function tryFinishModeVote()
    local v = activeVotation
    if not v or v.phase ~= 'mode' then return end
    local winner = resolveVoteWinner(v.modeVotes, v.participants)
    if not winner then return end
    advanceModeToMapPhase(v, winner)
end

local function tryExpireModeVote()
    local v = activeVotation
    if not v or v.phase ~= 'mode' or not v.modeDeadline then return end
    if osTime() < v.modeDeadline then return end
    local winner = resolveVoteWinner(v.modeVotes, v.participants)
        or pluralityAmongVotes(v.modeVotes)
        or defaultModeKey()
    if not config.Modes[winner] then winner = defaultModeKey() end
    advanceModeToMapPhase(v, winner)
end

local function startMatchFromVotation(v)
    if not v or not v.lockedMap or not v.lockedMode then return end

    local mapKey = v.lockedMap
    local modeKey = v.lockedMode
    local mapCfg = config.Maps and config.Maps[mapKey]
    local roomA = v.roomA and rooms[v.roomA]
    local roomB = v.roomB and rooms[v.roomB]
    if not mapCfg or not roomA or not roomB then return end

    local dist = tonumber(mapCfg.SpawnDistance) or 8

    local teamA, teamB = {}, {}
    for i = 1, #v.participants do
        local src = v.participants[i]
        local inA = false
        for j = 1, #roomA.members do
            if roomA.members[j] == src then inA = true break end
        end
        if inA then
            teamA[#teamA + 1] = src
        else
            teamB[#teamB + 1] = src
        end
    end

    if lgUseDimensions() and serverConfig.canUserJoinInGame then
        for i = 1, #v.participants do
            local src = v.participants[i]
            local ok, canJoin = pcall(serverConfig.canUserJoinInGame, src)
            if not ok or canJoin == false then
                local blockedName = GetPlayerName(src) or ('Jogador ' .. tostring(src))
                for j = 1, #v.participants do
                    config.notify(v.participants[j], 1, string.format(config.Language.MatchCanceled, blockedName), 9000)
                end
                return
            end
        end
    end

    nextLgMatchId = nextLgMatchId + 1
    local matchId = nextLgMatchId
    local m = {
        teamA = teamA,
        teamB = teamB,
        winsA = 0,
        winsB = 0,
        round = 1,
        alive = {},
        mapCfg = mapCfg,
        modeKey = modeKey,
        mapKey = mapKey,
        dist = dist,
        dimension = LG_BUCKET_BASE + matchId,
        usedDimensions = lgUseDimensions(),
        pendingResolve = false,
        labelA = roomA.name or 'Time A',
        labelB = roomB.name or 'Time B',
        stats = {},
        watchers = {},
    }
    for i = 1, #teamA do
        local src = teamA[i]
        m.alive[src] = true
        m.stats[src] = { name = getPlayerInfo(src).name, kills = 0, deaths = 0, team = 'A' }
    end
    for i = 1, #teamB do
        local src = teamB[i]
        m.alive[src] = true
        m.stats[src] = { name = getPlayerInfo(src).name, kills = 0, deaths = 0, team = 'B' }
    end
    lgMatches[matchId] = m

    if m.usedDimensions then
        for i = 1, #v.participants do
            local src = v.participants[i]
            pcall(serverConfig.savePlayerInfos, src)
            pcall(serverConfig.setPlayerRoutingBucket, src, m.dimension)
        end
    end

    lgSendRoundPayload(matchId, true)

    for i = 1, #v.participants do
        config.notify(v.participants[i], 2, 'Partida iniciada. Boa sorte!', 6000)
    end
end

local function finalizeMapVote(v)
    if not v or not v.lockedMap or not v.lockedMode then return end

    local mapKey = v.lockedMap
    local mapName = mapKey
    local mapCfg = config.Maps and config.Maps[mapKey]
    if type(mapCfg) == 'table' and mapCfg.Name then mapName = mapCfg.Name end

    for i = 1, #v.participants do
        local src = v.participants[i]
        config.notify(src, 2, ('Votação finalizada. Mapa: %s | Modo: %s'):format(mapName, tostring(v.lockedMode)), 10000)
        TriggerClientEvent('combo_lategame:votationClosed', src)
    end

    startMatchFromVotation(v)
    activeVotation = nil
end

local function tryFinishMapVote()
    local v = activeVotation
    if not v or v.phase ~= 'map' then return end
    local winner = resolveVoteWinner(v.mapVotes, v.participants)
    if not winner then return end
    v.lockedMap = winner
    finalizeMapVote(v)
end

local function tryExpireMapVote()
    local v = activeVotation
    if not v or v.phase ~= 'map' or not v.mapDeadline then return end
    if osTime() < v.mapDeadline then return end
    local winner = resolveVoteWinner(v.mapVotes, v.participants)
        or pluralityAmongVotes(v.mapVotes)
        or defaultMapKey()
    if winner and config.Maps and not config.Maps[winner] then
        winner = defaultMapKey()
    end
    if not winner then return end
    v.lockedMap = winner
    finalizeMapVote(v)
end

function apiServer.voteGameMode(modeKey)
    local source = source
    modeKey = modeKey and tostring(modeKey) or nil
    local v = activeVotation
    if not v or v.phase ~= 'mode' or not modeKey then return false end
    if not isVotationParticipant(source) then return false end
    if not config.Modes or not config.Modes[modeKey] then return false end

    v.modeVotes[source] = modeKey
    local label = (config.Modes[modeKey] and config.Modes[modeKey].Name) or modeKey
    broadcastVotationVoteChat(source, label)
    tryFinishModeVote()
    tryExpireModeVote()
    return true
end

function apiServer.voteGameMap(mapKey)
    local source = source
    mapKey = mapKey and tostring(mapKey) or nil
    local v = activeVotation
    if not v or v.phase ~= 'map' or not mapKey then return false end
    if not isVotationParticipant(source) then return false end
    if not config.Maps or not config.Maps[mapKey] then return false end

    v.mapVotes[source] = mapKey
    local label = (config.Maps[mapKey] and config.Maps[mapKey].Name) or mapKey
    broadcastVotationVoteChat(source, label)
    tryFinishMapVote()
    tryExpireMapVote()
    return true
end

function apiServer.sendChatMessage(content)
    local source = source
    if type(content) ~= 'string' then return false end
    content = content:gsub('^%s+', ''):gsub('%s+$', '')
    if content == '' then return false end
    if #content > 255 then content = content:sub(1, 255) end
    broadcastVotationTextChat(source, content)
    return true
end

function apiServer.getPlayerRoomId()
    local source = source
    for roomId, room in pairs(rooms) do
        for i = 1, #room.members do
            if room.members[i] == source then return roomId end
        end
    end
    return nil
end

function apiServer.createRoom(roomName)
    local source = source
    local playerInfo = getPlayerInfo(source)
    if not playerInfo then
        playerInfo = { source = source, name = GetPlayerName(source) or 'Desconhecido' }
    end

    if serverConfig and serverConfig.userCanOpenLateGame then
        local ok, allowed = pcall(serverConfig.userCanOpenLateGame, source)
        if ok and allowed == false then
            config.notify(source, 1, config.Language.CannotOpenPanel, 5000)
            return false
        end
    end

    if apiServer.getPlayerRoomId() ~= nil then
        config.notify(source, 1, 'Você já está em uma equipe.', 5000)
        return false
    end

    if not roomName or roomName == '' then
        config.notify(source, 1, config.Language.CannotUseThisName, 5000)
        return false
    end

    if serverConfig and serverConfig.checkQueueName then
        local ok, allowed = pcall(serverConfig.checkQueueName, roomName, source)
        if ok and allowed == false then
            config.notify(source, 1, config.Language.CannotUseThisName, 5000)
            return false
        end
    end

    for _, room in pairs(rooms) do
        if room.name == roomName then
            config.notify(source, 1, config.Language.NameAlreadyExists, 5000)
            return false
        end
    end

    local roomId = allocRoomId()
    rooms[roomId] = {
        id = roomId,
        name = roomName,
        owner = source,
        ownerName = playerInfo.name,
        members = { source },
        isInVoting = false,
        currentMatch = nil,
        createdAt = osTime()
    }

    config.notify(source, 2, 'Sala criada com sucesso!', 5000)
    return true, roomId
end

function apiServer.joinRoom(roomId)
    local source = source
    local playerInfo = getPlayerInfo(source)
    roomId = tonumber(roomId)
    if not playerInfo then return false end

    local currentRoomId = apiServer.getPlayerRoomId()
    if currentRoomId ~= nil then
        if currentRoomId == roomId then return false end
        config.notify(source, 1, 'Você já está em uma equipe.', 5000)
        return false
    end

    local room = rooms[roomId]
    if not room then return false end

    for i = 1, #room.members do
        if room.members[i] == source then return false end
    end

    if #room.members >= config.MaximumRoomMembers then
        config.notify(source, 1, config.Language.MaximumLimitOfPlayers, 5000)
        return false
    end

    tinsert(room.members, source)
    config.notify(source, 2, 'Você entrou na sala: ' .. room.name, 5000)
    return true
end

function apiServer.leaveRoom(roomId)
    local source = source
    roomId = tonumber(roomId)
    local room = rooms[roomId]
    if not room then return false end

    for i = 1, #room.members do
        if room.members[i] == source then
            tremove(room.members, i)
            break
        end
    end

    if room.owner == source then
        if #room.members > 0 then
            room.owner = room.members[1]
        else
            rooms[roomId] = nil
        end
    end

    config.notify(source, 2, 'Você saiu da sala', 5000)
    return true
end

function apiServer.getRooms()
    local result = {}
    for roomId, room in pairs(rooms) do
        result[#result + 1] = {
            id = roomId,
            name = room.name,
            members = #room.members,
            owner = room.owner,
            verified = false,
            hasPassword = false
        }
    end
    return result
end

function apiServer.getActiveMatchCards()
    local list = {}
    for mid, m in pairs(lgMatches) do
        if type(m) == 'table' and type(mid) == 'number' then
            list[#list + 1] = {
                id = mid,
                teamTop = { name = tostring(m.labelA or 'Time A'), verified = false },
                teamBottom = { name = tostring(m.labelB or 'Time B'), verified = false },
            }
        end
    end
    tsort(list, function(a, b) return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end)
    return list
end

function apiServer.spectateRunningMatch(matchId)
    local src = source
    matchId = tonumber(matchId)
    if not matchId then return false end

    local m = lgMatches[matchId]
    if not m then return false end

    local all = lgAllSources(m)
    for i = 1, #all do
        if all[i] == src then
            config.notify(src, 1, 'Você já está nesta partida.', 5000)
            return false
        end
    end

    local target = lgPickSpectateTargetSource(m)
    if not target then return false end

    local targetName = (m.stats and m.stats[target] and m.stats[target].name) or getPlayerInfo(target).name
    TriggerClientEvent('combo_lategame:startSpectateTarget', src, target, targetName)
    return true
end

function apiServer.monitorRunningMatch(matchId)
    return apiServer.spectateRunningMatch(matchId)
end

function apiServer.getCurrentRoom()
    local source = source
    local roomId = apiServer.getPlayerRoomId()
    if not roomId then return nil end

    local room = rooms[roomId]
    if not room then return nil end

    local myPassport = getUserId(source) or source
    local ownerPassport = getUserId(room.owner) or room.owner

    local members = {}
    for i = 1, #room.members do
        local memberSource = room.members[i]
        local memberPassport = getUserId(memberSource) or memberSource
        members[#members + 1] = {
            id = memberPassport,
            owner = memberPassport == ownerPassport,
            myself = memberPassport == myPassport
        }
    end

    return {
        team = { id = roomId, name = room.name, verified = false, members = #room.members },
        members = members
    }
end

function apiServer.deleteRoom(roomId)
    local source = source
    roomId = tonumber(roomId)
    local room = rooms[roomId]
    if not room or room.owner ~= source then return false end
    rooms[roomId] = nil
    return true
end

function apiServer.kickMember(roomId, targetSource)
    local source = source
    roomId = tonumber(roomId)
    targetSource = tonumber(targetSource)
    local room = rooms[roomId]
    if not room or room.owner ~= source then return false end

    for i = 1, #room.members do
        if room.members[i] == targetSource then
            tremove(room.members, i)
            config.notify(targetSource, 1, config.Language.YouWereKickedOfTheRoom, 5000)
            return true
        end
    end
    return false
end

function apiServer.kickFromMyRoom(targetSource)
    local source = source
    targetSource = tonumber(targetSource)
    local roomId = apiServer.getPlayerRoomId()
    if not roomId then return false end

    local resolvedTarget = targetSource
    local maybeSource = getUserSource(targetSource)
    if maybeSource then resolvedTarget = maybeSource end

    return apiServer.kickMember(roomId, resolvedTarget)
end

function apiServer.sendChallenge(targetRoomId)
    local source = source
    local playerInfo = getPlayerInfo(source)
    targetRoomId = tonumber(targetRoomId)
    if not playerInfo then return false end

    local sourceRoom = nil
    for _, room in pairs(rooms) do
        for i = 1, #room.members do
            if room.members[i] == source then sourceRoom = room break end
        end
        if sourceRoom then break end
    end
    if not sourceRoom then return false end

    if sourceRoom.id == targetRoomId then
        config.notify(source, 1, config.Language.CannotChallengeYourRoom, 5000)
        return false
    end

    local targetRoom = rooms[targetRoomId]
    if not targetRoom then return false end

    sourceRoom.isInVoting = false
    targetRoom.isInVoting = false

    local now = osTime()
    for cid, ch in pairs(pendingChallenges) do
        if ch and (now - ch.createdAt) > 600 then
            pendingChallenges[cid] = nil
        end
    end

    for _, ch in pairs(pendingChallenges) do
        if ch and ch.fromOwner == source then
            config.notify(source, 1, config.Language.PendingRequests, 5000)
            return false
        end
    end

    nextChallengeId = nextChallengeId + 1
    local challengeId = nextChallengeId
    pendingChallenges[challengeId] = {
        id = challengeId,
        fromRoom = sourceRoom.id,
        toRoom = targetRoomId,
        fromOwner = source,
        createdAt = osTime()
    }

    local message = string.format(config.Language.AcceptChallenge, sourceRoom.name, #sourceRoom.members, config.MaximumRoomMembers)
    TriggerClientEvent('combo_lategame:challengeInvite', targetRoom.owner, challengeId, message)

    config.notify(source, 2, config.Language.RequestSent, 5000)
    return true
end

function apiServer.acceptChallenge(challengeId)
    local source = source
    challengeId = tonumber(challengeId)
    local challenge = pendingChallenges[challengeId]
    if not challenge then return false end

    local targetRoom = rooms[challenge.toRoom]
    if not targetRoom or targetRoom.owner ~= source then return false end

    local fromRoom = rooms[challenge.fromRoom]
    if not fromRoom then return false end

    pendingChallenges[challengeId] = nil

    for i = 1, #fromRoom.members do
        config.notify(fromRoom.members[i], 3, config.Language.StartVotation, 5000)
    end
    for i = 1, #targetRoom.members do
        config.notify(targetRoom.members[i], 3, config.Language.StartVotation, 5000)
    end

    fromRoom.isInVoting = false
    targetRoom.isInVoting = false

    activeVotation = {
        participants = mergeRoomMembers(fromRoom, targetRoom),
        roomA = fromRoom.id,
        roomB = targetRoom.id,
        modeVotes = {},
        mapVotes = {},
        phase = 'mode',
        lockedMode = nil,
        lockedMap = nil,
        modeDeadline = osTime() + VOTE_MODE_SECONDS,
        mapDeadline = nil,
    }
    broadcastVotationPhase('mode')
    return true
end

function apiServer.setWeaponsPed(src, weapons)
    if not src or type(weapons) ~= 'table' then return false end
    TriggerClientEvent('combo_lategame:applyWeapons', src, weapons)
    return true
end

local function lgPlayerMatch(src)
    local mid = nil
    pcall(function() mid = tonumber(Player(src).state.combo_lategame_mid) end)
    if mid and lgMatches[mid] then
        return mid, lgMatches[mid]
    end
end

function apiServer.openMatchStatistic()
    local src = source
    local _, m = lgPlayerMatch(src)
    if not m then return nil end
    m.watchers[src] = true
    return lgBuildStatistic(m)
end

function apiServer.closeMatchStatistic()
    local src = source
    local _, m = lgPlayerMatch(src)
    if m and m.watchers then
        m.watchers[src] = nil
    end
    return true
end

RegisterNetEvent('combo_lategame:rejectChallenge', function(challengeId)
    local src = source
    challengeId = tonumber(challengeId)
    if not challengeId then return end
    local challenge = pendingChallenges[challengeId]
    if not challenge then return end
    local targetRoom = rooms[challenge.toRoom]
    if not targetRoom or targetRoom.owner ~= src then return end
    pendingChallenges[challengeId] = nil
end)

RegisterNetEvent('combo_lategame:requestWeapon', function(weaponName, ammo)
    local src = source
    if type(weaponName) ~= 'string' then return end
    TriggerClientEvent('combo_lategame:receiveWeapon', src, weaponName, tonumber(ammo) or 250)
end)

RegisterNetEvent('combo_lategame:clearMatchState', function()
    local src = source
    local mid = nil
    pcall(function() mid = tonumber(Player(src).state.combo_lategame_mid) end)
    if mid and lgMatches[mid] then
        local name = GetPlayerName(src) or 'Jogador'
        lgNotifyAll(lgMatches[mid], 1, ('Late game encerrado: %s abandonou a sessão.'):format(name), 8000)
        lgFinishSeries(mid, 'forfeit')
        return
    end
    clearPlayerLgStates(src)
end)

RegisterNetEvent('combo_lategame:stashReturnCoords', function(x, y, z, h)
    local src = source
    if not isVotationParticipant(src) then return end
    if type(x) ~= 'number' or type(y) ~= 'number' or type(z) ~= 'number' then return end
    lgReturnCoords[src] = { x = x + 0.0, y = y + 0.0, z = z + 0.0, h = tonumber(h) or 0.0 }
end)

RegisterNetEvent('combo_lategame:roundPlayerDown', function(killerSrc)
    local victim = source
    local mid = nil
    pcall(function() mid = Player(victim).state.combo_lategame_mid end)
    mid = tonumber(mid)
    if not mid then return end

    local m = lgMatches[mid]
    if not m then return end

    if m.pendingResolve then
        if lgRegisterDeath(m, victim, killerSrc) then
            lgBroadcastScoreboard(m)
        end
        return
    end

    if not lgRegisterDeath(m, victim, killerSrc) then return end
    lgBroadcastScoreboard(m)

    if lgTeamStillAlive(m, m.teamA) and lgTeamStillAlive(m, m.teamB) then return end

    m.pendingResolve = true
    CreateThread(function()
        Wait(lgRoundDelayMs())
        local m2 = lgMatches[mid]
        if not m2 then return end

        local aOk = lgTeamStillAlive(m2, m2.teamA)
        local bOk = lgTeamStillAlive(m2, m2.teamB)
        local winner = nil
        if aOk and not bOk then
            winner = 'A'
        elseif bOk and not aOk then
            winner = 'B'
        else
            local all = lgAllSources(m2)
            for i = 1, #all do m2.alive[all[i]] = true end
            lgNotifyAll(m2, 3, 'Round empatado — recomeço.', 5000)
            lgBroadcastScoreboard(m2)
            lgSendRoundPayload(mid, false)
            m2.pendingResolve = false
            return
        end

        if winner == 'A' then
            m2.winsA = m2.winsA + 1
        else
            m2.winsB = m2.winsB + 1
        end
        local wonName = winner == 'A' and m2.labelA or m2.labelB
        lgNotifyAll(m2, 2, ('Rodada para %s — placar %d × %d'):format(wonName, m2.winsA, m2.winsB), 7000)

        local cap = lgSeriesMaxWins()
        if m2.winsA >= cap or m2.winsB >= cap then
            local champ = m2.winsA >= cap and m2.labelA or m2.labelB
            local loser = m2.winsA >= cap and m2.labelB or m2.labelA
            lgNotifyAll(m2, 2, ('Série finalizada! Campeão (%d vitórias): %s'):format(cap, champ), 12000)
            m2.pendingResolve = false
            lgFinishSeries(mid, 'completed', champ, loser)
            return
        end

        m2.round = (m2.round or 1) + 1
        local all = lgAllSources(m2)
        for i = 1, #all do m2.alive[all[i]] = true end
        lgBroadcastScoreboard(m2)
        lgSendRoundPayload(mid, false)
        m2.pendingResolve = false
    end)
end)

RegisterCommand('combo_lategame_reset_voting', function(cmdSource)
    if cmdSource ~= 0 then return end
    for _, room in pairs(rooms) do
        room.isInVoting = false
    end
end, false)

AddEventHandler('playerDropped', function()
    local source = source
    local mid = nil
    pcall(function() mid = Player(source).state.combo_lategame_mid end)
    mid = tonumber(mid)
    if mid and lgMatches[mid] then
        lgDisconnectSeries(mid, source)
    else
        clearPlayerLgStates(source)
    end

    lastChatAt[source] = nil

    for roomId, room in pairs(rooms) do
        for i = 1, #room.members do
            if room.members[i] == source then
                tremove(room.members, i)
                if room.owner == source and #room.members > 0 then
                    room.owner = room.members[1]
                elseif room.owner == source then
                    rooms[roomId] = nil
                end
                break
            end
        end
    end

    for challengeId, challenge in pairs(pendingChallenges) do
        if challenge and challenge.fromOwner == source then
            pendingChallenges[challengeId] = nil
        end
    end

    for challengeId, challenge in pairs(pendingChallenges) do
        if challenge then
            if not rooms[challenge.fromRoom] or not rooms[challenge.toRoom] then
                pendingChallenges[challengeId] = nil
            end
        end
    end

    if activeVotation then
        for i = 1, #activeVotation.participants do
            if activeVotation.participants[i] == source then
                for j = 1, #activeVotation.participants do
                    config.notify(activeVotation.participants[j], 1, config.Language.VotingCanceled, 8000)
                end
                activeVotation = nil
                break
            end
        end
    end
end)

CreateThread(function()
    while true do
        Wait(5000)
        if activeVotation then
            tryExpireModeVote()
            tryExpireMapVote()
        end
    end
end)

return apiServer
