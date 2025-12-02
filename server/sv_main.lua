--======================================================================
-- rsg-election / server/sv_main.lua
-- UI data for NUI + open check for /election + admin election menu
--======================================================================

local RSGCore       = exports['rsg-core']:GetCoreObject()
RSGElection         = RSGElection or {}
RSGElection.Enums   = RSGElection.Enums or {}

local Notify         = RSGElection.Notify
local GetRegion      = RSGElection.GetPlayerRegionHash
local GetActive      = RSGElection.GetActiveElectionByRegion
local PHASE_LABELS   = RSGElection.PHASE_LABELS or {
    idle          = "Idle",
    registration  = "Registration",
    campaign      = "Campaign",
    voting        = "Voting",
    complete      = "Result",  -- show as "Result"
}
local MAX_CANDIDATES = RSGElection.MAX_CANDIDATES or 3
local IsOwner        = RSGElection.IsElectionOwner
local DbQuery        = RSGElection.DbQueryAwait
local DbExec         = RSGElection.DbExecAwait

-- ------------------------------------------------------------------
-- Backwards-compatible wrappers for old function names used in
-- older rsg-election code (so existing calls don’t crash).
-- ------------------------------------------------------------------
local function getPlayerRegionHash(src)
    return GetRegion and GetRegion(src) or nil
end

local function getActiveElectionByRegion(region_hash)
    return GetActive and GetActive(region_hash) or nil
end

local function notify(src, title, msg, ntype)
    if Notify then
        return Notify(src, title, msg, ntype)
    end
    -- simple fallback if Notify is ever nil
    print(("[rsg-election] %s: %s"):format(title or "Notice", msg or ""))
end

------------------------------------------------
-- UI DATA FOR NUI
------------------------------------------------

RegisterNetEvent("rsg-election:requestElectionData", function()
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid   = Player.PlayerData.citizenid
    local region_hash = RSGElection.GetPlayerRegionHash(src)
    if not region_hash then return end

    local elec = getActiveElectionByRegion(region_hash)
    if not elec then
        TriggerClientEvent("rsg-election:sendElectionData", src, {
            regionTitle = "No active election",
            phase       = PHASE_LABELS.idle,
            hasVoted    = false,
            candidates  = {}
        })
        return
    end

    -- Fetch ALL non-rejected candidates (pending + approved)
    local rows = MySQL.query.await([[
        SELECT id, character_name, region_alias, bio, portrait, status
        FROM election_candidacies
        WHERE election_id = ? AND status <> 'rejected'
        ORDER BY status = 'approved' DESC, id ASC
        LIMIT 3
    ]], { elec.id }) or {}

    -- Has the player already voted in this election?
    local votedRow = MySQL.single.await([[
        SELECT id FROM election_votes
        WHERE election_id = ? AND voter_cid = ?
    ]], { elec.id, citizenid })

    local candidates = {}
    for i, row in ipairs(rows) do
        local portrait = row.portrait
        if not portrait or portrait == '' then
            portrait = ('portrait%d.png'):format(((i - 1) % 3) + 1)
        end

        candidates[#candidates+1] = {
            id           = row.id,
            name         = row.character_name,
            region_alias = row.region_alias,
            portrait     = portrait,
            bio          = row.bio or "",
            status       = row.status -- 'pending' or 'approved'
        }
    end

    local title = ("ELECTIONS — %s"):format(string.upper(elec.region_alias))

    TriggerClientEvent("rsg-election:sendElectionData", src, {
        regionTitle = title,
        phase       = PHASE_LABELS[elec.phase] or elec.phase,
        hasVoted    = votedRow and true or false,
        candidates  = candidates
    })
end)

RegisterNetEvent("rsg-election:refreshElectionDataAll", function()
    TriggerClientEvent("rsg-election:refreshElectionData", -1)
end)

------------------------------------------------
-- PLAYER UI open check: only allow /election if election active
------------------------------------------------

