-- GNOME Apps Icon Quiz
-- (CC BY-SA 4.0) jimmac.eu

-- Virtual resolution & scaling
local VW, VH = 128, 128        -- virtual canvas
local SCALE = 5                 -- 128×5 = 640
local SW, SH = 720, 720        -- screen/window
local OX = (SW - VW * SCALE) / 2  -- 40px offset to center
local OY = (SH - VH * SCALE) / 2

-- GNOME HIG colors
local C = {
    bg       = {0x1e/255, 0x1e/255, 0x1e/255},
    fg       = {1, 1, 1},
    dim      = {0.6, 0.6, 0.6},
    accent   = {0x35/255, 0x84/255, 0xe4/255},
}

-- bitmap font system
function load_bfont(path, variant)
    local f = {}
    f.image = love.graphics.newImage(path)
    f.image:setFilter("nearest", "nearest")
    f.height = 5
    f.spacing = 1  -- 1px between characters
    f.glyphs = {}

    local g = f.glyphs

    if variant == "wide" then
        -- Wide font glyph map
        g["A"]={1,1,4}  g["B"]={6,1,4}  g["C"]={11,1,4} g["D"]={16,1,4}
        g["E"]={21,1,4} g["F"]={26,1,4}
        g["G"]={1,7,4}  g["H"]={6,7,4}  g["I"]={11,7,1} g["J"]={13,7,4}
        g["K"]={18,7,4} g["L"]={23,7,4}
        g["M"]={1,13,5} g["N"]={7,13,4} g["O"]={12,13,4} g["P"]={17,13,4}
        g["Q"]={22,13,4} g["R"]={27,13,4}
        g["S"]={1,19,4} g["T"]={6,19,5} g["U"]={12,19,4} g["V"]={17,19,4}
        g["W"]={22,19,7}
        g["X"]={1,25,4} g["Y"]={6,25,4} g["Z"]={11,25,4}
        g["0"]={1,31,4} g["1"]={6,31,2} g["2"]={9,31,4} g["3"]={14,31,4}
        g["4"]={19,31,4} g["5"]={24,31,4}
        g["6"]={1,37,4} g["7"]={6,37,4} g["8"]={11,37,4} g["9"]={16,37,4}
        g[":"]={2,43,1} g["."]={4,43,1} g[","]={6,43,2}
        g["/"]={10,43,1} g["!"]={12,43,1}
        g["<"]={14,43,4} g[">"]={19,43,3} g["?"]={23,43,3}
        g[" "]={0,0,3}   -- wider space for wide font
        g["-"]={0,0,4, synthetic="dash"}
    else
        -- Narrow font glyph map
        g["A"]={1,1,3}  g["B"]={5,1,3}  g["C"]={9,1,3}  g["D"]={13,1,3}
        g["E"]={17,1,3} g["F"]={21,1,3} g["G"]={25,1,3}
        g["H"]={1,7,3}  g["I"]={5,7,1}  g["J"]={7,7,2}  g["K"]={10,7,3}
        g["L"]={14,7,3} g["M"]={18,7,5} g["N"]={24,7,4}
        g["O"]={1,13,3} g["P"]={5,13,3} g["Q"]={9,13,3} g["R"]={13,13,3}
        g["S"]={17,13,3} g["T"]={21,13,3} g["U"]={25,13,3}
        g["V"]={1,19,3} g["W"]={5,19,5} g["X"]={11,19,3}
        g["Y"]={15,19,3} g["Z"]={19,19,3}
        g["0"]={1,25,3} g["1"]={5,25,2} g["2"]={8,25,3} g["3"]={12,25,3}
        g["4"]={16,25,3} g["5"]={20,25,3} g["6"]={24,25,3}
        g["7"]={1,31,3} g["8"]={5,31,3} g["9"]={9,31,3}
        g[":"]={2,37,1} g["."]={4,37,1} g[","]={6,37,2}
        g["/"]={10,37,1} g["?"]={14,37,3}
        g["<"]={18,37,3} g[">"]={22,37,3}
        -- Button glyphs (narrow font only)
        g["\1"]={1,45,5}  g["\2"]={7,45,5}  g["\3"]={13,45,5}
        g["\4"]={19,45,5} g["\5"]={25,45,5}
        g["\6"]={1,51,5}
        g[" "]={0,0,2}
        g["-"]={0,0,3, synthetic="dash"}
    end

    -- build quads
    local iw, ih = f.image:getDimensions()
    for ch, d in pairs(g) do
        if ch ~= " " and not d.synthetic then
            d.quad = love.graphics.newQuad(d[1], d[2], d[3], 5, iw, ih)
        end
    end

    return f
