--[[
  ForestDensityToggle.lua  -  in-sim window of XP12 Forest Tweak
  Version 1.6.0 (2026-11-12)   https://github.com/E11i0t09/xp12-forest-tweak
  (c) E11i0t09. Free community project, not for sale. License: CC BY-NC-SA 4.0 with additional permission (free use also for companies and flight schools), see the LICENSE file.

  In-sim control of the forest density on top of the tweak, without touching
  any files: a small window with density steps (1.0x to 2.8x trees) and an overview of the tree
  height set by the tweak, plus keyboard commands.

  How it works
    X-Plane multiplies the maximum density from the .for files by the art control
    "forest/density" (the vegetation slider writes 0.1 ... 1.0 into it).
    The tweak raised the maximum by 1/factor^2 (factor 0.7 -> ~2x trees).
    So:  density = slider value          -> full tweaked density
         density = slider value * f^2    -> about the original density
    Factors and tree heights are read from <X-Plane>\ForestDensityTweak\backup.log,
    the simHeaven hedge setting from hedges.log in the same folder.
    Trees are placed when scenery loads. In the window, pick a step and press
    Apply. With "Reload scenery on apply" ticked, all scenery around you is
    loaded again so the change shows at once (takes a while, like changing
    location). Without it, the new density applies to scenery loaded as you
    fly on. Tree height can't change in the sim.

  Usage
    - Menu: Plugins > Forest Tweak > Show / hide window
      (fallback: Plugins > FlyWithLua > FlyWithLua Macros > Forest Tweak: window)
    - Commands (Settings > Keyboard / Joystick, search "ForestDensity"):
        FlyWithLua/ForestDensity/window     show / hide the window
        FlyWithLua/ForestDensity/toggle     dense <-> original
        FlyWithLua/ForestDensity/dense
        FlyWithLua/ForestDensity/original
    - The chosen step is remembered and set again at the next sim start (no reload). If it is below
      the tool setting, a note is shown on screen and in the window. "Reload scenery" reloads at once.
    - Window position, size and the reload setting are saved in
      ForestDensityToggle.ini next to this script.

  Install: copy this file to  X-Plane 12\Resources\plugins\FlyWithLua\Scripts\
  Requires FlyWithLua NG+ for X-Plane 12 and the tweak applied.
  Note: changing graphics settings resets the value to the slider setting.
]]

-- ---------------------------------------------------------------- settings
local FALLBACK_FACTOR   = 0.7      -- used if backup.log can't be read
local MESSAGE_SECONDS   = 4        -- on-screen info after a change (0 = off)
local PLUGINS_MENU      = true     -- own entry under Plugins (needs LuaJIT ffi)
local RELOAD_COOLDOWN   = 60       -- seconds between two scenery reloads

-- ---------------------------------------------------------------- internals
local REF_NAME = "sim/private/controls/forest/density"
local INI_PATH = SCRIPT_DIRECTORY .. "ForestDensityToggle.ini"
local LOG_PATH = SYSTEM_DIRECTORY .. "ForestDensityTweak" .. DIRECTORY_SEPARATOR .. "backup.log"
local HEDGE_LOG = SYSTEM_DIRECTORY .. "ForestDensityTweak" .. DIRECTORY_SEPARATOR .. "hedges.log"
-- Fixed row of round "x times as many trees as original" steps. Steps above what the tweak tool
-- set in the forest files are greyed out; the highest usable step means the full tweak.
local STEP_VALUES = { 1.0, 1.25, 1.5, 1.8, 2.0, 2.5, 2.8 }
local NSTEPS   = #STEP_VALUES     -- set below: highest usable step (= full tweak)

if XPLMFindDataRef(REF_NAME) == nil then
    logMsg("ForestDensityToggle: dataref " .. REF_NAME .. " not found - script disabled.")
    return
end

