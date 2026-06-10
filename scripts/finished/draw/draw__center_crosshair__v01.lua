-- 在屏幕中央绘制一个固定的红色十字准星。
-- 使用 draw.screen 获取当前渲染分辨率，保证不同窗口尺寸下都居中。
-- 使用 draw.line 绘制水平线和垂直线，并在每个 frame_update 中重新提交。
-- 适合需要轻量、无菜单依赖的中心辅助瞄准标记。

local CROSSHAIR_HALF_LENGTH = 8
local CROSSHAIR_THICKNESS = 2
local CROSSHAIR_COLOR = draw.rgba(1.0, 0.0, 0.0, 1.0)

event.on("frame_update", function(e)
    local screen_w, screen_h = draw.screen()
    local center_x = screen_w / 2
    local center_y = screen_h / 2

    -- draw 列表每帧都会清空，所以必须在渲染事件里逐帧绘制，避免准星闪烁或消失。
    draw.line(
        center_x - CROSSHAIR_HALF_LENGTH,
        center_y,
        center_x + CROSSHAIR_HALF_LENGTH,
        center_y,
        CROSSHAIR_COLOR,
        { thickness = CROSSHAIR_THICKNESS }
    )

    draw.line(
        center_x,
        center_y - CROSSHAIR_HALF_LENGTH,
        center_x,
        center_y + CROSSHAIR_HALF_LENGTH,
        CROSSHAIR_COLOR,
        { thickness = CROSSHAIR_THICKNESS }
    )
end)

log.success("Center crosshair script loaded")
