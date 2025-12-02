--======================================================================
-- rsg-election / client/cl_admin.lua
-- Admin election menu using ox_lib context menus
--======================================================================

local function getRegionOptions()
    local opts = {}

    -- You can configure this in config.lua:
    -- Config.ElectionRegions = {
    --   { label = "New Hanover", value = "new_hanover" },
    --   { label = "Lemoyne",     value = "lemoyne" },
    --   ...
    -- }
    if Config and Config.ElectionRegions and #Config.ElectionRegions > 0 then
        for _, r in ipairs(Config.ElectionRegions) do
            opts[#opts+1] = {
                label = r.label or (r.value or r.alias or r.name or "Unknown"),
                value = r.value or r.alias or r.name or r
            }
        end
    else
        -- Fallback defaults if not configured
        local defaults = {
            { label = "New Hanover",   value = "new_hanover" },
            { label = "Lemoyne",       value = "lemoyne" },
            { label = "Ambarino",      value = "ambarino" },
            { label = "West Elizabeth",value = "west_elizabeth" },
            { label = "New Austin",    value = "new_austin" },
        }
        for _, r in ipairs(defaults) do
            opts[#opts+1] = r
        end
    end

    return opts
end

local function openSetupElectionDialog()
    local regionOptions = getRegionOptions()
    if #regionOptions == 0 then
        lib.notify({
            title       = 'Elections',
            description = 'No regions configured for elections.',
            type        = 'error'
        })
        return
    end

    local input = lib.inputDialog('Setup Election', {
        {
            type     = 'select',
            label    = 'Region',
            options  = regionOptions,
            required = true,
            default  = regionOptions[1].value,
        },
        {
            type    = 'number',
            label   = 'Registration Fee',
            default = 0,
            min     = 0,
        }
    })

    if not input then return end -- cancelled

    local regionAlias     = input[1]
    local registrationFee = tonumber(input[2]) or 0

    -- Only region + fee; phase will be handled separately in the phase menu
    TriggerServerEvent('rsg-election:adminCreateElection', regionAlias, registrationFee)
end

local function openElectionAdminMenu()
    lib.callback('rsg-election:getAdminElectionList', false, function(response)
        if not response or not response.ok then
            local msg = (response and response.error) or 'Failed to load elections.'
            lib.notify({
                title       = 'Elections',
                description = msg,
                type        = 'error'
            })
            return
        end

        local elections = response.elections or {}
        local options   = {}

        -- Setup new election option at the top
        options[#options+1] = {
            title       = "Setup new election",
            description = "Create a new election (region, phase, registration fee).",
            event       = 'rsg-election:client:OpenSetupElection',
            arrow       = true,
        }

        if #elections == 0 then
            options[#options+1] = {
                title       = "No existing elections.",
                description = "Use 'Setup new election' to create one.",
                disabled    = true,
            }
        else
            for _, elec in ipairs(elections) do
                local title = string.format("#%d — %s", elec.id, string.upper(elec.region_alias or 'UNKNOWN'))
                local descLines = {}

                table.insert(descLines, string.format("Phase: %s", elec.phase_label or elec.phase or 'unknown'))

                if elec.total_votes and elec.total_votes > 0 then
                    table.insert(descLines, string.format("Total votes: %d", elec.total_votes))
                else
                    table.insert(descLines, "Total votes: 0")
                end

                if elec.reg_start then
                    table.insert(descLines, "Reg start: " .. tostring(elec.reg_start))
                end
                if elec.vote_start then
                    table.insert(descLines, "Vote start: " .. tostring(elec.vote_start))
                end
                if elec.vote_end then
                    table.insert(descLines, "Vote end: " .. tostring(elec.vote_end))
                end

                options[#options+1] = {
                    title       = title,
                    description = table.concat(descLines, "\n"),
                    event       = 'rsg-election:client:OpenElectionAdminDetail',
                    args        = elec.id,
                    arrow       = true,
                }
            end
        end

        lib.registerContext({
            id      = 'rsg-election-admin-list',
            title   = 'Election Admin Menu',
            options = options
        })

        lib.showContext('rsg-election-admin-list')
    end)
end

RegisterNetEvent('rsg-election:client:OpenAdminMenu', function()
    openElectionAdminMenu()
end)

RegisterNetEvent('rsg-election:client:OpenSetupElection', function()
    openSetupElectionDialog()
end)

RegisterNetEvent('rsg-election:client:OpenElectionAdminDetail', function(electionId)
    electionId = tonumber(electionId)
    if not electionId then return end

    lib.callback('rsg-election:getElectionAdminDetail', false, function(response)
        if not response or not response.ok or not response.election then
            local msg = (response and response.error) or 'Election not found.'
            lib.notify({
                title       = 'Elections',
                description = msg,
                type        = 'error'
            })
            return
        end

        local elec  = response.election
        local tally = response.tally or {}

        local options = {}

        -- Summary header (non-interactive)
        options[#options+1] = {
            title       = string.format("Phase: %s", elec.phase_label or elec.phase or 'unknown'),
            description = string.format(
                "Region: %s\nReg start: %s\nVote start: %s\nVote end: %s",
                string.upper(elec.region_alias or 'UNKNOWN'),
                elec.reg_start or 'N/A',
                elec.vote_start or 'N/A',
                elec.vote_end or 'N/A'
            ),
            disabled    = true,
        }

        if #tally == 0 then
            options[#options+1] = {
                title    = "No candidates / votes yet.",
                disabled = true
            }
        else
            for _, row in ipairs(tally) do
                options[#options+1] = {
                    title       = string.format("%s — %d votes", row.character_name or ('Candidate #' .. row.candidate_id), row.votes or 0),
                    description = ("CitizenID: %s"):format(row.citizenid or 'unknown'),
                    disabled    = true,
                }
            end
        end

        local id = elec.id

        -- Phase change options
        options[#options+1] = {
            title = "Set phase: Registration",
            event = 'rsg-election:client:AdminSetPhase',
            args  = { id = id, phase = 'registration' },
        }
        options[#options+1] = {
            title = "Set phase: Campaign",
            event = 'rsg-election:client:AdminSetPhase',
            args  = { id = id, phase = 'campaign' },
        }
        options[#options+1] = {
            title = "Set phase: Voting",
            event = 'rsg-election:client:AdminSetPhase',
            args  = { id = id, phase = 'voting' },
        }
        options[#options+1] = {
            title       = "Set phase: Result",
            description = "Marks election as complete (Result).",
            event       = 'rsg-election:client:AdminSetPhase',
            args        = { id = id, phase = 'complete' },
        }

        if elec.phase == 'complete' and #tally > 0 then
            options[#options+1] = {
                title       = "Apply result (install governor + announce)",
                description = "Requires phase: Result.",
                event       = 'rsg-election:client:AdminApplyResult',
                args        = id,
            }
        end

        lib.registerContext({
            id      = 'rsg-election-admin-detail-' .. id,
            title   = string.format("Election #%d — %s", id, string.upper(elec.region_alias or 'UNKNOWN')),
            menu    = 'rsg-election-admin-list',
            options = options
        })

        lib.showContext('rsg-election-admin-detail-' .. id)
    end, electionId)
end)

RegisterNetEvent('rsg-election:client:AdminSetPhase', function(data)
    if not data or not data.id or not data.phase then return end

    local phase = data.phase

    -- Helper: current in-game date as YYYY-MM-DD
    local function getInGameDate()
        local year  = GetClockYear()
        local month = GetClockMonth() + 1 -- 0-based in game
        local day   = GetClockDayOfMonth()
        return string.format('%04d-%02d-%02d', year, month, day)
    end

    -- Phases that require a duration
    if phase == 'registration' or phase == 'campaign' or phase == 'voting' then
        local title = 'Set ' .. (phase:gsub("^%l", string.upper)) .. ' Duration'

        local input = lib.inputDialog(title, {
            {
                type     = 'number',
                label    = 'Duration (months)',
                default  = 1,
                min      = 1,
                required = true,
            },
            {
                type     = 'select',
                label    = 'Month type',
                options  = {
                    { label = 'In-game months',   value = 'ingame'   },
                    { label = 'Real-time months', value = 'realtime' },
                },
                default  = 'ingame',
                required = true,
            },
            {
                type     = 'select',
                label    = 'Send announcement to residents?',
                options  = {
                    { label = 'Yes', value = 'yes' },
                    { label = 'No',  value = 'no'  },
                },
                default  = 'yes',
                required = true,
            }
        })

        if not input then return end -- cancelled

        local months    = tonumber(input[1]) or 0
        local monthMode = tostring(input[2] or 'ingame')
        local announce  = tostring(input[3] or 'yes') == 'yes'

        if months <= 0 then
            lib.notify({
                title       = 'Elections',
                description = 'Months must be greater than 0.',
                type        = 'error'
            })
            return
        end

        local igDate = getInGameDate()

        -- Send phase + months + mode + in-game date + announce flag to server
        TriggerServerEvent('rsg-election:adminSetPhase', data.id, phase, months, monthMode, igDate, announce)
        return
    end

    -- Result phase (complete) – ask only for announce flag
    if phase == 'complete' then
        local input = lib.inputDialog('Set Result Phase', {
            {
                type     = 'select',
                label    = 'Announce result to residents?',
                options  = {
                    { label = 'Yes', value = 'yes' },
                    { label = 'No',  value = 'no'  },
                },
                default  = 'yes',
                required = true,
            }
        })

        if not input then return end

        local announce = tostring(input[1] or 'yes') == 'yes'
        local igDate   = getInGameDate()

        TriggerServerEvent('rsg-election:adminSetPhase', data.id, phase, 0, nil, igDate, announce)
        return
    end

    -- Fallback (if any other phase ever added, no duration)
    local igDate = getInGameDate()
    TriggerServerEvent('rsg-election:adminSetPhase', data.id, phase, 0, nil, igDate, false)
end)

RegisterNetEvent('rsg-election:client:AdminApplyResult', function(electionId)
    electionId = tonumber(electionId)
    if not electionId then return end
    TriggerServerEvent('rsg-election:adminApplyResult', electionId)
end)