end

-- measure text width in pixels
function bfont_width(font, text)
    text = string.upper(text)
    local w = 0
    for i = 1, #text do
        local ch = text:sub(i, i)
        local g = font.glyphs[ch]
        if g then
            w = w + g[3] + font.spacing
        else
            w = w + 3 + font.spacing  -- fallback width
        end
    end
    return math.max(0, w - font.spacing)  -- no trailing space
end

-- draw text at (x, y)
function bfont_print(font, text, x, y)
    text = string.upper(text)
    local cx = x
    for i = 1, #text do
        local ch = text:sub(i, i)
        local g = font.glyphs[ch]
        if g and g.synthetic == "dash" then
            love.graphics.rectangle("fill", math.floor(cx), math.floor(y) + 2, g[3], 1)
            cx = cx + g[3] + font.spacing
        elseif g and ch ~= " " and g.quad then
            love.graphics.draw(font.image, g.quad, math.floor(cx), math.floor(y))
            cx = cx + g[3] + font.spacing
        elseif g then
            cx = cx + g[3] + font.spacing  -- space
        else
            cx = cx + 3 + font.spacing  -- unknown char
        end
    end
end

-- draw text centered in a width
function bfont_printf(font, text, x, y, w, align)
    local tw = bfont_width(font, text)
    local ox = x
    if align == "center" then
        ox = x + math.floor((w - tw) / 2)
    elseif align == "right" then
        ox = x + w - tw
    end
    bfont_print(font, text, ox, y)
end

-- draw styled text: segments = {{text, {r,g,b,a}}, ...}
-- renders segments in sequence, each with its own color
function bfont_print_styled(font, segments, x, y)
    local cx = x
    for _, seg in ipairs(segments) do
        local text, color = seg[1], seg[2]
        love.graphics.setColor(color)
        bfont_print(font, text, cx, y)
        cx = cx + bfont_width(font, text) + font.spacing
    end
end

-- draw styled text centered
function bfont_printf_styled(font, segments, x, y, w, align)
    -- measure total width
    local tw = 0
    for i, seg in ipairs(segments) do
        tw = tw + bfont_width(font, seg[1])
        if i < #segments then tw = tw + font.spacing end
    end
    local ox = x
    if align == "center" then
        ox = x + math.floor((w - tw) / 2)
    elseif align == "right" then
        ox = x + w - tw
    end
    bfont_print_styled(font, segments, ox, y)
end

-- word-wrap text for bitmap font
function bfont_wrap(font, text, max_width)
    local words = {}
    for w in text:gmatch("%S+") do table.insert(words, w) end
    local lines = {}
    local line = ""
    local line_w = 0
    for _, word in ipairs(words) do
        local word_w = bfont_width(font, word)
        local sep_w = line ~= "" and (font.glyphs[" "] and font.glyphs[" "][3] + font.spacing or 3) or 0
        if line_w + sep_w + word_w <= max_width then
            line = line .. (line ~= "" and " " or "") .. word
            line_w = line_w + sep_w + word_w
        else
            if line ~= "" then table.insert(lines, line) end
            line = word
            line_w = word_w
        end
    end
    if line ~= "" then table.insert(lines, line) end
    return lines
end

-- canvases
local vcanvas = nil    -- main 128×128 virtual screen
local icon_canvas = nil -- 32×32 icon for shader effects

-- bitmap fonts
local bfont = nil      -- narrow 5px bitmap font (descriptions)
local bfont_w = nil    -- wide 5px bitmap font (titles)

-- shaders
local glitch_shader = nil
local transition_shader = nil
local crt_shader = nil
local crt_enabled = true

