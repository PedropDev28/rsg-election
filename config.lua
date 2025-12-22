Config = Config or {}

-- How long is 1 in-game "month" in real minutes
Config.InGameMonthMinutes = 60   -- example: 1 in-game month = 1 real hour

-- How long is 1 real "month" in real minutes (approx)
Config.RealTimeMonthMinutes = 30 * 24 * 60  -- 30 days

Config.TargetResource = 'ox_target'
-- Candidate registration peds (one per region/office)
-- regionKey is any string you also use when starting elections (e.g. 'new_hanover')
Config.CandidatePeds = {
    new_hanover_hash = {
        regionKey      = '0x41332496',
        coords         = vector3(-263.24, 762.16, 117.15),
        heading        = 287.50,

        -- Use a WORLD ped, not a CS_ ped
        model          = `A_M_M_ValTownfolk_01`,
        outfitPreset   = 0,

        scenario       = 'WORLD_HUMAN_STAND_IMPATIENT',
        targetIcon     = 'fa-solid fa-scale-balanced',
        targetLabel    = 'Register as Candidate',
        targetDistance = 2.0,

        boardCoords    = vector3(-269.44, 764.88, 117.42),
        boardHeading   = -172.18,
    },
}

Config.WinnerDisplayDuration = 72 * 60 * 60  -- seconds (72h)

Config.WinnerPortraits = {
    ['0x41332496'] = 'portrait_new_hanover', -- optional, consumed by your NUI later
}
