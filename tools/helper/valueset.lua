local vs = {}

---@class ValueSet

--- Creates a new value set (key is unique)
---@return ValueSet set
function vs.new()
    --- Dummy object
    ---@type ValueSet
    local obj = {}
    --- Metatable for valuesets
    local mt = {}
    
    ---@type table<string, any>
    local backer = {}
    ---@type string[]
    local order = {}
    ---@type table<string, number>
    local indexes = {}
    
    function mt.__index(this, index)
        return backer[index]
    end
    
    function mt.__newindex(this, index, val)
        backer[index] = val
        
        if indexes[index] then
            return
        end
        
        local newindex = #order + 1
        order[newindex] = index
        indexes[index] = newindex
    end
    
    --- Iterates over the value set in key insertion order
    ---@return fun(): string,any | nil
    function mt.__unm(this)
        local i = 1
        
        return function()
            if i > #order then
                return
            end
            
            local key = order[i]
            local value = backer[key]
            
            i = i + 1
            
            return key, value
        end
    end
    
    setmetatable(obj, mt)
    return obj
end

return vs
