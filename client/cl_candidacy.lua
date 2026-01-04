lib.locale()

RegisterNetEvent("rsg-election:client:openCandidacyForm", function()
    local input = lib.inputDialog(locale('apply_as_candidate') or "Apply as Candidate", {
        { type = 'input',  label = locale('ballot_name') or 'Ballot Name',  required = true },
        { type = 'textarea', label = locale('biography') or 'Biography', required = true },
        { type = 'input',  label = locale('portrait_path_optional') or 'Portrait Path (optional)', default = '' }
    })

    if not input then return end

    TriggerServerEvent("rsg-election:candidacy:submit", {
        name     = input[1],
        bio      = input[2],
        portrait = input[3] ~= '' and input[3] or nil
    })
end)

-- Governor / Admin: review menu
RegisterNetEvent("rsg-election:openCandidacyMenu", function(opts)
    lib.registerContext({
        id = 'election_candidacies',
        title = locale('candidate_applications') or 'Candidate Applications',
        options = opts
    })
    lib.showContext('election_candidacies')
end)

-- Show details of a single application
RegisterNetEvent("rsg-election:showCandidacyDetail", function(app)
    lib.registerContext({
        id = 'election_candidacy_detail',
        title = (locale('candidacy_title') or "Candidacy #%d — %s"):format(app.id, app.character_name),
        options = {
            { title = locale('name') or "Name",   description = app.character_name, disabled = true },
            { title = locale('region') or "Region", description = app.region_alias,   disabled = true },
            { title = locale('bio') or "Bio",    description = app.bio or "",      disabled = true },

            {
                title = locale('approve_candidate') or "Approve Candidate",
                description = locale('approve_candidate_desc') or "Approve this candidate for the ballot.",
                icon = "check",
                event = "rsg-election:approveCandidacy",
                args = app.id
            },
            {
                title = locale('reject_candidate') or "Reject Candidate",
                description = locale('reject_candidate_desc') or "Reject this candidacy.",
                icon = "x",
                event = "rsg-election:rejectCandidacy",
                args = app.id
            }
        }
    })
    lib.showContext('election_candidacy_detail')
end)

-- open detail from menu
RegisterNetEvent("rsg-election:reviewAppOpen", function(appId)
    TriggerServerEvent("rsg-election:reviewAppOpen", appId)
end)

-- forward approve from client → server
RegisterNetEvent("rsg-election:approveCandidacy", function(appId)
    TriggerServerEvent("rsg-election:approveCandidacy", appId)
end)

-- forward reject from client → server
RegisterNetEvent("rsg-election:rejectCandidacy", function(appId)
    TriggerServerEvent("rsg-election:rejectCandidacy", appId)
end)
