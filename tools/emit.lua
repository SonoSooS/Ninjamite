local pt = require "helper/path"
local glob = require "helper/glob"
local valueset = require "helper/valueset"

---@alias Emitter table
---@alias Target table<string, string>

---@alias MapperFunc fun(dst: string, src: string): string , string
---@alias MappingTable table<string, string>

---@alias FilterFunc fun(folder: string, filename: string): boolean

---@class MapTarget
---@field __cmd string
---@field __indeps table
---@field __outs string[]
---@field overrides table<string, string> | nil

---@class BuildRule
---@field rule string @ build rule
---@field ins string[] @ input files
---@field outs string[] @ output files
---@field overrides table<string, string> | nil @ optional rule flag overrides

---@class Depo
---@field __flag string
---@field build fun(): MapTarget | MapTarget[]
---@field build_internal fun(): MapTarget | MapTarget[]

---@class DepoArchive : Depo
---@field addinput fun(...): DepoArchive

---@class DepoMapper : Depo
---@field addmap fun(in1: string | table, in2: string | table, in3: table | nil): DepoMapper

---@class CommandTarget
---@field __name string @ name of the target
---@field command string @ command string


--[[
local function rp(tree, depth)
    if not depth then
        depth = 0
    end
    
    local prefix = ("  "):rep(depth) .. "- "
    
    for k,v in pairs(tree) do
        if v then
            print(prefix .. k .. "/")
            rp(v, depth + 1)
        else
            print(prefix .. k)
        end
    end
end

local function rpa(tree, prefix, cb)
    if not prefix then
        prefix = "./"
    end
    
    if not cb then
        cb = print
    end
    
    for k,v in pairs(tree) do
        if v then
            rpa(v, prefix .. k .. "/", cb)
        else
            cb(prefix, k)
        end
    end
end
]]--

---@param pat string
---@return string
local function ninjasan(pat)
    local ret = pat:gsub("([%$%:% ])", "$%1")
    return ret
end

---@param pat string
---@return string
local function ninjasan_novarescape(pat)
    local ret = pat:gsub("([%:% ])", "$%1")
    return ret
end

---@param pat string
---@return string
local function patternsan(pat)
    local ret = pat:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    return ret
end

---@param pat string
---@return string
local function patternsan_sregex(pat)
    local ret = pat:gsub("([%(%)%.%%%+%-%[%]%^%$])", "%%%1")
    return ret
end

---@param val string[] | string
---@param prefix string | nil
---@return string
local function val_expand(val, prefix)
    if type(val) == "table" then
        local ret = {}
        
        if prefix then
            for _,v in ipairs(val) do
                table.insert(ret, prefix .. ninjasan_novarescape(v))
            end
        else
            for _,v in ipairs(val) do
                table.insert(ret, ninjasan_novarescape(v))
            end
        end
        
        return table.concat(ret, " ")
    end
    
    if prefix then
        error("Can't prefix non-array values")
    end
    
    return val
end

---@param tbl table
---@param a table | string
---@param b string | nil
---@overload fun(tbl: table, values: table<string, string>): table
---@overload fun(tbl: table, key: string, value: string): table
---@return table
local function mergetable(tbl, a, b)
    if type(a) == "table" then
        for k,v in pairs(a) do
            tbl[k] = v
        end
    else
        tbl[a] = b
    end
    
    return tbl
end

