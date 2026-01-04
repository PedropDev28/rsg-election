--======================================================================
-- rsg-election / server/sv_candidates.lua
-- Candidacy: apply, list pending, approve, reject
--======================================================================

local RSGCore     = exports['rsg-core']:GetCoreObject()
RSGElection       = RSGElection or {}
RSGElection.Enums = RSGElection.Enums or {}
lib.locale()
local Notify    = RSGElection.Notify
local Audit     = RSGElection.Audit
local GetRegion = RSGElection.GetPlayerRegionHash
local GetActive = RSGElection.GetActiveElectionByRegion
local IsOwner   = RSGElection.IsElectionOwner

local MAX_CANDIDATES = RSGElection.MAX_CANDIDATES or 3

-- ---------------------------------------------------------------------
-- Helper: get clean character name from Player
-- ---------------------------------------------------------------------
local function getCharNameFromPlayer(Player)
    if not Player then return 'Unknown' end
    local charinfo = Player.PlayerData.charinfo or {}
    local first    = charinfo.firstname or locale('unknown') or 'Unknown'
    local last     = charinfo.lastname or ''
    return (first .. ' ' .. last):gsub('%s+$', '')
end

-- ---------------------------------------------------------------------
-- Helper: is player in a blocked job (lawman / medic)?
-- ---------------------------------------------------------------------
local function IsJobBlockedForGovernor(Player)
    if not Player then return false, nil end

    local job   = Player.PlayerData.job or {}
    local name  = tostring(job.name or ''):lower()

    -- You can override this in Config.ElectionBlockedJobs
    local blockedJobs = (Config and Config.ElectionBlockedJobs) or {
        'lawman',
        'medic',
    }

    for _, j in ipairs(blockedJobs) do
        if name == j then
            return true, name
        end
    end

    return false, name
end

-- ---------------------------------------------------------------------
-- Helper: does player have a residency document for this region?
-- ---------------------------------------------------------------------
local function HasResidencyDocument(Player, region_hash)
    if not Player then return false end

    -- Adjust item name if yours is different
    local item = Player.Functions.GetItemByName
        and Player.Functions.GetItemByName('residency_document')

    if not item or (item.amount or 0) <= 0 then
        return false
    end

    -- If you don't use metadata on the document, just accept it as generic proof
    local info = item.info or item.metadata or {}
    if not info or (not info.region_hash and not info.regionAlias and not info.region_alias) then
        return true
    end

    -- If you store region_hash on the item, try to match it (HEX preferred)
    local itemHash = info.region_hash
    if itemHash and region_hash then
        if tostring(itemHash):lower() == tostring(region_hash):lower() then
            return true
        end
    end

    -- Optional: you could also compare aliases here if needed (info.regionAlias)
    -- For now, any residency document with some metadata is accepted.
    return true
end

