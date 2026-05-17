function love.conf(t)
    t.title = "Flathub Arcade"
    t.version = "11.5"
    t.window.width = 720
    t.window.height = 720
    t.window.resizable = false
    t.window.vsync = 1
    t.window.minwidth = 720
    t.window.minheight = 720

    -- crisp pixel scaling
    t.window.highdpi = false

    t.modules.physics = false
    t.modules.video = false
end