---@generic TDepo : Depo
---@param depotype string | '"arch"' | '"mapper"'
---@param method string
---@param overrides table | nil
---@return TDepo
local function newdepo(depotype, method, overrides)
    --TODO: support rule method instead of just string
    
    ---@type string
    local buildrule = method
    
    local objtype = depotype
    ---@type table
    local globalopts = overrides or {}
    
    ---@type Depo
    local depo = {}
    depo.__flag = "depo_" .. objtype
    
    local builded = nil
    
    
    function depo.build()
        if not builded then
            builded = depo.build_internal()
        end
        
        return builded
    end
    
    
    if objtype == "arch" then
        
        ---@type string
        local outname = nil
        
        local inputs = {}
        
        ---@param filepath string
        function depo.output(filepath)
            if outname then
                error("Do not call this function directly")
            end
            
            outname = filepath
            
            depo.outfile = filepath
        end
        
        ---@vararg Depo | MapTarget | string | Depo[] | MapTarget[] | string[]
        ---@return DepoArchive
        function depo.addinput(...)
            if builded then
                error("Trying to modify immutable depmapper")
            end
            
            local params = {...}
            
            for _,v in ipairs(params) do
                if type(v) == "table" and not v.__flag and not v.__outs then
                    depo.addinput(unpack(v))
                else
                    table.insert(inputs, v)
                end
            end
            
            return depo
        end
        
        function depo.build_internal()
            if not outname then
                error("Can't build incomplete depmapper")
            end
            
            ---@type MapTarget
            local obj = { __cmd = buildrule, __outs = {outname}, __indeps = inputs, overrides = globalopts}
            
            return obj
        end
        
        ---@type DepoArchive
        return depo
        
    elseif objtype == "mapper" then
        
        ---@type MapTarget[]
        local mapping = {}
        
        ---@param in1 MappingTable | string
        ---@param in2 string | table<string, string> | nil
        ---@param in3 table<string, string> | nil
        ---@overload fun(dst: string, src: string, overrides: table<string, string> | nil) : DepoMapper
        ---@overload fun(mapping: MappingTable, overrides: table<string, string> | nil) : DepoMapper
        ---@return DepoMapper
        function depo.addmap(in1, in2, in3)
            if not in1 then
                return depo
            end
            
            ---@type MappingTable
            local inmap
            ---@type table<string, string> | nil
            local overrides
            
            if type(in1) == "string" then
                inmap = {}
                inmap[in1] = in2
                
                overrides = in3
            else
                inmap = in1
                overrides = in2
            end
            
            ---@type table<string, string>
            local tmpcopy = {}
            
            for k,v in pairs(globalopts) do
                tmpcopy[k] = v
            end
            
            if overrides then
                for k,v in pairs(overrides) do
                   tmpcopy[k] = v
                end
            end
            
            if not next(tmpcopy) then
                tmpcopy = nil
            end
            
            for k,v in pairs(inmap) do
                ---@type MapTarget
                local obj = { __cmd = buildrule, __outs = {k}, __indeps = {v}, overrides = tmpcopy }
                
                mapping[k] = obj
            end
            
            return depo
        end
        
        function depo.build_internal()
            ---@type MapTarget[]
            local res = {}
            
            for _,v in pairs(mapping) do
                table.insert(res, v)
            end
            
            return res
        end
        
        ---@type DepoMapper
        return depo
    end
    
    error("Invalid depmapper type '" .. objtype .. "'")
end

local mappingtools = {}

---@param data MappingTable
---@param mapper MapperFunc
---@return MappingTable
function mappingtools.remap(data, mapper)
    ---@type MappingTable
    local ret = {}
    
    ---@type string
    for k,v in pairs(data) do
        
        k,v = mapper(k,v)
        if k ~= nil then
            ret[k] = v
        end
    end
    
    return ret
end

---@param k string
---@param v string
---@return string, string
function mappingtools.dstprefixbuild(k, v)
    return "${builddir}/" .. k, v
end

---@vararg MapperFunc
---@return MapperFunc
function mappingtools.combine(...)
    local mappers = {}
    
    for _,v in ipairs({...}) do
        table.insert(mappers, v)
    end
    
    return function(data1, data2)
        --print(0, data1, data2)
        for _,v in ipairs(mappers) do
            data1, data2 = v(data1, data2)
            --print(_, data1, data2)
            if data1 == nil then
                return nil
            end
        end
        
        return data1, data2
    end
end