-- sound effects
local sfx_swoosh = nil
local sfx_glitch = nil
local sfx_reveal = nil
local sfx_bump = nil
local sfx_type = nil

-- state machine
local states = {}
local current_state = nil

function set_state(name, ...)
    current_state = states[name]
    if current_state.enter then
        current_state:enter(...)
    end
end

-- icon data
local icons = {}
local icon_count = 0
local meta = {}  -- appstream metadata

-- intro logo
local logo_top = nil
local logo_bot = nil

function love.load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setBackgroundColor(0, 0, 0)

    -- virtual canvas
    vcanvas = love.graphics.newCanvas(VW, VH)
    vcanvas:setFilter("nearest", "nearest")

    -- icon canvas (32×32 for shader effects)
    icon_canvas = love.graphics.newCanvas(32, 32)
    icon_canvas:setFilter("nearest", "nearest")

    -- load sounds
    sfx_swoosh = love.audio.newSource("assets/sfx/swoosh.wav", "static")
    sfx_swoosh:setVolume(0.5)
    sfx_glitch = love.audio.newSource("assets/sfx/glitch.wav", "static")
    sfx_glitch:setVolume(0.15)
    sfx_reveal = love.audio.newSource("assets/sfx/reveal.wav", "static")
    sfx_reveal:setVolume(0.4)
    sfx_bump = love.audio.newSource("assets/sfx/bump.wav", "static")
    sfx_bump:setVolume(0.6)
    sfx_type = love.audio.newSource("assets/sfx/type_loop.wav", "static")
    sfx_type:setVolume(0.25)
    sfx_type:setLooping(true)

    -- load shaders
    load_shaders()

    -- load bitmap fonts
    bfont = load_bfont("assets/fonts/5allcaps-narrow.png", "narrow")
    bfont_w = load_bfont("assets/fonts/5allcaps.png", "wide")

    -- load logo halves
    local logo_img = love.graphics.newImage("assets/logo.png")
    -- top half: 16×8 from y=0
    logo_top = love.graphics.newQuad(0, 0, 16, 8, 16, 16)
    -- bottom half: 16×8 from y=8
    logo_bot = love.graphics.newQuad(0, 8, 16, 8, 16, 16)
    -- store full image for drawing
    logo_image = logo_img

    -- load icons
    load_icons()

    -- start with intro
    set_state("intro")
end

function love.update(dt)
    if current_state and current_state.update then
        current_state:update(dt)
    end
end

function love.draw()
    -- draw current state to virtual canvas
    love.graphics.setCanvas(vcanvas)
    love.graphics.clear(C.bg[1], C.bg[2], C.bg[3], 1)
    if current_state and current_state.draw then
        current_state:draw()
    end
    love.graphics.setCanvas()

    -- draw virtual canvas scaled up to screen, centered
    love.graphics.setColor(1, 1, 1)
    if crt_enabled and crt_shader then
        crt_shader:send("scale", SCALE * 1.0)
        love.graphics.setShader(crt_shader)
    end
    love.graphics.draw(vcanvas, OX, OY, 0, SCALE, SCALE)
    love.graphics.setShader()
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    end
    if key == "tab" then
        crt_enabled = not crt_enabled
    end
    if current_state and current_state.keypressed then
        current_state:keypressed(key)
    end
end

function love.gamepadpressed(joystick, button)
    if button == "back" then  -- SELECT / SE button
        crt_enabled = not crt_enabled
    end
    if current_state and current_state.gamepadpressed then
        current_state:gamepadpressed(joystick, button)
    end
end

------------------------------------------------------------
-- ICON LOADING
------------------------------------------------------------
function load_icons()
    -- load metadata sidecar
    local ok, m = pcall(love.filesystem.load, "assets/meta.lua")
    if ok and m then
        local ok2, result = pcall(m)
        if ok2 and type(result) == "table" then
            meta = result
        end
    end

    local dir = "assets/icons"
    local files = love.filesystem.getDirectoryItems(dir)
    table.sort(files)

    for _, file in ipairs(files) do
        if file:match("%.png$") then
            local path = dir .. "/" .. file
            local img = love.graphics.newImage(path)
            local key = file:gsub("%.png$", "")
            local m = meta[key]
            local entry = {
                image = img,
                key = key,
                label = key:gsub("[-_.]", " "),
                name = m and m.name or key:gsub("[-_.]", " "),
                author = m and m.author or "",
                desc = m and m.desc or "",
            }
            table.insert(icons, entry)
        end
    end

    icon_count = #icons
