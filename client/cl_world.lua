local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()
local ActiveElectionPeds   = {}   -- [regionHash] = ped entity
local BulletinBoardTargets = {}   -- [key] = target id / true
local SpawnedCandidatePeds = {} -- [regionHash] = ped
local SpawnedCandidateBoards = {} -- [regionHash] = object
local AttachedTargets = AttachedTargets or {} -- [entity] = true

------------------------------------------------
-- Target helpers
------------------------------------------------

-- Normalize target callback:
-- Supports:
--   opts.onSelect (function)
--   opts.event (string) + opts.args (table|any)
local function buildOnSelect(opts)
    opts = opts or {}

    if type(opts.onSelect) == 'function' then
        return opts.onSelect
    end

    if type(opts.event) == 'string' and opts.event ~= '' then
        return function()
            if opts.args ~= nil then
                if type(opts.args) == 'table' then
                    TriggerEvent(opts.event, table.unpack(opts.args))
                else
                    TriggerEvent(opts.event, opts.args)
                end
            else
                TriggerEvent(opts.event)
            end
        end
    end

    -- no-op fallback to avoid nil callbacks
    return function()
        print('[rsg-election] Target pressed but no onSelect/event configured.')
    end
end

local function addTargetToEntity(entity, opts)
    opts = opts or {}

    local targetRes = (Config and Config.TargetResource) or 'ox_target'
    local onSelect = buildOnSelect(opts)

    if targetRes == 'ox_target' and exports['ox_target'] then
        exports.ox_target:addLocalEntity(entity, {
            {
                icon     = opts.icon or 'fa-solid fa-scale-balanced',
                label    = opts.label or locale('interact') or 'Interact',
                distance = opts.distance or 2.0,
                onSelect = onSelect,
            }
        })
    elseif targetRes == 'rsg-target' and exports['rsg-target'] then
        exports['rsg-target']:AddTargetEntity(entity, {
            options = {
                {
                    icon   = opts.icon or 'fa-solid fa-scale-balanced',
                    label  = opts.label or locale('interact') or 'Interact',
                    action = onSelect,
                }
            },
            distance = opts.distance or 2.0,
        })
    else
        print('[rsg-election] No supported target resource configured for candidate ped.')
    end
end

local function addTargetForCoords(key, coords, opts)
    opts = opts or {}
    local targetRes = (Config and Config.TargetResource) or 'ox_target'
    local onSelect = buildOnSelect(opts)

    if targetRes == 'ox_target' and exports['ox_target'] then
        local id = exports.ox_target:addSphereZone({
            coords  = coords,
            radius  = opts.radius or 1.0,
            debug   = false,
            options = {
                {
                    icon     = opts.icon or 'fa-solid fa-clipboard-list',
                    label    = opts.label or locale('interact') or 'Interact',
                    distance = opts.distance or 2.0,
                    onSelect = onSelect,
                }
            }
        })
        BulletinBoardTargets[key] = id

    elseif targetRes == 'rsg-target' and exports['rsg-target'] then
        exports['rsg-target']:AddCircleZone(key, coords, opts.radius or 1.0, {
            name      = key,
            debugPoly = false,
        }, {
            options = {
                {
                    icon   = opts.icon or 'fa-solid fa-clipboard-list',
                    label  = opts.label or locale('interact') or 'Interact',
                    action = onSelect,
                }
            },
            distance = opts.distance or 2.0,
        })
        BulletinBoardTargets[key] = true

    else
        print('[rsg-election] No supported target resource configured for bulletin boards.')
    end
end

local function safeDeleteEntity(ent)
    if ent and ent ~= 0 and DoesEntityExist(ent) then
        SetEntityAsMissionEntity(ent, true, true)
        DeleteEntity(ent)
    end
end

