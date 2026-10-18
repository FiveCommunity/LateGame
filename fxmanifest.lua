server_script '@ElectronAC/src/include/server.lua'
client_script '@ElectronAC/src/include/client.lua'




fx_version "bodacious"

game "gta5"

ui_page "web/dist/index.html"

ui_page_preload "yes"

files {
    "config/client/*.lua",
    "config/config.lua",
    "web/dist/*.*",
    "web/dist/**/*.*",
    "web/images/*.*"
}

dependencies {
    "/onesync",
    "/server:2843"
}

moduledist {
    "lib/xtype.lua",
    "lib/Luaoop.lua",
    "lib/Tools.lua",
    "lib/Proxy.lua",
    "lib/Tunnel.lua",
    "lib/Reseter.lua"
}

transfer {
    "config/server/*.lua"
}

this_is_a_map "yes"

watch_files {
    "_client.lua",
    "_server.lua"
}

client_script "_client.lua"

server_script "_server.lua"



