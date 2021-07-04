local pt = require "helper/path"
local glob = require "helper/glob"
local valueset = require "helper/valueset"

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

local function val_expand(val, prefix)
    if type(val) == "table" then
        if not prefix then
            return table.concat(val, " ")
        end
        
        if #val == 0 then
            return ""
        end
        
        return prefix .. table.concat(val, " " .. prefix)
    end
    
    return val
end

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

local function ninjasan(pat)
    return pat:gsub("([%$%:% ])", "$%1")
end

local function ninjasan_novarescape(pat)
    return pat:gsub("([%:% ])", "$%1")
end

local function patternsan(pat)
    return pat:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
end

local function patternsan_sregex(pat)
    return pat:gsub("([%(%)%.%%%+%-%[%]%^%$])", "%%%1")
end

local function newdepo(depotype, method, overrides)
    local buildrule = method and (method.__targetname or method)
    local objtype = depotype
    local globalopts = overrides or {}
    
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
        
        local outname = nil
        
        local inputs = {}
        
        function depo.output(filepath)
            if outname then
                error("Do not call this function directly")
            end
            
            outname = filepath
            
            depo.outfile = filepath
        end
        
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
            
            local obj = { __cmd = buildrule, __outs = {outname}, __indeps = inputs, overrides = globalopts}
            
            return obj
        end
        
        return depo
        
    elseif objtype == "mapper" then
        
        local mapping = {}
        
        function depo.addmap(in1, in2, in3)
            if not in1 then
                return depo
            end
            
            local inmap
            local overrides
            
            if type(in1) == "string" then
                inmap = {}
                inmap[in1] = in2
                
                overrides = in3
            else
                inmap = in1
                overrides = in2
            end
            
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
                local obj = { __cmd = buildrule, __outs = {k}, __indeps = {v}, overrides = tmpcopy }
                
                mapping[k] = obj
            end
            
            return depo
        end
        
        function depo.build_internal()
            local res = {}
            
            for _,v in pairs(mapping) do
                table.insert(res, v)
            end
            
            return res
        end
        
        return depo
    end
    
    error("Invalid depmapper type '" .. objtype .. "'")
end


local mappingtools = {}

function mappingtools.remap(data, mapper)
    local ret = {}
    
    for k,v in pairs(data) do
        
        k,v = mapper(k,v)
        if k ~= nil then
            ret[k] = v
        end
    end
    
    return ret
end

function mappingtools.dstprefixbuild(k, v)
    return "${builddir}/" .. k, v
end

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

function mappingtools.srctodstmap(k, v)
    return v, v
end

function mappingtools.dsttosrcmap(k, v)
    return k, k
end

function mappingtools.dstremap(files, mapper)
    local res = {}
    
    for k,v in pairs(files) do
        k, v = mapper(k, k)
        if k ~= nil then
            res[k] = v
        end
    end
    
    return res
end

function mappingtools.srcremap(files, mapper)
    local res = {}
    
    for k,v in pairs(files) do
        k, v = mapper(v, v)
        if k ~= nil then
            res[k] = v
        end
    end
    
    return res
end

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


local api = {}