end

------------------------------------------------------------
-- SHADERS
------------------------------------------------------------
function load_shaders()
    local ok

    -- ambient glitch (applied to 32×32 icon canvas)
    ok, glitch_shader = pcall(love.graphics.newShader, [[
        extern float time;
        extern float intensity;

        vec4 effect(vec4 color, Image tex, vec2 uv, vec2 px) {
            vec4 orig = Texel(tex, uv);
            if (orig.a < 0.01) return orig;

            float row = floor(uv.y * 32.0);

            // RGB channel split
            float split = intensity * 0.06;
            float r = Texel(tex, uv + vec2(split, 0.0)).r;
            float g = orig.g;
            float b = Texel(tex, uv - vec2(split, 0.0)).b;

            // Scanline displacement
            float wave = sin(row * 0.8 + time * 25.0);
            float displace = step(0.88, abs(wave)) * intensity * 0.05;
            vec2 duv = uv + vec2(displace * sign(wave), 0.0);
            vec4 displaced = Texel(tex, duv);
            float mix_amt = step(0.88, abs(wave)) * intensity;
            r = mix(r, displaced.r, mix_amt);
            g = mix(g, displaced.g, mix_amt);
            b = mix(b, displaced.b, mix_amt);

            // Scanline darkening
            float scanline = 1.0 - intensity * 0.2 * step(0.5, mod(row, 2.0));

            // Color flash
            float flash = step(0.96, sin(time * 13.0)) * intensity * 0.4;
            r += flash * 0.3;
            b += flash * 0.5;

            return vec4(r * scanline, g * scanline, b * scanline, orig.a) * color;
        }
    ]])
    if not ok then
        print("glitch shader failed: " .. tostring(glitch_shader))
        glitch_shader = nil
    end

    -- channel-switch transition (applied to 32×32 icon canvas)
    ok, transition_shader = pcall(love.graphics.newShader, [[
        extern float time;
        extern float seed;

        // GLES-safe hash using smaller constants
        float hash(vec2 p) {
            vec2 k = vec2(23.1406, 2.6651);
            float d = dot(p + seed, k);
            return fract(sin(d) * 437.585);
        }

        vec4 effect(vec4 color, Image tex, vec2 uv, vec2 px) {
            vec4 orig = Texel(tex, uv);
            float row = floor(uv.y * 32.0);

            if (time < 0.4) {
                float p = time / 0.4;
                float strength = 1.0 - p;

                float displace = (hash(vec2(row, seed)) - 0.5) * strength * 0.2;
                vec4 displaced = Texel(tex, vec2(uv.x + displace, uv.y));

                float noise = hash(vec2(px.x, px.y + seed * 7.0));
                float noise_mask = step(0.3, strength) * step(noise, strength * 0.7);
                float flash = step(time, 0.06) * 0.8;

                vec4 result = mix(displaced, vec4(noise, noise, noise, 1.0), noise_mask * displaced.a);
                result = mix(result, vec4(1.0), flash * displaced.a);
                result.a = displaced.a;
                return result * color;

            } else if (time < 0.7) {
                float p = (time - 0.4) / 0.3;
                float strength = 1.0 - p;

                float roll = strength * 0.12;
                vec2 ruv = vec2(uv.x, fract(uv.y + roll));
                vec4 rolled = Texel(tex, ruv);

                float jitter = step(0.8, hash(vec2(row * 0.1, seed + 7.0))) * strength * 0.06;
                vec4 jittered = Texel(tex, ruv + vec2(jitter, 0.0));

                float band_center = hash(vec2(seed, 3.7));
                float in_band = step(abs(uv.y - band_center), strength * 0.1);
                float noise = hash(vec2(px.x * 3.0, px.y + seed * 5.0));

                vec4 result = mix(jittered, vec4(noise * 0.5), in_band * 0.7 * jittered.a);
                result.a = rolled.a;
                return result * color;

            } else {
                float p = (time - 0.7) / 0.3;
                float strength = 1.0 - p;

                float split = strength * 0.025;
                float r = Texel(tex, uv + vec2(split, 0.0)).r;
                float g = orig.g;
                float b = Texel(tex, uv - vec2(split, 0.0)).b;

                float line_mask = step(0.93, hash(vec2(row * 0.3, seed + 3.0))) * strength;
                r = mix(r, 0.1, line_mask * orig.a);
                g = mix(g, 0.1, line_mask * orig.a);
                b = mix(b, 0.1, line_mask * orig.a);

                return vec4(r, g, b, orig.a) * color;
            }
        }
    ]])
    if not ok then
        print("transition shader failed: " .. tostring(transition_shader))
        transition_shader = nil
    end

    -- CRT overlay (applied to final scaled output)
    ok, crt_shader = pcall(love.graphics.newShader, [[
        extern float scale;

        vec4 effect(vec4 color, Image tex, vec2 uv, vec2 px) {
            vec4 orig = Texel(tex, uv) * color;

            // CRT scanlines — hard dark gap between rows
            float row = mod(px.y, scale);
            float scanline = 1.0 - 0.6 * smoothstep(scale * 0.5, scale * 0.75, row);

            // Phosphor bloom — rows glow bright in the center
            float glow = 1.0 + 0.15 * smoothstep(0.0, scale * 0.25, row)
                             * smoothstep(scale * 0.75, scale * 0.35, row);

            // Subtle RGB subpixel separation
            float col = mod(px.x, 3.0);
            float r_mult = 1.0 + 0.06 * step(col, 1.0);
            float g_mult = 1.0 + 0.06 * step(1.0, col) * step(col, 2.0);
            float b_mult = 1.0 + 0.06 * step(2.0, col);

            // Heavy vignette — curved CRT glass
            vec2 center = uv - 0.5;
            float vig = 1.0 - dot(center, center) * 2.0;
            vig = clamp(vig * vig, 0.0, 1.0);

            // Slight barrel curvature tint at edges
            float edge_tint = dot(center, center) * 0.4;

            vec3 c = orig.rgb * scanline * glow;
            c *= vec3(r_mult, g_mult, b_mult);
            c *= vig;
            c -= edge_tint * 0.1;

            return vec4(clamp(c, 0.0, 1.0), orig.a);
        }
    ]])
    if not ok then
        print("crt shader failed: " .. tostring(crt_shader))
        crt_shader = nil
    end
