local WEAPON_MODES = {
    Pistols = { 'WEAPON_PISTOL','WEAPON_PISTOL_MK2','WEAPON_COMBATPISTOL' },
    Rifles = { 'WEAPON_ASSAULTRIFLE','WEAPON_ASSAULTRIFLE_MK2','WEAPON_SPECIALCARBINE_MK2','WEAPON_CARBINERIFLE_MK2' },
    Submachine = { 'WEAPON_SMG','WEAPON_SMG_MK2','WEAPON_ASSAULTSMG' },
}

globalConfig = {
    MaximumRoomMembers = 10,

    Markers = {
        vector3(193.24,-908.70,28.42),
    }, 

    DisableDimensionsVerify = false,
    ChangeSideByRound = false,

    --- Série de rounds: primeiro time a atingir esta quantidade de vitórias encerra a partida.
    MaxRoundWins = 10,
    --- Pausa (ms) após eliminar o time adversário antes de iniciar o próximo round.
    RoundResetDelayMs = 4000,

    --- Proteção de spawn (segundos de invencibilidade) ao nascer em cada round.
    SpawnTimes = {
        FirstRound = 30,
        OthersRounds = 5,
    },

    Maps = {
        ['Mirage Exclusive'] = {
            Name = 'Mirage',
            Banner = '../images/mirage.png',
            SpawnDistance = 10,
            SideOne = { 
                [1] = vector3(-2719.95,-2708.05,453.97),
            },
            SideTwo = { 
                [1] = vector3(-2613.64,-2718.96,457.89),
            },
            Safezone = {
                Center = vector3(-2661.03,-2704.47,455.02), 
                Variation = 20,
                DamagePerSecond = 25,
                TimeToClose = 150,
                Initial = {
                    Radius = 150
                },
                Finale = {
                    Radius = 5
                }
            }, 
        },
        ['Dust 1.6'] = {
            Name = 'Dust 1.6',
            Banner = '../images/dust.png',
            SpawnDistance = 10,
            SideOne = { 
                [1] = vector3(-5886.45,1857.57,667.73),
            },
            SideTwo = { 
                [1] = vector3(-5839.81,1787.44,674.13),
            },
            Safezone = {
                Center = vector3(-5872.77,1825.9,668.43), 
                Variation = 20,
                DamagePerSecond = 25,
                TimeToClose = 150,
                Initial = {
                    Radius = 150
                },
                Finale = {
                    Radius = 5
                }
            }, 
        },
        ['Dust Go'] = {
            Name = 'Dust Go',
            Banner = '../images/dust2.png',
            SpawnDistance = 10,
            SideOne = { 
                [1] = vector3(-4437.01,2841.37,405.94),
            },
            SideTwo = { 
                [1] = vector3(-4464.64,2754.06,412.34),
            },
            Safezone = {
                Center = vector3(-4456.77,2805.09,407.26), 
                Variation = 20,
                DamagePerSecond = 25,
                TimeToClose = 150,
                Initial = {
                    Radius = 150
                },
                Finale = {
                    Radius = 5
                }
            }, 
        },
        ['ItalyV1'] = {
            Name = 'Italy 1.6',
            Banner = '../images/italy.png',
            SpawnDistance = 10,
            SideOne = { 
                [1] = vector3(-4862.02,4053.89,415.06),
            },
            SideTwo = { 
                [1] = vector3(-4838.54,4155.52,421.03),
            },
            Safezone = {
                Center = vector3(-4866.02,4123.75,417.05), 
                Variation = 20,
                DamagePerSecond = 25,
                TimeToClose = 150,
                Initial = {
                    Radius = 150
                },
                Finale = {
                    Radius = 5
                }
            }, 
        },
        ['ClockTower'] = {
            Name = 'ClockTower',
            Banner = '../images/clocktower.png',
            SpawnDistance = 10,
            SideOne = { 
                [1] = vector3(-3187.83,-2572.74,12.24),
            },
            SideTwo = { 
                [1] = vector3(-3331.67,-2486.48,10.75),
            },
            Safezone = {
                Center = vector3(-3294.78,-2533.22,18.23), 
                Variation = 20,
                DamagePerSecond = 25,
                TimeToClose = 200,
                Initial = {
                    Radius = 200
                },
                Finale = {
                    Radius = 5
                }
            }, 
        }
    },

    Modes = {
        ['Pistols'] = { Name = 'Pistola', Banner = '../images/pistol.png' },
        ['Rifles'] = { Name = 'Rifle', Banner = '../images/rifle.png' },
        ['Submachine'] = { Name = 'Subs', Banner = '../images/smg.png' },
        ['MixedGuns'] = { Name = 'Misto', Banner = '../images/mixed.png' },
    },

    Rounds = {
        Pistols = {
            [1] = WEAPON_MODES.Pistols,
            [2] = WEAPON_MODES.Pistols,
            [3] = WEAPON_MODES.Pistols,
            [4] = WEAPON_MODES.Pistols,
            [5] = WEAPON_MODES.Pistols,
            [6] = WEAPON_MODES.Pistols,
            [7] = WEAPON_MODES.Pistols,
        },
        Rifles = {
            [1] = WEAPON_MODES.Rifles,
            [2] = WEAPON_MODES.Rifles,
            [3] = WEAPON_MODES.Rifles,
            [4] = WEAPON_MODES.Rifles,
            [5] = WEAPON_MODES.Rifles,
            [6] = WEAPON_MODES.Rifles,
            [7] = WEAPON_MODES.Rifles,
        },
        Submachine = {
            [1] = WEAPON_MODES.Submachine,
            [2] = WEAPON_MODES.Submachine,
            [3] = WEAPON_MODES.Submachine,
            [4] = WEAPON_MODES.Submachine,
            [5] = WEAPON_MODES.Submachine,
            [6] = WEAPON_MODES.Submachine,
            [7] = WEAPON_MODES.Submachine,
        },
        MixedGuns = {
            [1] = WEAPON_MODES.Pistols,
            [2] = WEAPON_MODES.Pistols,
            [3] = WEAPON_MODES.Submachine,
            [4] = WEAPON_MODES.Submachine,
            [5] = WEAPON_MODES.Rifles,
            [6] = WEAPON_MODES.Rifles,
            [7] = WEAPON_MODES.Rifles,
        },
    },

    Language = {
        WinningTeam = 'Round finalizado! O time ganhador foi: %s',
        RequestSent = 'Solicitação enviada.',
        MatchCanceled = 'Partida cancelada pois o player: %s está proibido de entrar no Late Game.',
        StartVotation = 'Iniciando votações. Digite /lategame para acompanhar.',
        VotingCanceled = 'Votação cancelada pois algum membro desconectou.',
        PendingRequests = 'Você tem solicitações pendentes. Aguarde um pouco para enviar novamente.',
        ScriptRestarted = 'Seu jogo foi cancelado devido a reinicialização do script.',
        CannotOpenPanel = 'Você não pode abrir o painel do LateGame no momento.',
        AcceptChallenge = '%s com %d/%d membros está te desafiando, deseja aceitar?',
        ThisRoomInVoting = 'Esta sala já está em votação.',
        SpectatingPlayer = 'Você está espectando o player: ',
        ExitSpectatorMode = 'Deseja sair do modo spectador?',
        CannotUseThisName = 'Você não pode usar esse nome.',
        NameAlreadyExists = 'Já existe uma sala com esse nome.',
        WeaponVoteCompleted = 'Votação de armas finalizada. Iniciando votação de mapas. Digite /lategame para acompanhar.',
        MaximumLimitOfPlayers = 'Limite maximo de players atingidos.',
        YouWereKickedOfTheRoom = 'Você foi expulso da sala.',
        CannotChallengeYourRoom = 'Você não pode desafiar sua propria sala.',
        TooLongToVote = '%s Perdeu o voto, pois demorou para votar.', 
        Teams = 'Times',
        Monitor = 'Monitorar',
        Spectate = 'Espectar',
        Challenges = 'Desafiar',
    }
}

function globalConfig.notify(...)
    local args = {...}

    if IsDuplicityVersion() then 
        local source = args[1]

        TriggerClientEvent('Notify', source,"amarelo", args[3], args[4])
    else 
        TriggerEvent('Notify',"amarelo", args[2], args[3])
    end 
end

return globalConfig