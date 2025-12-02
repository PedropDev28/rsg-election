--======================================================================
-- rsg-election / server/sv_helpers.lua
-- Shared helpers, logging, DB wrappers, and core utility functions
--======================================================================

local RSGCore = exports['rsg-core']:GetCoreObject()

-- Global election namespace (shared with other server files)
RSGElection       = RSGElection or {}
RSGElection.Enums = RSGElection.Enums or {}

-- --------------------------------------------------------------------
-- Basic config fallbacks (can be overridden from shared/sh_election.lua)
-- --------------------------------------------------------------------
RSGElection.PHASE_LABELS = RSGElection.PHASE_LABELS or {
    idle         = "Idle",
    registration = "Registration",
    campaign     = "Campaign",
    voting       = "Voting",
    complete     = "Complete",
}

RSGElection.MAX_CANDIDATES = RSGElection.MAX_CANDIDATES or 3

-- Optional debug flag (or use Config.Debug if you prefer)
local function isDebug()
    if Config and Config.Debug ~= nil then
        return Config.Debug
    end
    return true -- default to true while developing, set to false in production
end

-- ---------------------
-- Logging helpers
-- ---------------------

local function log(msg, ...)
    msg = ('[rsg-election] %s'):format(msg)
    if select('#', ...) > 0 then
        print(msg:format(...))
    else
        print(msg)
    end
end

local function debug(msg, ...)
    if not isDebug() then return end
    msg = ('[DEBUG] %s'):format(msg)
    if select('#', ...) > 0 then
        log(msg, ...)
    else
        log(msg)
    end
end

RSGElection.Log   = log
RSGElection.Debug = debug

-- ---------------------
-- Database helpers
-- ---------------------

--- Synchronous query (SELECT)
---@param query string
---@param params table|nil
---@return table|nil result, string|nil error
function RSGElection.DbQueryAwait(query, params)
    local ok, result = pcall(function()
        return MySQL.query.await(query, params or {})
    end)
    if not ok then
        log('DB query error: %s', tostring(result))
        return nil, result
    end
    return result, nil
end

--- Synchronous update/insert/delete (UPDATE/DELETE without insert-id)
---@param query string
---@param params table|nil
---@return number|nil affectedRows, string|nil error
function RSGElection.DbExecAwait(query, params)
    local ok, result = pcall(function()
        return MySQL.update.await(query, params or {})
    end)
    if not ok then
        log('DB exec error: %s', tostring(result))
        return nil, result
    end
    return result, nil
end

--- Synchronous insert returning last insert id
---@param query string
---@param params table|nil
---@return number|nil insertId, string|nil error
function RSGElection.DbInsertId(query, params)
    local ok, result = pcall(function()
        return MySQL.insert.await(query, params or {})
    end)
    if not ok then
        log('DB insert error: %s', tostring(result))
        return nil, result
    end
    return result, nil
end

-- ---------------------
-- Audit logging
-- ---------------------

--- Write to election_audit table (fire-and-forget, like old code)
---@param actor string
---@param action string
---@param details string
function RSGElection.Audit(actor, action, details)
    MySQL.insert('INSERT INTO election_audit (actor, action, details) VALUES (?, ?, ?)', {
        actor or "system",
        action or "unknown",
        details or ""
    })
end

-- ---------------------
-- Player helpers
-- ---------------------

--- Get RSGCore player by source
---@param src number
---@return table|nil Player
function RSGElection.GetPlayer(src)
    if not src or src <= 0 then return nil end
    return RSGCore.Functions.GetPlayer(src)
end

--- Get citizenid from player source
---@param src number
---@return string|nil citizenid
function RSGElection.GetCitizenId(src)
    local Player = RSGElection.GetPlayer(src)
    return Player and Player.PlayerData and Player.PlayerData.citizenid or nil
end

--- Get character name "Firstname Lastname"
---@param src number
---@return string|nil charName
function RSGElection.GetCharName(src)
    local Player = RSGElection.GetPlayer(src)
    if not Player then return nil end
    local charinfo = Player.PlayerData.charinfo or {}
    local first    = charinfo.firstname or 'Unknown'
    local last     = charinfo.lastname or ''
    return (first .. ' ' .. last):gsub('%s+$', '')
end

-- ---------------------
-- Region helpers
-- ---------------------

--- Get player's region hash (hex string) via rsg-governor callback
--- This mirrors the old getPlayerRegionHash behavior.
---@param src number
---@return string|nil regionHashHex
function RSGElection.GetPlayerRegionHash(src)
    local ok, hash = pcall(function()
        return lib.callback.await('rsg-governor:getRegionHash', src)
    end)
    if not ok or not hash then
        debug('Failed to get region hash for %s: %s', tostring(src), tostring(hash))
        return nil
    end
    return string.format("0x%08X", hash)
end

--- Lookup latest election row for a region hash
---@param regionHash string
---@return table|nil electionRow
function RSGElection.GetActiveElectionByRegion(regionHash)
    if not regionHash then return nil end
    local rows, err = RSGElection.DbQueryAwait([[
        SELECT * FROM elections
        WHERE region_hash = ?
        ORDER BY id DESC
        LIMIT 1
    ]], { regionHash })

    if not rows or not rows[1] then
        if err then
            debug('GetActiveElectionByRegion DB error: %s', tostring(err))
        end
        return nil
    end

    return rows[1]
end

-- ---------------------
-- Phases
-- ---------------------

--- Get human label for a phase (Idle / Registration / Campaign / Voting / Complete)
---@param phase string
---@return string
function RSGElection.GetPhaseLabel(phase)
    if not phase or phase == '' then return 'Unknown' end
    local labels = RSGElection.PHASE_LABELS or {}
    return labels[phase] or phase
end

--- Update election phase in DB
---@param electionId number
---@param phase string
function RSGElection.SetElectionPhase(electionId, phase)
    if not electionId or not phase then return end
    debug('Setting election %s phase to %s', tostring(electionId), tostring(phase))
    MySQL.update('UPDATE elections SET phase = ? WHERE id = ?', { phase, electionId })
end

-- ---------------------
-- Notifications
-- ---------------------

--- Wrapper for ox_lib:notify, to keep message style consistent
---@param src number
---@param title string
---@param desc string
---@param nType string
function RSGElection.Notify(src, title, desc, nType)
    if not src or src <= 0 then return end
    TriggerClientEvent('ox_lib:notify', src, {
        title       = title or 'Elections',
        description = desc  or '',
        type        = nType or 'inform',
        duration    = 6000
    })
end

-- ---------------------
-- Permissions
-- ---------------------

--- Election owner = server owner (god permission), same as old system.
---@param src number
---@return boolean
function RSGElection.IsElectionOwner(src)
    -- You can change this later to use your own permission system.
    return RSGCore.Functions.HasPermission(src, 'god')
end

-- --------------------------------------------------------------------
-- (Optional) small helper: safe fetch election by id
-- --------------------------------------------------------------------

--- Get election row by ID
---@param electionId number
---@return table|nil
function RSGElection.GetElectionById(electionId)
    if not electionId then return nil end
    local rows, err = RSGElection.DbQueryAwait('SELECT * FROM elections WHERE id = ? LIMIT 1', { electionId })
    if not rows or not rows[1] then
        if err then
            debug('GetElectionById error: %s', tostring(err))
        end
        return nil
    end
    return rows[1]
end