-- ---------------------------------------------------------------- read the tweak's backup log
-- info.x / info.h      density and height factor (last entry wins, like the tweak tool)
-- info.hp              height profile: "uniform" or "realistic" (1.4+)
-- info.files           tweaked files, info.meshes = files with scaled 3D models
-- info.typ_o/typ_n     typical min/max height of the main trees (TREE lines), before/after
-- info.max_o/max_n     tallest tree before/after
local function median(t)
    if #t == 0 then return nil end
    table.sort(t)
    local m = math.floor((#t + 1) / 2)
    return (#t % 2 == 1) and t[m] or (t[m] + t[m + 1]) / 2
end

local function tree_heights(arr_text, mins, maxs, only_tree)
    local tallest = 0
    for s in arr_text:gmatch('"(.-)"') do
        local tok = {}
        for w in s:gsub("\\t", " "):gmatch("%S+") do tok[#tok + 1] = w end
        if (tok[1] == "TREE" or (tok[1] == "TREE2" and not only_tree)) and tok[9] then
            local mn, mx = tonumber(tok[8]), tonumber(tok[9])
            if mn and mx then
                mins[#mins + 1], maxs[#maxs + 1] = mn, mx
                if mx > tallest then tallest = mx end
            end
        end
    end
    return tallest
end

local function read_log()
    local info = { x = nil, h = 1, hp = "uniform", files = 0, meshes = 0, heights = 0 }
    local f = io.open(LOG_PATH, "r")
    if not f then return info end
    local omin, omax, nmin, nmax = {}, {}, {}, {}
    local otall, ntall = 0, 0
    for line in f:lines() do
        local lx = line:match('"x"%s*:%s*([%d%.]+)')
        if lx then
            info.x = tonumber(lx)
            info.h = tonumber(line:match('"h"%s*:%s*([%d%.]+)') or "1")
            info.hp = line:match('"hp"%s*:%s*"(%a+)"') or "uniform"
            info.files = info.files + 1
            if line:find('"mb"%s*:%s*true') then info.meshes = info.meshes + 1 end
            local ot = line:match('"ot"%s*:%s*%[(.-)%]')
            local nt = line:match('"nt"%s*:%s*%[(.-)%]')
            if ot and nt then
                info.heights = info.heights + 1
                otall = math.max(otall, tree_heights(ot, omin, omax, true))
                ntall = math.max(ntall, tree_heights(nt, nmin, nmax, true))
            end
        end
    end
    f:close()
    info.typ_o = { median(omin), median(omax) }
    info.typ_n = { median(nmin), median(nmax) }
    info.max_o, info.max_n = otall, ntall
    return info
end

local info = read_log()

-- simHeaven hedges: "enhanced" while hedges.log holds entries (the tool empties it on restore)
local function read_hedges()
    local f = io.open(HEDGE_LOG, "r")
    if not f then return nil end
    local n = 0
    for line in f:lines() do if line:find('"nl"') then n = n + 1 end end
    f:close()
    return n
end
local hedge_files = read_hedges()
-- Knicks: library generated by the tool in Custom Scenery
local knicks_on = false
local knick_map_on = false   -- hedge overlay (official hedge maps, see DATA_LICENSES.txt) in use
local hedge_choice = "Knicks"  -- "Knicks" or "enhanced" (choice of the tool, step 3)
do
    local f = io.open(SYSTEM_DIRECTORY .. "Custom Scenery" .. DIRECTORY_SEPARATOR .. "XP12_ForestTweak_Knicks"
                      .. DIRECTORY_SEPARATOR .. "library.txt", "r")
    if f then
        local txt = f:read("*a") or ""
        knicks_on = txt:find("generated by XP12 Forest Tweak", 1, true) ~= nil
        knick_map_on = knicks_on and txt:find("| map", 1, true) ~= nil
        hedge_choice = txt:match("|%s*choice%s+(%w+)") or "Knicks"
        f:close()
    end
end
local factor, factor_source = info.x, "backup.log"
if not factor or factor <= 0 or factor > 1 then factor, factor_source = FALLBACK_FACTOR, "fallback (no backup.log)" end
local height = info.h or 1
-- switched to original with [5] in the tool: the files are original right now
local switched_off = false
do
    local f = io.open(SYSTEM_DIRECTORY .. "ForestDensityTweak" .. DIRECTORY_SEPARATOR .. "switched_off.json", "r")
    if f then
        f:close()
        switched_off = true
        factor, factor_source, height = 1.0, "switched to original in the tool", 1
        knicks_on, knick_map_on, hedge_files = false, false, 0
    end
end

-- ---------------------------------------------------------------- reset by an update?
-- An X-Plane or Global Forests v2 update puts the original forest files back. Checks up to 150 of the
-- tweaked files (spread over the whole log, first 4 KB each): reset = original SPACING line, not the tweaked one.
local reset_files, reset_checked = 0, 0
local function squeeze(t) return (t:gsub("%s+", " ")) end
if not switched_off then
    local entries = {}
    local f = io.open(LOG_PATH, "r")
    if f then
        for line in f:lines() do
            local fr = line:match('"f"%s*:%s*"(.-)"')
            local n1 = line:match('"n"%s*:%s*%["(.-)"')
            local o1 = line:match('"o"%s*:%s*%["(.-)"')
            if fr and n1 and o1 and n1 ~= o1 then entries[#entries + 1] = { fr, (n1:gsub("\\t", " ")), (o1:gsub("\\t", " ")) } end
        end
        f:close()
    end
    local stride = math.max(1, math.ceil(#entries / 150))
    for i = 1, #entries, stride do
        local e = entries[i]
        local fr = e[1]:gsub("\\\\", "/"):gsub("/", DIRECTORY_SEPARATOR)
        local ff = io.open(SYSTEM_DIRECTORY .. fr, "rb")
        if ff then
            local head = squeeze(ff:read(4096) or "")
            ff:close()
            reset_checked = reset_checked + 1
            if not head:find(squeeze(e[2]), 1, true) and head:find(squeeze(e[3]), 1, true) then reset_files = reset_files + 1 end
        end
    end
end

-- ---------------------------------------------------------------- settings file
local cfg = { auto_reload = false, visible = false, l = nil, t = nil, r = nil, b = nil }

local function load_cfg()
    local f = io.open(INI_PATH, "r")
    if not f then return end
    for line in f:lines() do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
        if k == "auto_reload" or k == "visible" then cfg[k] = (v == "true")
        elseif k == "l" or k == "t" or k == "r" or k == "b" or k == "dense" or k == "step" then cfg[k] = tonumber(v) end
    end
    f:close()
end

local function save_cfg()
    local f = io.open(INI_PATH, "w")
    if not f then return end
    f:write("auto_reload=" .. tostring(cfg.auto_reload) .. "\n")
    f:write("visible=" .. tostring(cfg.visible) .. "\n")
    if cfg.l then f:write(string.format("l=%d\nt=%d\nr=%d\nb=%d\n", cfg.l, cfg.t, cfg.r, cfg.b)) end
    if cfg.dense then f:write(string.format("dense=%.4f\nstep=%d\n", cfg.dense, cfg.step or 4)) end
    f:close()
end

load_cfg()

-- ---------------------------------------------------------------- density logic
local dense_value = get(REF_NAME)
if dense_value == nil or dense_value <= 0 then dense_value = 1.0 end

local function orig_value() return math.max(0.05, dense_value * factor * factor) end
local function max_trees() return 1 / (factor * factor) end
for _, extra in ipairs({ 3.5, 4.0, 5.0, 6.25 }) do              -- only when the tool was set denser than 0.6
    if extra <= max_trees() * 1.08 then STEP_VALUES[#STEP_VALUES + 1] = extra end
end
local NSHOW = #STEP_VALUES
NSTEPS = 1
for i = 1, NSHOW do if STEP_VALUES[i] <= max_trees() * 1.08 then NSTEPS = i end end
-- the highest usable step uses the exact tweak maximum; its label stays the round value
local function ratio_for_step(step)
    if step >= NSTEPS then return max_trees() end
    return STEP_VALUES[step]
end
local function value_for_step(step) return math.min(dense_value, orig_value() * ratio_for_step(step)) end
local function trees_for_step(step) return ratio_for_step(step) end
-- label: how many times as many trees as the original, e.g. "1.5x"; the last step is the full tweak
local function xfac(step)
    local s = string.format("%.2f", STEP_VALUES[step]):gsub("0+$", ""):gsub("%.$", ".0")
    return s .. "x"                       -- round value, e.g. full tweak 2.04 is shown as "2.0x"
end
local function step_label(step)
    if step == 1 then return "Original 1.0x" end
    return xfac(step)
end

local current_step  = NSTEPS               -- step currently set in the sim
-- After "Reload all Lua script files" the sim may still be on a lower step. If the current
-- value matches the step saved last time, keep the saved full-density value instead of
-- taking the lowered value as "full". On a fresh start X-Plane resets it to the slider value.
if cfg.dense and cfg.step and cfg.step >= 1 and cfg.step <= NSTEPS then
    local saved_dense = dense_value
    dense_value = cfg.dense
    if math.abs(value_for_step(cfg.step) - saved_dense) < 0.001 then current_step = cfg.step
    else dense_value = saved_dense end
end
local selected_step = current_step        -- step picked in the window, set with Apply
local last_reload   = -1e9
local msg_text, msg_until = nil, 0

local function show(text)
    logMsg("ForestDensityToggle: " .. text)
    if MESSAGE_SECONDS > 0 then msg_text, msg_until = text, os.time() + MESSAGE_SECONDS end
end

local function reload_scenery()
    -- returns a note for the message; respects the cooldown between two reloads
    local wait = RELOAD_COOLDOWN - (os.time() - last_reload)
    if wait > 0 then
        return string.format(" - no reload (last one %d s ago), applies to newly loaded scenery", RELOAD_COOLDOWN - math.floor(wait))
    end
    last_reload = os.time()
    command_once("sim/operation/reload_scenery")
    return " - reloading scenery"
end

local function apply_step(step)
    -- pick up a slider change made in the graphics settings since the last switch
    local cur = get(REF_NAME)
    if current_step == NSTEPS and cur and cur > 0 and math.abs(cur - dense_value) > 0.001 then dense_value = cur end
    current_step, selected_step = step, step
    local v = value_for_step(step)
    set(REF_NAME, v)
    cfg.dense, cfg.step = dense_value, step; save_cfg()
    local note = " - applies to scenery loaded from now on"
    if cfg.auto_reload then note = reload_scenery() end
    show(string.format("Forests: %s as many trees as original (density %.2f)%s", xfac(step), v, note))
end

-- Fresh sim start: X-Plane has reset the value to the slider setting (= full tweak). Set the step
-- chosen last time again, without a scenery reload: it applies to scenery loaded from now on.
local remembered_step = nil      -- set at start from the last flight (shown in the window and on screen)
local start_msg = nil
if cfg.step and cfg.step >= 1 and cfg.step < NSTEPS and current_step == NSTEPS then
    local keep = cfg.auto_reload
    cfg.auto_reload = false
    apply_step(cfg.step)
    cfg.auto_reload = keep
    save_cfg()
    remembered_step = cfg.step
    start_msg = string.format("Forest Tweak: density %s (remembered from your last flight, full tweak = %s)",
                              xfac(cfg.step), xfac(NSTEPS))
end

if reset_files > 0 then
    start_msg = string.format("Forest Tweak: an update reset the forest files (%d of %d checked) - run Choose settings in the tool, X-Plane closed",
                              reset_files, reset_checked)
    logMsg("ForestDensityToggle: " .. start_msg)
end

function fdt_set_dense()    apply_step(NSTEPS) end
function fdt_set_original() apply_step(1) end
function fdt_toggle()       if current_step == 1 then apply_step(NSTEPS) else apply_step(1) end end

-- ---------------------------------------------------------------- window (layout B)
local C_GREEN_BTN = 0xFF3A7F4F      -- ImGui colours are 0xAABBGGRR
local C_SEL_BTN   = 0xFF91643C      -- picked, not yet applied
local C_OFF_BTN   = 0xFF46403A
local C_GREEN_TXT = 0xFF89D19F
local C_DIM_TXT   = 0xFF8C847E
local C_TXT       = 0xFFE4E4E4
local C_WARN_TXT  = 0xFF41A4D9
local CW          = 420            -- content width: everything lines up on this
local GAP         = 8
local GAP5        = 6
local BTN_W       = math.floor((CW - (NSHOW - 1) * GAP5) / NSHOW)
local RELOAD_W    = 120            -- "Reload scenery" button next to Apply
local LABEL_X     = 118            -- value column
local WIN_W, WIN_H = 448, 340      -- default and minimum window size

local function colored(col, text)
    imgui.PushStyleColor(imgui.constant.Col.Text, col); imgui.TextUnformatted(text); imgui.PopStyleColor()
end

local function kv(label, value, col)
    colored(C_DIM_TXT, label); imgui.SameLine(LABEL_X)
    if col then colored(col, value) else imgui.TextUnformatted(value) end
end

local function range(t) return (t[1] and t[2]) and string.format("%.4g-%.4g m", t[1], t[2]) or "?" end

local wnd = nil

function fdt_build(w, x, y)
    -- 1) density: click picks a step (blue), Apply sets it (green = active in the sim)
    colored(C_DIM_TXT, "Trees compared to original (up to the tweak tool setting)")
    for i = 1, NSHOW do
        if i > 1 then imgui.SameLine(0, GAP5) end
        if i > NSTEPS then
            -- more than the tweak tool set in the files: greyed out
            imgui.PushStyleColor(imgui.constant.Col.Button, C_OFF_BTN)
            imgui.PushStyleColor(imgui.constant.Col.Text, C_DIM_TXT)
            imgui.Button(xfac(i) .. "##fdt" .. i, BTN_W, 40)
            imgui.PopStyleColor(); imgui.PopStyleColor()
        else
            local col = (i == current_step) and C_GREEN_BTN or ((i == selected_step) and C_SEL_BTN or nil)
            if col then imgui.PushStyleColor(imgui.constant.Col.Button, col) end
            if imgui.Button(xfac(i) .. "##fdt" .. i, BTN_W, 40) then selected_step = i end
            if col then imgui.PopStyleColor() end
        end
    end
    if NSTEPS < NSHOW then
        colored(C_DIM_TXT, string.format("Grey: more than the tool setting. For up to %s set tree spacing", xfac(NSHOW)))
        colored(C_DIM_TXT, string.format("%.2f in the tweak tool (X-Plane closed).", 1 / math.sqrt(STEP_VALUES[NSHOW])))
    end
    local pending = (selected_step ~= current_step)
    if not pending then imgui.PushStyleColor(imgui.constant.Col.Button, C_OFF_BTN) end
    if imgui.Button(pending and ("Apply: " .. step_label(selected_step)) or ("Active in sim: " .. step_label(current_step)), CW - RELOAD_W - GAP5, 26) and pending then
        apply_step(selected_step)
        remembered_step = nil
    end
    if not pending then imgui.PopStyleColor() end
    imgui.SameLine(0, GAP5)
    if imgui.Button("Reload scenery", RELOAD_W, 26) then
        show("Forests: " .. xfac(current_step) .. " as many trees as original" .. reload_scenery())
    end
    if remembered_step and remembered_step == current_step then
        colored(C_WARN_TXT, string.format("Set at start from your last flight: %s (full tweak: %s)", xfac(current_step), xfac(NSTEPS)))
    end
    local c, v = imgui.Checkbox("Reload scenery on apply", cfg.auto_reload)
    if c then cfg.auto_reload = v; save_cfg() end
    colored(cfg.auto_reload and C_TXT or C_DIM_TXT, "On:  shows at once, scenery reload takes a while")
    colored(cfg.auto_reload and C_DIM_TXT or C_TXT, "Off: shows on scenery loaded as you fly on")

    -- 2) what the tweak set in the files
    imgui.Separator()
    if switched_off then
        kv("Tool setting", "switched to original - switch back with [5] in the tool", C_WARN_TXT)
    else
        kv("Tool setting", string.format("tree spacing %.2f = max %s trees", factor, xfac(NSTEPS))
            .. (factor_source == "backup.log" and "" or "  (" .. factor_source .. ")"))
        if reset_files > 0 then
            colored(C_WARN_TXT, string.format("An update reset the forest files (%d of %d checked): forests are original again.", reset_files, reset_checked))
            colored(C_WARN_TXT, "Run Choose settings in the tweak tool (X-Plane closed) to tweak them again.")
        end
    end
    if height < 1 then kv("Tree height", string.format("%d %%", math.floor(height * 100 + 0.5)) .. (info.hp == "realistic" and "  (realistic profile)" or ""), C_GREEN_TXT)
    else kv("Tree height", "100 % (original)") end
    if height < 1 and info.heights > 0 then
        kv("Typical tree", range(info.typ_o) .. "  ->  " .. range(info.typ_n))
        kv("Tallest tree", string.format("%.4g m  ->  %.4g m", info.max_o, info.max_n))
        if info.meshes > 0 then kv("3D models", string.format("scaled (%d files)", info.meshes), C_GREEN_TXT)
        else kv("3D models", "not scaled - re-apply with 1.2", C_WARN_TXT) end
        kv("Undergrowth", "scaled along")
    end
    if knicks_on then
        local name = hedge_choice == "enhanced" and "green hedges (4-5 m)" or "green hedges + hedgebanks (Knicks)"
        kv("Hedges", knick_map_on and (name .. " + hedge maps") or name, C_GREEN_TXT)
    elseif hedge_files ~= nil then
        if hedge_files > 0 then kv("Hedges", "green hedges (4-5 m, up to 8 km)", C_GREEN_TXT)
        else kv("Hedges", "default") end
    end
    colored(C_DIM_TXT, "Change with the tweak tool, X-Plane closed.")
end

local function remember_geometry()
    if not wnd then return end
    local ok, l, t, r, b = pcall(float_wnd_get_geometry, wnd)
    if ok and l and r and r > l then cfg.l, cfg.t, cfg.r, cfg.b = l, t, r, b end
end

function fdt_on_close(w)
    remember_geometry()
    wnd = nil
    cfg.visible = false
    save_cfg()
end

local function open_window()
    if wnd then return end
    wnd = float_wnd_create(WIN_W, WIN_H, 1, true)
    float_wnd_set_title(wnd, "Forest Tweak")
    float_wnd_set_imgui_builder(wnd, "fdt_build")
    float_wnd_set_onclose(wnd, "fdt_on_close")
    pcall(float_wnd_set_resizing_limits, wnd, WIN_W, WIN_H, 1200, 900)
    if cfg.l then
        -- saved position; never smaller than the default size (X-Plane: top > bottom)
        local l, t = cfg.l, cfg.t
        local r = math.max(cfg.r, l + WIN_W)
        local b = math.min(cfg.b, t - WIN_H)
        pcall(float_wnd_set_geometry, wnd, l, t, r, b)
    end
    cfg.visible = true
    save_cfg()
end

function fdt_toggle_window()
    if wnd then
        remember_geometry()
        local w = wnd; wnd = nil
        float_wnd_destroy(w)
        cfg.visible = false; save_cfg()
    else open_window() end
end

local last_save = 0
function fdt_often()
    if wnd and os.time() - last_save > 5 then remember_geometry(); save_cfg(); last_save = os.time() end
end
do_often("fdt_often()")

-- ---------------------------------------------------------------- commands, macros, OSD
create_command("FlyWithLua/ForestDensity/window",   "Forest density: show/hide window",        "fdt_toggle_window()", "", "")
create_command("FlyWithLua/ForestDensity/toggle",   "Forest density: toggle dense / original", "fdt_toggle()",        "", "")
create_command("FlyWithLua/ForestDensity/dense",    "Forest density: dense (tweaked)",         "fdt_set_dense()",     "", "")
create_command("FlyWithLua/ForestDensity/original", "Forest density: original",                "fdt_set_original()",  "", "")

add_macro("Forest Tweak: window", "fdt_toggle_window()")   -- fallback if the Plugins menu can't be created

function fdt_draw()
    if start_msg then      -- first frame after loading: the remembered step, so it is noticed
        msg_text, msg_until, start_msg = start_msg, os.time() + 20, nil
    end
    if msg_text and os.time() < msg_until then draw_string(30, SCREEN_HIGHT - 60, msg_text, "white") end
end
do_every_draw("fdt_draw()")

-- ---------------------------------------------------------------- own entry under "Plugins"
-- Uses the X-Plane SDK menu API through LuaJIT's ffi; each item simply runs one of the commands above.
local fdt_menu = nil
local function create_plugins_menu()
    local ok, ffi = pcall(require, "ffi")
    if not ok then return false end
    local decls = {
        "typedef void * XPLMMenuID;", "typedef void * XPLMCommandRef;",
        "XPLMMenuID XPLMFindPluginsMenu(void);",
        "XPLMMenuID XPLMCreateMenu(const char *, XPLMMenuID, int, void *, void *);",
        "int XPLMAppendMenuItem(XPLMMenuID, const char *, void *, int);",
        "int XPLMAppendMenuItemWithCommand(XPLMMenuID, const char *, XPLMCommandRef);",
        "void XPLMDestroyMenu(XPLMMenuID);", "void XPLMRemoveMenuItem(XPLMMenuID, int);",
        "XPLMCommandRef XPLMFindCommand(const char *);",
    }
    for _, d in ipairs(decls) do pcall(ffi.cdef, d) end      -- other scripts may have declared them already
    local libname = "XPLM_64"
    if SYSTEM == "APL" then libname = SYSTEM_DIRECTORY .. "Resources/plugins/XPLM.framework/XPLM"
    elseif SYSTEM == "LIN" then libname = SYSTEM_DIRECTORY .. "Resources/plugins/XPLM_64.so" end
    local okl, xplm = pcall(ffi.load, libname)
    if not okl then return false end
    local plugins = xplm.XPLMFindPluginsMenu()
    local item = xplm.XPLMAppendMenuItem(plugins, "Forest Tweak", nil, 0)
    if item < 0 then return false end
    local menu = xplm.XPLMCreateMenu("Forest Tweak", plugins, item, nil, nil)
    for _, e in ipairs({ { "Show / hide window", "window" }, { "Dense", "dense" },
                         { "Original", "original" }, { "Toggle dense / original", "toggle" } }) do
        xplm.XPLMAppendMenuItemWithCommand(menu, e[1], xplm.XPLMFindCommand("FlyWithLua/ForestDensity/" .. e[2]))
    end
    fdt_menu = { lib = xplm, plugins = plugins, item = item, menu = menu }
    return true
end

function fdt_exit()
    if wnd then remember_geometry(); save_cfg() end
    if fdt_menu then                                        -- remove the menu on script reload / exit
        pcall(fdt_menu.lib.XPLMDestroyMenu, fdt_menu.menu)
        pcall(fdt_menu.lib.XPLMRemoveMenuItem, fdt_menu.plugins, fdt_menu.item)
        fdt_menu = nil
    end
end
do_on_exit("fdt_exit()")

if PLUGINS_MENU then
    local ok, res = pcall(create_plugins_menu)
    if not (ok and res) then logMsg("ForestDensityToggle: Plugins menu not available, use the FlyWithLua macro instead.") end
end

if cfg.visible then open_window() end

logMsg(string.format("ForestDensityToggle 1.6.0: ready (dense %.2f, original %.2f, factor %.2f, height %.2f, %d files, %d with 3D models scaled)",
       dense_value, orig_value(), factor, height, info.files, info.meshes))
