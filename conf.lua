function love.conf(t)
    t.title = "Flathub Arcade"
    t.version = "11.5"
    -- Use 0×0 + desktop fullscreen so the game fills whatever screen it runs on.
    -- Scale is computed at runtime in love.load() based on actual display size.
    t.window.width = 0
    t.window.height = 0
    t.window.fullscreen = true
    t.window.fullscreentype = "desktop"  -- keeps native resolution, no mode switch
    t.window.resizable = false
    t.window.vsync = 1

    -- crisp pixel scaling
    t.window.highdpi = false

    t.modules.physics = false
    t.modules.video = false
end