function api.new(rootarg, isempty)
    if not rootarg then
        error("Parameter #1 must be the source root path")
    end
    
    local config =
    {
        srcroot = pt.abssan(rootarg),
        
        build = "build",
        outdir = "out"
    }
    
    local targets = {}
    local pubtargets = {}
    
    local outputs = {}
    local envvars = {}
    
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
    
    local buildflags =
    {
        ARCH = "",
        ALLCCFLAGS = "-g -Og -Wall",
        CFLAGS = "",
        CXXFLAGS = "",
        OBJCFLAGS = "",
        ASFLAGS = ""
    }
    
    local specialflags =
    {
        LIBS = {},
        LIBDIRS = {},
        INCLUDES = {}
    }
    
    
    local emit = {}
    
    emit.map = mappingtools
    emit.targets = pubtargets
    
    function emit.reset()
        config = {}
        
        targets = {}
        pubtargets = {}
        
        outputs = {}
        envvars = {}
        
        compilerflags = {}
        buildflags = {}
        specialflags = {}
    end
    
    
    function emit.srcappendmap(fndst, fnsrc)
        return fndst, pt.combine(config.srcroot, fnsrc)
    end
    
    function emit.dstappendmap(fndst, fnsrc)
        return pt.combine(config.srcroot, fndst), fnsrc
    end
    
    function emit.add(target)
        table.insert(outputs, target)
        return target
    end
    
    function emit.newtarget(name, method, ...)
        local target = newdepo("arch", method)
        
        target.output(name)
        target.addinput(...)
        
        --return emit.add(target)
        return target
    end
    
    function emit.newmapper(method, ...)
        local target = newdepo("mapper", method)
        
        target.addmap(...)
        
        --return emit.add(target)
        return target
    end
    
    function emit.env(cfg, val)
        mergetable(envvars, cfg, val)
        return emit
     end
    
    function emit.config(cfg, val)
       mergetable(config, cfg, val)
       return emit
    end
    
    function emit.compiler(cfg, val)
        mergetable(compilerflags, cfg, val)
        return emit
    end
    
    function emit.cflags(cfg, val)
        mergetable(buildflags, cfg, val)
        return emit
    end
    
    function emit.special(cfg, val)
        mergetable(specialflags, cfg, val)
        return emit
    end
    
    function emit.addtarget(name, cmd, extras)
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
    end
    
    function emit.infile(pattern, filter, remap)
        if type(filter) == "string" then
            pattern = pt.join(pattern, filter)
            filter = nil
        elseif type(filter) ~= "function" and filter ~= true and filter ~= false and filter ~= nil then
            error("Filter is not string, function, true, false, or nil")
        end
        
        if filter == nil and pattern:find("[*?#]") then
            local newpattern = patternsan_sregex(pt.san(pattern))
            
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
        
        local results = {}
        
        if filter == true then
            local filtpattern = pattern
            
            filter = function(fd, fn)
                local fullpath = pt.combine(fd, fn)
                
                if fullpath:match(filtpattern) then
                    results[fullpath] = fullpath
                end
                
                return false
            end
        end
        
        if not filter then
            filter = function(fd, fn)
                local fullpath = pt.combine(fd, fn)
                results[fullpath] = fullpath
                
                return false
            end
        end
        
        glob.glob(config.srcroot, filter)
        
        if remap then
            if type(remap) ~= "function" then
                remap = emit.dstappendmap
            end
            
            results = mappingtools.dstremap(results, remap)
        end
        
        return results
    end
    
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
    
    function emit.newinfilemap(target, pattern, filter, extra, mapper)
        local files = emit.infile(pattern, filter, mapper)
        
        return emit.newfilemap(files, target, extra)
    end
    
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
            print(debugprefix .. "- mapper " .. input.__flag)
            
            local results = input.build()
            
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
            local debugouts = {}
            
            for _,v in ipairs(input.__outs) do
                table.insert(debugouts, v)
            end
            
            print(debugprefix .. "- raw cmd = " .. input.__cmd .. " | outs = " .. table.concat(debugouts, ", "))
            
            local ins = valueset.new()
            
            local instr = {}
            local outstr = {}
            
            if input.__indeps then
                for _,v in ipairs(input.__indeps) do
                   local infiles = flatten_map(deps, outmap, v, depth) 
                   for k,w in -infiles do
                       ins[k] = w
                   end
                end
                
                for k in -ins do
                    table.insert(instr, k)
                end
            end
            
            for _,v in ipairs(input.__outs) do
                outs[v] = instr
                deps[v] = instr
                table.insert(outstr, v)
            end
            
            local outobj =
            {
                rule = input.__cmd,
                ins = instr,
                outs = outstr,
                overrides = input.overrides
            }
            
            table.insert(outmap, outobj)
            
            return outs
        end
        
        print(debugprefix .. "- array")
        
        for _,v in ipairs(input) do
            local outmap = flatten_map(deps, outmap, v, depth)
            for k,w in -outmap do
                outs[k] = w
            end
        end
        
        return outs
    end
    
    local function build_map(intarget)
        local outmap = {}
        local rootfiles = {}
        
        local depset = valueset.new()
        
        if intarget then
            flatten_map(depset, outmap, intarget)
            if intarget.outfile then
                table.insert(rootfiles, intarget.outfile)
            end
        else
            for _,v in pairs(outputs) do
                flatten_map(depset, outmap, v)
                if v.outfile then
                    table.insert(rootfiles, v.outfile)
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
            local ins = {}
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
