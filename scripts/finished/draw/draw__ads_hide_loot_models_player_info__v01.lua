-- Copyright 2026 https://github.com/leejch/
-- Project URL: https://github.com/leejch/hapex3-lua-script-factory/
-- SPDX-License-Identifier: Apache-2.0

-- 开镜时临时关闭 HApex3.0 的物资、实体模型和人物信息绘制。
-- 使用 game.localplayer.is_zooming 读取玩家侧开镜状态，适配双机环境。
-- 人物菜单按 visual/ESP 分支递归匹配，已注册的 esp.elements 则关闭四种人物场景。
-- 退出开镜或卸载脚本时恢复所有匹配项目进入开镜前的原始值。

local LOOT_ROOTS = { "loots", "loot", "items" }

-- 先尝试具体人物分支，再从常见视觉根节点中按 id/label 识别人物分支。
-- 这样不会因为扫描整个 visuals 根节点而顺带关闭无关的准星或界面开关。
local PLAYER_INFO_ROOTS = {
    "players", "player", "player_info", "player_visuals", "player_visual",
    "player_esp", "players_esp", "enemy", "enemies", "opponent", "opponents",
    "characters", "character", "visuals.players", "visuals.player",
    "visuals.player_info", "visuals.player_visuals", "visuals.player_esp",
    "visual.players", "visual.player", "esp.players", "esp.player",
    "visuals", "visual", "esp",
}

local PLAYER_TOKENS = {
    "player", "players", "enemy", "enemies", "opponent", "opponents",
    "character", "characters", "human", "humans", "person", "persons",
    "legend", "squad", "team", "ally", "allies", "player info",
    "player visual", "player esp", "人物", "玩家", "敌人", "敌方", "队友",
    "队伍",
}

local SCENARIOS = {}
if esp ~= nil then
    SCENARIOS = { esp.INV, esp.VIS, esp.DWN, esp.ALLY }
end

local saved_controls = {}
local saved_esp_elements = {}
local suppression_active = false
local missing_loot_reported = false
local missing_player_reported = false

local function contains_player_token(text)
    local normalized = string.lower(tostring(text or ""))
    for _, token in ipairs(PLAYER_TOKENS) do
        if string.find(normalized, token, 1, true) then
            return true
        end
    end
    return false
end

local function collect_loot_controls(parent_path, visited_paths, controls)
    for _, element in ipairs(gui.children(parent_path)) do
        local id = tostring(element:get_id())
        local path = parent_path .. "." .. id
        if not visited_paths[path] then
            visited_paths[path] = true

            if element:has_value() then
                local value = element:get()
                if type(value) == "boolean" then
                    controls[#controls + 1] = {
                        element = element,
                        path = path,
                        value = value,
                    }
                end
            end

            collect_loot_controls(path, visited_paths, controls)
        end
    end
end

local function collect_player_controls(
    parent_path,
    parent_context,
    inherited_player_branch,
    visited_paths,
    controls
)
    for _, element in ipairs(gui.children(parent_path)) do
        local id = tostring(element:get_id())
        local path = parent_path .. "." .. id
        if not visited_paths[path] then
            visited_paths[path] = true

            local label = tostring(element:get_label() or "")
            local context = parent_context .. " " .. id .. " " .. label
            local player_branch = inherited_player_branch or contains_player_token(context)

            if player_branch and element:has_value() then
                local value = element:get()
                if type(value) == "boolean" then
                    controls[#controls + 1] = {
                        element = element,
                        path = path,
                        value = value,
                    }
                end
            end

            collect_player_controls(path, context, player_branch, visited_paths, controls)
        end
    end
end

local function collect_target_controls()
    local loot_controls = {}
    local player_controls = {}
    local loot_visited_paths = {}
    local player_visited_paths = {}

    for _, root in ipairs(LOOT_ROOTS) do
        if #gui.children(root) > 0 then
            collect_loot_controls(root, loot_visited_paths, loot_controls)
        end
    end

    for _, root in ipairs(PLAYER_INFO_ROOTS) do
        if #gui.children(root) > 0 then
            collect_player_controls(
                root,
                root,
                contains_player_token(root),
                player_visited_paths,
                player_controls
            )
        end
    end

    return loot_controls, player_controls
end

local function save_and_disable_controls(controls)
    for _, control in ipairs(controls) do
        if saved_controls[control.path] == nil then
            saved_controls[control.path] = {
                element = control.element,
                value = control.value,
            }
        end

        if control.value then
            control.element:set(false)
        end
    end
end

local function suppress_menu_controls()
    local loot_controls, player_controls = collect_target_controls()
    save_and_disable_controls(loot_controls)
    save_and_disable_controls(player_controls)

    if #loot_controls == 0 and not missing_loot_reported then
        missing_loot_reported = true
        log.warn("未在 loots 菜单树中找到可关闭的布尔开关")
    end

    return #loot_controls, #player_controls
end

local function suppress_esp_elements()
    if esp == nil or esp.elements == nil then return 0 end

    local count = 0
    for id, element in pairs(esp.elements) do
        count = count + 1
        local saved = saved_esp_elements[id]
        if saved == nil then
            saved = { element = element, enabled = {} }
            saved_esp_elements[id] = saved
            for _, scenario in ipairs(SCENARIOS) do
                saved.enabled[scenario] = element:get_enabled(scenario)
            end
        end

        for _, scenario in ipairs(SCENARIOS) do
            if element:get_enabled(scenario) then
                element:set_enabled(false, scenario)
            end
        end
    end

    return count
end

local function begin_suppression()
    saved_controls = {}
    saved_esp_elements = {}

    local _, player_count = suppress_menu_controls()
    local esp_count = suppress_esp_elements()

    if player_count == 0 and esp_count == 0 and not missing_player_reported then
        missing_player_reported = true
        log.warn("未找到人物 visual/ESP 分支或可关闭的人物信息绘制")
    end

    suppression_active = true
end

local function enforce_suppression()
    -- 热键或其他脚本可能重新打开开关，因此开镜期间持续压制已暂存项目。
    for _, saved in pairs(saved_controls) do
        if saved.element:get() then
            saved.element:set(false)
        end
    end

    -- 新增的 ESP 元素也要在开镜期间立即纳入压制，并记录其原始场景状态。
    suppress_esp_elements()
end

local function restore_targets()
    if not suppression_active then return end

    for path, saved in pairs(saved_controls) do
        local element = gui.find(path)
        if element ~= nil and element:has_value() then
            element:set(saved.value)
        end
    end

    if esp ~= nil then
        for id, saved in pairs(saved_esp_elements) do
            local element = saved.element
            if esp.find ~= nil then
                element = esp.find(id)
            end

            if element ~= nil then
                for _, scenario in ipairs(SCENARIOS) do
                    element:set_enabled(saved.enabled[scenario], scenario)
                end
            end
        end
    end

    saved_controls = {}
    saved_esp_elements = {}
    suppression_active = false
end

event.on("frame_update", function()
    if game.localplayer.is_zooming then
        if not suppression_active then
            begin_suppression()
        end
        enforce_suppression()
    else
        restore_targets()
    end
end)

event.on("script_unloaded", function(unload_event)
    if unload_event.script_path ~= _SCRIPT_PATH then return end
    restore_targets()
end)

log.success("ADS loot/model/player-info drawing filter registered")
