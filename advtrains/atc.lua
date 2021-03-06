--atc.lua
--registers and controls the ATC system

local atc={}

local eval_conditional

-- ATC persistence table. advtrains.atc is created by init.lua when it loads the save file.
atc.controllers = {}
-- Assignment of signals to stoprails: signal_to_stoprail[stoprailpos]=signalpos
atc.signal_to_stoprail = {}
-- signal_refcount[signalpos]=number of times this signal is referenced in signal_to_stoprail
atc.signal_refcount = {}
-- cmds_for_signals[pos][train_id]="ATC command string"
atc.cmds_for_signals = {}
function atc.load_data(data)
	local temp = data and data.controllers or {}
	--transcode atc controller data to node hashes: table access times for numbers are far less than for strings
	for pts, data in pairs(temp) do
		if type(pts)=="number" then
			pts=minetest.pos_to_string(minetest.get_position_from_hash(pts))
		end
		atc.controllers[pts] = data
	end
	if not data then return end
	if data.signal_to_stprl then
		atc.signal_to_stoprail = data.signal_to_stprl
	end
	if data.signalrc then
		atc.signal_refcount = data.signalrc
	end
	if data.c4s then
		atc.cmds_for_signals = data.c4s
	end
end
function atc.save_data()
	return {
		controllers = atc.controllers,
		signal_to_stprl = atc.signal_to_stoprail,
		signalrc = atc.signal_refcount,
		c4s = atc.cmds_for_signals,
	}
end
--contents: {command="...", arrowconn=0-15 where arrow points}

--general
function atc.train_set_command(train, command, arrow)
	atc.train_reset_command(train, true)
	train.atc_delay = 0
	train.atc_arrow = arrow
	train.atc_command = command
end

function atc.send_command(pos, par_tid)
	local pts=minetest.pos_to_string(pos)
	if atc.controllers[pts] then
		--atprint("Called send_command at "..pts)
		local train_id = par_tid or advtrains.get_train_at_pos(pos)
		if train_id then
			if advtrains.trains[train_id] then
				--atprint("send_command inside if: "..sid(train_id))
				if atc.controllers[pts].arrowconn then
					atlog("ATC controller at",pts,": This controller had an arrowconn of", atc.controllers[pts].arrowconn, "set. Since this field is now deprecated, it was removed.")
					atc.controllers[pts].arrowconn = nil
				end
				
				local train = advtrains.trains[train_id]
				local index = advtrains.path_lookup(train, pos)
				
				local iconnid = 1
				if index then
					iconnid = train.path_cn[index]
				else
					atwarn("ATC rail at", pos, ": Rail not on train's path! Can't determine arrow direction. Assuming +!")
				end
				
				local command = atc.controllers[pts].command				
				command = eval_conditional(command, iconnid==1, train.velocity)
				if not command then command="" end
				command=string.match(command, "^%s*(.*)$")
				
				if command == "" then
					atprint("Sending ATC Command to", train_id, ": Not modifying, conditional evaluated empty.")
					return true
				end
				
				atc.train_set_command(train, command, iconnid==1)
				atprint("Sending ATC Command to", train_id, ":", command, "iconnid=",iconnid)
				return true
				
			else
				atwarn("ATC rail at", pos, ": Sending command failed: The train",train_id,"does not exist. This seems to be a bug.")
			end
		else
			atwarn("ATC rail at", pos, ": Sending command failed: There's no train at this position. This seems to be a bug.")
		end
	else
		atwarn("ATC rail at", pos, ": Sending command failed: Entry for controller not found.")
		atwarn("ATC rail at", pos, ": Please visit controller and click 'Save'")
	end
	return false
end

-- Resets any ATC commands the train is currently executing, including the target speed (tarvelocity) it is instructed to hold
-- if keep_tarvel is set, does not clear the tarvelocity
function atc.train_reset_command(train, keep_tarvel)
	train.atc_command=nil
	train.atc_delay=nil
	train.atc_brake_target=nil
	train.atc_wait_finish=nil
	train.atc_arrow=nil
	if not keep_tarvel then
		train.tarvelocity=nil
	end
end

--nodes
local idxtrans={static=1, mesecon=2, digiline=3}
local apn_func=function(pos)
	-- FIX for long-persisting ndb bug: there's no node in parameter 2 of this function!
	local meta=minetest.get_meta(pos)
	if meta then
		meta:set_string("infotext", attrans("ATC controller, unconfigured."))
		meta:set_string("formspec", atc.get_atc_controller_formspec(pos, meta))
	end