local function cleanupCandidateEntities()
    -- remove spawned candidate entities
    for regionHash, ped in pairs(SpawnedCandidatePeds) do
        safeDeleteEntity(ped)
        SpawnedCandidatePeds[regionHash] = nil
    end
    for regionHash, obj in pairs(SpawnedCandidateBoards) do
        safeDeleteEntity(obj)
        SpawnedCandidateBoards[regionHash] = nil
    end

    -- clear target guard table
    AttachedTargets = {}
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    cleanupCandidateEntities()
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    -- ensure stale entities from a crash/restart are gone client-side
    cleanupCandidateEntities()
end)

-- ============================================================
-- Candidate Ped (ONE global ped, client-owned spawn, shared netId)
-- ============================================================

local function waitForNetEntity(netId, timeoutMs)
    timeoutMs = timeoutMs or 8000
    local t0 = GetGameTimer()

    while (GetGameTimer() - t0) < timeoutMs do
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent and ent ~= 0 and DoesEntityExist(ent) then
            return ent
        end
        Wait(50)
    end
    return nil
end

-- SERVER -> ONE CLIENT: spawn ped + bounty board object (networked)
RegisterNetEvent('rsg-election:client:spawnCandidateEntities', function(regionHash)
    if not Config or not Config.CandidatePeds then return end
    regionHash = tostring(regionHash or '')
    if regionHash == '' then return end

    -- if already spawned locally, do nothing
    if SpawnedCandidatePeds[regionHash] and DoesEntityExist(SpawnedCandidatePeds[regionHash]) then
        return
    end

    -- Find config for region
    local cfg
    for _, data in pairs(Config.CandidatePeds) do
        if tostring(data.regionKey) == regionHash then
            cfg = data
            break
        end
    end
    if not cfg then
        print(('[rsg-election] No CandidatePeds config found for region "%s"'):format(regionHash))
        return
    end

    -- ============================================================
    -- Appearance helper (same fix pattern as rsg-residency)
    -- ============================================================
    local function setupCandidateAppearance(ped, heading, outfitPreset)
        if not ped or ped == 0 or not DoesEntityExist(ped) then return end

        local preset = tonumber(outfitPreset) or 0

        -- Force visible
        SetEntityVisible(ped, true)
        SetEntityAlpha(ped, 255, false)

        -- Apply outfit preset (this is the key fix for "blank" metapeds)
        if type(EquipMetaPedOutfitPreset) == "function" then
            pcall(function()
                EquipMetaPedOutfitPreset(ped, preset, false)
            end)
        elseif type(SetPedOutfitPreset) == "function" then
            pcall(function()
                SetPedOutfitPreset(ped, preset, false)
            end)
        end

        -- Refresh variation (best-effort)
        if type(UpdatePedVariation) == "function" then
            pcall(function()
                UpdatePedVariation(ped, false, true, true, true, false)
            end)
        end

        -- Harden like residency clerks
        SetEntityHeading(ped, heading or 0.0)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedCanRagdoll(ped, false)
        SetPedFleeAttributes(ped, 0, false)
        SetPedCombatAttributes(ped, 46, true)
        SetPedSeeingRange(ped, 0.0)
        SetPedHearingRange(ped, 0.0)
    end

    -- =========================
    -- Spawn PED
    -- =========================
    local model = cfg.model or `S_M_M_GenConductor_01`
    if type(model) == 'string' then model = joaat(model) end

    RequestModel(model)
    while not HasModelLoaded(model) do Wait(50) end

    local ped = CreatePed(
        model,
        cfg.coords.x, cfg.coords.y, cfg.coords.z,
        cfg.heading or 0.0,
        true, true, false, false
    )

    if not DoesEntityExist(ped) then
        print(('[rsg-election] Failed to create candidate ped for region "%s"'):format(regionHash))
        return
    end

    SetEntityCanBeDamaged(ped, false)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    FreezeEntityPosition(ped, true)

    -- IMPORTANT: apply outfit/visibility fix BEFORE scenario + before reporting netId
    setupCandidateAppearance(ped, cfg.heading or 0.0, cfg.outfitPreset)

    if cfg.scenario then
        TaskStartScenarioInPlace(ped, joaat(cfg.scenario), -1, true, false, false, false)
    end

    if NetworkRegisterEntityAsNetworked then
        NetworkRegisterEntityAsNetworked(ped)
    end
    local pedNetId = NetworkGetNetworkIdFromEntity(ped)
    if SetNetworkIdExistsOnAllMachines then
        SetNetworkIdExistsOnAllMachines(pedNetId, true)
    end

    SpawnedCandidatePeds[regionHash] = ped

    -- Target PED -> registration UI (attach once)
    if not AttachedTargets[ped] then
        addTargetToEntity(ped, {
            label    = cfg.targetLabel or locale('register_as_candidate') or 'Register as Candidate',
            icon     = cfg.targetIcon or 'fa-solid fa-id-card',
            distance = cfg.targetDistance or 2.0,
            onSelect = function()
                TriggerEvent('rsg-election:client:openCandidacyForm')
            end
        })
        AttachedTargets[ped] = true
    end

    -- =========================
    -- Spawn BOARD OBJECT
    -- =========================
    local boardModel = joaat('mp005_p_mp_bountyboard02x')

    RequestModel(boardModel)
    while not HasModelLoaded(boardModel) do Wait(50) end

    local boardPos     = cfg.boardCoords or vector3(cfg.coords.x + 1.0, cfg.coords.y, cfg.coords.z)
    local boardHeading = cfg.boardHeading or (cfg.heading or 0.0)

    local obj = CreateObjectNoOffset(boardModel, boardPos.x, boardPos.y, boardPos.z, true, true, false)

    if not DoesEntityExist(obj) then
        print(('[rsg-election] Failed to create bounty board object for region "%s"'):format(regionHash))
        return
    end

    SetEntityHeading(obj, boardHeading)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetEntityInvincible(obj, true)

    if NetworkRegisterEntityAsNetworked then
        NetworkRegisterEntityAsNetworked(obj)
    end
    local boardNetId = NetworkGetNetworkIdFromEntity(obj)
    if SetNetworkIdExistsOnAllMachines then
        SetNetworkIdExistsOnAllMachines(boardNetId, true)
    end

    SpawnedCandidateBoards[regionHash] = obj

    -- Target BOARD -> election UI (attach once)
    if not AttachedTargets[obj] then
        addTargetToEntity(obj, {
            label    = locale('open_election_board') or 'Open Election Board',
            icon     = 'fa-solid fa-clipboard-list',
            distance = 2.0,
            onSelect = function()
                ExecuteCommand('election')
            end
        })
        AttachedTargets[obj] = true
    end

    -- Release model memory
    SetModelAsNoLongerNeeded(model)
    SetModelAsNoLongerNeeded(boardModel)

    -- report to server
    TriggerServerEvent('rsg-election:server:registerCandidateEntities', regionHash, pedNetId, boardNetId)
end)