lib.callback.register('rsg-election:canOpenElection', function(src)
    local region_hash = GetRegion(src)
    if not region_hash then
        return false, "Unable to determine your region."
    end

    local elec = GetActive(region_hash)
    if not elec or elec.phase == 'idle' or elec.phase == 'complete' then
        return false, "No active election in this region."
    end

    return true, PHASE_LABELS[elec.phase] or elec.phase, elec.region_alias
end)

------------------------------------------------
-- ADMIN: /electionmenu
------------------------------------------------

RSGCore.Commands.Add('electionmenu', 'Open election admin menu', {}, false, function(source, _)
    if not IsOwner(source) then
        Notify(source, "Elections", "Only the server owner can open the election menu.", "error")
        return
    end

    TriggerClientEvent('rsg-election:client:OpenAdminMenu', source)
end, 'god')

------------------------------------------------
-- ADMIN: create / setup election (from Setup form)
-- Only creates the election in "idle" state.
-- Phase changes (Registration/Campaign/Voting/Result)
-- are done separately via the phase menu.
------------------------------------------------

RegisterNetEvent('rsg-election:adminCreateElection', function(regionAlias, registrationFee)
    local src = source
    if not IsOwner(src) then return end

    regionAlias     = tostring(regionAlias or ''):lower()
    registrationFee = tonumber(registrationFee) or 0

    if regionAlias == '' then
        Notify(src, "Elections", "Region is required.", "error")
        return
    end

    local region_hash = GetRegion(src)
    if not region_hash then
        Notify(src, "Elections", "Could not determine your current region hash.", "error")
        return
    end

    -- 🚩 Important: do NOT start in "registration".
    -- Start as "idle" so admin can explicitly set the first phase.
    local defaultPhase = 'idle'

    -- NOTE: assumes `registration_fee` column exists in `elections`.
    -- If it doesn't, remove `registration_fee` from the insert.
    local insertId, err = RSGElection.DbInsertId([[
        INSERT INTO elections (region_hash, region_alias, phase, registration_fee)
        VALUES (?, ?, ?, ?)
    ]], {
        region_hash,
        regionAlias,
        defaultPhase,
        registrationFee
    })

    if not insertId then
        RSGElection.Log('adminCreateElection failed: %s', tostring(err))
        Notify(src, "Elections", "Database error creating election.", "error")
        return
    end

    RSGElection.Audit(("src:%s"):format(src), "admin_create_election",
        ("Created election #%d in %s (%s), phase=%s, reg_fee=%s"):format(
            insertId, regionAlias, region_hash, defaultPhase, tostring(registrationFee)
        )
    )

    Notify(src, "Elections",
        ("Election #%d created for region %s. Phase: Idle."):format(
            insertId, regionAlias
        ),
        "success"
    )

    -- Re-open / refresh the admin menu on client
    TriggerClientEvent('rsg-election:client:OpenAdminMenu', src)
end)

------------------------------------------------
-- ADMIN: list elections for /electionmenu
------------------------------------------------

lib.callback.register('rsg-election:getAdminElectionList', function(src)
    if not IsOwner(src) then
        return { ok = false, error = "No permission." }
    end

    local rows, err = DbQuery([[
        SELECT 
            e.id,
            e.region_alias,
            e.region_hash,
            e.phase,
            e.reg_start,
            e.vote_start,
            e.vote_end,
            (
                SELECT COUNT(*) 
                FROM election_votes v 
                WHERE v.election_id = e.id
            ) AS total_votes
        FROM elections e
        ORDER BY e.id DESC
        LIMIT 20
    ]], {})

    if not rows then
        return { ok = false, error = err or "Database error." }
    end

    local monthNames = {
        "January","February","March","April","May","June",
        "July","August","September","October","November","December"
    }

        local monthNames = {
        "January","February","March","April","May","June",
        "July","August","September","October","November","December"
    }

    local function fmtPretty(val)
        if not val or val == 0 or val == "0" then
            return nil
        end

        -- Try numeric first (oxmysql often returns DATETIME as ms)
        local num = tonumber(val)
        if num then
            -- If it looks like milliseconds, convert to seconds
            if math.abs(num) > 1e9 then
                num = num / 1000
            end

            local t = os.date("*t", num)
            if t and t.year and t.month and t.day then
                local mn = monthNames[t.month] or tostring(t.month)
                return string.format("%s %d, %d", mn, t.day, t.year)
            end
        end

        -- Fallback: parse "YYYY-MM-DD ..." strings
        local s = tostring(val)
        local y, m, d = s:match("^(%d+)%-(%d+)%-(%d+)")
        if y then
            local mi = tonumber(m) or 0
            local monthName = monthNames[mi] or m
            return string.format("%s %d, %s", monthName, tonumber(d) or d, y)
        end

        return s
    end

    for _, row in ipairs(rows) do
        row.phase_label = PHASE_LABELS[row.phase] or row.phase
        row.reg_start   = fmtPretty(row.reg_start)
        row.vote_start  = fmtPretty(row.vote_start)
        row.vote_end    = fmtPretty(row.vote_end)
    end

    return { ok = true, elections = rows }
end)

