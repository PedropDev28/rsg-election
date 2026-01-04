fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

author 'fr0st'
description 'Regional elections for governors'
version '1.5.0'

lua54 'yes'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
    --'shared/sh_election.lua',
}

files {
    'locales/*.json',
    'html/index.html',
    'html/style.css',
    'html/script.js',
    'html/fonts/*.woff',
    'html/fonts/*.woff2',
    'html/assets/*.png',
    'html/assets/*.jpg',
    'html/assets/*.webp',
    'html/assets/*.ttf'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/sv_helpers.lua',     -- defines RSGElection + helpers first
    'server/sv_elections.lua',
    'server/sv_candidates.lua',
    'server/sv_votes.lua',
    'server/sv_results.lua',
    'server/sv_exports.lua',
    'server/sv_main.lua'        -- registers commands/events last
}

client_scripts {
    --'client/cl_main.lua',
    --'client/cl_ui.lua',
    'client/cl_admin.lua',
    'client/cl_candidacy.lua',
    'client/cl_election.lua',
    'client/cl_world.lua'
}

ui_page 'html/index.html'