-- SERVER -> ALL CLIENTS: resolve entities and attach targets
RegisterNetEvent('rsg-election:client:onCandidateEntitiesSpawned', function(regionHash, pedNetId, boardNetId)
    regionHash = tostring(regionHash or '')
    pedNetId   = tonumber(pedNetId)
    boardNetId = tonumber(boardNetId)
    if regionHash == '' or not pedNetId or not boardNetId then return end

    if not (SpawnedCandidatePeds[regionHash] and DoesEntityExist(SpawnedCandidatePeds[regionHash])) then
        local ped = waitForNetEntity(pedNetId, 10000)
        if ped then
            SpawnedCandidatePeds[regionHash] = ped

            -- Target PED -> registration UI
            if not AttachedTargets[ped] then
                addTargetToEntity(ped, {
                    label    = locale('register_as_candidate') or 'Register as Candidate',
                    icon     = 'fa-solid fa-id-card',
                    distance = 2.0,
                    onSelect = function()
                        TriggerEvent('rsg-election:client:openCandidacyForm')
                    end
                })
                AttachedTargets[ped] = true
            end
        end
    end

    if not (SpawnedCandidateBoards[regionHash] and DoesEntityExist(SpawnedCandidateBoards[regionHash])) then
        local obj = waitForNetEntity(boardNetId, 10000)
        if obj then
            SpawnedCandidateBoards[regionHash] = obj

            -- Target BOARD -> election UI (view candidates / vote if voting phase)
            if not AttachedTargets[obj] then
                addTargetToEntity(obj, {
                    label    = locale('open_election_board') or 'Open Election Board',
                    icon     = 'fa-solid fa-clipboard-list',
                    distance = 2.0,
                    onSelect = function()
                        ExecuteCommand('election')
                    end
                })
                AttachedTargets[obj] = true
            end
        end
    end
end)

