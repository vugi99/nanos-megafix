

local store_cookie = ''

-- Will make sure the current installed version is published (asset pack has to be loaded)
local asset_packs = {
    --"uselessassetpack",
}


function split_str(str,sep)
    local sep, fields = sep or ":", {}
    local pattern = string.format("([^%s]+)", sep)
    str:gsub(pattern, function(c) fields[#fields+1] = c end)
    return fields
end


local RequestRunning = {}

function StartMegaFixCheck(asset_name)
    local cur_version
    for i, v in ipairs(Assets.GetAssetPacks()) do
        if v.Path == asset_name then
            cur_version = v.Version
        end
    end
    if cur_version then
        if not RequestRunning[asset_name] then
            RequestRunning[asset_name] = true
            HTTP.RequestAsync("https://store.nanos.world", "/assets/".. asset_name .. "/releases", "GET", "", "application/json", false, {cookie=store_cookie}, function(status, data)
                RequestRunning[asset_name] = nil
                if (status == 200 and not string.find(data, "Password")) then
                    --print("GetReleasesTabForPackage", status, data)
                    local split_lines = split_str(data, "\n")
                    local next_version_nb
                    local next_status
                    local last_version
                    local versions = {}
                    for i, v in ipairs(split_lines) do
                        --print(v)
                        if (string.find(v, '<h3 class="text%-lg leading%-6 font%-medium text%-gray%-900">')) then
                            next_version_nb = true
                        elseif next_version_nb then
                            next_version_nb = nil
                            local split_spaces = split_str(v, " ")
                            --print(split_spaces[1])
                            versions[split_spaces[1]] = {status = "???"}
                            last_version = split_spaces[1]
                        elseif next_status then
                            next_status = nil
                            if last_version then
                                local split_spaces = split_str(v, " ")
                                versions[last_version].status = (split_spaces[1] == "Released")
                                if split_spaces[1] == "Released" then
                                    versions[last_version].status = true
                                elseif split_spaces[1] == "Approved" then
                                    versions[last_version].status = false
                                end
                            end
                        elseif ((string.find(v, "form") and string.find(v, 'method="post"')) and string.find(v, 'action') and string.find(v, 'class="inline%-block"')) then
                            if last_version then
                                local split_delim = split_str(v, '"')
                                local count = #split_delim
                                if count > 1 then
                                    local endpoint = split_delim[count-1]
                                    local endpoint_split = split_str(endpoint, "/")
                                    versions[last_version].release_id = endpoint_split[#endpoint_split]
                                end
                            end
                        else
                            local split_str_delim = split_str(v, '"')
                            if (split_str_delim[1] and split_str_delim[2] and split_str_delim[3]) then
                                if (string.find(split_str_delim[1], "<span class=") and string.find(split_str_delim[2], "inline%-flex") and string.find(split_str_delim[2], "items%-center") and string.find(split_str_delim[2], "px%-2.5")) then
                                    next_status = true
                                end
                            end
                        end
                    end
                    --print(NanosTable.Dump(versions))
                    if (versions[cur_version] ~= nil) then
                        if versions[cur_version].status == "???" then
                            Console.Warn("MegaFix : Wrong release state or cannot find release state of current version (" .. asset_name .. ")")
                        end
                        if (versions[cur_version].status == false) then
                            if versions[cur_version].release_id then
                                local request_publish_page = HTTP.Request("https://store.nanos.world", "/assets/" .. asset_name .. "/releases/" .. versions[cur_version].release_id .. "/publish", "GET", "", "application/json", false, {cookie=store_cookie})
                                --print("request_publish_page", asset_name, request_publish_page.Status, request_publish_page.Data)

                                if request_publish_page.Status == 200 then
                                    local split_lines_rppage = split_str(request_publish_page.Data, "\n")
                                    local __RequestVerificationToken

                                    for i, v in ipairs(split_lines_rppage) do
                                        --print(v)
                                        if (string.find(v, "<input") and string.find(v, 'name="__RequestVerificationToken"') and string.find(v, 'value')) then
                                            local split_delim = split_str(v, '"')
                                            local count = #split_delim
                                            if count > 1 then
                                                __RequestVerificationToken = split_delim[count-1]
                                            end
                                        end
                                    end

                                    if __RequestVerificationToken then
                                        --print(__RequestVerificationToken)
                                        local request = HTTP.Request("https://store.nanos.world", "/assets/" .. asset_name .. "/releases/" .. versions[cur_version].release_id .. "/publish", "POST", "__RequestVerificationToken="..__RequestVerificationToken, "application/x-www-form-urlencoded", false, {cookie=store_cookie})
                                        --print("PublishRelease", asset_name, request.Status, request.Data)
                                        print("MegaFix : Published " .. cur_version .. " for " .. asset_name)
                                    else
                                        Console.Warn("MegaFix : Cannot find __RequestVerificationToken for " .. asset_name)
                                    end
                                else
                                    Console.Warn("MegaFix : Cannot GET publish page of " .. asset_name .. " (" .. cur_version .. ")")
                                end
                            else
                                Console.Warn("MegaFix : Cannot find release id for current version of " .. asset_name)
                            end
                        else
                            --print("MegaFix : Good current version for " .. asset_name)
                        end
                    else
                        Console.Warn("MegaFix : Cannot find the current version on the Vault for " .. asset_name .. " (make sure to upload it first)")
                    end
                else
                    Console.Warn("MegaFix : Store package request failed, (update cookie ?)")
                end
            end)
        end
    else
        Console.Warn("MegaFix : Cannot find current version for " .. asset_name)
    end
end

function MFMain()
    if store_cookie ~= "" then
        for i, v in ipairs(asset_packs) do
            StartMegaFixCheck(v)
        end
    else
        Console.Warn("MegaFix : Enter your cookie inside the script")
    end
end

Package.Subscribe("Load", MFMain)
Server.Subscribe("PlayerConnect", function(IP, player_account_ID, player_name, player_steam_ID)
	MFMain()
end)