------------------------------------------------
-- ADMIN: detail for single election (phase + tally)
------------------------------------------------

------------------------------------------------
-- ADMIN: detail for single election (phase + tally)
------------------------------------------------

lib.callback.register('rsg-election:getElectionAdminDetail', function(src, electionId)
    if not IsOwner(src) then
        return { ok = false, error = "No permission." }
    end

    electionId = tonumber(electionId)
    if not electionId then
        return { ok = false, error = "Invalid election id." }
    end

    local elec = RSGElection.GetElectionById(electionId)
    if not elec then
        return { ok = false, error = "Election not found." }
    end

    local tally, err = RSGElection.GetElectionTally(electionId)
    if not tally then
        return { ok = false, error = err or "Failed to load tally." }
    end

    -- Pretty-print DB dates like "November 22, 1898"
    local monthNames = {
        "January","February","March","April","May","June",
        "July","August","September","October","November","December"
    }

        local monthNames = {
        "January","February","March","April","May","June",
        "July","August","September","October","November","December"
    }

    local function fmtPretty(val)
        if not val or val == 0 or val == "0" then
            return "N/A"
        end

        local num = tonumber(val)
        if num then
            if math.abs(num) > 1e9 then
                num = num / 1000
            end

            local t = os.date("*t", num)
            if t and t.year and t.month and t.day then
                local mn = monthNames[t.month] or tostring(t.month)
                return string.format("%s %d, %d", mn, t.day, t.year)
            end
        end

        local s = tostring(val)
        local y, m, d = s:match("^(%d+)%-(%d+)%-(%d+)")
        if y then
            local mi = tonumber(m) or 0
            local monthName = monthNames[mi] or m
            return string.format("%s %d, %s", monthName, tonumber(d) or d, y)
        end

        return s
    end

    elec.reg_start  = fmtPretty(elec.reg_start)
    elec.reg_end    = fmtPretty(elec.reg_end)
    elec.vote_start = fmtPretty(elec.vote_start)
    elec.vote_end   = fmtPretty(elec.vote_end)

    elec.phase_label = PHASE_LABELS[elec.phase] or elec.phase

    return {
        ok       = true,
        election = elec,
        tally    = tally
    }
end)

-- --------------------------------------------------------------
-- Broadcast election announcement to all approved residents
-- in the same region (online players only)
-- --------------------------------------------------------------
local function BroadcastToRegionResidents(region_hash, message, msgType)
    msgType = msgType or "inform"

    local rows = MySQL.query.await(
        'SELECT citizenid FROM rsg_residency WHERE region_hash = ? AND status = "approved"',
        { region_hash }
    )
    if not rows or #rows == 0 then return end

    if not RSGCore or not RSGCore.Functions or not RSGCore.Functions.GetPlayerByCitizenId then
        return
    end

    for _, row in ipairs(rows) do
        local target = RSGCore.Functions.GetPlayerByCitizenId(row.citizenid)
        if target then
            Notify(target.PlayerData.source, "Elections", message, msgType)
        end
    end
end

