-- 开镜时临时关闭 HApex3.0 的物资绘制与实体模型绘制。
-- 使用 game.localplayer.is_zooming 读取玩家侧开镜状态，适配双机环境。
-- 只递归检查 loots 菜单树，不访问任何人物 visual/ESP 菜单。
-- 退出开镜或卸载脚本时恢复相关开关进入开镜前的原始值。

local LOOT_ROOTS = { "loots", "loot", "items" }

local saved_controls = {}
local suppression_active = false
local missing_branch_reported = false

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

local function suppress_targets()
    local visited_paths = {}
    local controls = {}

    for _, root in ipairs(LOOT_ROOTS) do
        if #gui.children(root) > 0 then
            collect_loot_controls(root, visited_paths, controls)
        end
    end

    for _, control in ipairs(controls) do
        saved_controls[control.path] = {
            element = control.element,
            value = control.value,
        }
        if control.value then
            control.element:set(false)
        end
    end

    if #controls == 0 and not missing_branch_reported then
        missing_branch_reported = true
        log.warn("未在 loots 菜单树中找到可关闭的布尔开关")
    end

    suppression_active = true
end

local function enforce_suppression()
    -- 热键可能重新打开开关，因此开镜期间只重压制已找到的绘制控件。
    for _, saved in pairs(saved_controls) do
        if saved.element:get() then
            saved.element:set(false)
        end
    end
end

local function restore_targets()
    if not suppression_active then return end

    for path, saved in pairs(saved_controls) do
        local element = gui.find(path)
        if element ~= nil and element:has_value() then
            element:set(saved.value)
        end
    end

    saved_controls = {}
    suppression_active = false
end

event.on("frame_update", function()
    if game.localplayer.is_zooming then
        if not suppression_active then
            suppress_targets()
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

log.success("ADS loot/model drawing filter registered")
