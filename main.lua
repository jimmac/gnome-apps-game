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

-- canvases
local vcanvas = nil    -- main 128×128 virtual screen
local icon_canvas = nil -- 32×32 icon for shader effects

-- fonts
local font_sm = nil    -- small (counter, nav)
local font_md = nil    -- medium (labels, intro)

-- shaders
local glitch_shader = nil
local transition_shader = nil
local crt_shader = nil

-- sound effects
local sfx_swoosh = nil
local sfx_glitch = nil
local sfx_reveal = nil

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

    -- load shaders
    load_shaders()

    -- load fonts — Departure Mono
    -- size 11 gives cap height = 8px (pixel-clean)
    local fpath = "assets/fonts/DepartureMono.otf"
    font_sm = love.graphics.newFont(fpath, 11)
    font_md = love.graphics.newFont(fpath, 11)
    font_sm:setFilter("nearest", "nearest")
    font_md:setFilter("nearest", "nearest")

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
    if crt_shader then
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
    if current_state and current_state.keypressed then
        current_state:keypressed(key)
    end
end

function love.gamepadpressed(joystick, button)
    if current_state and current_state.gamepadpressed then
        current_state:gamepadpressed(joystick, button)
    end
end

------------------------------------------------------------
-- ICON LOADING
------------------------------------------------------------
function load_icons()
    local dir = "assets/icons"
    local files = love.filesystem.getDirectoryItems(dir)
    table.sort(files)

    for _, file in ipairs(files) do
        if file:match("%.png$") then
            local path = dir .. "/" .. file
            local img = love.graphics.newImage(path)
            local name = file:gsub("%.png$", ""):gsub("[-_.]", " ")
            table.insert(icons, {image = img, label = name})
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
    self.duration = 2.5
end

function states.intro:update(dt)
    self.t = self.t + dt
    if self.t > self.duration then
        set_state("game")
    end
end

function states.intro:draw()
    local alpha = math.min(self.t / 0.8, 1)
    if self.t > self.duration - 0.5 then
        alpha = math.max((self.duration - self.t) / 0.5, 0)
    end

    love.graphics.setFont(font_md)
    love.graphics.setColor(C.dim[1], C.dim[2], C.dim[3], alpha)
    love.graphics.printf("jimmac.eu", 0, VH/2 - 6, VW, "center")
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

-- icon is 32×32, drawn at 1:1 on the 128×128 canvas
local ICON_X = (VW - 32) / 2   -- 48
local ICON_Y = (VH - 32) / 2 - 8  -- centered, nudged up for label

function states.game:enter()
    self.index = 1
    self.revealed = false
    self.input_delay = 0
    self.repeat_rate = 0.15

    -- transition
    self.trans = {active = false, timer = 0, duration = 0.5, seed = 0}

    -- glitch
    self.glitch = {
        active = false, timer = 0, duration = 0,
        next_trigger = 3 + math.random() * 7,
        elapsed = 0,
    }
end

function states.game:update(dt)
    self.input_delay = math.max(self.input_delay - dt, 0)

    -- keyboard
    if self.input_delay <= 0 then
        if love.keyboard.isDown("right") then
            self:go(1)
        elseif love.keyboard.isDown("left") then
            self:go(-1)
        end
    end

    -- gamepad
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
end

function states.game:go(dir)
    local ni = self.index + dir
    if ni < 1 then ni = icon_count end
    if ni > icon_count then ni = 1 end
    self.index = ni
    self.revealed = false
    self.input_delay = self.repeat_rate
    self.trans.active = true
    self.trans.timer = self.trans.duration
    self.trans.seed = math.random() * 1000
    sfx_swoosh:stop()
    sfx_swoosh:play()
end

function states.game:jump_random()
    self.index = math.random(1, icon_count)
    self.revealed = false
    self.trans.active = true
    self.trans.timer = self.trans.duration
    self.trans.seed = math.random() * 1000
    sfx_swoosh:stop()
    sfx_swoosh:play()
end

function states.game:keypressed(key)
    if key == "x" or key == "return" then
        self.revealed = true
        sfx_reveal:stop()
        sfx_reveal:play()
    elseif key == "z" or key == "space" then
        self:jump_random()
    end
end

function states.game:gamepadpressed(joystick, button)
    if button == "a" then
        self.revealed = true
        sfx_reveal:stop()
        sfx_reveal:play()
    elseif button == "b" then
        self:jump_random()
    end
end

function states.game:draw()
    if icon_count == 0 then
        love.graphics.setColor(C.fg)
        love.graphics.setFont(font_sm)
        love.graphics.printf("no icons found", 0, VH/2, VW, "center")
        return
    end

    local icon = icons[self.index]

    -- draw icon to 32×32 canvas
    love.graphics.setCanvas(icon_canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(icon.image, 0, 0)
    love.graphics.setCanvas(vcanvas)  -- back to virtual canvas

    -- draw icon with shader effects at 1:1 on the 128×128 canvas
    love.graphics.setColor(1, 1, 1)
    if self.trans.active and transition_shader then
        local p = 1 - self.trans.timer / self.trans.duration
        transition_shader:send("time", p)
        transition_shader:send("seed", self.trans.seed)
        love.graphics.setShader(transition_shader)
        love.graphics.draw(icon_canvas, ICON_X, ICON_Y)
        love.graphics.setShader()
    elseif self.glitch.active and glitch_shader then
        local intensity = math.min(self.glitch.timer / self.glitch.duration, 1)
        glitch_shader:send("time", love.timer.getTime())
        glitch_shader:send("intensity", intensity)
        love.graphics.setShader(glitch_shader)
        love.graphics.draw(icon_canvas, ICON_X, ICON_Y)
        love.graphics.setShader()
    else
        love.graphics.draw(icon_canvas, ICON_X, ICON_Y)
    end

    -- counter
    love.graphics.setFont(font_sm)
    love.graphics.setColor(C.dim)
    love.graphics.printf(self.index .. "/" .. icon_count, 0, 3, VW, "center")

    -- label
    if self.revealed then
        love.graphics.setFont(font_md)
        love.graphics.setColor(C.fg)
        love.graphics.printf(icon.label, 0, ICON_Y + 37, VW, "center")
    end

    -- nav hints
    love.graphics.setFont(font_md)
    love.graphics.setColor(C.dim[1], C.dim[2], C.dim[3], 0.3)
    love.graphics.print("<", 4, VH/2 - 6)
    love.graphics.print(">", VW - 12, VH/2 - 6)
end