-- Delete ONLY the registration ped (keep bulletin board until election ends)
RegisterNetEvent('rsg-election:client:deleteCandidatePedOnly', function(regionHash)
    regionHash = tostring(regionHash or '')
    if regionHash == '' then return end

    safeDeleteEntity(SpawnedCandidatePeds[regionHash])
    SpawnedCandidatePeds[regionHash] = nil
end)

-- Compatibility alias (server may broadcast this too)
RegisterNetEvent('rsg-election:client:onCandidatePedDeleted', function(regionHash)
    regionHash = tostring(regionHash or '')
    if regionHash == '' then return end

    SpawnedCandidatePeds[regionHash] = nil
end)

RegisterNetEvent('rsg-election:client:deleteCandidateEntities', function(regionHash)
    regionHash = tostring(regionHash or '')
    if regionHash == '' then return end

    safeDeleteEntity(SpawnedCandidatePeds[regionHash])
    safeDeleteEntity(SpawnedCandidateBoards[regionHash])

    SpawnedCandidatePeds[regionHash]   = nil
    SpawnedCandidateBoards[regionHash] = nil
end)

-- Delete ONLY the registration ped (keep bulletin board until election ends)
RegisterNetEvent('rsg-election:client:deleteCandidatePedOnly', function(regionHash)
    regionHash = tostring(regionHash or '')
    if regionHash == '' then return end

    safeDeleteEntity(SpawnedCandidatePeds[regionHash])
    SpawnedCandidatePeds[regionHash] = nil
end)

------------------------------------------------
-- Bulletin boards (voting / winner display)
------------------------------------------------

CreateThread(function()
    if not Config or not Config.BulletinBoards then
        return
    end

    for key, data in pairs(Config.BulletinBoards) do
        local coords = data.coords
        if coords then
            addTargetForCoords(key, coords, {
                radius   = 1.5,
                distance = data.targetDistance or 2.0,
                icon     = data.targetIcon or 'fa-solid fa-clipboard-list',
                label    = data.targetLabel or locale('open_election_board') or 'Open Election Board',
                onSelect = function()
                    local result = lib.callback.await('rsg-election:getBulletinData', false, data.regionKey)
                    if not result then return end

                    if result.state == 'voting' then
                        -- Reuse existing /election UI logic
                        ExecuteCommand('election')

                    elseif result.state == 'winner' and result.winner then
                        local w = result.winner
                        local fullName = ((w.firstname or '') .. ' ' .. (w.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
                        local votes = tonumber(w.total_votes or 0) or 0

                        lib.notify({
                            title       = locale('elections') or 'Elections',
                            description = ('Winner: %s\nVotes: %d'):format(fullName ~= '' and fullName or (w.citizenid or 'Unknown'), votes),
                            type        = 'success'
                        })
                    else
                        lib.notify({
                            title       = locale('elections') or 'Elections',
                            description = locale('no_active_election') or 'No active voting or recent winner for this region.',
                            type        = 'inform'
                        })
                    end
                end
            })
        end
    end
end)

AddEventHandler('onClientResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetTimeout(2000, function()
        TriggerServerEvent('rsg-election:server:requestElectionSync')
    end)
end)

RegisterNetEvent('rsg-election:client:onElectionSync', function(activeRegions, electionPeds)
    if type(electionPeds) ~= 'table' then return end

    for regionHash, data in pairs(electionPeds) do
        if data and data.pedNetId and data.boardNetId then
            TriggerEvent('rsg-election:client:onCandidateEntitiesSpawned', regionHash, data.pedNetId, data.boardNetId)
        end
    end
end)
