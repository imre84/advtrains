-- stoprail.lua
-- adds "stop rail". Recognized by lzb. (part of behavior is implemented there)


local players_assign_signal_to_stoprail={}


local function to_int(n)
	--- Disallow floating-point numbers
	local k = tonumber(n)
	if k then
		return math.floor(k)
	end
end

local function updatemeta(pos)
	local meta = minetest.get_meta(pos)
	local pe = advtrains.encode_pos(pos)
	local stdata = advtrains.lines.stops[pe]
	if not stdata then
		meta:set_string("infotext", "Error")
	end
	
	meta:set_string("infotext", "Stn. "..stdata.stn.." T. "..stdata.track)
end

local door_dropdown = {L=1, R=2, C=3}
local door_dropdown_rev = {Right="R", Left="L", Closed="C"}


local function signalmarker(ipos, texture)
	-- using tcbmarker here
	local obj = minetest.add_entity(vector.add(ipos, {x=0, y=0.2, z=0}), "advtrains_interlocking:tcbmarker")
	if not obj then return end
	if not texture then texture = "advtrains_dtrack_redcirc.png" end
	obj:set_properties({
		textures = { texture },
	})
end


local function show_stoprailform(pos, player)
	local pe = advtrains.encode_pos(pos)
	local pname = player:get_player_name()
	if minetest.is_protected(pos, pname) then
		minetest.chat_send_player(pname, "Position is protected!")
		return
	end
	
	local stdata = advtrains.lines.stops[pe]
	if not stdata then
		advtrains.lines.stops[pe] = {
					stn="", track="", doors="R", wait=10, ars={default=true}, ddelay=1,speed="M"
				}
		stdata = advtrains.lines.stops[pe]
	end
	
	local stn = advtrains.lines.stations[stdata.stn]
	local stnname = stn and stn.name or ""
	if not stdata.ddelay then
		stdata.ddelay = 1
	end
	if not stdata.speed then
		stdata.speed = "M"
	end
	
	local form = "size[8,8]"
	form = form.."field[0.5,0.5;7,1;stn;"..attrans("Station Code")..";"..minetest.formspec_escape(stdata.stn).."]"
	form = form.."field[0.5,1.5;7,1;stnname;"..attrans("Station Name")..";"..minetest.formspec_escape(stnname).."]"
	form = form.."field[0.5,2.5;1.5,1;ddelay;"..attrans("Door Delay")..";"..minetest.formspec_escape(stdata.ddelay).."]"
	form = form.."field[2,2.5;2,1;speed;"..attrans("Departure Speed")..";"..minetest.formspec_escape(stdata.speed).."]"
	form = form.."checkbox[5,1.75;reverse;"..attrans("Reverse train")..";"..(stdata.reverse and "true" or "false").."]"
	form = form.."checkbox[5,2.0;kick;"..attrans("Kick out passengers")..";"..(stdata.kick and "true" or "false").."]"
	form = form.."label[0.5,3;Door side:]"
	form = form.."dropdown[1.5,3;2;doors;Left,Right,Closed;"..door_dropdown[stdata.doors].."]"
	form = form.."field[5,3.5;2,1;track;"..attrans("Track")..";"..minetest.formspec_escape(stdata.track).."]"
	form = form.."field[5,4.5;2,1;wait;"..attrans("Stop Time")..";"..stdata.wait.."]"

	form = form.."textarea[0.5,4;4,2;ars;Trains stopping here (ARS rules);"..advtrains.interlocking.ars_to_text(stdata.ars).."]"

	--[[ If you have a signal near to your stoprail in a way that your trains
	     leave station just to advance 2m, stop, and wait for the signal to
	     turn green, this feature is for you: it makes the train wait in the
	     station with its doors open ]]--

	local mysignal=advtrains.atc.get_signal_for_stoprail(pos)

	if not mysignal then
		form = form.."button[0.5,6;7,1;assignsignal;"..attrans("Assign signal").."]"
	else
		form = form.."label[0.5,6.25;"..attrans("Signal set").."]"
		form = form.."button[2,6;1.5,1;unsetsignal;"..attrans("Unset").."]"
		form = form.."button[4,6;1.5,1;showsignal;"..attrans("Show").."]"
	end

	form = form.."button[0.5,7;7,1;save;"..attrans("Save").."]"
	
	minetest.show_formspec(pname, "at_lines_stop_"..pe, form)