end

------------------------------------------------------------
-- INTRO STATE
------------------------------------------------------------
states.intro = {}

function states.intro:enter()
    self.t = 0
    self.delay = 1.0          -- pause before animation starts
    self.duration = 4.5       -- total time including delay
    self.x_top = -16          -- start off-screen left
    self.x_bot = VW           -- start off-screen right
    self.target_x = (VW - 16) / 2
    self.bumped = false
end

function states.intro:update(dt)
    self.t = self.t + dt
    local at = self.t - self.delay  -- animation time
    if at > 0 then
        -- ease in (faster approach)
        self.x_top = self.x_top - (self.x_top - self.target_x) / 3
        self.x_bot = self.x_bot - (self.x_bot - self.target_x) / 3
        -- snap when close enough
        if math.abs(self.x_top - self.target_x) < 0.5 then
            self.x_top = self.target_x
            self.x_bot = self.target_x
            if not self.bumped then
                self.bumped = true
                sfx_bump:stop()
                sfx_bump:play()
            end
        end
    end
    if self.t > self.duration then
        set_state("game")
    end
end

function states.intro:draw()
    local at = self.t - self.delay
    if at < 0 then return end  -- still in delay

    local logo_y = VH/2 - 16

    -- draw two halves easing in
    love.graphics.setColor(1, 1, 1)
    if at < 0.8 then
        love.graphics.draw(logo_image, logo_top, math.floor(self.x_top), logo_y)
        love.graphics.draw(logo_image, logo_bot, math.floor(self.x_bot), logo_y + 8)
    else
        love.graphics.draw(logo_image, logo_top, math.floor(self.target_x), logo_y)
        love.graphics.draw(logo_image, logo_bot, math.floor(self.target_x), logo_y + 8)
    end

    -- "jimmac.eu" text fades in after logo settles
    if at > 0.8 then
        local alpha = math.min((at - 0.8) / 0.5, 1)
        if self.t > self.duration - 0.5 then
            alpha = math.max((self.duration - self.t) / 0.5, 0)
        end
        love.graphics.setColor(C.dim[1], C.dim[2], C.dim[3], alpha)
        bfont_printf(bfont, "jimmac.eu", 0, logo_y + 20, VW, "center")
    end