---------------------------------------------------------------------
-- Shared finalize helper
--   Finalizes the election for a region:
--   - tallies votes
--   - marks election complete
--   - installs governor via rsg-governor
--   Returns: ok (bool), errmsg (string|nil)
---------------------------------------------------------------------
if not RSGElection.FinalizeElectionForRegion then
    function RSGElection.FinalizeElectionForRegion(source, region_hash, igDateStr)
        if not region_hash then
            Notify(source, "Elections", "Could not determine region hash for finalizing.", "error")
            return false, "no_region"
        end

        igDateStr = tostring(igDateStr or '')

        -- Get active election in this region
        local elec = GetActive(region_hash)
        if not elec then
            Notify(source, "Elections", "No active election in this region.", "error")
            return false, "no_election"
        end

        -- Tally votes for this election
        local rows, err = DbQuery([[
            SELECT candidate_id, COUNT(*) as votes
            FROM election_votes
            WHERE election_id = ?
            GROUP BY candidate_id
            ORDER BY votes DESC
        ]], { elec.id })

        if err then
            if RSGElection.Log then
                RSGElection.Log('Error tallying votes for election %d: %s', elec.id, tostring(err))
            end
            Notify(source, "Elections", "Database error tallying votes.", "error")
            return false, "db_error"
        end

        if not rows or not rows[1] then
            Notify(source, "Elections", "No votes cast. No winner.", "error")
            return false, "no_votes"
        end

        local winnerCandId = rows[1].candidate_id
        local winnerVotes  = rows[1].votes

        -- Fetch winning candidate record
        local winner = MySQL.single.await(
            'SELECT * FROM election_candidacies WHERE id = ? LIMIT 1',
            { winnerCandId }
        )

        -- Decide vote_end value: in-game date if provided, else NOW()
        local voteEndIsCustom = (igDateStr ~= "")
        if voteEndIsCustom then
            local dt = igDateStr .. " 00:00:00"
            local _, err3 = DbExec(
                'UPDATE elections SET phase = "complete", vote_end = ? WHERE id = ?',
                { dt, elec.id }
            )
            if err3 and RSGElection.Log then
                RSGElection.Log('Failed to mark election %d complete (custom date): %s', elec.id, tostring(err3))
            end
        else
            local _, err3 = DbExec(
                'UPDATE elections SET phase = "complete", vote_end = NOW() WHERE id = ?',
                { elec.id }
            )
            if err3 and RSGElection.Log then
                RSGElection.Log('Failed to mark election %d complete (NOW): %s', elec.id, tostring(err3))
            end
        end

        local actorCid = ("src:%s"):format(source)
        if Audit then
            Audit(actorCid, "finalizeelection",
                ("Election %d winner: %s (%s votes)"):format(
                    elec.id,
                    winner and winner.character_name or "unknown",
                    winnerVotes
                )
            )
        end

        if not winner then
            Notify(source, "Elections", "Winner record missing, cannot install governor.", "error")
            return false, "no_winner_record"
        end

        -- 🏛 Auto-install new governor through rsg-governor
        local ok, result = pcall(function()
            return exports['rsg-governor']:InstallGovernor(elec.region_alias, winner.citizenid)
        end)

        if ok and result then
            -- Notify admin
            Notify(source, "Governorship",
                ("New Governor installed: %s (%s votes)."):format(winner.character_name, winnerVotes),
                "success"
            )

            -- Broadcast to all players
            TriggerClientEvent('ox_lib:notify', -1, {
                title       = "Elections",
                description = ("New Governor of %s: %s"):format(
                    string.upper(elec.region_alias), winner.character_name
                ),
                type        = "success",
                duration    = 8000
            })

            return true, nil
        else
            Notify(source, "Governorship",
                "Failed to automatically install governor. Check rsg-governor / winner online state.",
                "error"
            )
            return false, "install_failed"
        end
    end
end

------------------------------------------------
-- ADMIN: change phase for an election (months + mode + in-game date + announcement)
------------------------------------------------

