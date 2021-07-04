local pt = require "helper/path"

local glob = {}

local function fslist_escape(path)
    local pl = #path
    local ch1 = path:sub(1, 1)
    local ch2 = path:sub(pl, pl)
    if (ch1 == '"' or ch1 == "'") and ch1 == ch2 then
        return path:sub(2, #path - 1)
    end
    
    return path
end

local function flatten_recursive(into, what, prefix)
    for k,v in pairs(what) do
        if not v then
            into[prefix .. k] = true
        else
            flatten_recursive(into, v, prefix .. k .. "/")
        end
    end
end

function glob.flatten(res)
    local ret = {}
    
    flatten_recursive(ret, res, "")
    
    return ret
end

function glob.glob(path, filterfunc)
    if not path or path == "" then
        path = "."
    else
        path = pt.abssan(path)
    end
    
    local result = {}
    local f = io.popen('ls -1pR "' .. path .. '"')
    
    local pathlen = #path
    
    local tmp = nil
    local tfolder = nil
    
    for v in f:lines() do repeat
        local vl = #v
        
        if vl == 0 then
            break
        end
        
        local trail = v:sub(vl, vl)
        
        if trail == ":" then
            v = fslist_escape(v:sub(1, vl - 1))
            vl = #v
            
            if v:sub(1, pathlen) == path then
                v = v:sub(pathlen + 1)
                vl = vl - pathlen
                
                if v:sub(1, 1) == "/" then
                    v = v:sub(2)
                    vl = vl - 1
                end
            end
            
            if filterfunc then
                if v:sub(vl, vl) == "/" then
                    v = v :sub(1, vl - 1)
                    vl = vl - 1
                end
                
                vl = #v
                tfolder = pt.relpath(v)
            end
            
            tmp = result
            for _, k in ipairs(pt.abssplit(v)) do
                local swap = tmp
                tmp = swap[k]
                if not tmp then
                    tmp = {}
                    swap[k] = tmp
                end
            end
            
            break
        end
        
        local isfolder = (trail == "/")
        
        if isfolder then
            v = v:sub(1, vl - 1)
            vl = vl - 1
        end
        
        v = fslist_escape(v)
        vl = #v
        
        if not isfolder then
            if filterfunc and not filterfunc(tfolder, v) then
                break
            end
            
            tmp[v] = false
        end
        
    until true end
    
    if not tmp then
        return nil
    end
    
    f:close()
    
    return result
end

return glob
