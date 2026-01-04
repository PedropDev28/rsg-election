--======================================================================
-- rsg-election / client/cl_admin.lua
-- Admin election menu using ox_lib context menus
--======================================================================
lib.locale()
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
            title       = locale('elections') or 'Elections',
            description = locale('no_regions_configured') or 'No regions configured for elections.',
            type        = 'error'
        })
        return
    end

    local input = lib.inputDialog(locale('setup_election') or 'Setup Election', {
        {
            type     = 'select',
            label    = locale('region') or 'Region',
            options  = regionOptions,
            required = true,
            default  = regionOptions[1].value,
        },
        {
            type    = 'number',
            label   = locale('registration_fee') or 'Registration Fee',
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
            local msg = (response and response.error) or locale('failed_to_load_elections') or 'Failed to load elections.'
            lib.notify({
                title       = locale('elections') or 'Elections',
                description = msg,
                type        = 'error'
            })
            return
        end

        local elections = response.elections or {}
        local options   = {}

        -- Setup new election option at the top
        options[#options+1] = {
            title       = locale('setup_new_election') or "Setup new election",
            description = locale('setup_new_election_desc') or "Create a new election (region, phase, registration fee).",
            event       = 'rsg-election:client:OpenSetupElection',
            arrow       = true,
        }

        if #elections == 0 then
            options[#options+1] = {
                title       = locale('no_existing_elections') or "No existing elections.",
                description = locale('use_setup_new_election') or "Use 'Setup new election' to create one.",
                disabled    = true,
            }
        else
            for _, elec in ipairs(elections) do
                local title = string.format("#%d — %s", elec.id, string.upper(elec.region_alias or locale('unknown') or 'UNKNOWN'))
                local descLines = {}

                table.insert(descLines, string.format(locale('phase_label') or "Phase: %s", elec.phase_label or elec.phase or locale('unknown') or 'unknown'))

                if elec.total_votes and elec.total_votes > 0 then
                    table.insert(descLines, string.format(locale('total_votes') or "Total votes: %d", elec.total_votes))
                else
                    table.insert(descLines, locale('total_votes_zero') or "Total votes: 0")
                end

                if elec.reg_start then
                    table.insert(descLines, locale('reg_start') .. ": " .. tostring(elec.reg_start))
                end
                if elec.vote_start then
                    table.insert(descLines, locale('vote_start') .. ": " .. tostring(elec.vote_start))
                end
                if elec.vote_end then
                    table.insert(descLines, locale('vote_end') .. ": " .. tostring(elec.vote_end))
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
            title   = locale('election_admin_menu') or 'Election Admin Menu',
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
            local msg = (response and response.error) or locale('election_not_found') or 'Election not found.'
            lib.notify({
                title       = locale('elections') or 'Elections',
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
            title       = string.format(locale('phase_label') or "Phase: %s", elec.phase_label or elec.phase or locale('unknown') or 'unknown'),
            description = string.format(
                locale('region_label') .. ": %s\n" .. locale('reg_start') .. ": %s\n" .. locale('vote_start') .. ": %s\n" .. locale('vote_end') .. ": %s",
                string.upper(elec.region_alias or locale('unknown') or 'UNKNOWN'),
                elec.reg_start or locale('not_available') or 'N/A',
                elec.vote_start or locale('not_available') or 'N/A',
                elec.vote_end or locale('not_available') or 'N/A'
            ),
            disabled    = true,
        }

        if #tally == 0 then
            options[#options+1] = {
                title    = locale('no_candidates_votes') or "No candidates / votes yet.",
                disabled = true
            }
        else
            for _, row in ipairs(tally) do
                options[#options+1] = {
                title       = string.format( locale('candidate_votes') or "%s — %d votes", row.character_name or (locale('candidate') .. ' #' .. row.candidate_id), row.votes or 0),
                description = (locale('citizen_id') or "CitizenID: %s"):format(row.citizenid or locale('unknown') or 'unknown'),
                    disabled    = true,
                }
            end
        end

        local id = elec.id

        -- Phase change options
        options[#options+1] = {
            title = locale('set_phase_registration') or "Set phase: Registration",
            event = 'rsg-election:client:AdminSetPhase',
            args  = { id = id, phase = 'registration' },
        }
        options[#options+1] = {
            title = locale('set_phase_campaign') or "Set phase: Campaign",
            event = 'rsg-election:client:AdminSetPhase',
            args  = { id = id, phase = 'campaign' },
        }
        options[#options+1] = {
            title = locale('set_phase_voting') or "Set phase: Voting",
            event = 'rsg-election:client:AdminSetPhase',
            args  = { id = id, phase = 'voting' },
        }
        options[#options+1] = {
            title       = locale('set_phase_result') or "Set phase: Result",
            description = locale('set_phase_result_desc') or "Marks election as complete (Result).",
            event       = 'rsg-election:client:AdminSetPhase',
            args        = { id = id, phase = 'complete' },
        }

        if elec.phase == 'complete' and #tally > 0 then
            options[#options+1] = {
                title       = locale('apply_result') or "Apply result (install governor + announce)",
                description = locale('apply_result_desc') or "Requires phase: Result.",
                event       = 'rsg-election:client:AdminApplyResult',
                args        = id,
            }
        end

        lib.registerContext({
            id      = 'rsg-election-admin-detail-' .. id,
            title   = string.format(locale('election_title') or "Election #%d — %s", id, string.upper(elec.region_alias or locale('unknown') or 'UNKNOWN')),
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
        local title = locale(set) or 'Set ' .. (phase:gsub("^%l", string.upper)) .. locale('duration') or ' Duration'

        local input = lib.inputDialog(title, {
            {
                type     = 'number',
                label    = locale('duration_months') or 'Duration (months)',
                default  = 1,
                min      = 1,
                required = true,
            },
            {
                type     = 'select',
                label    = locale('month_type') or 'Month type',
                options  = {
                    { label = locale('in_game_months') or 'In-game months',   value = 'ingame'   },
                    { label = locale('real_time_months') or 'Real-time months', value = 'realtime' },
                },
                default  = 'ingame',
                required = true,
            },
            {
                type     = 'select',
                label    = locale('send_announcement') or 'Send announcement to residents?',
                options  = {
                    { label = locale('yes') or 'Yes', value = 'yes' },
                    { label = locale('no') or 'No',  value = 'no'  },
                },
                default  = locale('yes') or 'yes',
                required = true,
            }
        })

        if not input then return end -- cancelled

        local months    = tonumber(input[1]) or 0
        local monthMode = tostring(input[2] or 'ingame')
        local announce  = tostring(input[3] or 'yes') == 'yes'

        if months <= 0 then
            lib.notify({
                title       = locale('elections') or 'Elections',
                description = locale('months_must_be_greater_than_0') or 'Months must be greater than 0.',
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
        local input = lib.inputDialog(locale('set_result_phase') or 'Set Result Phase', {
            {
                type     = 'select',
                label    = locale('announce_result') or 'Announce result to residents?',
                options  = {
                    { label = locale('yes') or 'Yes', value = 'yes' },
                    { label = locale('no') or 'No',  value = 'no'  },
                },
                default  = 'yes',
                required = true,
            }
        })

        if not input then return end

        local announce = tostring(input[1] or locale('yes') or 'yes') == 'yes'
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
