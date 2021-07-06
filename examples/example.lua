local emitter = require "emit"
local path = require "helper/path"

local devkitPro = os.getenv("DEVKITPRO")
if not devkitPro then
    error("DEVKITPRO is not set!")
end
devkitPro = path.mwpath(devkitPro)

local devkitARM = os.getenv("DEVKITARM")
if devkitARM then
    devkitARM = path.mwpath(devkitARM)
else
    devkitARM = path.combine(devkitPro, "devkitARM")
end

local ctrupath = os.getenv("CTRULIB")
if ctrupath then
    ctrupath = path.mwpath(ctrupath)
else
    ctrupath = path.combine(devkitPro, "libctru")
end


local emit = emitter.new("../LgyBg/soos/")

--[[
emit.add(
    emit
        .newtarget("${OUTDIR}/LgyBg.elf", emit.targets.LINK)
        .addinput(
            emit.newinfilemap(emit.targets.CL, "**.c", nil, nil, emit.map.combine(
                emit.map.dstchext(".c", ".o"),
                emit.map.dstprefixbuild
            ))
        )
)
]]--

local cfiles = emit.infile("**c")
local ofiles = emit.newfilemap(cfiles, emit.targets.CL, emit.map.combine(
    emit.map.dstchext(".c", ".o"),
    emit.map.dstprefixbuild
))

local elf = emit.newtarget(
    "${OUTDIR}/LgyBg.elf", emit.targets.LINK,
    ofiles)

emit.add(elf)

emit.compiler { CPREFIX = "arm-none-eabi-" }

emit.cflags
{
    ARCH = "-march=armv6k -mtune=mpcore -mfloat-abi=hard",
    
    ALLCCFLAGS = "-g -O2 -Wall -DARM11 -D_3DS -ffast-math -ffunction-sections -fdata-sections -Wno-format",
    LDFLAGS = "-specs=3dsx.specs -g -Wl,--gc-sections"
}

emit.special
{
    LIBS = {"ctru", "m"},
    LIBDIRS = { path.combine(ctrupath, "lib") },
    INCLUDES = { path.combine(ctrupath, "include"), "-${builddir}", "-${SOURCES}" }
}

emit.emit()

