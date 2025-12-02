-- cl_election.lua — toggle NUI + talk to server

local showing = false

local function setUI(show)
    showing = show
    SetNuiFocus(show, show)
    SendNUIMessage({ type = 'election:toggle', display = show })

    if show then
        -- Ask server for current election data (candidates, phase, etc.)
        TriggerServerEvent("rsg-election:requestElectionData")
    end
end

-- /election to open UI — only when election is active
RegisterCommand('election', function()
    -- if already open, just close
    if showing then
        setUI(false)
        return
    end

    -- ask server if election is active in this region
    lib.callback('rsg-election:canOpenElection', false, function(canOpen, info, regionAlias)
        if not canOpen then
            lib.notify({
                title       = "Elections",
                description = info or "No active election in this region.",
                type        = "error"
            })
            return
        end

        setUI(true)
    end)
end, false)

-- Server pushes fresh data -> NUI
RegisterNetEvent("rsg-election:sendElectionData", function(data)
    SendNUIMessage({
        type        = 'election:update',
        regionTitle = data.regionTitle,
        phase       = data.phase,
        hasVoted    = data.hasVoted,
        candidates  = data.candidates
    })
end)

-- When vote succeeds (server)
RegisterNetEvent("rsg-election:voted", function()
    SendNUIMessage({
        type      = 'election:update',
        hasVoted  = true
    })
end)

-- Allow server to ask client to refresh (after approvals)
RegisterNetEvent("rsg-election:refreshElectionData", function()
    if showing then
        TriggerServerEvent("rsg-election:requestElectionData")
    end
end)

-- NUI callbacks
RegisterNUICallback('electionVote', function(data, cb)
    local cid = tonumber(data.candidateId)
    if cid then
        TriggerServerEvent("rsg-election:castVote", cid)
    end
    cb({})
end)

RegisterNUICallback('electionClose', function(data, cb)
    setUI(false)
    cb({})
end)
