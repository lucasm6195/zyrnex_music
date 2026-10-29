fx_version 'cerulean'
games { 'gta5' }
lua54 'yes'

name 'zyrnex_music'
author 'Lucas M.'
description 'Car radio, portable boombox and concerts with YouTube or audio links'
version '1.0.0'
repository 'https://github.com/lucasm6195/zyrnex_music'

ui_page 'ui/index.html'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'locales/*.lua',
    'shared/locale.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/main.lua'
}

files {
    'ui/index.html',
    'ui/index.js',
    'ui/style.css',
    'ui/fonts/*.woff2'
}

dependencies {
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'xsound'
}
