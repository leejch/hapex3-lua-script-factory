-- Copyright 2026 https://github.com/leejch/
-- Project URL: https://github.com/leejch/hapex3-lua-script-factory/
-- SPDX-License-Identifier: Apache-2.0

-- 功能：模拟 HApex3.0 运行时并验证网页雷达成品脚本的核心契约。
-- 范围：覆盖本机监听、广播节流、玩家与毒圈快照、ping/pong 和禁用关闭。
-- 方法：使用最小 mock 注入脚本依赖，不访问真实游戏或网络服务。
-- 目标：在正式联调前捕获 API 调用方式、协议字段和生命周期回归。
-- 运行：npx --yes --package=fengari-node-cli fengari tests/net__web_radar_server__v01_test.lua

local event_handlers = {}
local enabled_control
local interval_control
local encoded_values = {}
local notifications = {}
local logs = {}
local now = 10.0

event = {
    on = function(name, handler)
        event_handlers[name] = handler
    end,
}

local function make_control(default)
    local control = { value = default }

    function control:get()
        return self.value
    end

    function control:set_hint(_)
        return self
    end

    function control:set_format(_)
        return self
    end

    return control
end

local group = {}

function group:checkbox(id, _, default)
    assert(id == "enabled")
    enabled_control = make_control(default)
    return enabled_control
end

function group:slider(id, _, min_value, max_value, default)
    assert(id == "interval")
    assert(min_value == 16 and max_value == 500)
    interval_control = make_control(default)
    return interval_control
end

local tab = {}

function tab:group(id, _, x, y, width, height)
    assert(id == "bridge")
    assert(x == 0 and y == 0 and width == 350 and height == 0)
    return group
end

gui = {
    tab = function(name)
        assert(name == "misc")
        return tab
    end,
    notify = {
        success = function(_, text, duration)
            notifications[#notifications + 1] = { text = text, duration = duration }
        end,
    },
}

log = {
    info = function(message)
        logs[#logs + 1] = message
    end,
    success = function(message)
        logs[#logs + 1] = message
    end,
}

time = {
    now = function()
        return now
    end,
    curtime = function()
        return 25.0
    end,
}

function math.WorldToMapPixel(wx, wy, width, height)
    assert(width == 1000 and height == 1000)
    return wx / 10, wy / 10, true
end

function math.WorldRadiusToMapPixel(radius, size)
    assert(size == 1000)
    return radius / 10, true
end

json = {
    encode = function(value)
        encoded_values[#encoded_values + 1] = value
        if value.kind == "pong" then return "pong-json" end
        return "state-json"
    end,
    decode = function(text)
        if text == "ping-json" then return { kind = "ping" } end
        return nil, "invalid json"
    end,
}

local server = {
    open = true,
    clients = 0,
    broadcasts = {},
    sends = {},
}

function server:is_open()
    return self.open
end

function server:client_count()
    return self.clients
end

function server:send(client, message)
    self.sends[#self.sends + 1] = { client = client, message = message }
    return true
end

function server:broadcast(message)
    self.broadcasts[#self.broadcasts + 1] = message
end

function server:close()
    self.open = false
    self.clients = 0
end

local listen_count = 0
net = { ws_server = {} }

function net.ws_server:listen(port, callbacks)
    assert(port == 9001)
    listen_count = listen_count + 1
    server.open = true
    server.callbacks = callbacks
    return server
end

game = {
    localplayer = {
        index = 1,
        origin = { x = 999, y = 999 },
        camera_origin = { x = 100, y = 200 },
    },
    entities = {
        players = {
            [7] = {
                index = 1,
                name = "Self",
                origin = { x = 999, y = 999 },
                yaw = 45,
                team_num = 1,
                squad_id = 2,
                health = 90,
                shield = 50,
                max_shield = 50,
                platform_uid = "1001",
                is_npc = false,
            },
            [12] = {
                index = 2,
                name = "Enemy",
                origin = { x = 300, y = 400 },
                yaw = 90,
                team_num = 8,
                squad_id = 9,
                health = 75,
                shield = 25,
                max_shield = 100,
                platform_uid = "2002",
                is_npc = false,
            },
            [99] = {
                index = 3,
                name = "Npc",
                origin = { x = 500, y = 600 },
                yaw = 0,
                is_npc = true,
            },
        },
    },
    world = {
        map_name = "mp_rr_test_map",
        ring = {
            is_active = true,
            origin = { x = 500, y = 600 },
            radius_start = 100,
            radius_end = 0,
            time_start = 20,
            time_end = 30,
        },
    },
}

dofile("scripts/finished/net/web_radar.lua")

assert(type(event_handlers.frame_update) == "function")
assert(type(event_handlers.script_unloaded) == "function")
assert(enabled_control.value == true)
assert(interval_control.value == 30)
assert(#logs == 1 and logs[1]:find("Web Radar Server loaded", 1, true))

event_handlers.frame_update({})
assert(listen_count == 1)
assert(#notifications == 1)
assert(#server.broadcasts == 0)

server.clients = 1
event_handlers.frame_update({})
assert(#server.broadcasts == 1 and server.broadcasts[1] == "state-json")

local state = encoded_values[#encoded_values]
assert(state.kind == "state")
assert(state.map == "mp_rr_test_map")
assert(#state.players == 2)

local players_by_id = {}
for _, player in ipairs(state.players) do
    players_by_id[player.id] = player
end

assert(players_by_id.ix1.self == true)
assert(players_by_id.ix1.x == 10 and players_by_id.ix1.y == 20)
assert(players_by_id.ix2.x == 30 and players_by_id.ix2.y == 40)
assert(state.ring.x == 50 and state.ring.y == 60)
assert(state.ring.radius == 5)
assert(state.ring.t_now == 25)

now = 10.01
event_handlers.frame_update({})
assert(#server.broadcasts == 1)

now = 10.031
event_handlers.frame_update({})
assert(#server.broadcasts == 2)

server.callbacks.on_message(42, "invalid-json")
assert(#server.sends == 0)

server.callbacks.on_message(42, "ping-json")
assert(#server.sends == 1)
assert(server.sends[1].client == 42 and server.sends[1].message == "pong-json")

enabled_control.value = false
event_handlers.frame_update({})
assert(server.open == false)

enabled_control.value = true
now = 10.6
event_handlers.frame_update({})
assert(listen_count == 2 and server.open == true)

event_handlers.script_unloaded({})
assert(server.open == false)