RegisterNetEvent('rsg-election:adminSetPhase', function(electionId, newPhase, durationMonths, monthMode, igDate, announceFlag)
    local src = source
    if not IsOwner(src) then return end

    electionId      = tonumber(electionId)
    newPhase        = tostring(newPhase or ''):lower()
    local months    = tonumber(durationMonths or 0) or 0
    local mode      = tostring(monthMode or 'ingame')
    local igDateStr = tostring(igDate or '')
    local announce  = announceFlag and true or false

    if not electionId or newPhase == '' then return end

    local allowed = {
        registration = true,
        campaign     = true,
        voting       = true,
        complete     = true,  -- Result
    }
    if not allowed[newPhase] then
        Notify(src, "Elections", "Invalid phase.", "error")
        return
    end

    local elec = RSGElection.GetElectionById(electionId)
    if not elec then
        Notify(src, "Elections", "Election not found.", "error")
        return
    end

    -- Already in this phase?
    if (elec.phase or ''):lower() == newPhase then
        local label = PHASE_LABELS[newPhase] or newPhase
        Notify(src, "Elections", (label .. " phase is already initiated."), "inform")
        return
    end

    -- Build a DATETIME string from in-game date (if provided)
    local function igDatetimeOrNull()
        if igDateStr ~= '' then
            return igDateStr .. " 00:00:00"
        end
        return nil
    end

    ------------------------------------------------
    -- Immediate phase change – write in-game date
    ------------------------------------------------
    if newPhase == 'registration' then
        local ts = igDatetimeOrNull()
        local _, err = DbExec(
            'UPDATE elections SET phase = "registration", reg_start = ?, reg_end = NULL, vote_start = NULL, vote_end = NULL WHERE id = ?',
            { ts, electionId }
        )
        if err then
            Notify(src, "Elections", "Failed to set phase to Registration.", "error")
            return
        end

    elseif newPhase == 'campaign' then
        local ts = igDatetimeOrNull()
        local _, err = DbExec(
            'UPDATE elections SET phase = "campaign", reg_end = ? WHERE id = ?',
            { ts, electionId }
        )
        if err then
            Notify(src, "Elections", "Failed to set phase to Campaign.", "error")
            return
        end

    elseif newPhase == 'voting' then
        local ts = igDatetimeOrNull()
        local _, err = DbExec(
            'UPDATE elections SET phase = "voting", vote_start = ? WHERE id = ?',
            { ts, electionId }
        )
        if err then
            Notify(src, "Elections", "Failed to set phase to Voting.", "error")
            return
        end

    elseif newPhase == 'complete' then
        -- Use shared finalize helper: tally votes, mark complete, install governor
        -- Pass igDateStr so vote_end uses the in-game date (1898) instead of NOW().
        local ok, msg = RSGElection.FinalizeElectionForRegion(src, elec.region_hash, igDateStr)
        if not ok then
            if msg and RSGElection.Log then
                RSGElection.Log("FinalizeElectionForRegion from adminSetPhase failed: %s", msg)
            end
            return
        end
    end

    local label = PHASE_LABELS[newPhase] or newPhase
    Notify(src, "Elections",
        ("Election #%d phase set to %s."):format(electionId, label),
        "success"
    )

    ------------------------------------------------
    -- Optional: announce to all residents in region
    ------------------------------------------------
    if announce and elec.region_hash then
        -- Pretty date if we have igDate
        local prettyDate = "today"
        if igDateStr ~= '' then
            local months = {
                "January","February","March","April","May","June",
                "July","August","September","October","November","December"
            }
            local y, m, d = igDateStr:match("^(%d+)%-(%d+)%-(%d+)")
            if y and m and d then
                local mi = tonumber(m) or 0
                local monthName = months[mi] or m
                prettyDate = ("%s %d, %s"):format(monthName, tonumber(d) or d, y)
            end
        end

        local regionName = elec.region_alias or "this region"
        local msg

        if newPhase == 'registration' then
            msg = ("Registration for the governor election in %s has begun on %s. You may now apply as a candidate."):format(regionName, prettyDate)
        elseif newPhase == 'campaign' then
            msg = ("Campaign period for the governor election in %s has begun on %s. Support your preferred candidates."):format(regionName, prettyDate)
        elseif newPhase == 'voting' then
            msg = ("Voting has opened for the governor election in %s on %s. Residents may now cast their votes."):format(regionName, prettyDate)
        elseif newPhase == 'complete' then
            msg = ("The governor election in %s has concluded on %s. Results are now available."):format(regionName, prettyDate)
        end

        if msg then
            BroadcastToRegionResidents(elec.region_hash, msg, "inform")
        end
    end

    TriggerClientEvent("rsg-election:refreshElectionData", -1)

    ------------------------------------------------
    -- Auto-advance timer (unchanged, for timing only)
    ------------------------------------------------
    local timedPhases = {
        registration = true,
        campaign     = true,
        voting       = true,
    }

    if timedPhases[newPhase] and months > 0 then
        local gameMonthMinutes = (Config and Config.InGameMonthMinutes) or 60
        local realMonthMinutes = (Config and Config.RealTimeMonthMinutes) or (30 * 24 * 60)

        local durationMinutes
        if mode == 'realtime' then
            durationMinutes = months * realMonthMinutes
        else
            durationMinutes = months * gameMonthMinutes
        end

        local ms = math.floor(durationMinutes * 60000)
        local expectedPhase = newPhase

        local nextMap = {
            registration = 'campaign',
            campaign     = 'voting',
            voting       = 'complete', -- Result
        }
        local nextPhase = nextMap[expectedPhase]

        if nextPhase and ms > 0 then
            SetTimeout(ms, function()
                local current = RSGElection.GetElectionById(electionId)
                if not current or (current.phase or ''):lower() ~= expectedPhase then
                    return -- phase changed manually or election removed
                end

                if nextPhase == 'campaign' then
                    DbExec('UPDATE elections SET phase = "campaign" WHERE id = ?', { electionId })
                elseif nextPhase == 'voting' then
                    DbExec('UPDATE elections SET phase = "voting" WHERE id = ?', { electionId })
                elseif nextPhase == 'complete' then
                    -- keep existing auto-complete behavior here,
                    -- or switch to FinalizeElectionForRegion if you want auto-install too
                    RSGElection.MarkElectionComplete(electionId)
                end

                local nextLabel = PHASE_LABELS[nextPhase] or nextPhase
                TriggerClientEvent('ox_lib:notify', -1, {
                    title       = "Elections",
                    description = ("Election #%d automatically advanced to %s."):format(
                        electionId, nextLabel
                    ),
                    type        = "inform",
                    duration    = 8000
                })

                TriggerClientEvent("rsg-election:refreshElectionData", -1)
            end)
        end
    end
end)

