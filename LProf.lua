--[[
	LProf v1.3, by Luke Perkin 2012. MIT Licence http://www.opensource.org/licenses/mit-license.php.
	
	Example:
		LProf = require 'LProf'
		LProf:start()
		some_function()
		another_function()
		coroutine.resume( some_coroutine )
		LProf:stop()
		LProf:writeReport( 'MyProfilingReport.txt' )

	API:
	*Arguments are specified as: type/name/default.
		LProf:start( string/once/nil )
		LProf:stop()
		LProf:checkMemory( number/interval/0, string/note/'' )
		LProf:writeReport( string/filename/'LProf.txt' )
		LProf:reset()
		LProf:setHookCount( number/hookCount/0 )
		LProf:setGetTimeMethod( function/getTimeMethod/os.clock )
		LProf:setInspect( string/methodName, number/levels/1 )
]]

-----------------------
-- Locals:
-----------------------
local socket = require "socket"
local max_depth = 0
local LProf = {}
local onDebugHook, sortByDurationDesc, sortByCallCount, getTime
local DEFAULT_DEBUG_HOOK_COUNT = 0
local DEPTH_WIDTH			   = 6
local FORMAT_HEADER_LINE       = "| %-50s: %-40s: %-20s: %-12s: %-12s: %-12s|\n"
local FORMAT_OUTPUT_LINE       = "| %s: %-12s: %-12s: %-12s|\n"
local FORMAT_INSPECTION_LINE   = "> %s: %-12s\n"
local FORMAT_TOTALTIME_LINE    = "| TOTAL TIME = %f\n"
local FORMAT_MEMORY_LINE 	   = "| %-20s: %-16s: %-16s| %s\n"
local FORMAT_HIGH_MEMORY_LINE  = "H %-20s: %-16s: %-16sH %s\n"
local FORMAT_LOW_MEMORY_LINE   = "L %-20s: %-16s: %-16sL %s\n"
local FORMAT_TITLE             = "%-90.90s: %-30.30s: %-10s"
local FORMAT_TITLE_KEY		   = "%s : %s : %d"
local FORMAT_LINENUM           = "%4i"
local FORMAT_TIME              = "%04.6f"
local FORMAT_RELATIVE          = "%03.4f%%"
local FORMAT_COUNT             = "%7i"
local FORMAT_DEPTH             = "%5i"
local FORMAT_KBYTES  		   = "%7i Kbytes"
local FORMAT_MBYTES  		   = "%7.1f Mbytes"
local FORMAT_MEMORY_HEADER1    = "\n=== HIGH & LOW MEMORY USAGE ===============================\n"
local FORMAT_MEMORY_HEADER2    = "=== MEMORY USAGE ==========================================\n"
local FORMAT_BANNER 		   = [[
###############################################################################################################
#####  LProf, a lua profiler. This profile was generated on: %s
#####  LProf is created by Luke Perkin 2012 under the MIT Licence, www.locofilm.co.uk
#####  Version 1.3. Get the most recent version at this gist: https://gist.github.com/2838755
###############################################################################################################

]]


-----------------------
-- Stack Table:
-----------------------
-- Since I can't figure out how to call code in other files without luarocks complaining about EVERYTHING
-- Stack Table
-- Uses a table as stack, use <table>:push(value) and <table>:pop()
-- Lua 5.1 compatible

-- GLOBAL
local Stack = {}

