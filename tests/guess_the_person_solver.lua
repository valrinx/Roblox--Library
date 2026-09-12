return function(adaptiveQuestion, chars, cat)
    local function simulate(adaptive)
        local sum, worst, unresolved = 0, 0, 0
        for _, secret in ipairs(chars) do
            local remaining = table.clone(chars)
            local steps = 0
            while #remaining > 1 and steps < #chars do
                local pair
                if adaptive then pair = adaptiveQuestion(remaining, cat) end
                if not pair then
                    local best = math.huge
                    for _, p in ipairs(cat.allPairs()) do
                        local yes = 0
                        for _, c in ipairs(remaining) do if cat.matches(c,p.question,p.answer) then yes=yes+1 end end
                        local diff = math.abs(#remaining-2*yes)
                        if yes>0 and yes<#remaining and diff<best then best=diff; pair=p end
                    end
                end
                if not pair then break end
                local answer = cat.matches(secret,pair.question,pair.answer)
                local filtered = {}
                for _, c in ipairs(remaining) do
                    if cat.matches(c,pair.question,pair.answer)==answer then table.insert(filtered,c) end
                end
                assert(#filtered>0 and #filtered<#remaining, "Question failed to reduce candidates")
                assert(table.find(filtered,secret), "Eliminated actual secret")
                remaining=filtered
                steps=steps+1
            end
            if #remaining>1 then unresolved=unresolved+1 end
            sum=sum+steps
            worst=math.max(worst,steps)
        end
        return {average=sum/#chars,worst=worst,unresolved=unresolved,characters=#chars}
    end
    assert(adaptiveQuestion({},cat)==nil)
    assert(adaptiveQuestion({chars[1]},cat)==nil)
    return {balanced=simulate(false),adaptive=simulate(true)}
end