end

function states.intro:keypressed(key)
    set_state("game")
end

function states.intro:gamepadpressed(joystick, button)
    set_state("game")
end

------------------------------------------------------------
-- GAME STATE
------------------------------------------------------------
states.game = {}

-- icon layout constants
local ICON_X = (VW - 32) / 2       -- 48, centered
local ICON_Y_CENTER = (VH - 32) / 2 - 4  -- quiz position (centered)
local TEXT_MARGIN = 4
local TEXT_WIDTH = VW - TEXT_MARGIN * 2
local LINE_H = 7                    -- 5px font + 2px gap

-- reveal phases
local PHASE_IDLE = 0     -- icon centered, waiting for guess
local PHASE_SLIDE = 1    -- icon sliding to top
local PHASE_TYPE = 2     -- typewriter name + author
local PHASE_DESC = 3     -- description fades in

function states.game:enter()
    self.index = 1
    self.input_delay = 0
    self.repeat_rate = 0.15

    -- transition (icon change glitch)
    self.trans = {active = false, timer = 0, duration = 0.5, seed = 0}

    -- ambient glitch
    self.glitch = {
        active = false, timer = 0, duration = 0,
        next_trigger = 3 + math.random() * 7,
        elapsed = 0,
    }

    -- reveal animation
    self.reveal = {
        phase = PHASE_IDLE,
        timer = 0,
        icon_y = ICON_Y_CENTER,
        chars_shown = 0,
        type_text = "",       -- full text to type (name + by author)
        title_lines = {},     -- pre-wrapped title lines
        desc_lines = {},      -- word-wrapped description
        desc_alpha = 0,
        last_char_tick = 0,   -- timer for typewriter sound rate-limiting
        icon_y_target = ICON_Y_CENTER,
        text_y = 0,
    }
end

function states.game:update(dt)
    self.input_delay = math.max(self.input_delay - dt, 0)
    local r = self.reveal

    -- keyboard held-nav
    if self.input_delay <= 0 then
        if love.keyboard.isDown("right") then
            self:go(1)
        elseif love.keyboard.isDown("left") then
            self:go(-1)
        end
    end

    -- gamepad held-nav
    if self.input_delay <= 0 then
        for _, js in ipairs(love.joystick.getJoysticks()) do
            if js:isGamepad() then
                if js:isGamepadDown("dpright") then
                    self:go(1)
                elseif js:isGamepadDown("dpleft") then
                    self:go(-1)
                end
            end
        end
    end

    -- transition
    if self.trans.active then
        self.trans.timer = self.trans.timer - dt
        if self.trans.timer <= 0 then
            self.trans.active = false
        end
    end

    -- glitch timing
    self.glitch.elapsed = self.glitch.elapsed + dt
    if self.glitch.active then
        self.glitch.timer = self.glitch.timer - dt
        if self.glitch.timer <= 0 then
            self.glitch.active = false
            self.glitch.next_trigger = self.glitch.elapsed + 3 + math.random() * 7
        end
    else
        if self.glitch.elapsed >= self.glitch.next_trigger then
            self.glitch.active = true
            self.glitch.duration = 0.4 + math.random() * 0.6
            self.glitch.timer = self.glitch.duration
            sfx_glitch:stop()
            sfx_glitch:play()
        end
    end

    -- reveal animation phases
    if r.phase == PHASE_SLIDE then
        r.timer = r.timer + dt
        -- ease icon to calculated position
        r.icon_y = r.icon_y - (r.icon_y - r.icon_y_target) / 4
        if math.abs(r.icon_y - r.icon_y_target) < 0.5 then
            r.icon_y = r.icon_y_target
            r.phase = PHASE_TYPE
            r.timer = 0
            r.chars_shown = 0
        end

    elseif r.phase == PHASE_TYPE then
        r.timer = r.timer + dt
        -- ~2 chars per frame at 30fps ≈ 60 chars/sec
        local new_chars = math.floor(r.timer * 50)
        if new_chars > r.chars_shown then
            -- play tick sound (rate-limited)
            -- start type loop if not already playing
            if not sfx_type:isPlaying() then
                sfx_type:play()
            end
            r.chars_shown = new_chars
        end
        if r.chars_shown >= #r.type_text then
            r.chars_shown = #r.type_text
            r.phase = PHASE_DESC
            r.timer = 0
            r.desc_alpha = 0
            sfx_type:stop()
        end

    elseif r.phase == PHASE_DESC then
        r.timer = r.timer + dt
        r.desc_alpha = math.min(r.timer / 0.4, 1)  -- fade in over 0.4s
    end