------------------------------------------------
-- ADMIN: apply result (tally + install governor + broadcast)
------------------------------------------------

RegisterNetEvent('rsg-election:adminApplyResult', function(electionId)
    local src = source
    if not IsOwner(src) then return end

    electionId = tonumber(electionId)
    if not electionId then return end

    local elec = RSGElection.GetElectionById(electionId)
    if not elec then
        Notify(src, "Elections", "Election not found.", "error")
        return
    end

    if elec.phase ~= 'complete' then
        Notify(src, "Elections", "Set phase to Result before applying result.", "error")
        return
    end

    local winner, tally, err = RSGElection.GetElectionWinner(electionId)
    if not winner then
        Notify(src, "Elections", err or "No winner could be determined.", "error")
        return
    end

    local ok, result = pcall(function()
        return exports['rsg-governor']:InstallGovernor(elec.region_alias, winner.citizenid)
    end)

    if ok and result then
        Notify(src, "Governorship",
            ("New Governor installed: %s (%d votes)."):format(winner.character_name, winner.votes or 0),
            "success"
        )

        TriggerClientEvent('ox_lib:notify', -1, {
            title       = "Elections",
            description = ("New Governor of %s: %s"):format(
                string.upper(elec.region_alias or "UNKNOWN"), winner.character_name
            ),
            type        = "success",
            duration    = 8000
        })
    else
        Notify(src, "Governorship",
            "Failed to install governor. Check rsg-governor or the winner's online state.",
            "error"
        )
    end
end)