---@param k string
---@param v string
---@return string, string
function mappingtools.srctodstmap(k, v)
    return v, v
end

---@param k string
---@param v string
---@return string, string
function mappingtools.dsttosrcmap(k, v)
    return k, k
end

---@param files MappingTable
---@param mapper MapperFunc
---@return MappingTable
function mappingtools.dstremap(files, mapper)
    ---@type MappingTable
    local res = {}
    
    for k,v in pairs(files) do
        k, v = mapper(k, k)
        if k ~= nil then
            res[k] = v
        end
    end
    
    return res
end

---@param files MappingTable
---@param mapper MapperFunc
---@return MappingTable
function mappingtools.srcremap(files, mapper)
    ---@type MappingTable
    local res = {}
    
    for k,v in pairs(files) do
        k, v = mapper(v, v)
        if k ~= nil then
            res[k] = v
        end
    end
    
    return res
end

---@param oldext string
---@param newext string
---@return MapperFunc
function mappingtools.dstchext(oldext, newext)
    local oldextlen = #oldext
    
    local oldextpattern = patternsan(oldext) .. "$"
    
    return function(fn, fi)
        if #fn < oldextlen then
            return fn .. newext, fi
        end
        
        local matstart = fn:find(oldextpattern)
        if not matstart then
            return fn .. newext, fi
        end
        
        return fn:sub(1, matstart - 1) .. newext, fi
    end
end

---@type Emitter
local api = {}