end

function states.game:go(dir)
    local ni = self.index + dir
    if ni < 1 then ni = icon_count end
    if ni > icon_count then ni = 1 end
    self.index = ni
    self.input_delay = self.repeat_rate
    self.trans.active = true
    self.trans.timer = self.trans.duration
    self.trans.seed = math.random() * 1000
    sfx_swoosh:stop()
    sfx_swoosh:play()
    -- reset reveal
    self.reveal.phase = PHASE_IDLE
    self.reveal.icon_y = ICON_Y_CENTER
    self.reveal.chars_shown = 0
    self.reveal.desc_alpha = 0
    sfx_type:stop()
end

function states.game:jump_random()
    self.index = math.random(1, icon_count)
    self.trans.active = true
    self.trans.timer = self.trans.duration
    self.trans.seed = math.random() * 1000
    sfx_swoosh:stop()
    sfx_swoosh:play()
    -- reset reveal
    self.reveal.phase = PHASE_IDLE
    self.reveal.icon_y = ICON_Y_CENTER
    self.reveal.chars_shown = 0
    sfx_type:stop()
    self.reveal.desc_alpha = 0
end

function states.game:start_reveal()
    if self.reveal.phase ~= PHASE_IDLE then return end
    local icon = icons[self.index]
    local r = self.reveal
    r.phase = PHASE_SLIDE
    r.timer = 0
    -- store name and author separately for coloring
    r.name_text = icon.name
    r.author_text = icon.author ~= "" and ("by " .. icon.author) or ""
    -- full type text for typewriter char counting
    r.type_text = r.name_text
    if r.author_text ~= "" then
        r.type_text = r.type_text .. " " .. r.author_text
    end
    -- pre-wrap full title for layout calculation
    r.title_lines = bfont_wrap(bfont_w, r.type_text, TEXT_WIDTH)
    r.name_len = #r.name_text  -- char index where name ends
    if icon.desc ~= "" then
        r.desc_lines = bfont_wrap(bfont, icon.desc, TEXT_WIDTH)
    else
        r.desc_lines = {}
    end
    -- calculate target icon Y based on content height
    local title_h = #r.title_lines * LINE_H
    local desc_h = #r.desc_lines > 0 and (#r.desc_lines * LINE_H + 3) or 0
    local total_content = 32 + 4 + title_h + desc_h  -- icon + gap + title + desc
    r.icon_y_target = math.max(3, math.floor((VH - total_content) / 2))
    r.text_y = r.icon_y_target + 32 + 4
    sfx_reveal:stop()
    sfx_reveal:play()
end

function states.game:keypressed(key)
    if key == "x" or key == "return" then
        self:start_reveal()
    elseif key == "z" or key == "space" then
        self:jump_random()
    end
end

function states.game:gamepadpressed(joystick, button)
    if button == "a" then
        self:start_reveal()
    elseif button == "b" then
        self:jump_random()
    end
end

