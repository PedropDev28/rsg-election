--======================================================================
-- rsg-election / server/sv_results.lua
-- Tally votes and fetch winners for elections
--======================================================================

local RSGCore      = exports['rsg-core']:GetCoreObject()
RSGElection        = RSGElection or {}
RSGElection.Enums  = RSGElection.Enums or {}

local Log      = RSGElection.Log
local Debug    = RSGElection.Debug
local DbQuery  = RSGElection.DbQueryAwait
local DbExec   = RSGElection.DbExecAwait
local GetElec  = RSGElection.GetElectionById

-----------------------------------------------------------------------
-- GetElectionTally(electionId)
-- Returns a list of candidates + vote counts (approved only),
-- ordered by votes DESC. Includes zero-vote candidates.
--
-- Result format:
-- {
--   { candidate_id = 1, citizenid = 'ABC', character_name = 'John Doe', votes = 5 },
--   { ... },
-- }
-----------------------------------------------------------------------
function RSGElection.GetElectionTally(electionId)
    if not electionId then return nil, "no_id" end

    local rows, err = DbQuery([[
        SELECT 
            c.id              AS candidate_id,
            c.citizenid       AS citizenid,
            c.character_name  AS character_name,
            COALESCE(COUNT(v.id), 0) AS votes
        FROM election_candidacies c
        LEFT JOIN election_votes v
            ON v.candidate_id = c.id
           AND v.election_id  = c.election_id
        WHERE c.election_id = ?
          AND c.status = 'approved'
        GROUP BY c.id
        ORDER BY votes DESC, c.id ASC
    ]], { electionId })

    if not rows then
        return nil, err or "db_error"
    end

    return rows, nil
end

-----------------------------------------------------------------------
-- GetElectionWinner(electionId)
-- Uses GetElectionTally and returns:
--   winnerRow, tallyList
-- where winnerRow = first entry in tallyList or nil.
-----------------------------------------------------------------------
function RSGElection.GetElectionWinner(electionId)
    local tally, err = RSGElection.GetElectionTally(electionId)
    if not tally then
        return nil, nil, err
    end

    local winner = tally[1]
    if not winner then
        return nil, tally, "no_candidates"
    end

    return winner, tally, nil
end

-----------------------------------------------------------------------
-- MarkElectionComplete(electionId)
-- Sets phase = "complete", vote_end = NOW()
-----------------------------------------------------------------------
function RSGElection.MarkElectionComplete(electionId)
    if not electionId then return false, "no_id" end

    local _, err = DbExec(
        'UPDATE elections SET phase = "complete", vote_end = NOW() WHERE id = ?',
        { electionId }
    )
    if err then
        Log('Failed to mark election %d complete: %s', electionId, tostring(err))
        return false, err
    end

    return true, nil
end