end
local tmp_checkboxes = {}
minetest.register_on_player_receive_fields(function(player, formname, fields)
	local pname = player:get_player_name()
	local pe = string.match(formname, "^at_lines_stop_(............)$")
	local pos = advtrains.decode_pos(pe)
	if pos then
		if minetest.is_protected(pos, pname) then
			minetest.chat_send_player(pname, "Position is protected!")
			return
		end
		
		local stdata = advtrains.lines.stops[pe]
		if not tmp_checkboxes[pe] then
			tmp_checkboxes[pe] = {}
		end
		if fields.kick then			-- handle checkboxes due to MT's weird handling
			tmp_checkboxes[pe].kick = (fields.kick == "true")
		end
		if fields.reverse then
			tmp_checkboxes[pe].reverse = (fields.reverse == "true")
		end
		if fields.assignsignal then
			--TODO: what if a player assigns signal to a stoprail and a TCP concurrently?
			minetest.chat_send_player(pname, "Configuring stoprail: Please punch the signal to assign.")
			players_assign_signal_to_stoprail[pname] = pos
			minetest.close_formspec(pname, formname)
			return
		end
		if fields.unsetsignal then
			advtrains.atc.set_signal_for_stoprail(pos,nil)
			minetest.chat_send_player(pname, "The signal got unset for that stoprail.")
			minetest.close_formspec(pname, formname)
			return
		end
		if fields.showsignal then
			minetest.close_formspec(pname, formname)
			local showme = advtrains.atc.get_signal_for_stoprail(pos)
			if not showme then
				minetest.chat_send_player(pname, "There is no signal associated with that stoprail.")
				return
			end
			signalmarker(showme)
			return
		end
		if fields.save then
			if fields.stn and stdata.stn ~= fields.stn then
				if fields.stn ~= "" then
					local stn = advtrains.lines.stations[fields.stn]
					if stn then
						if (stn.owner == pname or minetest.check_player_privs(pname, "train_admin")) then
							stdata.stn = fields.stn
						else
							minetest.chat_send_player(pname, "Station code '"..fields.stn.."' does already exist and is owned by "..stn.owner)
						end
					else
						advtrains.lines.stations[fields.stn] = {name = fields.stnname, owner = pname}
						stdata.stn = fields.stn
					end
				end
				updatemeta(pos)
				show_stoprailform(pos, player)
				return
			end
			local stn = advtrains.lines.stations[stdata.stn]
			if stn and fields.stnname and fields.stnname ~= stn.name then
				if (stn.owner == pname or minetest.check_player_privs(pname, "train_admin")) then
					stn.name = fields.stnname
				else
					minetest.chat_send_player(pname, "Not allowed to edit station name, owned by "..stn.owner)
				end
			end
			
			-- dropdowns
			if fields.doors then
				stdata.doors = door_dropdown_rev[fields.doors] or "C"
			end
			
			if fields.track then
				stdata.track = fields.track
			end
			if fields.wait then
				stdata.wait = to_int(fields.wait) or 10
			end
			
			if fields.ars then
				stdata.ars = advtrains.interlocking.text_to_ars(fields.ars)
			end

			if fields.ddelay then
				stdata.ddelay = to_int(fields.ddelay) or 1
			end
			if fields.speed then
				stdata.speed = to_int(fields.speed) or "M"
			end

			for k,v in pairs(tmp_checkboxes[pe]) do --handle checkboxes
				stdata[k] = v or nil
			end
			tmp_checkboxes[pe] = nil
			--TODO: signal
			updatemeta(pos)
			show_stoprailform(pos, player)
		end
	end
	
end)