function states.game:draw()
    if icon_count == 0 then
        love.graphics.setColor(C.fg)
        bfont_printf(bfont, "no icons found", 0, VH/2, VW, "center")
        return
    end

    local icon = icons[self.index]
    local r = self.reveal
    local icon_y = math.floor(r.icon_y)

    -- draw icon to 32×32 canvas
    love.graphics.setCanvas(icon_canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(icon.image, 0, 0)
    love.graphics.setCanvas(vcanvas)

    -- draw icon with shader effects
    love.graphics.setColor(1, 1, 1)
    if self.trans.active and transition_shader then
        local p = 1 - self.trans.timer / self.trans.duration
        transition_shader:send("time", p)
        transition_shader:send("seed", self.trans.seed)
        love.graphics.setShader(transition_shader)
        love.graphics.draw(icon_canvas, ICON_X, icon_y)
        love.graphics.setShader()
    elseif self.glitch.active and glitch_shader then
        local intensity = math.min(self.glitch.timer / self.glitch.duration, 1)
        glitch_shader:send("time", love.timer.getTime())
        glitch_shader:send("intensity", intensity)
        love.graphics.setShader(glitch_shader)
        love.graphics.draw(icon_canvas, ICON_X, icon_y)
        love.graphics.setShader()
    else
        love.graphics.draw(icon_canvas, ICON_X, icon_y)
    end

    -- counter (always at top)
    love.graphics.setColor(C.dim)
    bfont_printf(bfont, self.index .. "/" .. icon_count, 0, VH - 8, VW, "center")

    -- reveal text
    if r.phase >= PHASE_TYPE then
        local shown = r.type_text:sub(1, r.chars_shown)
        local name_len = r.name_len

        -- split shown text into name part and author part
        local shown_name = shown:sub(1, math.min(#shown, name_len))
        local shown_author = ""
        if #shown > name_len then
            shown_author = shown:sub(name_len + 1)
        end

        -- word-wrap the shown text to get line breaks
        local shown_lines = bfont_wrap(bfont_w, shown, TEXT_WIDTH)
        local ty = r.text_y

        -- render each line with color split
        local chars_consumed = 0
        for _, line in ipairs(shown_lines) do
            local line_upper = string.upper(line)
            local lw = bfont_width(bfont_w, line)
            local lx = math.floor((VW - lw) / 2)

            -- figure out where in this line the name->author boundary falls
            local line_start = chars_consumed
            local line_end = chars_consumed + #line
            -- account for space between words eaten by wrapping
            chars_consumed = line_end + 1  -- +1 for space between lines

            if line_end <= name_len then
                -- entire line is name
                love.graphics.setColor(C.fg)
                bfont_print(bfont_w, line, lx, ty)
            elseif line_start >= name_len then
                -- entire line is author (trim leading space)
                love.graphics.setColor(C.dim)
                bfont_print(bfont_w, line, lx, ty)
            else
                -- split within this line
                local split = name_len - line_start
                local name_part = line:sub(1, split)
                local author_part = line:sub(split + 1)
                love.graphics.setColor(C.fg)
                bfont_print(bfont_w, name_part, lx, ty)
                local nx = lx + bfont_width(bfont_w, name_part) + bfont_w.spacing
                love.graphics.setColor(C.dim)
                bfont_print(bfont_w, author_part, nx, ty)
            end
            ty = ty + LINE_H
        end
        -- use full title height for desc positioning
        local full_ty = r.text_y + #r.title_lines * LINE_H

        -- description (narrow font, centered, even dimmer)
        if r.phase >= PHASE_DESC and #r.desc_lines > 0 then
            local dy = full_ty + 3
            local desc_dim = 0.4 * r.desc_alpha
            love.graphics.setColor(desc_dim, desc_dim, desc_dim, r.desc_alpha)
            for _, line in ipairs(r.desc_lines) do
                bfont_printf(bfont, line, 0, dy, VW, "center")
                dy = dy + LINE_H
            end
        end
    end

    -- nav hints (only when not revealed)
    if r.phase == PHASE_IDLE then
        love.graphics.setColor(C.dim[1], C.dim[2], C.dim[3], 0.3)
        bfont_print(bfont, "<", 4, VH/2 - 3)
        bfont_print(bfont, ">", VW - 7, VH/2 - 3)
    end
end
