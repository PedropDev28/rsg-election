--======================================================================
-- rsg-election / server/sv_votes.lua
-- Voting: residents cast their ballots for approved candidates
--======================================================================

local RSGCore     = exports['rsg-core']:GetCoreObject()
RSGElection       = RSGElection or {}
RSGElection.Enums = RSGElection.Enums or {}

local Notify    = RSGElection.Notify
local Audit     = RSGElection.Audit
local GetRegion = RSGElection.GetPlayerRegionHash
local GetActive = RSGElection.GetActiveElectionByRegion

------------------------------------------------
-- VOTING (LOCKED TO RESIDENTS)
------------------------------------------------

RegisterNetEvent("rsg-election:castVote", function(candidateId)
    local src    = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    candidateId = tonumber(candidateId)
    if not candidateId or candidateId <= 0 then
        Notify(src, "Voting", "Invalid candidate.", "error")
        return
    end

    local citizenid  = Player.PlayerData.citizenid
    local identifier = Player.PlayerData.license or Player.PlayerData.steam or ("src:" .. src)

    local region_hash = GetRegion(src)
    if not region_hash then
        Notify(src, "Voting", "Could not determine your region.", "error")
        return
    end

    local elec = GetActive(region_hash)
    if not elec or elec.phase ~= 'voting' then
        Notify(src, "Voting", "Voting is not active.", "error")
        return
    end

    -- 🔒 RESIDENCY LOCK FOR VOTING
    -- (Same behavior as old code: checks election_residents directly.
    --  Later we can swap this to use rsg-residency exports.)
    local residency = MySQL.single.await(
        'SELECT region_hash FROM election_residents WHERE citizenid = ?',
        { citizenid }
    )

    if not residency then
        Notify(src, "Voting", "You must be a registered resident to vote.", "error")
        return
    end

    if residency.region_hash ~= region_hash then
        Notify(src, "Voting", "You can only vote in your home region.", "error")
        return
    end

    -- Candidate must be an approved candidate in this election
    local cand = MySQL.single.await([[
        SELECT * FROM election_candidacies
        WHERE id = ? AND election_id = ? AND status = 'approved'
    ]], { candidateId, elec.id })

    if not cand then
        Notify(src, "Voting", "Invalid candidate.", "error")
        return
    end

    -- Prevent double voting
    local already = MySQL.single.await([[
        SELECT id FROM election_votes
        WHERE election_id = ? AND voter_cid = ?
    ]], { elec.id, citizenid })

    if already then
        Notify(src, "Voting", "You already voted.", "error")
        return
    end

    -- Record the vote
    MySQL.insert([[
        INSERT INTO election_votes (election_id, region_hash, voter_cid, voter_ident, candidate_id)
        VALUES (?, ?, ?, ?, ?)
    ]], { elec.id, region_hash, citizenid, identifier, candidateId })

    Audit(citizenid, "vote_cast",
        ("Voted for candidate %d in election %d"):format(candidateId, elec.id)
    )

    Notify(src, "Voting", "Your vote has been cast.", "success")

    -- Let the client know so it can close UI / show confirmation
    TriggerClientEvent("rsg-election:voted", src)
end)
