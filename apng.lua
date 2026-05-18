-- APNG parser for LÖVE2D
-- Parses animated PNG files and extracts frames as Love2D Images
-- No external tools or filesystem writes needed

local apng = {}

-- Read a 4-byte big-endian unsigned integer from string at position pos (1-indexed)
local function read_u32(data, pos)
    local b1, b2, b3, b4 = data:byte(pos, pos + 3)
    return b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
end

-- Read a 2-byte big-endian unsigned integer
local function read_u16(data, pos)
    local b1, b2 = data:byte(pos, pos + 1)
    return b1 * 256 + b2
end

-- Write a 4-byte big-endian unsigned integer
local function write_u32(n)
    local b4 = n % 256; n = math.floor(n / 256)
    local b3 = n % 256; n = math.floor(n / 256)
    local b2 = n % 256; n = math.floor(n / 256)
    local b1 = n % 256
    return string.char(b1, b2, b3, b4)
end

-- Build a PNG chunk: length + type + data + CRC
local function make_chunk(ctype, cdata)
    local len = write_u32(#cdata)
    -- CRC covers type + data
    local payload = ctype .. cdata
    -- Use Love2D's data module for CRC32 or compute manually
    local crc = apng._crc32(payload)
    return len .. payload .. write_u32(crc)
end

-- CRC32 lookup table
local crc_table = nil
local function init_crc_table()
    if crc_table then return end
    crc_table = {}
    for i = 0, 255 do
        local c = i
        for _ = 1, 8 do
            if c % 2 == 1 then
                c = bit.bxor(0xEDB88320, bit.rshift(c, 1))
            else
                c = bit.rshift(c, 1)
            end
        end
        crc_table[i] = c
    end
end

function apng._crc32(data)
    init_crc_table()
    local crc = 0xFFFFFFFF
    for i = 1, #data do
        local byte = data:byte(i)
        local idx = bit.band(bit.bxor(crc, byte), 0xFF)
        crc = bit.bxor(crc_table[idx], bit.rshift(crc, 8))
    end
    -- Return as unsigned 32-bit
    return bit.band(bit.bxor(crc, 0xFFFFFFFF), 0xFFFFFFFF)
end

-- Check if Lua has bit operations available
-- LÖVE2D uses LuaJIT which has 'bit' module
local bit_ok = pcall(function() return bit.bxor(1, 2) end)
if not bit_ok then
    -- Fallback: won't work but provides error message
    apng._crc32 = function() error("bit operations not available") end
end

local PNG_SIG = "\137PNG\r\n\26\n"

-- Parse an APNG file and return frame data
-- Returns nil if not an APNG (just a regular PNG)
-- Returns { frames = {Image, ...}, delays = {seconds, ...}, num_plays = int }
function apng.load(path)
    -- Read raw file data as a plain string
    local data, size = love.filesystem.read("string", path)
    if not data then
        return nil, "Cannot read file: " .. path
    end

    -- Verify PNG signature
    if data:sub(1, 8) ~= PNG_SIG then
        return nil, "Not a PNG file"
    end

    -- Quick check: scan for acTL chunk type in first 256 bytes
    -- acTL must appear before IDAT per spec, so it's always early
    if not data:find("acTL", 1, true) then
        return nil  -- Not animated, fast path
    end

    -- Parse all chunks
    local chunks = {}
    local pos = 9
    while pos <= #data - 8 do
        local length = read_u32(data, pos)
        local ctype = data:sub(pos + 4, pos + 7)
        local cdata = data:sub(pos + 8, pos + 7 + length)
        local crc_bytes = data:sub(pos + 8 + length, pos + 11 + length)
        table.insert(chunks, {
            type = ctype,
            data = cdata,
            raw_crc = crc_bytes,
            offset = pos,
        })
        pos = pos + 12 + length
    end

    -- Find acTL (animation control) chunk
    local actl = nil
    for _, c in ipairs(chunks) do
        if c.type == "acTL" then
            actl = c
            break
        end
    end

    if not actl then
        return nil  -- Not animated
    end

    local num_frames = read_u32(actl.data, 1)
    local num_plays = read_u32(actl.data, 5)

    if num_frames <= 1 then
        return nil  -- Single frame, treat as static
    end

    -- Extract IHDR
    local ihdr_chunk = nil
    local other_chunks = {}  -- chunks to include in reconstructed PNGs (sRGB, gAMA, etc.)
    for _, c in ipairs(chunks) do
        if c.type == "IHDR" then
            ihdr_chunk = c
        elseif c.type == "sRGB" or c.type == "gAMA" or c.type == "cHRM"
            or c.type == "iCCP" or c.type == "sBIT" or c.type == "PLTE"
            or c.type == "tRNS" or c.type == "bKGD" or c.type == "pHYs" then
            table.insert(other_chunks, c)
        end
    end

    if not ihdr_chunk then
        return nil, "No IHDR chunk"
    end

    -- Parse frame control and data
    local frames_info = {}
    local current_fctl = nil
    local idat_chunks = {}

    for _, c in ipairs(chunks) do
        if c.type == "fcTL" then
            -- If we have a previous fcTL with data, finalize it
            if current_fctl then
                table.insert(frames_info, current_fctl)
            end
            -- Parse fcTL
            local d = c.data
            local fctl = {
                sequence = read_u32(d, 1),
                width = read_u32(d, 5),
                height = read_u32(d, 9),
                x_offset = read_u32(d, 13),
                y_offset = read_u32(d, 17),
                delay_num = read_u16(d, 21),
                delay_den = read_u16(d, 23),
                dispose_op = d:byte(25),
                blend_op = d:byte(26),
                idat_data = {},  -- collected IDAT/fdAT data for this frame
                is_default = false,
            }
            if fctl.delay_den == 0 then fctl.delay_den = 100 end
            current_fctl = fctl

        elseif c.type == "IDAT" then
            -- IDAT belongs to the default image; if there's a preceding fcTL,
            -- it means frame 0 uses the default image
            table.insert(idat_chunks, c.data)
            if current_fctl and #current_fctl.idat_data == 0 then
                current_fctl.is_default = true
                -- We'll use IDAT data for this frame
                table.insert(current_fctl.idat_data, c.data)
            end

        elseif c.type == "fdAT" then
            if current_fctl then
                -- fdAT data = 4 bytes sequence + actual image data
                local frame_data = c.data:sub(5)  -- skip sequence number
                table.insert(current_fctl.idat_data, frame_data)
            end
        end
    end

    -- Don't forget the last frame
    if current_fctl then
        table.insert(frames_info, current_fctl)
    end

    -- For default-image frames that used IDAT, ensure all IDAT data is collected
    for _, fi in ipairs(frames_info) do
        if fi.is_default then
            fi.idat_data = idat_chunks
        end
    end

    -- Now reconstruct each frame as a standalone PNG in memory
    local result_frames = {}
    local result_delays = {}

    -- Original IHDR data
    local orig_width = read_u32(ihdr_chunk.data, 1)
    local orig_height = read_u32(ihdr_chunk.data, 5)

    for i, fi in ipairs(frames_info) do
        -- Build IHDR with this frame's dimensions
        local frame_ihdr = write_u32(fi.width) .. write_u32(fi.height)
            .. ihdr_chunk.data:sub(9)  -- bit depth, color type, etc.

        -- Assemble PNG
        local png_parts = { PNG_SIG }
        table.insert(png_parts, make_chunk("IHDR", frame_ihdr))

        -- Add color-related chunks
        for _, oc in ipairs(other_chunks) do
            table.insert(png_parts, make_chunk(oc.type, oc.data))
        end

        -- Add IDAT chunks
        for _, idata in ipairs(fi.idat_data) do
            table.insert(png_parts, make_chunk("IDAT", idata))
        end

        -- IEND
        table.insert(png_parts, make_chunk("IEND", ""))

        local png_data = table.concat(png_parts)

        -- Create Love2D image from in-memory PNG
        local ok, img_or_err = pcall(function()
            local fdata = love.filesystem.newFileData(png_data, "frame_" .. i .. ".png")
            local idata = love.image.newImageData(fdata)
            local img = love.graphics.newImage(idata)
            img:setFilter("nearest", "nearest")
            return img
        end)

        if ok then
            table.insert(result_frames, img_or_err)
            table.insert(result_delays, fi.delay_num / fi.delay_den)
        else
            print("APNG: Failed to load frame " .. i .. ": " .. tostring(img_or_err))
            -- Use first successful frame or skip
        end
    end

    if #result_frames == 0 then
        return nil, "No frames could be loaded"
    end

    print("APNG: Loaded " .. #result_frames .. " frames from " .. path
        .. " (delay=" .. string.format("%.3f", result_delays[1]) .. "s)")

    return {
        frames = result_frames,
        delays = result_delays,
        num_plays = num_plays,
        num_frames = #result_frames,
    }
end

-- Animation player object
function apng.newPlayer(anim_data)
    local player = {
        frames = anim_data.frames,
        delays = anim_data.delays,
        num_frames = anim_data.num_frames,
        num_plays = anim_data.num_plays,  -- 0 = infinite
        current_frame = 1,
        elapsed = 0,
        playing = false,
        play_count = 0,
    }

    function player:play()
        self.playing = true
        self.current_frame = 1
        self.elapsed = 0
        self.play_count = 0
    end

    function player:stop()
        self.playing = false
        self.current_frame = 1
        self.elapsed = 0
    end

    function player:update(dt)
        if not self.playing then return end

        self.elapsed = self.elapsed + dt
        local delay = self.delays[self.current_frame]

        while self.elapsed >= delay do
            self.elapsed = self.elapsed - delay
            self.current_frame = self.current_frame + 1

            if self.current_frame > self.num_frames then
                self.play_count = self.play_count + 1
                if self.num_plays > 0 and self.play_count >= self.num_plays then
                    self.playing = false
                    self.current_frame = self.num_frames
                    return
                end
                self.current_frame = 1
            end

            delay = self.delays[self.current_frame]
        end
    end

    function player:getImage()
        return self.frames[self.current_frame]
    end

    return player
end

return apng