minetest.register_on_punchnode(function(pos, node, player, pointed_thing)
	local pname = player:get_player_name()
	local stoppos=players_assign_signal_to_stoprail[pname]
	if not stoppos then
		return
	end
	local is_signal = minetest.get_item_group(node.name, "advtrains_signal") >= 2
	if not is_signal then
		minetest.chat_send_player(pname, "Configuring stoprail: Not a compatible signal. Aborted.")
		return
	end
	advtrains.atc.set_signal_for_stoprail(stoppos,pos)
	minetest.chat_send_player(pname, "Configuring stoprail: Ok, signal set.")
	players_assign_signal_to_stoprail[pname]=nil
end)


local adefunc = function(def, preset, suffix, rotation)
		return {
			after_place_node=function(pos)
				local pe = advtrains.encode_pos(pos)
				advtrains.lines.stops[pe] = {
					stn="", track="", doors="R", wait=10
				}
				updatemeta(pos)
			end,
			after_dig_node=function(pos)
				advtrains.atc.set_signal_for_stoprail(pos,nil)
				local pe = advtrains.encode_pos(pos)
				advtrains.lines.stops[pe] = nil
			end,
			on_rightclick = function(pos, node, player)
				show_stoprailform(pos, player)
			end,
			advtrains = {
				on_train_approach = function(pos,train_id, train, index)
					if train.path_cn[index] == 1 then
						local pe = advtrains.encode_pos(pos)
						local stdata = advtrains.lines.stops[pe]
						if stdata and stdata.stn then
						
							--TODO REMOVE AFTER SOME TIME (only migration)
							if not stdata.ars then
								stdata.ars = {default=true}
							end
							if stdata.ars and (stdata.ars.default or advtrains.interlocking.ars_check_rule_match(stdata.ars, train) ) then
								advtrains.lzb_add_checkpoint(train, index, 2, nil)
								local stn = advtrains.lines.stations[stdata.stn]
								local stnname = stn and stn.name or "Unknown Station"
								train.text_inside = "Next Stop:\n"..stnname
							end
						end
					end
				end,
				on_train_enter = function(pos, train_id, train, index)
					if train.path_cn[index] == 1 then
						local pe = advtrains.encode_pos(pos)
						local stdata = advtrains.lines.stops[pe]
						if not stdata then
							return
						end
						
						if stdata.ars and (stdata.ars.default or advtrains.interlocking.ars_check_rule_match(stdata.ars, train) ) then
							local stn = advtrains.lines.stations[stdata.stn]
							local stnname = stn and stn.name or "Unknown Station"
							
							-- Send ATC command and set text
							local cmd="B0 W O"..stdata.doors..(stdata.kick and "K" or "").." D"..stdata.wait
							local mysignal=advtrains.atc.get_signal_for_stoprail(pos)
							if mysignal then
								cmd=cmd.."G"..mysignal.x..","..mysignal.y..","..mysignal.z
							end
							cmd=cmd.." OC "..(stdata.reverse and "R" or "").."D"..(stdata.ddelay or 1) .. "S" ..(stdata.speed or "M")
							advtrains.atc.train_set_command(train, cmd, true)
							train.text_inside = stnname
							if tonumber(stdata.wait) then
								minetest.after(tonumber(stdata.wait), function() train.text_inside = "" end)
							end
						end
					end
				end
			},
		}
end

if minetest.get_modpath("advtrains_train_track") ~= nil then
	advtrains.register_tracks("default", {
		nodename_prefix="advtrains_line_automation:dtrack_stop",
		texture_prefix="advtrains_dtrack_stop",
		models_prefix="advtrains_dtrack",
		models_suffix=".b3d",
		shared_texture="advtrains_dtrack_shared_stop.png",
		description="Station/Stop Rail",
		formats={},
		get_additional_definiton = adefunc,
	}, advtrains.trackpresets.t_30deg_straightonly)
end
