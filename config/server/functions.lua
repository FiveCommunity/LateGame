local Tunnel = import('lib/Tunnel')
local Proxy = import('lib/Proxy')

local vRP = Proxy.getInterface('vRP')
local vRPclient = Tunnel.getInterface('vRP')

local apiConfig = Tunnel.getInterface('combo_lategame:config')

local playerInfos = {}
local QUEUE_SPECIAL_NAMES = {
    ['NOME1'] = 'Perm'
}

serverConfig = {
    checkQueueName = function(queueName, queueOwnerSource)
        if QUEUE_SPECIAL_NAMES[queueName] then
            local userId = serverConfig.getUserId(queueOwnerSource)

            if not serverConfig.hasPermission(userId, QUEUE_SPECIAL_NAMES[queueName]) then
                return false
            end
        end

        return true
    end, 

    isUserAdmin = function(userSource)
        local userId = serverConfig.getUserId(userSource)

        return serverConfig.hasPermission(userId, 'Admin')
    end,

    getUserNameToSpec = function(userSource)
        local userName = serverConfig.getUserName(userSource)
        return userName
    end,

    getUserIdentifier = function(userSource)
        local userId = serverConfig.getUserId(userSource)
        
        return userId
    end,

    userCanOpenLateGame = function(userSource)
        return true
    end,

    getUserSource = function(userId)
        if userId then
            return vRP.Source(userId)
        end
    end,

    getUserId = function(userSource)
        if userSource then
            return vRP.Passport(userSource)
        end
    end,

    hasPermission = function(userId, permission)
        if userId and permission then
            return vRP.HasPermission(userId, permission)
        end
    end,

    hasUserVip = function(userSource)
        return true
    end,

    getUserName = function(userSource)
        local passport = vRP.Passport(userSource)
        if not passport then
            return 'Indivíduo Indigente'
        end

        local identity = vRP.Identity(passport) or {}
        local name = identity.Name or 'Indivíduo'
        local lastname = identity.Lastname or 'Indigente'

        return name..' '..lastname
    end,

    request = function(userSource, text)
        if userSource and text then
            return vRP.Request(userSource, 'Late Game', text)
        end
    end,

    setPlayerRoutingBucket = function(userSource, dimension)
        SetPlayerRoutingBucket(userSource, dimension)
    end,

    canUserJoinInGame = function(userSource)
        if GetPlayerRoutingBucket(userSource) > 0 then return false end 
        local playerPed = GetPlayerPed(userSource)
        local health = GetEntityHealth(playerPed)
        return health > 101 
    end,

    savePlayerInfos = function(userSource)
        Player(userSource).state:set('inLateGame', true, true)

        Citizen.Wait(50)

        local playerPed = GetPlayerPed(userSource)
        local health = GetEntityHealth(playerPed)

        playerInfos[userSource] = {
            armour = GetPedArmour(playerPed),
            coords = GetEntityCoords(playerPed),
            health = health,
            dimension = GetPlayerRoutingBucket(userSource)
        }

        Player(userSource).state:set('temporaryDataLateGame', playerInfos[userSource], true)
    end,

    setPlayerInfos = function(userSource)
        Player(userSource).state:set('teamLateGame', nil, true)

        Citizen.Wait(50)

        local userInfos = playerInfos[userSource]
        
        if userInfos then
            local playerPed = GetPlayerPed(userSource)

            SetEntityCoords(playerPed, userInfos.coords)
            SetPedArmour(playerPed, userInfos.armour)
            
            apiConfig._setPlayerHealth(userSource, userInfos.health)
            serverConfig.setPlayerRoutingBucket(userSource, userInfos.dimension)

            playerInfos[userSource] = nil
            Player(userSource).state:set('temporaryDataLateGame', playerInfos[userSource], true)
        end

        Citizen.SetTimeout(2000, function()
            Player(userSource).state:set('inLateGame', false, true)
        end)
    end,

    sendWebhookWinner = function(winningTeamName, looserTeamName, matchMap, matchWeapon)
        -- local embed = {
        --     {
        --         title = 'Winner LateGame', 
                
        --         description = 'Time '..winningTeamName..' ganhou do time '..looserTeamName, 

        --         fields = { 
        --             {
        --                 name = 'Mapa jogado', 
        --                 value = tostring(matchMap)
        --             },
        --             {
        --                 name = 'Modo jogado', 
        --                 value = tostring(matchWeapon)
        --             },
        --         }, 
    
        --         footer = { 
        --             text = 'LateGame - '..os.date('%d/%m/%Y | %H:%M:%S'), 
        --             icon_url = 'https://i.imgur.com/kF30dRK.png' 
        --         }, 
    
        --         color = 15158332, 
        --     }
        -- }
        
        -- local webhook = ''
        
        -- PerformHttpRequest(webhook, function(error, text, headers) end, 'POST', json.encode(
        --     {
        --         username = 'Combo Store - LateGame', 
        --         avatar_url = 'https://i.imgur.com/kF30dRK.png', 
        --         embeds = embed
        --     }
        -- ), { ['Content-Type'] = 'application/json' })
    end,
}

return serverConfig