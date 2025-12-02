--======================================================================
-- rsg-election / server/sv_exports.lua
-- Public exports for other resources (read-only helpers)
--======================================================================

local RSGCore      = exports['rsg-core']:GetCoreObject()
RSGElection        = RSGElection or {}
RSGElection.Enums  = RSGElection.Enums or {}

local GetRegionActive = RSGElection.GetActiveElectionByRegion
local GetElectionById = RSGElection.GetElectionById
local GetTally        = RSGElection.GetElectionTally
local GetWinner       = RSGElection.GetElectionWinner

-----------------------------------------------------------------------
-- Export: GetActiveElectionForRegionHash(region_hash)
-- Returns the raw election row or nil.
-----------------------------------------------------------------------
exports('GetActiveElectionForRegionHash', function(region_hash)
    if not region_hash then return nil end
    return GetRegionActive(region_hash)
end)

-----------------------------------------------------------------------
-- Export: GetElectionById(electionId)
-- Simple pass-through to helper (one row or nil).
-----------------------------------------------------------------------
exports('GetElectionById', function(electionId)
    return GetElectionById(electionId)
end)

-----------------------------------------------------------------------
-- Export: GetElectionTally(electionId)
-- Returns { tally = {...}, error = "..." }
-----------------------------------------------------------------------
exports('GetElectionTally', function(electionId)
    local tally, err = GetTally(electionId)
    return {
        tally = tally or {},
        error = err or nil
    }
end)

-----------------------------------------------------------------------
-- Export: GetElectionWinner(electionId)
-- Returns { winner = {...}, tally = {...}, error = "..." }
-- winner can be nil if no candidates / no votes.
-----------------------------------------------------------------------
exports('GetElectionWinner', function(electionId)
    local winner, tally, err = GetWinner(electionId)
    return {
        winner = winner or nil,
        tally  = tally or {},
        error  = err or nil
    }
end)

-----------------------------------------------------------------------
-- Export: HasCitizenVoted(electionId, citizenid)
-- True if this citizen has a vote in election_votes.
-----------------------------------------------------------------------
exports('HasCitizenVoted', function(electionId, citizenid)
    if not electionId or not citizenid then return false end

    local row = MySQL.single.await([[
        SELECT id FROM election_votes
        WHERE election_id = ? AND voter_cid = ?
        LIMIT 1
    ]], { electionId, citizenid })

    return row and true or false
end)

-----------------------------------------------------------------------
-- Export: GetLastCompletedElectionForRegion(region_alias)
-- Returns the latest "complete" election row for the given region alias.
-----------------------------------------------------------------------
exports('GetLastCompletedElectionForRegion', function(region_alias)
    if not region_alias or region_alias == '' then return nil end

    local rows = MySQL.query.await([[
        SELECT * FROM elections
        WHERE region_alias = ? AND phase = "complete"
        ORDER BY id DESC
        LIMIT 1
    ]], { region_alias:lower() })

    return rows and rows[1] or nil
end)