-- Create a Table with stack functions
function Stack:Create()

  -- stack table
  local t = {}
  -- entry table
  t._et = {}

  -- push a value on to the stack
  function t:push(...)
    if ... then
      local targs = {...}
      -- add values
      for _,v in ipairs(targs) do
        table.insert(self._et, v)
      end
    end
  end

  -- pop a value from the stack
  function t:pop(num)

    -- get num values from stack
    local num = num or 1

    -- return table
    local entries = {}

    -- get values into entries
    for i = 1, num do
      -- get last entry
      if #self._et ~= 0 then
        table.insert(entries, self._et[#self._et])
        -- remove last value
        table.remove(self._et)
      else
        break
      end
    end
    -- return unpacked entries
    return unpack(entries)
  end

  -- peek at the top of the stack
  function t:peek(num)
    -- get last entry
    if #self._et ~= 0 and not num then
    	return self._et[#self._et]
    elseif #self._et ~= 0 and num then
    	return self._et[num]
    else
    	return nil
	end
  end

  -- get entries
  function t:getn()
    return #self._et
  end

  -- list values
  function t:list()
    for i,v in pairs(self._et) do
      print(i, v)
    end
  end
  return t
end

-- CHILLCODE™

-----------------------
-- Public Methods:
-----------------------

--[[
	Starts profiling any method that is called between this and LProf:stop().
	Pass the parameter 'once' to so that this methodis only run once.
	Example: 
		LProf:start( 'once' )
]]
function LProf:start( param )
	if param == 'once' then
		if self:shouldReturn() then
			return
		else
			self.should_run_once = true
		end
	end
	self.has_started  = true
	self.has_finished = false
	self:resetReports( self.reports )
	self:startHooks()
	self.startTime = getTime()
end

--[[
	Stops profiling.
]]
function LProf:stop()
	if self:shouldReturn() then 
		return
	end
	self.stopTime = getTime()
	self:stopHooks()
	self.has_finished = true
	local funcInfo = debug.getinfo( 2, 'nS' )
	LProf:onFunctionReturn( funcInfo )
end

function LProf:checkMemory( interval, note )
	local time = getTime()
	local interval = interval or 0
	if self.lastCheckMemoryTime and time < self.lastCheckMemoryTime + interval then
		return
	end
	self.lastCheckMemoryTime = time
	local memoryReport = {
		['time']   = time;
		['memory'] = collectgarbage('count');
		['note']   = note or '';
	}
	table.insert( self.memoryReports, memoryReport )
	self:setHighestMemoryReport( memoryReport )
	self:setLowestMemoryReport( memoryReport )
end

--[[
	Writes the profile report to a file.
	Param: [filename:string:optional] defaults to 'LProf.txt' if not specified.
]]
function LProf:writeReport( filename )
	if #self.reports > 0 or #self.memoryReports > 0 then
		filename = filename or 'LProf.txt'
		-- self:sortReportsWithSortMethod( self.reports, self.sortMethod )
		self:writeReportsToFilename( filename )
		print( string.format("[LProf]\t Report written to %s", filename) )
	end
end

--[[
	Resets any profile information stored.
]]
function LProf:reset()
	self.reports = {}
	self.reportsByTitle = {}
	self.memoryReports  = {}
	self.highestMemoryReport = nil
	self.lowestMemoryReport  = nil
	self.has_started  = false
	self.has_finished = false
	self.should_run_once = false
	self.lastCheckMemoryTime = nil
	self.hookCount = self.hookCount or DEFAULT_DEBUG_HOOK_COUNT
	self.sortMethod = self.sortMethod or sortByDurationDesc
	self.inspect = {}
	self.nameWidth = 8 -- length of the header string "FUNCTION"
	self.sourceWidth = 4 -- length of the header string "FILE"
	self.linedefinedWidth = 4 -- length of the header string "LINE"
	self.timerWidth = 4 -- length of the header string "TIME"
	self.countWidth = 6 -- length of the header string "CALLED"
	self.relTimeWidth = 8 -- length of the header string "RELATIVE"
	self.finalReport = nil
	self.firstReport = {}
end

--[[
	Set how often a hook is called.
	See http://pgl.yoyo.org/luai/i/debug.sethook for information.
	Param: [hookCount:number] if 0 LProf counts every time a function is called.
	if 2 LProf counts every other 2 function calls.
]]
function LProf:setHookCount( hookCount )
	self.hookCount = hookCount
end

--[[
	Set how the report is sorted when written to file.
	Param: [sortType:string] either 'duration' or 'count'.
	'duration' sorts by the time a method took to run.
	'count' sorts by the number of times a method was called.
]]
function LProf:setSortMethod( sortType )
	if sortType == 'duration' then
		self.sortMethod = sortByDurationDesc
	elseif sortType == 'count' then
		self.sortMethod = sortByCallCount
	end
end

--[[
	By default the getTime method is os.clock (CPU time),
	If you wish to use other time methods pass it to this function.
	Param: [getTimeMethod:function]
]]
function LProf:setGetTimeMethod( getTimeMethod )
	getTime = getTimeMethod
end

--[[
	Allows you to inspect a specific method.
	Will write to the report a list of methods that
	call this method you're inspecting, you can optionally
	provide a levels parameter to traceback a number of levels.
	Params: [methodName:string] the name of the method you wish to inspect.
	        [levels:number:optional] the amount of levels you wish to traceback, defaults to 1.
]]
function LProf:setInspect( methodName, levels )
	print("setting method name: " .. methodName .. " to inspect up to levels: " .. levels)
	if self.inspect[methodName] == nil then
		self.inspect[methodName] = levels or 1
		print(string.format("Set inspect on %s, %d", methodName, self.inspect[methodName]))
	else
		print(string.format("Tried to set inspection on method %s more than once.", methodName))
	end
end

-----------------------
-- Implementations methods:
-----------------------

function LProf:shouldReturn( )
	return self.should_run_once and self.has_finished
end

function LProf:startHooks()
	local funcInfo = debug.getinfo( 2, 'nS' )
	self.firstReport = {
		['name']        = '$$ROOT$$';
		['source']      = 'BEGIN';
		['linedefined'] = 0;
		['count'] 		= {};
		['timer']      	= {};
		['callees'] 	= {};
	}
	self.prevReport = Stack:Create()  
	self.prevReport:push(self.firstReport)
	print(string.format("stack size %d\n", self.prevReport:getn()))
	self.prevReport:push(LProf:onFunctionCall( funcInfo ))
	debug.sethook( onDebugHook, 'cr', self.hookCount )
end

function LProf:stopHooks()
	debug.sethook()
end

function LProf:sortReportsWithSortMethod( reports, sortMethod )
	if reports then
		table.sort( reports, sortMethod )
	end
end

function LProf:writeReportsToFilename( filename )
	local file, err = io.open( filename, 'w' )
	assert( file, err )
	self:writeBannerToFile( file )
	if #self.reports > 0 then
		self:writeProfilingReportsToFile( self.reports, file )
	end
	if #self.memoryReports > 0 then
		self:writeMemoryReportsToFile( self.memoryReports, file )
	end
	file:close()
end

function LProf:writeProfilingReportsToFile( reports, file )
	local totalTime = self.stopTime - self.startTime
	local totalTimeOutput =  string.format(FORMAT_TOTALTIME_LINE, totalTime)
	file:write( totalTimeOutput )
	for i, funcReport in pairs( reports ) do
		for j, timer in pairs(funcReport.timer) do
			local timerStr = string.format("%04.6f", timer)
			if string.len(timerStr) > self.timerWidth then
				self.timerWidth = string.len(timerStr)
			end
			local relTimeStr = string.format("%03.4f", (timer / totalTime) * 100)
			if string.len(relTimeStr) > self.relTimeWidth then
				self.relTimeWidth = string.len(relTimeStr)
			end
		end
		for j, count in pairs(funcReport.count) do
			local countStr = string.format("%7i", count)
			if string.len(countStr) > self.countWidth then
				self.countWidth = string.len(countStr)
			end
		end
	end
	local headerFormat = "|    %-" .. self.nameWidth + 13 - max_depth*2 .. "s: %-" .. self.sourceWidth + 1 .. "s: %-" .. self.linedefinedWidth + 1 .. "s: %-" .. self.timerWidth + 1 .."s: %-" .. self.relTimeWidth + 1 .. "s: %-" .. self.countWidth .. "s|\n"
	local header = string.format( headerFormat, "FILE", "FUNCTION", "LINE", "TIME", "RELATIVE", "CALLED" )
	-- file:write( header )
	local stack = Stack:Create()
	stack:push(self.firstReport)
	print(string.format("Stack depth %d: type: %s", stack:getn() or -1, type(stack)))
	self:RecurseStackVisit(stack, totalTime, "", outputFormat, header, file)
end

function LProf:RecurseStackVisit(stack, totalTime, indent, outputFormat, header, file)
	if ( stack == nil ) or ( type(stack) ~= "table" ) then
		if ( type(stack) ~= "table" ) then
			print("Somehow a non-stack got passed into RecurseStackVisit: " .. type(stack))
		else
			print("Somehow a nil stack got passed into RecurseStackVisit.")
		end
		return;
	end
	local top = stack:peek()
	if top ~= nil then
		print(string.format("Stack depth: %d, current top: %s, number of children: %d", stack:getn(), stack:peek().name, #stack:peek().callees))
	else
		print(string.format("Stack depth: %d", stack:getn() or -1))
	end
	while stack:getn() == 0 do return end
	local top = stack:peek()
	local c = 0
	local depth = 0
	if top ~= nil then
		if stack:getn() > 1 then
			indent = string.rep("|  ", stack:getn() - 1) .. "|--"
		else
			indent = "***"
		end
		table.sort(top.callees, sortMethod)
		print(string.format("Callees: %d", self:tablelength(top.callees)))
		--file:write( header )
	 	for i, funcReport in pairs( top.callees ) do
	 		local outputFormat = "%s %-" .. self.nameWidth + 13 - (max_depth - depth)*2 .. "." .. self.nameWidth + 13 - (max_depth - depth)*2 .. "s: %-" .. self.sourceWidth + 1 .. "." ..  self.sourceWidth + 1 .. "s: %-" .. self.linedefinedWidth + 1 .. "s: %-" .. self.timerWidth + 1 .."s: %-" .. self.relTimeWidth + 1 .. "s:%-" .. self.countWidth + 1 .. "s|\n"
	
	 		print(string.format("Processing child of method %s. Function: %s", top.name, funcReport.name))
			local timer         = string.format(FORMAT_TIME, funcReport.timer[top.name])
			local count         = string.format("%" .. self.countWidth .. "i", funcReport.count[top.name])
			local relTime 		= string.format(FORMAT_RELATIVE, (funcReport.timer[top.name] / totalTime) * 100 )
			local outputLine    = string.format(outputFormat, indent, funcReport.name, funcReport.source, funcReport.linedefined, timer, relTime, count )
			print(outputLine)
			file:write( outputLine )
			if funcReport.inspections then
				self:writeInpsectionsToFile( funcReport.inspections, file )
			end
			local skip = false
			for t = 1, stack:getn() do

				print("t name: " .. stack:peek(t).name .. " funcReport name " .. funcReport.name)
				if stack:peek(t).name == funcReport.name then
					skip = true
					break
				end
			end
			if not skip then
				stack:push(funcReport)
				depth = depth + 1
				self:RecurseStackVisit(stack, totalTime, indent, outputFormat, header, file)
				c = c + 1
			end
		end
	end
	print("Stack pop.")
	depth = depth - 1
	_ = stack:pop()
	indent = string.sub(indent, 3)
end

function LProf:writeMemoryReportsToFile( reports, file )
	file:write( FORMAT_MEMORY_HEADER1 )
	self:writeHighestMemoryReportToFile( file )
	self:writeLowestMemoryReportToFile( file )
	file:write( FORMAT_MEMORY_HEADER2 )
	for i, memoryReport in ipairs( reports ) do
		local outputLine = self:formatMemoryReportWithFormatter( memoryReport, FORMAT_MEMORY_LINE )
		file:write( outputLine )
	end
end

function LProf:writeHighestMemoryReportToFile( file )
	local memoryReport = self.highestMemoryReport
	local outputLine   = self:formatMemoryReportWithFormatter( memoryReport, FORMAT_HIGH_MEMORY_LINE )
	file:write( outputLine )
end

function LProf:writeLowestMemoryReportToFile( file )
	local memoryReport = self.lowestMemoryReport
	local outputLine   = self:formatMemoryReportWithFormatter( memoryReport, FORMAT_LOW_MEMORY_LINE )
	file:write( outputLine )
end

function LProf:formatMemoryReportWithFormatter( memoryReport, formatter )
	local time       = string.format(FORMAT_TIME, memoryReport.time)
	local kbytes     = string.format(FORMAT_KBYTES, memoryReport.memory)
	local mbytes     = string.format(FORMAT_MBYTES, memoryReport.memory/1024)
	local outputLine = string.format(formatter, time, kbytes, mbytes, memoryReport.note)
	return outputLine
end

function LProf:writeBannerToFile( file )
	local banner = string.format(FORMAT_BANNER, os.date())
	file:write( banner )
end

function LProf:writeInpsectionsToFile( inspections, file )
	local inspectionsList = self:sortInspectionsIntoList( inspections )
	local lenBeforeCount = 2 + self.sourceWidth + 1 + 2 + self.nameWidth + 1 + 2 + self.linedefinedWidth + 2
	local inspectionFormat = "> %-" .. self.sourceWidth + 1 .. "." ..  self.sourceWidth + 1 .. "s: %-" .. self.nameWidth + 1 .. "." .. self.nameWidth + 1 .. "s: %-" .. self.linedefinedWidth + 1 .. "s: %-" .. DEPTH_WIDTH .. "s:%-" .. self.countWidth + 1 .. "s\n"
	for i, inspection in ipairs( inspectionsList ) do
		file:write('\n==^ INSPECT ^' .. string.rep("=", lenBeforeCount - 13) .. " DEPTH = COUNT =\n")
		for j, inspect_line in ipairs( inspection ) do
			local line 			= string.format(FORMAT_LINENUM, inspect_line.line)
			local count         = string.format("%" .. self.countWidth .. "i", inspect_line.count)
			local depth         = string.format(FORMAT_DEPTH, inspect_line.depth)
			local outputLine    = string.format(inspectionFormat, inspect_line.source, inspect_line.name, line, depth, count)
			file:write( outputLine )
		end
	end
	file:write(string.rep("=", lenBeforeCount + 16) .. '\n')
end

function LProf:sortInspectionsIntoList( inspections )
	local inspectionsList = {}
	for k, inspection in pairs(inspections) do
		inspectionsList[#inspectionsList+1] = inspection
	end
	table.sort( inspectionsList, sortByCallCount )
	return inspectionsList
end

function LProf:resetReports( reports )
	for i, report in ipairs( reports ) do
		report.timer = 0
		report.count = 0
		report.inspections = {}
	end
end

function LProf:shouldInspect( funcInfo )
	return self.inspect[funcInfo.name] ~= nil
end

function LProf:getInspectionsFromReport( funcReport )
	local inspections = funcReport.inspections
	if not inspections then
		inspections = {}
		funcReport.inspections = inspections
	end
	return inspections
end

function LProf:getInspectionWithKeyFromInspections( key, inspections )
	local inspection = inspections[key]
	if not inspection then
		inspection = {}
		inspections[key] = inspection
	end
	return inspection
end

function LProf:doInspection( levels, funcReport )
	local inspections = self:getInspectionsFromReport( funcReport )
	local levels = 5 + levels
	local currentLevel = 5
	local key = ''
	while currentLevel < levels do
		local funcInfo = debug.getinfo( currentLevel, 'nS' )
		if funcInfo then
			local source = funcInfo.short_src or '[C]'
			local name = funcInfo.name or 'anonymous'
			local line = funcInfo.linedefined
			local lineStr = string.format(FORMAT_LINENUM, line)
			if string.len(source) > self.sourceWidth then
				self.sourceWidth = string.len(source)
			end
			if string.len(name) > self.nameWidth then
				self.nameWidth = string.len(name)
			end
			if string.len(lineStr) > self.linedefinedWidth then
				self.linedefinedWidth = string.len(lineStr)
			end
			key = key..source..name..line..currentLevel
			currentLevel = currentLevel + 1
		else
			break
		end
	end
	currentLevel = 5
	local count = 0
	local inspection = self:getInspectionWithKeyFromInspections( key, inspections )
	local new = false
	if next(inspection) == nil then
		new = true
	end
	while currentLevel < levels do
		local funcInfo = debug.getinfo( currentLevel, 'nS' )
		if funcInfo then
			local source = funcInfo.short_src or '[C]'
			local name = funcInfo.name or 'anonymous'
			local line = funcInfo.linedefined
			if new then
				inspection[count] = {
					['source']  = source;
					['name'] = name;
					['line'] = line;
					['depth'] = currentLevel - 5;
					['count'] = 1;
				}
			else
				local countStr = string.format(FORMAT_COUNT, inspection[count].count)
				if string.len(countStr) > self.countWidth then
					self.countWidth = string.len(countStr)
				end
				inspection[count].count = inspection[count].count + 1
			end
			inspection[count].level = currentLevel
			currentLevel = currentLevel + 1
			count = count + 1
		else
			break
		end
	end
end

function LProf:getFuncReport( funcInfo, ret)
	local title = self:getTitleFromFuncInfo( funcInfo )
	print("Generated title: " .. title)
	local funcReport = self.reportsByTitle[ title ]

	if not funcReport then
		funcReport = self:createFuncReport( funcInfo )
		self.reportsByTitle[ title ] = funcReport
		table.insert( self.reports, funcReport )
	end
	if self.prevReport:peek().callees[title] == nil and not ret then
		self.prevReport:peek().callees[title] = funcReport
		print(string.format("Adding child %s to parent %s\nTITLE: %s, Parent TITLE: %s : %s : %d", funcReport.name, self.prevReport:peek().name, title, self.prevReport:peek().source, self.prevReport:peek().name, self.prevReport:peek().linedefined))
		print(string.format("Parent %s now has %d children. Callee name: XK", self.prevReport:peek().name, self:tablelength(self.prevReport:peek().callees)))
	end

	return funcReport
end

function LProf:tablelength(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

function LProf:getTitleFromFuncInfo( funcInfo )
	local name        = funcInfo.name or 'anonymous'
	local source      = funcInfo.short_src or 'C_FUNC'
	local linedefined = funcInfo.linedefined or 0
	return string.format(FORMAT_TITLE_KEY, source, name, linedefined)
end

function LProf:getTitleFromFuncReport( funcReport )
	local name        = funcReport.name or 'anonymous'
	local source      = funcReport.source or 'C_FUNC'
	local linedefined = funcReport.linedefined or 0
	return string.format(FORMAT_TITLE_KEY, source, name, linedefined)
end

function LProf:createFuncReport( funcInfo )
	local name = funcInfo.name or 'anonymous'
	local source = funcInfo.source or 'C Func'
	local linedefined = funcInfo.linedefined or 0
	linedefined = string.format( '%4i', linedefined )
	if string.len(name) > self.nameWidth then
		self.nameWidth = string.len(name)
	end
	if string.len(source) > self.sourceWidth then
		self.sourceWidth = string.len(source)
	end
	if string.len(linedefined) > self.linedefinedWidth then
		self.linedefinedWidth = string.len(linedefined)
	end
	local funcReport = {
		['name']        = name;
		['source']      = source;
		['linedefined'] = linedefined;
		['count'] 		= {};
		['timer']      	= {};
		['callees'] 	= {};
		['callTime']    = 0.0;
		['parent']      = '';
		['id']			= -1;
	}
	return funcReport
end
call_count = 0
return_count = 0
id = 0
function LProf:onFunctionCall( funcInfo )
	call_count = call_count + 1
	print("onFuncCall: " .. funcInfo.name .. ", prev size: " .. self.prevReport:getn() .. " call count: " .. call_count)
	local prev = self.prevReport:peek()
	local funcReport = LProf:getFuncReport( funcInfo, false )
	funcReport.parent = prev.name;
	funcReport.callTime = getTime()
	funcReport.id = id
	id = id + 1
	print(string.format("^^^ Getting calltime %f, for id %d with prevName: %s", funcReport.callTime, funcReport.id, prev.name))
	if funcReport.count[prev.name] == nil then
		funcReport.count[prev.name] = 0
	else
		funcReport.count[prev.name] = funcReport.count[prev.name] + 1
	end
	if funcReport.timer[prev.name] == nil then
		funcReport.timer[prev.name] = 0.0
	end
	if self:shouldInspect( funcInfo ) then
		self:doInspection( self.inspect[funcInfo.name or 'anonymous'], funcReport )
	end
	self.prevReport:push(funcReport)
	if self.prevReport:getn() > max_depth then
		max_depth = self.prevReport:getn()
	end
	return funcReport
end

function LProf:onFunctionReturn( funcInfo )
	return_count = return_count + 1
	print("onFuncReturn: " .. (funcInfo.name or 'anonymous') .. ", prev size: " .. self.prevReport:getn() .. " return count: " .. return_count)
	-- if self.prevReport:getn() > 1 then
	-- 	self.prevReport:pop()
	-- end
	local funcReport = LProf:getFuncReport( funcInfo, true )
	print("id: " .. funcReport.id .. " parent " .. funcReport.parent .. " ")

	while self.prevReport:getn() > 1 do
		if self.prevReport:peek().name == "$$ROOT$$" or funcReport.parent == self.prevReport:peek().name then
			break
		end
		self.prevReport:pop()
	end
	local prev = self.prevReport:peek()
	print(string.format("Previous function after return: %s", self.prevReport:peek().name))
	print(string.format("FuncReport: %s, %s, %d, %f", funcReport.name, funcReport.source, funcReport.linedefined, funcReport.callTime or -9999.99))
	if funcReport.callTime and funcReport.timer[prev.name] ~= nil then
		print(string.format("CallTime prev.name: %s, timer %f, calltime %f, current time: %f", prev.name, funcReport.timer[prev.name], funcReport.callTime, getTime()))
		funcReport.timer[prev.name] = funcReport.timer[prev.name] + (getTime() - funcReport.callTime)
	end
	return funcReport
end

function LProf:setHighestMemoryReport( memoryReport )
	if not self.highestMemoryReport then
		self.highestMemoryReport = memoryReport
	else
		if memoryReport.memory > self.highestMemoryReport.memory then
			self.highestMemoryReport = memoryReport
		end
	end
end

function LProf:setLowestMemoryReport( memoryReport )
	if not self.lowestMemoryReport then
		self.lowestMemoryReport = memoryReport
	else
		if memoryReport.memory < self.lowestMemoryReport.memory then
			self.lowestMemoryReport = memoryReport
		end
	end
end

-----------------------
-- Local Functions:
-----------------------

getTime = socket.gettime

onDebugHook = function( hookType )
	local funcInfo = debug.getinfo( 2, 'nS' )
	if hookType == "call" then
		LProf:onFunctionCall( funcInfo )
	elseif hookType == "return" then
		LProf:onFunctionReturn( funcInfo )
	end
end

sortByDurationDesc = function( a, b )
	return a.timer > b.timer
end

sortByCallCount = function( a, b )
	return a[0].count > b[0].count
end

-----------------------
-- Return Module:
-----------------------

LProf:reset()
return LProf