end

advtrains.atc_function = function(def, preset, suffix, rotation)
		return {
			after_place_node=apn_func,
			after_dig_node=function(pos)
				return advtrains.pcall(function()
					advtrains.invalidate_all_paths(pos)
					advtrains.ndb.clear(pos)
					local pts=minetest.pos_to_string(pos)
					atc.controllers[pts]=nil
				end)
			end,
			on_receive_fields = function(pos, formname, fields, player)
				return advtrains.pcall(function()
					if advtrains.is_protected(pos, player:get_player_name()) then
						minetest.record_protection_violation(pos, player:get_player_name())
						return
					end
					local meta=minetest.get_meta(pos)
					if meta then
						if not fields.save then 
							--maybe only the dropdown changed
							if fields.mode then
								meta:set_string("mode", idxtrans[fields.mode])
								if fields.mode=="digiline" then
									meta:set_string("infotext", attrans("ATC controller, mode @1\nChannel: @2", (fields.mode or "?"), meta:get_string("command")) )
								else
									meta:set_string("infotext", attrans("ATC controller, mode @1\nCommand: @2", (fields.mode or "?"), meta:get_string("command")) )
								end
								meta:set_string("formspec", atc.get_atc_controller_formspec(pos, meta))
							end
							return
						end
						meta:set_string("mode", idxtrans[fields.mode])
						meta:set_string("command", fields.command)
						meta:set_string("command_on", fields.command_on)
						meta:set_string("channel", fields.channel)
						if fields.mode=="digiline" then
							meta:set_string("infotext", attrans("ATC controller, mode @1\nChannel: @2", (fields.mode or "?"), meta:get_string("command")) )
						else
							meta:set_string("infotext", attrans("ATC controller, mode @1\nCommand: @2", (fields.mode or "?"), meta:get_string("command")) )
						end
						meta:set_string("formspec", atc.get_atc_controller_formspec(pos, meta))
						
						local pts=minetest.pos_to_string(pos)
						local _, conns=advtrains.get_rail_info_at(pos, advtrains.all_tracktypes)
						atc.controllers[pts]={command=fields.command}
						if #advtrains.occ.get_trains_at(pos) > 0 then
							atc.send_command(pos)
						end
					end
				end)
			end,
			advtrains = {
				on_train_enter = function(pos, train_id)
					atc.send_command(pos)
				end,
			},
		}
end

function atc.get_atc_controller_formspec(pos, meta)
	local mode=tonumber(meta:get_string("mode")) or 1
	local command=meta:get_string("command")
	local command_on=meta:get_string("command_on")
	local channel=meta:get_string("channel")
	local formspec="size[8,6]"
	--	"dropdown[0,0;3;mode;static,mesecon,digiline;"..mode.."]"
	if mode<3 then
		formspec=formspec.."field[0.5,1.5;7,1;command;"..attrans("Command")..";"..minetest.formspec_escape(command).."]"
		if tonumber(mode)==2 then
			formspec=formspec.."field[0.5,3;7,1;command_on;"..attrans("Command (on)")..";"..minetest.formspec_escape(command_on).."]"
		end
	else
		formspec=formspec.."field[0.5,1.5;7,1;channel;"..attrans("Digiline channel")..";"..minetest.formspec_escape(channel).."]"
	end
	return formspec.."button_exit[0.5,4.5;7,1;save;"..attrans("Save").."]"
end

local function sub_atc_g(id, train, matchL, fullcmd, signalpos, descriptivename)
	local influencepoint_pts, iconnid = advtrains.interlocking.db.get_ip_by_signalpos(signalpos)
	local influencepoint = minetest.string_to_pos(influencepoint_pts)
	local is_green = true -- if all else fails we'll assume it was green (the same way if there's no influence point set, the signal is disregarded (and considered green)
	local found=false
	for k,v in ipairs(train.lzb.oncoming) do
		if vector.equals(v.pos,influencepoint) then
			is_green = ( v.spd == nil ) or ( v.spd >0.001 )
			found=true
			break
		end
	end

	if not found then
		local msg = minetest.pos_to_string(signalpos)
		if descriptivename then msg=msg.." ("..descriptivename..")" end
		msg=attrans("ATC G command warning: signal at @1 is not in the path of the train",msg)
		atwarn(sid(id), msg)
	end

	if is_green then
		return matchL
	end

	local mycmds = train.atc_command
	local a, b = string.find(mycmds,fullcmd,1,true)
	mycmds = string.sub(mycmds,b+1)
	advtrains.atc.set_commands_when_green(signalpos,id,mycmds)

	return #(train.atc_command)+1
