local pt = require "helper/path"

local glob = {}

---@alias GlobFileList table<string, boolean>
---@alias GlobResult table<string, boolean | GlobFileList>
---@alias GlobFileFilterFunc fun(folder: string, filename: string): boolean


--- Unescapes results from ls output
---@param path string escaped ls output line
---@return string unescaped output
local function fslist_escape(path)
    local pl = #path
    local ch1 = path:sub(1, 1)
    local ch2 = path:sub(pl, pl)
    if (ch1 == '"' or ch1 == "'") and ch1 == ch2 then
        return path:sub(2, #path - 1)
    end
    
    return path
end

--- Flattens recursive file listing data into a flat array
---@param into GlobResult destination array with flattened path
---@param what GlobResult input unflattened array
---@param prefix string | '""'
local function flatten_recursive(into, what, prefix)
    for k,v in pairs(what) do
        if not v then
            into[prefix .. k] = true
        else
            flatten_recursive(into, v, prefix .. k .. "/")
        end
    end
end

--- Flattens recursive file listing into a flat array
---@param res GlobResult input file listing
---@return GlobResult result flattened file listing
function glob.flatten(res)
    local ret = {}
    
    flatten_recursive(ret, res, "")
    
    return ret
end

--- Recursive file listing
---@param path string input folder
---@param filterfunc GlobFileFilterFunc | nil optional file filter funciton
function glob.glob(path, filterfunc)
    if not path or path == "" then
        path = "."
    else
        path = pt.abssan(path)
    end
    
    ---@type GlobResult
    local result = {}
    
    local f = io.popen('ls -1pR "' .. path .. '"')
    
    local pathlen = #path
    
    --- Temporary variable for quickly traversing the result table
    ---@type GlobFileList | nil
    local tmp = nil
    --- Folder prefix for filename passed to filter function
    ---@type string | nil
    local tfolder = nil
    
    ---@type string
    for v in f:lines() do repeat
        local vl = #v
        
        if vl == 0 then
            break -- continue
        end
        
        local trail = v:sub(vl, vl)
        
        if trail == ":" then -- new ls directory (header)
            -- unescape quotes and spaces
            v = fslist_escape(v:sub(1, vl - 1))
            vl = #v
            
            -- trim readed parent directory (absolute to relative)
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
        
        if isfolder then -- trim trailing slash
            v = v:sub(1, vl - 1)
            vl = vl - 1
        end
        
        -- unescape line with spaces in it
        v = fslist_escape(v)
        vl = #v
        
        --TODO: folder filtering?
        if not isfolder then -- can't filter folders, only files (for now)
            if filterfunc and not filterfunc(tfolder, v) then
                break
            end
            
            tmp[v] = false
        end
        
    until true end
    
    if not tmp then
        error "WTF"
        return nil
    end
    
    f:close()
    
    return result
end

return glob