-- ---------------------------------------------------------------------
-- Apply as candidate
--   Event: rsg-election:candidacy:submit
--   From: client/cl_candidacy.lua (lib.inputDialog)
-- ---------------------------------------------------------------------
RegisterNetEvent("rsg-election:candidacy:submit", function(data)
    local src    = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    -- 🔒 Block lawman / medic (or any blocked job) from running
    local blocked, jobName = IsJobBlockedForGovernor(Player)
    if blocked then
        Notify(src, locale('candidacy') or "Candidacy",
            locale('must_resign_job', jobName) or ("You must resign from your %s job before running for governor."):format(jobName),
            "error"
        )
        return
    end

    local citizenid  = Player.PlayerData.citizenid
    local identifier = Player.PlayerData.license or Player.PlayerData.steam or ("src:" .. src)
    local charName   = data and data.name
        or getCharNameFromPlayer(Player)

    local region_hash = GetRegion(src)       -- should already be HEX like "0x41332496"
    if not region_hash then
        Notify(src, locale('candidacy') or "Candidacy", locale('cannot_determine_region') or "Cannot determine your region.", "error")
        return
    end

    local elec = GetActive(region_hash)
    if not elec or elec.phase ~= 'registration' then
        Notify(src, locale('candidacy') or "Candidacy", locale('no_active_registration') or "No active registration in this region.", "error")
        return
    end

    --------------------------------------------------------------------
    -- Residency check using NEW rsg-residency table (HEX region_hash)
    --------------------------------------------------------------------
    local res = MySQL.single.await(
        'SELECT region_hash FROM rsg_residency WHERE citizenid = ? AND status = "approved"',
        { citizenid }
    )

    if not res then
        Notify(src, locale('candidacy') or "Candidacy", locale('not_approved_resident') or "You are not an approved resident of any region.", "error")
        return
    end

    local resHash  = tostring(res.region_hash or ''):lower()
    local elecHash = tostring(elec.region_hash or ''):lower()

    if resHash == '' or elecHash == '' or resHash ~= elecHash then
        Notify(src, locale('candidacy') or "Candidacy", locale('must_be_resident') or "You must be a resident of this region to apply.", "error")
        return
    end

    -- Additional check: residency document item as proof
    if not HasResidencyDocument(Player, elec.region_hash) then
        Notify(src, locale('candidacy') or "Candidacy", locale('must_carry_residency_document') or "You must carry your residency document to apply as a candidate.", "error")
        return
    end

    -- Not already a candidate in this election
    local existing = MySQL.single.await([[
        SELECT id FROM election_candidacies
        WHERE election_id = ? AND citizenid = ?
    ]], { elec.id, citizenid })
    if existing then
        Notify(src, locale('candidacy') or "Candidacy", locale('already_applied') or "You have already applied for this election.", "error")
        return
    end

    -- Insert candidacy row
    MySQL.insert([[
        INSERT INTO election_candidacies
            (election_id, identifier, citizenid, character_name, region_hash, region_alias, bio, portrait)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        elec.id,
        identifier,
        citizenid,
        charName,
        elec.region_hash,
        elec.region_alias,
        (data and data.bio) or "",
        (data and data.portrait) or "assets/portrait1.png"
    })

    Audit(citizenid, "apply_candidacy",
        (locale('applied_as_candidate') or "Applied as candidate in election %d (%s)"):format(elec.id, elec.region_alias)
    )

    Notify(src, locale('candidacy') or "Candidacy", locale('application_submitted') or "Your application has been submitted for review.", "success")
end)

-- ---------------------------------------------------------------------
-- Helper: openPendingCandidaciesMenuFor(src)
-- Reused by /reviewapps and after approve/reject
-- ---------------------------------------------------------------------
local function openPendingCandidaciesMenuFor(src)
    if not IsOwner(src) then
        Notify(src, locale('candidacy') or "Candidacy", locale('only_owner_review') or "Only the server owner may review candidates.", "error")
        return
    end

    local region_hash = GetRegion(src)
    if not region_hash then
        Notify(src, locale('candidacy') or "Candidacy", locale('cannot_determine_region') or "Cannot determine your region.", "error")
        return
    end

    local elec = GetActive(region_hash)
    if not elec then
        Notify(src, locale('candidacy') or "Candidacy", locale('no_active_election') or "No active election in this region.", "error")
        return
    end

    local apps = MySQL.query.await([[
        SELECT * FROM election_candidacies
        WHERE election_id = ? AND status = 'pending'
    ]], { elec.id })

    if not apps or #apps == 0 then
        Notify(src, locale('candidacy') or "Candidacy", locale('no_pending_applications') or "No pending applications.", "inform")
        return
    end

    local opts = {}
    for _, app in ipairs(apps) do
        opts[#opts+1] = {
            title       = ("#%d — %s"):format(app.id, app.character_name),
            description = app.bio or '',
            event       = "rsg-election:reviewAppOpen",
            args        = app.id,
            arrow       = true
        }
    end

    TriggerClientEvent("rsg-election:openCandidacyMenu", src, opts)
end

-- ---------------------------------------------------------------------
-- /reviewapps – OWNER ONLY
-- Opens the pending candidacy list (ox_lib context menu on client)
-- ---------------------------------------------------------------------
RSGCore.Commands.Add('reviewapps', locale('review_pending_applications') or 'Review pending candidate applications', {}, false, function(source, _)
    openPendingCandidaciesMenuFor(source)
end, 'god')

-- ---------------------------------------------------------------------
-- Open a specific candidacy (detail view)
--   Event: rsg-election:reviewAppOpen (from client menu)
-- ---------------------------------------------------------------------
RegisterNetEvent("rsg-election:reviewAppOpen", function(appId)
    local src = source
    if not IsOwner(src) then return end

    local app = MySQL.single.await('SELECT * FROM election_candidacies WHERE id = ?', { appId })
    if not app then return end

    TriggerClientEvent("rsg-election:showCandidacyDetail", src, app)
end)

-- ---------------------------------------------------------------------
-- Approve a candidacy
--   Event: rsg-election:approveCandidacy
-- ---------------------------------------------------------------------
RegisterNetEvent("rsg-election:approveCandidacy", function(appId)
    local src = source
    if not IsOwner(src) then return end

    local app = MySQL.single.await('SELECT * FROM election_candidacies WHERE id = ?', { appId })
    if not app or app.status ~= 'pending' then return end

    -- Enforce MAX_CANDIDATES per election
    local approvedCount = MySQL.scalar.await([[
        SELECT COUNT(*) FROM election_candidacies
        WHERE election_id = ? AND status = 'approved'
    ]], { app.election_id }) or 0

    if approvedCount >= MAX_CANDIDATES then
        Notify(src, locale('candidacy') or "Candidacy", (locale('maximum_candidates_approved') or "Maximum %d candidates already approved."):format(MAX_CANDIDATES), "error")
        return
    end

    MySQL.update('UPDATE election_candidacies SET status = "approved" WHERE id = ?', { appId })

    local Player   = RSGCore.Functions.GetPlayer(src)
    local actorCid = Player and Player.PlayerData.citizenid or ('src:' .. src)

    Audit(actorCid, "approve_candidate",
        (locale('approved_candidacy') or "Approved candidacy %d (%s)"):format(appId, app.character_name)
    )

    Notify(src, locale('candidacy') or "Candidacy",
        (locale('approved_as_candidate') or "Approved %s as candidate."):format(app.character_name),
        "success"
    )

    -- Notify candidate if online
    if RSGCore.Functions.GetPlayerByCitizenId then
        local target = RSGCore.Functions.GetPlayerByCitizenId(app.citizenid)
        if target then
            Notify(target.PlayerData.source, locale('candidacy') or "Candidacy",
                locale('your_candidacy_approved') or "Your candidacy has been APPROVED.", "success")
        end
    end

    -- Re-open menu and refresh election UI
    openPendingCandidaciesMenuFor(src)
    TriggerClientEvent("rsg-election:refreshElectionData", -1)
end)

-- ---------------------------------------------------------------------
-- Reject a candidacy
--   Event: rsg-election:rejectCandidacy
-- ---------------------------------------------------------------------
RegisterNetEvent("rsg-election:rejectCandidacy", function(appId)
    local src = source
    if not IsOwner(src) then return end

    local app = MySQL.single.await('SELECT * FROM election_candidacies WHERE id = ?', { appId })
    if not app or app.status ~= 'pending' then return end

    MySQL.update('UPDATE election_candidacies SET status = "rejected" WHERE id = ?', { appId })

    local Player   = RSGCore.Functions.GetPlayer(src)
    local actorCid = Player and Player.PlayerData.citizenid or ('src:' .. src)

    Audit(actorCid, "reject_candidate",
        (locale('rejected_candidacy') or "Rejected candidacy %d (%s)"):format(appId, app.character_name)
    )

    Notify(src, locale('candidacy') or "Candidacy",
        (locale('rejected_candidacy_notify') or "Rejected %s's candidacy."):format(app.character_name),
        "error"
    )

    -- Notify candidate if online
    if RSGCore.Functions.GetPlayerByCitizenId then
        local target = RSGCore.Functions.GetPlayerByCitizenId(app.citizenid)
        if target then
            Notify(target.PlayerData.source, locale('candidacy') or "Candidacy",
                locale('your_candidacy_rejected') or "Your candidacy has been REJECTED.", "error")
        end
    end

    openPendingCandidaciesMenuFor(src)
    TriggerClientEvent("rsg-election:refreshElectionData", -1)
end)

-- ============================================================
-- /applycandidate
-- Opens the candidacy application form (client)
-- ============================================================

RSGCore.Commands.Add('applycandidate', locale('apply_as_candidate') or 'Apply as a candidate in the active election.', {}, false, function(source, args)
    local src    = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    -- 🔒 Block lawman / medic from running
    local blocked, jobName = IsJobBlockedForGovernor(Player)
    if blocked then
        RSGElection.Notify(src, locale('candidacy') or "Candidacy",
            (locale('must_resign_job') or "You must resign from your %s job before running for governor."):format(jobName),
            "error"
        )
        return
    end

    -- Get player's region hash (HEX)
    local region_hash = RSGElection.GetPlayerRegionHash(src)
    if not region_hash then
        RSGElection.Notify(src, locale('candidacy') or "Candidacy", locale('could_not_determine_region') or "Could not determine your region.", "error")
        return
    end

    -- Get active election in that region
    local elec = RSGElection.GetActiveElectionByRegion(region_hash)
    if not elec then
        RSGElection.Notify(src, locale('candidacy') or "Candidacy", locale('no_election_found') or "No election found for your region.", "error")
        return
    end

    -- Must be in registration phase
    if tostring(elec.phase or ''):lower() ~= 'registration' then
        RSGElection.Notify(src, locale('candidacy') or "Candidacy", locale('registration_phase_only') or "You can only apply during Registration phase.", "error")
        return
    end

    -- All good, open client-side form
    TriggerClientEvent('rsg-election:client:openCandidacyForm', src)
end)