end

--from trainlogic.lua train step
local matchptn={
	["B([0-9]+)"]=function(id, train, match)
		if train.velocity>tonumber(match) then
			train.atc_brake_target=tonumber(match)
			if not train.tarvelocity or train.tarvelocity>train.atc_brake_target then
				train.tarvelocity=train.atc_brake_target
			end
		end
		return #match+1
	end,
	["BB"]=function(id, train)
		train.atc_brake_target = -1
		train.tarvelocity = 0
		return 2
	end,
	["D([0-9]+)"]=function(id, train, match)
		train.atc_delay=tonumber(match)
		return #match+1
	end,
	["G([-]?%d+,[-]?%d+,[-]?%d+)"] = function(id, train, match)
		--it's G because we're waiting for the green signal
		local signalpos = minetest.string_to_pos(match)
		return sub_atc_g(id, train, #match+1, "G"..match, signalpos)
	end,
	["G%(([^)]+)%)"] = function(id, train, match)
		local signalpos = atlatc.pcnaming.resolve_pos(match)
		if signalpos then
			return sub_atc_g(id, train, #match+3, "G("..match..")", signalpos, match)
		else
			atwarn(sid(id), attrans("ATC G command warning: passive component named \"@1\" not found.",match))
			return #match+3
		end
	end,
	["K"] = function(id, train)
		if train.door_open == 0 then
			atwarn(sid(id), attrans("ATC Kick command warning: Doors closed"))
			return 1
		end
		if train.velocity > 0 then
			atwarn(sid(id), attrans("ATC Kick command warning: Train moving"))
			return 1
		end
		local tp = train.trainparts
		for i=1,#tp do
			local data = advtrains.wagons[tp[i]]
			local obj = advtrains.wagon_objects[tp[i]]
			if data and obj then
				local ent = obj:get_luaentity()
				if ent then
					for seatno,seat in pairs(ent.seats) do
						if data.seatp[seatno] and not ent:is_driver_stand(seat) then
							ent:get_off(seatno)
						end
					end
				end
			end
		end
		return 1
	end,
	["O([LRC])"]=function(id, train, match)
		local tt={L=-1, R=1, C=0}
		local arr=train.atc_arrow and 1 or -1
		train.door_open = tt[match]*arr
		return 2
	end,
	["R"]=function(id, train)
		if train.velocity<=0 then
			advtrains.invert_train(id)
			advtrains.train_ensure_init(id, train)
			-- no one minds if this failed... this shouldn't even be called without train being initialized...
		else
			atwarn(sid(id), attrans("ATC Reverse command warning: didn't reverse train, train moving!"))
		end
		return 1
	end,
	["S([0-9]+)"]=function(id, train, match)
		train.tarvelocity=tonumber(match)
		return #match+1
	end,
	["SM"]=function(id, train)
		train.tarvelocity=train.max_speed
		return 2
	end,
	["W"]=function(id, train)
		train.atc_wait_finish=true
		return 1
	end,
}

eval_conditional = function(command, arrow, speed)
	--conditional statement?
	local is_cond, cond_applies, compare
	local cond, rest=string.match(command, "^I([%+%-])(.+)$")
	if cond then
		is_cond=true
		if cond=="+" then
			cond_applies=arrow
		end
		if cond=="-" then
			cond_applies=not arrow
		end
	else 
		cond, compare, rest=string.match(command, "^I([<>]=?)([0-9]+)(.+)$")
		if cond and compare then
			is_cond=true
			if cond=="<" then
				cond_applies=speed<tonumber(compare)
			end
			if cond==">" then
				cond_applies=speed>tonumber(compare)
			end
			if cond=="<=" then
				cond_applies=speed<=tonumber(compare)
			end
			if cond==">=" then
				cond_applies=speed>=tonumber(compare)
			end
		end
	end	
	if is_cond then
		atprint("Evaluating if statement: "..command)
		atprint("Cond: "..(cond or "nil"))
		atprint("Applies: "..(cond_applies and "true" or "false"))
		atprint("Rest: "..rest)
		--find end of conditional statement
		local nest, pos, elsepos=0, 1
		while nest>=0 do
			if pos>#rest then
				atwarn(sid(id), attrans("ATC command syntax error: I statement not closed: @1",command))
				return ""
			end
			local char=string.sub(rest, pos, pos)
			if char=="I" then
				nest=nest+1
			end
			if char==";" then
				nest=nest-1
			end
			if nest==0 and char=="E" then
				elsepos=pos+0
			end
			pos=pos+1
		end
		if not elsepos then elsepos=pos-1 end
		if cond_applies then
			command=string.sub(rest, 1, elsepos-1)..string.sub(rest, pos)
		else
			command=string.sub(rest, elsepos+1, pos-2)..string.sub(rest, pos)
		end
		atprint("Result: "..command)
	end
	return command
end

function atc.execute_atc_command(id, train)
	--strip whitespaces
	local command=string.match(train.atc_command, "^%s*(.*)$")
	
	
	if string.match(command, "^%s*$") then
		train.atc_command=nil
		return
	end

	train.atc_command = eval_conditional(command, train.atc_arrow, train.velocity)
	
	if not train.atc_command then return end
	command=string.match(train.atc_command, "^%s*(.*)$")
	
	if string.match(command, "^%s*$") then
		train.atc_command=nil
		return
	end
	
	for pattern, func in pairs(matchptn) do
		local match=string.match(command, "^"..pattern)
		if match then
			local patlen=func(id, train, match)
			
			atprint("Executing: "..string.sub(command, 1, patlen))
			
			train.atc_command=string.sub(command, patlen+1)
			if train.atc_delay<=0 and not train.atc_wait_finish then
				--continue (recursive, cmds shouldn't get too long, and it's a end-recursion.)
				atc.execute_atc_command(id, train)
			end
			return
		end
	end
	atwarn(sid(id), attrans("ATC command parse error: Unknown command: @1", command))
	atc.train_reset_command(train, true)
end


-- registers commands for given train for the event of given signal turning green
function atc.set_commands_when_green(signal_pos,train_id,cmd)
	local pts = advtrains.roundfloorpts(signal_pos)
	if not atc.cmds_for_signals[pts] then
		atc.cmds_for_signals[pts]={}
	end
	atc.cmds_for_signals[pts][train_id]=cmd
end


-- signal turned green callback
function atc.signal_is_green(signal_pos)
	local pts = advtrains.roundfloorpts(signal_pos)
	local mylist=atc.cmds_for_signals[pts]
	if not mylist then return end
	for train_id,cmd in pairs(mylist) do
		local thistrain=advtrains.trains[train_id]
		if thistrain then
			advtrains.atc.train_set_command(thistrain, cmd, true)
		end
	end
	atc.cmds_for_signals[pts]=nil
end


--we have 3 routines for signal_refcount: add new reference, subtract reference, query the number of references. for add and subtract nil is accepted as parameter for simplicity of usage
function atc.add_signal_reference(signalpos)
	if signalpos == nil then return end
	local pts = advtrains.roundfloorpts(signalpos)
	if atc.signal_refcount[pts] == nil then
		atc.signal_refcount[pts] = 1
	else
		atc.signal_refcount[pts] = atc.signal_refcount[pts] + 1
	end
end
function atc.subtract_signal_reference(signalpos)
	if signalpos == nil then return end
	local pts=advtrains.roundfloorpts(signalpos)
	if atc.signal_refcount[pts] == 1 then
		atc.signal_refcount[pts] = nil
	else
		atc.signal_refcount[pts] = atc.signal_refcount[pts] - 1
	end
end
function atc.get_signal_referencecount(signalpos)
	local pts = advtrains.roundfloorpts(signalpos)
	local num = atc.signal_refcount[pts]
	return num or 0
end


-- returns the signal for the stoprail at given position, if this is known
function atc.get_signal_for_stoprail(stoprailpos)
	local pts = advtrains.roundfloorpts(stoprailpos)
	return atc.signal_to_stoprail[pts]
end
function atc.set_signal_for_stoprail(stoprailpos, signalpos)
	local pts_stoprail = advtrains.roundfloorpts(stoprailpos)
	atc.subtract_signal_reference(atc.signal_to_stoprail[pts_stoprail])
	atc.signal_to_stoprail[pts_stoprail] = signalpos
	atc.add_signal_reference(signalpos)
end


function atc.signal_can_dig(pos)
	if advtrains.interlocking and not advtrains.interlocking.signal_can_dig(pos) then
		return false
	end
	return atc.get_signal_referencecount(pos) == 0
end


function atc.signal_after_dig(pos)
	atc.signal_is_green(pos)
	if advtrains.interlocking then
		advtrains.interlocking.signal_after_dig(pos)
	end
end


--move table to desired place
advtrains.atc=atc