--- Creates a new emitter
---@param rootarg string @ source root
---@param isempty boolean | nil @ if true, the emitter is created without any targets
---@return Emitter
function api.new(rootarg, isempty)
    if not rootarg then
        error("Parameter #1 must be the source root path")
    end
    
    ---@type table<string, string>
    local config =
    {
        srcroot = pt.abssan(rootarg),
        
        build = "build",
        outdir = "out"
    }
    
    ---@type table<string, CommandTarget>
    local targets = {}
    ---@type table<string, string>
    local pubtargets = {}
    
    ---@type Depo[]
    local outputs = {}
    ---@type table<string, string>
    local envvars = {}
    
    ---@type table<string, string>
    local compilerflags =
    {
        CPREFIX = "",
        CC = "${CPREFIX}gcc",
        CXX = "${CPREFIX}g++",
        OBJCC = "${CPREFIX}gcc",
        LD = "${CPREFIX}gcc",
        AS = "${CPREFIX}as",
        AR = "${CPREFIX}ar",
        OBJCOPY = "${CPREFIX}objcopy",
        STRIP = "${CPREFIX}strip"
    }
    
    ---@type table<string, string>
    local buildflags =
    {
        ARCH = "",
        ALLCCFLAGS = "-g -Og -Wall",
        CFLAGS = "",
        CXXFLAGS = "",
        OBJCFLAGS = "",
        ASFLAGS = ""
    }
    
    ---@type table<string, string[] | string>
    local specialflags =
    {
        LIBS = {},
        LIBDIRS = {},
        INCLUDES = {}
    }
    
    ---@type Emitter
    local emit = {}
    
    emit.map = mappingtools
    emit.targets = pubtargets
    
    --- Resets the emitter to empty
    ---@return Emitter
    function emit.reset()
        config = {}
        
        targets = {}
        pubtargets = {}
        
        outputs = {}
        envvars = {}
        
        compilerflags = {}
        buildflags = {}
        specialflags = {}
        
        return emit
    end
    
    ---@param fndst string
    ---@param fnsrc string
    ---@return string, string
    function emit.srcappendmap(fndst, fnsrc)
        return fndst, pt.combine(config.srcroot, fnsrc)
    end
    
    ---@param fndst string
    ---@param fnsrc string
    ---@return string, string
    function emit.dstappendmap(fndst, fnsrc)
        return pt.combine(config.srcroot, fndst), fnsrc
    end
    
    --- Adds a top-level target to the build tree
    ---@param target Depo
    ---@return Emitter
    function emit.add(target)
        table.insert(outputs, target)
        return target
    end
    
    --- Creates a new top-level build target
    ---@param name string @ output file path
    ---@param method string | Target @ target used to make this output
    ---@return DepoArchive
    function emit.newtarget(name, method, ...)
        ---@type DepoArchive
        local target = newdepo("arch", method)
        
        target.output(name)
        target.addinput(...)
        
        --return emit.add(target)
        return target
    end
    
    --- Creates a new output mappercomment
    ---@param method string | Target @ target used to build the mapped files
    ---@vararg MappingTable @ optional input to already add as target
    ---@return DepoMapper
    function emit.newmapper(method, ...)
        local target = newdepo("mapper", method)
        
        target.addmap(...)
        
        --return emit.add(target)
        return target
    end
    
    ---@return Emitter
    function emit.env(cfg, val)
        mergetable(envvars, cfg, val)
        return emit
     end
    
     ---@return Emitter
    function emit.config(cfg, val)
       mergetable(config, cfg, val)
       return emit
    end
    
    ---@return Emitter
    function emit.compiler(cfg, val)
        mergetable(compilerflags, cfg, val)
        return emit
    end
    
    ---@return Emitter
    function emit.cflags(cfg, val)
        mergetable(buildflags, cfg, val)
        return emit
    end
    
    ---@return Emitter
    function emit.special(cfg, val)
        mergetable(specialflags, cfg, val)
        return emit
    end
    
    --- Adds a new action to transform the inputs into outputs
    ---@param name string @ name of action
    ---@param cmd string | table<string, string> @ command descriptor
    ---@param extras table<string, string> | nil @ extra flags
    ---@overload fun(name: string, cmd: string, extras: table<string, string> | nil)
    ---@overload fun(name: string, data: table<string, string>)
    ---@return CommandTarget
    function emit.addtarget(name, cmd, extras)
        ---@type CommandTarget
        local target = {}
        
        if type(extras) == "table" then
            for k,v in pairs(extras) do
                target[k] = v
            end
        end
        
        if type(cmd) == "table" then
            for k,v in pairs(cmd) do
                target[k] = v
            end
        end
        
        if type(cmd) == "string" then
            target.command = cmd
        end
        
        if not target.command then
            error("Target command not set")
        end
        
        target.__name = name
        targets[name] = target
        pubtargets[name] = name
        
        return target
    end
    
    --[[
    function emit.filelist(...)
        local params = {...}
        
        local res = {}
        
        for k,v in ipairs(params) do
            if type(v) == "string" then
                res[v] = true
            else
                for u,w in pairs(v) do
                    if w == true then
                        res[u] = true
                    else
                        res[w] = true
                    end
                end
            end
        end
        
        return res
    end
    ]]--
    
    --- Creates an unfinished file mapping target
    ---@param pattern string @ path or pattern
    ---@param filter FilterFunc | string | boolean | nil @ pattern or filter function, or nil for no filtering
    ---@param remap MapperFunc | nil @ input-output remapper
    ---@return MappingTable
    function emit.infile(pattern, filter, remap)
        local rootpath = "."
        
        if type(filter) == "string" then
            rootpath = pt.abssan(pattern)
            pattern = pt.join(pattern, filter)
            filter = nil
        elseif type(filter) ~= "function" and filter ~= nil then
            error("Filter is not string, function, or nil")
        else
            --rootpath = pt.abssan(pattern)
            --TODO: handle this better?
            local rootpath = "."
        end
        
        if not pt.isabs(rootpath) then -- confine relative path to src root
            rootpath = pt.absjoin(config.srcroot, rootpath)
        end
        
        if filter == nil and pattern:find("[*?#]") then -- default filtering is path matching
            local newpattern = patternsan_sregex(pt.san(pattern))
            
            ---@type string
            newpattern = newpattern
                :gsub("%*%*+", ".+")
                :gsub("%*$", "[^/]*$")
                :gsub("%*([^$])", "[^/]*%1")
                :gsub("%.%+", ".*")
                :gsub("%?", ".")
                :gsub("%#", "[0-9]")
            
            
            if newpattern:sub(#newpattern, #newpattern) ~= "$" then
                newpattern = newpattern .. "$"
            end
            
            if newpattern:sub(1, 1) ~= "^" then
                newpattern = "^" .. newpattern
            end
            
            print(newpattern)
            
            pattern = newpattern
            filter = true
        end
        
        ---@type MappingTable
        local results = {}
        
        if filter == true then
            local filtpattern = pattern
            
            filter = function(fd, fn)
                local fullpath = pt.combine(fd, fn)
                
                if fullpath:match(filtpattern) then
                    results[fullpath] = pt.combine(rootpath, fullpath)
                end
                
                return false
            end
        end
        
        if not filter then
            filter = function(fd, fn)
                local fullpath = pt.combine(fd, fn)
                results[fullpath] = pt.combine(rootpath, fullpath)
                
                return false
            end
        end
        
        glob.glob(rootpath, filter)
        
        if remap then
            if type(remap) ~= "function" then
                remap = emit.dstappendmap
            end
            
            results = mappingtools.dstremap(results, remap)
        end
        
        return results
    end
    
    --- Creates a new file mapper from a flattened file listing
    ---@param files MappingTable @ file map
    ---@param target string @ target name
    ---@param extra table<string, string> | nil @ extra settings to this target of files
    ---@param mapper MapperFunc | nil @ optional remapper
    ---@overload fun(files: MappingTable, target: string, mapper: MapperFunc | nil): DepoMapper
    ---@overload fun(files: MappingTable, target: string, extra: table<string, string>, mapper: MapperFunc | nil): DepoMapper
    ---@return DepoMapper
    function emit.newfilemap(files, target, extra, mapper)
        if type(extra) == "function" then
            mapper = extra
            extra = nil
        end
        
        if mapper then
            files = mappingtools.remap(files, mapper)
        end
        
        local depmap = emit.newmapper(target, files, extra)
        
        return depmap
    end
    
    --- Creates a file mapping by discovering files from the fileystem and remapping them
    ---@param target string @ target name
    ---@param pattern string
    ---@param filter FilterFunc | string | nil
    ---@param extra table<string, string> | nil
    ---@param mapper MapperFunc | nil
    ---@return MappingTable
    function emit.newinfilemap(target, pattern, filter, extra, mapper)
        local files = emit.infile(pattern, filter, mapper)
        
        return emit.newfilemap(files, target, extra)
    end
    
    ---@param deps ValueSet @ dependency cache
    ---@param outmap BuildRule[] @ output rules
    ---@param input any @ string | Depo | MapTarget
    ---@return ValueSet outfiles
    local function flatten_map(deps, outmap, input, depth)
        local outs = valueset.new()
        
        if depth then
            depth = depth + 1
        else
            depth = 0
        end
        
        local debugprefix = ("  "):rep(depth)
        
        if type(input) == "string" then
            print(debugprefix .. "- string in '" .. input .. "'")
            
            deps[input] = true
            outs[input] = false
            return outs
        end
        
        if input.__flag then
            ---@type Depo
            local indepo = input
            
            print(debugprefix .. "- mapper " .. indepo.__flag)
            
            local results = indepo.build()
            
            if not results.__outs then
                for _,v in ipairs(results) do
                    local outmap = flatten_map(deps, outmap, v, depth)
                    for k,w in -outmap do
                        outs[k] = w
                    end
                end 
                
                return outs
            end
            
            local outmap = flatten_map(deps, outmap, results, depth)
            for k,w in -outmap do
                outs[k] = w
            end
            
            return outs
        end
        
        if input.__outs then
            ---@type MapTarget
            local intarget = input
            
            local debugouts = {}
            
            for _,v in ipairs(intarget.__outs) do
                table.insert(debugouts, v)
            end
            
            print(debugprefix .. "- endpoint cmd = " .. intarget.__cmd .. " | outs = " .. table.concat(debugouts, ", "))
            
            local ins = valueset.new()
            
            ---@type string[]
            local instr = {}
            ---@type string[]
            local outstr = {}
            
            if intarget.__indeps then
                for _,v in ipairs(intarget.__indeps) do
                   local infiles = flatten_map(deps, outmap, v, depth) 
                   for k,w in -infiles do
                       ins[k] = w
                   end
                end
                
                for k in -ins do
                    table.insert(instr, k)
                end
            end
            
            for _,v in ipairs(intarget.__outs) do
                outs[v] = instr
                deps[v] = instr
                table.insert(outstr, v)
            end
            
            ---@type BuildRule
            local outobj =
            {
                rule = intarget.__cmd,
                ins = instr,
                outs = outstr,
                overrides = intarget.overrides
            }
            
            table.insert(outmap, outobj)
            
            return outs
        end
        
        print(debugprefix .. "- sublist")
        
        for _,v in ipairs(input) do
            local outmap = flatten_map(deps, outmap, v, depth)
            for k,w in -outmap do
                outs[k] = w
            end
        end
        
        return outs
    end
    
    ---@param intarget Depo | nil
    ---@return BuildRule[], string[]
    local function build_map(intarget)
        ---@type BuildRule[]
        local outmap = {}
        ---@type string[]
        local rootfiles = {}
        
        local depset = valueset.new()
        
        ---@type ValueSet[]
        local debugouts = {}
        
        if intarget then
            local debugout = flatten_map(depset, outmap, intarget)
            table.insert(debugouts, debugout)
            
            --[[
            if intarget.outfile then
                table.insert(rootfiles, intarget.outfile)
            end
            ]]--
        else
            for _,v in pairs(outputs) do
                local debugout = flatten_map(depset, outmap, v)
                table.insert(debugouts, debugout)
                
                --[[
                if v.outfile then
                    table.insert(rootfiles, v.outfile)
                end
                ]]--
            end
        end
        
        print("Top-level outputs")
        
        for k,v in ipairs(debugouts) do
            print("[" .. k .. "]")
            for u,w in -v do
                table.insert(rootfiles, u) --TODO: use set instead of table
                
                print("- ", u, w)
                for j,z in pairs(w) do
                    print("  -", j, z)
                end
            end
        end
        
        return outmap, rootfiles
    end
    
    function emit.emit()
        
        local map, rootfiles = build_map()
        
        if #map == 0 then
            error("Nothing to build")
        end
        
        
        local templatehdr =
[[
rule RMDIR
    command = rm -rf $in

build ${OUTDIR}: phony
build clean_: RMDIR ${OUTDIR} ${builddir}
build clean: phony clean_

]]
        
        local f = assert(io.open("build.ninja", "w"))
        
        f:write("builddir = ", config.build, "\n")
        f:write("\n")
        
        f:write("SOURCES = ", config.srcroot, "\n")
        f:write("BUILD = ", config.build, "\n")
        f:write("OUTDIR = ", config.outdir, "\n")
        f:write("\n")
        
        if next(envvars) then
            for k,v in pairs(envvars) do
                f:write(k, "=", v, "\n")
            end
            f:write("\n")
            f:write("\n")
        end
        
        f:write(templatehdr, "\n")
        f:write("\n")
        
        for k,v in pairs(targets) do
            f:write("rule ", k, "\n")
            for u, w in pairs(v) do
                if u ~= "__name" then
                    f:write("    ", u, " = ", w, "\n")
                end
            end
            f:write("\n")
        end
        f:write("\n")
        
        if compilerflags.CPREFIX then
            f:write("CPREFIX=", compilerflags.CPREFIX, "\n")
        end
        for k,v in pairs(compilerflags) do
            if k ~= "CPREFIX" then
                f:write(k, "=", v, "\n")
            end
        end
        f:write("\n")
        
        for k,v in pairs(buildflags) do
            f:write(k, "=", v, "\n")
        end
        f:write("\n")
        
        for k,v in pairs(specialflags) do
            local prefix = nil
            
            if k == "LIBS" then
                prefix = "-l"
            elseif k == "LIBDIRS" then
                prefix = "-L"
            elseif k == "INCLUDES" then
                prefix = "-I"
            end
            
            f:write(k, "=", val_expand(v, prefix), "\n")
        end
        f:write("EMITCFLAGS=${INCLUDES}", "\n")
        f:write("EMITLDFLAGS=${LIBDIRS} ${LIBS}", "\n")
        f:write("\n")
        
        f:write("\n")
        
        for _,v in ipairs(map) do
            ---@type string[]
            local ins = {}
            ---@type string[]
            local outs = {}
            
            for _,w in ipairs(v.outs) do
                local sanw = ninjasan_novarescape(w)
                table.insert(outs, sanw)
            end
            
            if v.ins then
                for _,w in ipairs(v.ins) do
                    local sanw = ninjasan_novarescape(w)
                    table.insert(ins, sanw)
                end
            end
            
            f:write(
                "build ",
                table.concat(outs, " "),
                " : ",
                v.rule,
                " ",
                table.concat(ins, " "),
                "\n"
            )
        end
        
        f:write("\n")
        
        ---@type string[]
        local rootfiles_all = {}
        
        for _,w in ipairs(rootfiles) do
            local sanw = ninjasan_novarescape(w)
            table.insert(rootfiles_all, sanw)
        end
        
        if #rootfiles_all ~= 0 then
            
            f:write("\n")
            f:write("build all : phony ", table.concat(rootfiles_all, " ") , "\n")
            f:write("\n")
            
            f:write("default all")
            f:write("\n")
            
        end
        
        
        f:close()
    end
    
    if not isempty then
        emit.addtarget("CL",
            "${CC} ${ARCH} ${ALLCCFLAGS} -MMD -MP -MF $out.d ${CFLAGS} ${EMITCFLAGS} ${EXTRAFLAGS} -c $in -o $out",
            { depfile = "$out.d" })
        
        emit.addtarget("CXL",
            "${CXX} ${ARCH} ${ALLCCFLAGS} -MMD -MP -MF $out.d ${CXXFLAGS} ${EMITCFLAGS} ${EXTRAFLAGS} -c $in -o $out",
            { depfile = "$out.d" })
        
        emit.addtarget("OBJCL",
            "${CC} ${ARCH} ${ALLCCFLAGS} -MMD -MP -MF $out.d ${CFLAGS} ${EMITCFLAGS} ${OBJCFLAGS} ${EXTRAFLAGS} -c $in -o $out",
            { depfile = "$out.d" })
        
        emit.addtarget("OBJCXL",
            "${CXX} ${ARCH} ${ALLCCFLAGS} -MMD -MP -MF $out.d ${CFLAGS} ${EMITCFLAGS} ${OBJCXXFLAGS} ${EXTRAFLAGS} -c $in -o $out",
            { depfile = "$out.d" })
        
        emit.addtarget("ASM",
            "${AS} ${ARCH} ${ALLCCFLAGS} -MMD -MP -MF $out.d ${CFLAGS} ${EMITCFLAGS} ${OBJCXXFLAGS} ${EXTRAFLAGS} -c $in -o $out",
            { depfile = "$out.d" })
        
        emit.addtarget("ARMIPS",
            "armips -strequ outfile $out $in")
        
        emit.addtarget("LINK",
            "${LD} ${ARCH} $in ${LDFLAGS} ${EMITLDFLAGS} -o $out")
    else
       emit.reset() 
    end
    
    return emit
end

return api
