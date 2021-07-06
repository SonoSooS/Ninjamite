local path = {}

---@alias PathArray table

--- Checks if the input path is absolute or not
---@param str string | PathArray
---@return boolean result path is absolute or not
function path.isabs(str)
    if type(str) == "table" then
        str = str[1]
        if not str then
            return false
        end
    end
    
    --[[
    if str == "" then
        return false -- isabs is mainly used on relative paths, so empty string means current
    end
    ]]--
    
    return path.isunixabs(str) or path.iswinabs(str)
end

--- Checks whether the given path is UNIX absolute or not
---@param str string UNIX path
---@return boolean result whether str is absolute UNIX path or not
function path.isunixabs(str)
    return str == "" or str:sub(1, 1) == "/"
end

--- Checks whether the given path is Windows absolute or not.
--- UNC paths are not supported.
---@param str string path
---@return boolean result whether str is absolute Windows path or not
function path.iswinabs(str)
    return str:match("^[A-Za-z]:") and true or false
end

--- Splits relative input path into a PathArray
---@param str string relative input path
---@return PathArray splitpath path components split into an array
---@see path.abssplit
function path.split(str)
    ---@type PathArray
    local ret = {}
    
    for v in str:gmatch("[^\\/]+") do -- split path by slashes, trimming them in the process
        table.insert(ret, v)
    end
    
    return ret
end

--- Splits relative or absolute path into a PathArray
---@param str string absolute or relative input path
---@return PathArray splitpath path components split into an array where the first entry might be a root
---@see path.split
function path.abssplit(str)
    ---@type PathArray
    local ret = {}
    
    if path.iswinabs(str) then -- path is Windows path (like "C:")
        local first = str:sub(1, 2) -- trim path letter and colon
        table.insert(ret, first)
        
        str = str:sub(3) -- parse the rest as relative path
        
        for v in str:gmatch("[^\\/]+") do
            table.insert(ret, v)
        end
        
        return ret
    end
    
    -- try using the whole string before the first slash as a root
    local idx, idxe = str:find("[\\/]+")
    if idx then -- there is string before first root
       local first = str:sub(1, idx - 1)
       table.insert(ret, first)
       
       str = str:sub(idxe + 1) -- parse the rest below as usual (fallthru)
    end
    
    for v in str:gmatch("[^\\/]+") do
        table.insert(ret, v)
    end
    
    return ret
end

--- Mini-sanitize string input into a safer relative path
---@param str string relative path to mini-sanitize
---@return string sanpath mini-sanitized path
function path.relpath(str)
    if str == nil then
        return "" -- default is current directory (no dots allowed)
    end
    
    return path.combine(path.split(str))
end

--- Mini-sanitize input while trying to respect the absolute prefix
---@param str string absolute path to mini-sanitize
---@return string abssanpath mini-sanitized absolute path
function path.abspath(str)
    if str == nil then
        return "/" -- default is root
    end
    
    local ret = path.combine(path.abssplit(str))
    if ret ~= "" then
        return ret
    else
        return "/" -- empty means current directory, so return absolute root instead
    end
end

--- Mini-ssanitize MinGW path into absolute Windows path
---@param str string absolute MinGW path
---@return string abswinpath mini-sanitized absolute Windows path
function path.mwpath(str)
    local ret = path.abssplit(str)
    local retlen = #ret
    
    if retlen == 0 or retlen == 1 or ret[1] ~= "" or #ret[2] ~= 1 then
        return path.abspath(str)
    end
    
    local newchar = ret[2]:byte()
    newchar = newchar - 0x20
    
    if newchar < 0x41 or newchar > 0x5A then
        return path.abspath(str)
    end
    
    local newret = {}
    
    local first = string.char(newchar) .. ":"
    
    table.insert(newret, first)
    
    for k,v in ipairs(ret) do
        if k ~= 1 and k ~= 2 then
            table.insert(newret, v)
        end
    end
    
    return path.combine(newret)
end

--- Combines path fragments into a full relative path.
--- Turns absolute UNIX paths into relative paths.
---@vararg string
---@return string combinepath input fragments combined
function path.combine(...)
    ---@type string[]
    local args = {...}
    
    if #args == 1 and type(args[1]) == "table" then
        args = args[1]
    end
    
    if args[1] == "" then -- strip (accidental?) absolute UNIX path prefix
        ---@type string[]
        local largs = {}
        for k,v in ipairs(args) do
            if k ~= 1 then
                table.insert(largs, v)
            end
        end
        
        args = largs
    end
    
    return table.concat(args, "/")
end

--- Joins path fragments while sanitizing it
---@vararg string
---@return string combinepath sanitized combined path
function path.join(...)
    local args = {...}
    
    local buf = {}
    
    for _, v in ipairs(args) do
        for _, w in ipairs(path.split(v)) do
            table.insert(buf, w)
        end
    end
    
    return path.san(buf)
end

--- Joins absolute path fragments while sanitizing it
---@vararg string
---@return string combinepath sanitized combined path
function path.absjoin(...)
    local args = {...}
    
    local buf = {}
    
    for _, v in ipairs(args) do
        for _, w in ipairs(path.split(v)) do
            table.insert(buf, w)
        end
    end
    
    return path.abssan(buf)
end

--- Raw sanitize path via path stack mechanism
---@param obj PathArray input path fragment array
---@param abs boolean | nil whether the input path fragment array is absolute path
---@see path.san
---@see path.abssan
function path.rawsan(obj, abs)
    local split = obj
    
    local deep = 0
    local stack = {}
    
    local lastval
    if abs and #split ~= 0 then
        lastval = table.remove(split, 1)
    end
    
    for _, v in ipairs(split) do
        if v == ".." then
            table.remove(stack)
            deep = deep - 1
        elseif v ~= "." then
            table.insert(stack, v)
            deep = deep + 1
        end
    end
    
    deep = #stack - deep
    if abs or deep ~= 0 then
        local ret = {}
        
        if not abs then
            repeat
                table.insert(ret, "..")
                deep = deep - 1
            until deep == 0
        elseif lastval then
            table.insert(ret, lastval)
        end
        
        for _, v in ipairs(stack) do
            table.insert(ret, v)
        end
        
        return ret
    elseif #stack ~= 0 then
        return stack
    else
        return {}
    end
end

--- Sanitize relative path
---@param obj string | PathArray unsanitized path or path fragment
---@return string sanpath sanitized path
function path.san(obj)
    ---@type PathArray
    local split
    
    if type(obj) ~= "table" then
        split = path.split(obj)
    else
        split = obj
    end
    
    local ret = path.rawsan(split)
    
    if #ret ~= 0 then
        return table.concat(ret, "/")
    else
        return "." -- sanitizing returns directoryy and optional file
    end
end

--- Sanitize absolute path
---@param obj string | PathArray unsanitized absolute path or path fragment with absolute prefix
---@return string abssanpath sanitized absolute path
function path.abssan(obj)
    if not path.isabs(obj) then
        return path.san(obj)
    end
    
    ---@type PathArray
    local split
    
    if type(obj) ~= "table" then
        split = path.abssplit(obj)
    else
        split = obj
    end
    
    local ret = path.rawsan(split, true)
    
    if #ret ~= 0 then
        if #ret == 1 and ret[1] == "" then
            return "/"
        end
        
        return table.concat(ret, "/")
    else
        return "." --TODO: what warrants this behavior?
    end
end

return path
