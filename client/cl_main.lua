local RSGCore = exports['rsg-core']:GetCoreObject()
local ActiveElectionPeds = {}      -- [regionKey] = ped entity
local BulletinBoardTargets = {}    -- [key] = zone/target id if your target API returns one

-- Small helper to add a target to an entity
local function AddTargetToEntity(entity, opts)
    if Config.TargetResource == 'ox_target' and exports['ox_target'] then
        exports.ox_target:addLocalEntity(entity, {
            {
                icon   = opts.icon or 'fa-solid fa-circle-info',
                label  = opts.label or 'Interact',
                distance = opts.distance or 2.0,
                onSelect = opts.onSelect,
            }
        })
    elseif Config.TargetResource == 'rsg-target' and exports['rsg-target'] then
        -- Adjust to your rsg-target API if different
        exports['rsg-target']:AddTargetEntity(entity, {
            options = {
                {
                    icon  = opts.icon or 'fa-solid fa-circle-info',
                    label = opts.label or 'Interact',
                    action = opts.onSelect,
                }
            },
            distance = opts.distance or 2.0,
        })
    else
        -- No target system: you can fallback to 3D text or do nothing
        print('[rsg-election] No supported target resource configured.')
    end
end

-- Helper to add an area/coords target (for bulletin boards)
local function AddTargetForCoords(key, coords, opts)
    if Config.TargetResource == 'ox_target' and exports['ox_target'] then
        local id = exports.ox_target:addSphereZone({
            coords   = coords,
            radius   = opts.radius or 1.0,
            debug    = false,
            options  = {
                {
                    icon   = opts.icon or 'fa-solid fa-circle-info',
                    label  = opts.label or 'Interact',
                    onSelect = opts.onSelect,
                }
            }
        })
        BulletinBoardTargets[key] = id
    elseif Config.TargetResource == 'rsg-target' and exports['rsg-target'] then
        -- Adjust to your rsg-target API; many use box/sphere zones
        exports['rsg-target']:AddCircleZone(key, coords, opts.radius or 1.0, {
            name = key,
            debugPoly = false,
        }, {
            options = {
                {
                    icon  = opts.icon or 'fa-solid fa-circle-info',
                    label = opts.label or 'Interact',
                    action = opts.onSelect,
                }
            },
            distance = opts.distance or 2.0,
        })
        BulletinBoardTargets[key] = true
    else
        print('[rsg-election] No supported target resource configured for bulletin board.')
    end
end

-- Server tells us a candidate ped was created
RegisterNetEvent('rsg-election:client:onCandidatePedSpawned', function(regionKey, netId)
    local ped = NetToPed(netId)
    if not DoesEntityExist(ped) then
        -- Give time for entity to actually exist on this client
        local timeout = GetGameTimer() + 5000
        while not DoesEntityExist(ped) and GetGameTimer() < timeout do
            Wait(50)
            ped = NetToPed(netId)
        end
    end

    if not DoesEntityExist(ped) then
        print(('[rsg-election] Failed to resolve ped for region "%s"'):format(regionKey))
        return
    end

    ActiveElectionPeds[regionKey] = ped

    -- Attach target
    local cfg
    for _, data in pairs(Config.CandidatePeds) do
        if data.regionKey == regionKey then
            cfg = data
            break
        end
    end

    AddTargetToEntity(ped, {
        icon    = cfg and cfg.targetIcon or 'fa-solid fa-scale-balanced',
        label   = cfg and cfg.targetLabel or 'Register as Candidate',
        distance= cfg and cfg.targetDistance or 2.0,
        onSelect = function()
            -- Trigger your existing registration flow here
            -- e.g. TriggerEvent('rsg-election:client:openCandidateRegistration', regionKey)
            TriggerServerEvent('rsg-election:server:openRegistration', regionKey)
        end
    })
end)

-- Server tells us a candidate ped was deleted
RegisterNetEvent('rsg-election:client:onCandidatePedDeleted', function(regionKey)
    ActiveElectionPeds[regionKey] = nil
    -- Target removal is handled by target resource when entity is removed
end)

-- Full sync when joining or when resource restarts
RegisterNetEvent('rsg-election:client:onElectionSync', function(activeRegions, pedData)
    -- Spawn targets for any existing peds we know about
    for regionKey, data in pairs(pedData or {}) do
        if data.netId then
            TriggerEvent('rsg-election:client:onCandidatePedSpawned', regionKey, data.netId)
        end
    end
end)

-- Create bulletin board targets for voting / winner display
CreateThread(function()
    for key, data in pairs(Config.BulletinBoards) do
        AddTargetForCoords(key, data.coords, {
            radius   = 1.5,
            distance = data.targetDistance or 2.0,
            icon     = data.targetIcon or 'fa-solid fa-clipboard-list',
            label    = data.targetLabel or 'Open Election Board',
            onSelect = function()
                -- When player interacts, ask the server about the board's state
                local result = lib.callback.await('rsg-election:getBulletinData', false, data.regionKey)
                if not result then
                    return
                end

                if result.state == 'voting' then
                    -- Open your voting UI for that region
                    SetNuiFocus(true, true)
                    SendNUIMessage({
                        action    = 'election:openVoting',
                        regionKey = result.regionKey,
                    })
                elseif result.state == 'winner' and result.winner then
                    -- Show winner + portrait
                    SetNuiFocus(true, true)
                    SendNUIMessage({
                        action      = 'election:openWinner',
                        regionKey   = result.regionKey,
                        winner      = result.winner,
                        portraitKey = result.portraitKey,
                    })
                else
                    -- No active election and no current winner display
                    SetNuiFocus(true, true)
                    SendNUIMessage({
                        action  = 'election:openInfo',
                        message = 'No election is currently running in this region.',
                    })
                end
            end
        })
    end
end)
