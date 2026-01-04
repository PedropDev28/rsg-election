--======================================================================
-- rsg-election / server/sv_election.lua
-- Voting + NUI data (uses shared RSGElection helpers)
--======================================================================

local RSGCore      = exports['rsg-core']:GetCoreObject()
RSGElection        = RSGElection or {}
RSGElection.Enums  = RSGElection.Enums or {}
lib.locale()
-- Shortcuts to shared helpers (defined in sv_helpers.lua / sv_elections.lua)
local Notify      = RSGElection.Notify
local Audit       = RSGElection.Audit
local GetRegion   = RSGElection.GetPlayerRegionHash
local GetActive   = RSGElection.GetActiveElectionByRegion

local PHASE_LABELS = RSGElection.PHASE_LABELS or {
    idle          = "Idle",
    registration  = "Registration",
    campaign      = "Campaign",
    voting        = "Voting",
    complete      = "Complete",
}

----------------------------------------------------------------------
-- VOTING (LOCKED TO RESIDENTS)
--   Event: rsg-election:castVote
--   Called from NUI via cl_election + html/script.js
----------------------------------------------------------------------

RegisterNetEvent("rsg-election:castVote", function(candidateId)
    local src    = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    candidateId = tonumber(candidateId)
    if not candidateId or candidateId <= 0 then
        Notify(src, locale('voting') or "Voting", locale('invalid_candidate') or "Invalid candidate.", "error")
        return
    end

    local citizenid  = Player.PlayerData.citizenid
    local identifier = Player.PlayerData.license or Player.PlayerData.steam or ("src:" .. src)

    local region_hash = GetRegion(src)
    if not region_hash then
        Notify(src, locale('voting') or "Voting", locale('cannot_determine_region') or "Could not determine your region.", "error")
        return
    end

    local elec = GetActive(region_hash)
    if not elec or tostring(elec.phase or ''):lower() ~= 'voting' then
        Notify(src, locale('voting') or "Voting", locale('voting_not_active') or "Voting is not active.", "error")
        return
    end

    -- 🔒 RESIDENCY LOCK FOR VOTING
    -- NOTE: still using `election_residents` here (old table).
    -- You already migrated candidacy to `rsg_residency` in sv_candidates.lua.
    local residency = MySQL.single.await(
        'SELECT region_hash FROM rsg_residency WHERE citizenid = ?',
        { citizenid }
    )

    if not residency then
        Notify(src, locale('voting') or "Voting", locale('must_be_resident_vote') or "You must be a registered resident to vote.", "error")
        return
    end

    if residency.region_hash ~= region_hash then
        Notify(src, locale('voting') or "Voting", locale('must_be_resident_region') or "You can only vote in your home region.", "error")
        return
    end

    -- Candidate must be approved in this election
    local cand = MySQL.single.await([[
        SELECT *
        FROM election_candidacies
        WHERE id = ? AND election_id = ? AND status = 'approved'
    ]], { candidateId, elec.id })

    if not cand then
        Notify(src, locale('voting') or "Voting", locale('invalid_candidate') or "Invalid candidate.", "error")
        return
    end

    -- One vote per citizen per election
    local already = MySQL.single.await([[
        SELECT id FROM election_votes
        WHERE election_id = ? AND voter_cid = ?
    ]], { elec.id, citizenid })

    if already then
        Notify(src, locale('voting') or "Voting", locale('already_voted') or "You already voted.", "error")
        return
    end

    -- Insert vote
    MySQL.insert([[
        INSERT INTO election_votes (election_id, region_hash, voter_cid, voter_ident, candidate_id)
        VALUES (?, ?, ?, ?, ?)
    ]], { elec.id, region_hash, citizenid, identifier, candidateId })

    if Audit then
        Audit(citizenid, "vote_cast",
            ("Voted for candidate %d in election %d"):format(candidateId, elec.id)
        )
    end

    Notify(src, locale('voting') or "Voting", locale('vote_cast') or "Your vote has been cast.", "success")

    -- Let client update UI state
    TriggerClientEvent("rsg-election:voted", src)
end)

----------------------------------------------------------------------
-- UI DATA FOR NUI
--   Event: rsg-election:requestElectionData
--   Called from client when opening the panel or refreshing
----------------------------------------------------------------------

RegisterNetEvent("rsg-election:requestElectionData", function()
    local src    = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid   = Player.PlayerData.citizenid
    local region_hash = GetRegion(src)
    if not region_hash then return end

    local elec = GetActive(region_hash)
    if not elec then
        TriggerClientEvent("rsg-election:sendElectionData", src, {
            regionTitle = locale('no_active_election') or "No active election",
            phase       = PHASE_LABELS.idle,
            hasVoted    = false,
            candidates  = {}
        })
        return
    end

    local approved = MySQL.query.await([[
        SELECT id, character_name, region_alias, bio, portrait, status
        FROM election_candidacies
        WHERE election_id = ? AND status = 'approved'
        ORDER BY id ASC
        LIMIT 3
    ]], { elec.id }) or {}

    local votedRow = MySQL.single.await([[
        SELECT id FROM election_votes
        WHERE election_id = ? AND voter_cid = ?
    ]], { elec.id, citizenid })

    local candidates = {}
    for i, row in ipairs(approved) do
        local portrait = row.portrait
        if not portrait or portrait == '' then
            -- Fallback to portrait1/2/3.png cycling
            portrait = ('portrait%d.png'):format(((i - 1) % 3) + 1)
        end

        candidates[#candidates+1] = {
            id           = row.id,
            name         = row.character_name,
            region_alias = row.region_alias,
            portrait     = portrait,
            bio          = row.bio or "",
            status       = row.status
        }
    end

    local title = (locale('elections') or "ELECTIONS") .. " — " .. string.upper(elec.region_alias)

    TriggerClientEvent("rsg-election:sendElectionData", src, {
        regionTitle = title,
        phase       = PHASE_LABELS[elec.phase] or elec.phase,
        hasVoted    = votedRow and true or false,
        candidates  = candidates
    })
end)

----------------------------------------------------------------------
-- Allow server to tell all clients to refresh (after approvals, etc.)
--   Event: rsg-election:refreshElectionDataAll
----------------------------------------------------------------------

RegisterNetEvent("rsg-election:refreshElectionDataAll", function()
    TriggerClientEvent("rsg-election:refreshElectionData", -1)
end)

----------------------------------------------------------------------
-- UI open check: /election allowed only if election is active
--   Callback: rsg-election:canOpenElection
--   Returns: bool canOpen, string phaseLabelOrError, string regionAlias
----------------------------------------------------------------------

lib.callback.register('rsg-election:canOpenElection', function(src)
    local region_hash = GetRegion(src)
    if not region_hash then
        return false, locale('cannot_determine_region') or "Unable to determine your region."
    end

    local elec = GetActive(region_hash)
    if not elec or elec.phase == 'idle' or elec.phase == 'complete' then
        return false, locale('no_active_election') or "No active election in this region."
    end

    return true, PHASE_LABELS[elec.phase] or elec.phase, elec.region_alias
end)
