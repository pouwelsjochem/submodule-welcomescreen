------------------------------------------------------------------------------
--
-- This file is part of the Corona game engine.
-- For overview and more information on licensing please refer to README.md 
-- Home page: https://github.com/coronalabs/corona
-- Contact: support@coronalabs.com
--
------------------------------------------------------------------------------

local simErr, simulator = pcall(require, "simulator")
if not simErr then
	simulator = require "simulator_stub"
end
local json = require "json"
local lfs = require "lfs"

-- Reference locals
local stage = display.getCurrentStage()
local screenW, screenH = display.contentWidth, display.contentHeight
local halfW, halfH = screenW*.5, screenH*.5
local platform = system.getInfo( "platformName" )
local userHome = nil
if platform == "Mac OS X" then
	userHome = os.getenv("HOME")
end

local uiFont = "HelveticaNeue"
local dirSeparator = "/"
if platform == "Win" then
	uiFont = "Arial"
	dirSeparator = "\\"
end


-- Colors and fonts
local windowBackgroundColor = { 29/255 , 29/255 , 29/255, 1 }
local topBlockBackgroundColor = { 37/255, 37/255, 37/255, 1 }
local linesColor = { 1, 1, 1, 10/100}
local hintsBGColor = { 37/255, 37/255, 37/255, 1 }

local tabColorSelected = {238/255, 238/255, 238/255, 1}
local tabColorHidden = {159/255, 159/255, 159/255, 1}

local textColorNormal = tabColorSelected
local textColorSelected = { 249/255, 111/255, 41/255, 1 }

local textColorLinks = {177/255,177/255,177/255,1}

local textColorCopyright = { 115/255, 115/255, 115/255 }

local textColorHits = { 165/255, 165/255, 165/255 }

local fontSizeTabBar = 17.5
local fontSizeProjectButtons = 17.5
local fontSizeSections = 17.5
local fontSizeLinkAndNews = 12.5
local fontSizeTooltip = 11
local fontSizeCopyright = 10
local fontSizeRecetProjectName = 15
local fontSizeRecetProjectPath = 12.5

local fontRegular = native.newFont("Exo2-Regular", 35)
local fontBold = native.newFont("Exo2-Bold", 35)


-- Local module vars/groups/etc
local uiTouchesDisabled = false
local isRetinaEnabled = (platform == "Mac OS X")

-- Log analytics when opening URLs
local function OpenURL(url, tag)
	local tag = tag or url
	system.openURL(url)
	simulator.analytics("welcome", "link", tag)
end

-- Creating Pointer Location variable to hold all the pointer location data
-- Need this inorder to disable and enable the mouse pointers
local g_pointerLocations = {}
g_pointerLocations.button = {}
g_pointerLocations.button.text = {}
g_pointerLocations.button.image = {}
g_pointerLocations.project = {}
g_pointerLocations.quickLink = {}
g_pointerLocations.feeds = {}
g_pointerLocations.chrome = {}

-- Limit the length of displayed strings to some number of pixels
local function limitDisplayLength(len, str, font, fontSize, isPath)
	local process
	local origStr = str
	local txtObj = nil
	repeat
		txtObj = display.newText( str, 0, 0, font, fontSize )
		width = txtObj.width
		txtObj:removeSelf( )
		if width > len and str:len() > 3 then
			str = str:gsub('...$', '') -- reduce length of string by 3 characters
			-- str = str .. "…" -- this messes things up because … is a UTF-8 character
		end
	until width <= len

    -- return the possibly trimmed string and add an elipsis if it was trimmed
	return str .. (str ~= origStr and "…" or "")
end


-- Functions to enable and remove pointers

local function setPointers(element, cursor) --Will set pointer for all elements in array
	if element then
		for k, v in pairs(element) do
			local location = v
			location.cursor = cursor
			simulator.setCursorRect(location)
		end
	end
end

local function setPointer(element, cursor) --Will set pointer to single element
	element.cursor = cursor
	simulator.setCursorRect(element)
end

local function removeAllPointers()
	-- Method to remove simulator pointing arrow
	local cursor = "none"

	setPointers(g_pointerLocations.button.text,cursor)
	setPointers(g_pointerLocations.button.image,cursor)
	setPointers(g_pointerLocations.project,cursor)
	setPointers(g_pointerLocations.link,cursor)
	setPointers(g_pointerLocations.feeds,cursor)
	setPointers(g_pointerLocations.chrome,cursor)
end

local function restoreAllPointers()
	-- Method to remove simulator pointing arrow
	local cursor = "pointingHand"

	setPointers(g_pointerLocations.button.text,cursor)
	setPointers(g_pointerLocations.button.image,cursor)
	setPointers(g_pointerLocations.project,cursor)
	setPointers(g_pointerLocations.link,cursor)
	setPointers(g_pointerLocations.feeds,cursor)
	setPointers(g_pointerLocations.chrome,cursor)
end


-----------------------------------------------------------------------------------------


local hovered = {}
local hoveredListeners = {}
local function howerListener(event)
	if event.target == nil then
		for k, v in pairs(hoveredListeners) do
			if (not hovered[k]) == (not hovered[k]) and v.state == (not hovered[k]) then
				v.state = not (not hovered[k])
				for i=1,#v.listeners do
					v.listeners[i](v.state)
				end
			end
		end
		hovered = {}
	else
		hovered[event.target] = true
	end
end

local function addHoverObject(object, onHover)
	if hoveredListeners[object] then
		hoveredListeners[object].listeners[#hoveredListeners[object].listeners + 1] = onHover
	else
		object:addEventListener( "mouse", howerListener )
		hoveredListeners[object] = {
			state = false,
			listeners = {onHover,},
		}
	end
end

Runtime:addEventListener("mouse", howerListener)



-----------------------------------------------------------------------------------------

-- Functions to enable/disable uiTouches (used as an onComplete listeners for some transitions)
local enableTouches = function()
	uiTouchesDisabled = false
end

local disableTouches = function()
	uiTouchesDisabled = true
end

local function unescape(str)
  str = string.gsub( str, '&lt;', '<' )
  str = string.gsub( str, '&gt;', '>' )
  str = string.gsub( str, '&quot;', '"' )
  str = string.gsub( str, '&apos;', "'" )
  str = string.gsub( str, '&mdash;', "-" )
  str = string.gsub( str, '&ndash;', "-" )
  str = string.gsub( str, '&#(%d+);', function(n) return (tonumber(n) > 255 and "" or string.char(n)) end )
  str = string.gsub( str, '&amp;', '&' ) -- and finally ...
  return str
end


-----------------------------------------------------------------------------------------

local function jsonFile( filename, base )
	base = base or system.ResourceDirectory
	local path = system.pathForFile( filename, base )
	local contents
	local file = io.open( path, "r" )
	if file then
		contents = file:read( "*a" )
		io.close( file ) -- close the file after using it
	end
	return contents
end


-----------------------------------------------------------------------------------------
-- Utility Functions
local function scaleForRetina( text )
	if isRetinaEnabled then
		text.xScale = 0.5
		text.yScale = 0.5
	end
end


local function newRetinaText( text, x, y, size, bold )
	local obj
	if isRetinaEnabled then
		obj = display.newText( text, x, y, bold and fontBold or fontRegular, size*2 )
		obj.xScale = 0.5
		obj.yScale = 0.5
	else
		obj = display.newText( text, x, y, bold and fontBold or fontRegular, size )
	end
	return obj
end
-----------------------------------------------------------------------------------------


-- Background rectangles and lines

-- background

display.setDefault('background', unpack(windowBackgroundColor))

local bgRect = display.newRect(halfW, halfH, screenW, screenH )
bgRect:setFillColor(unpack(windowBackgroundColor))

-- Lines

local vertLine = display.newLine( 634, 0, 634, display.contentHeight )
vertLine:setStrokeColor( unpack(linesColor) )
vertLine.strokeWidth = 1

local footerLine = display.newLine( 34, 649.75, 633.5, 649.75 )
footerLine:setStrokeColor( unpack(linesColor) )
footerLine.strokeWidth = 1

-- header rect

local bgTop = display.newRect(halfW, 40, screenW, 80 )
bgTop:setFillColor(unpack(topBlockBackgroundColor))

-- Corona Logo
local g_coronaLogo = display.newImageRect( "assets/CoronaLogo.png", 144.5, 45.5)
g_coronaLogo.x = 927 + g_coronaLogo.contentWidth*0.5
g_coronaLogo.y = 15 + g_coronaLogo.contentHeight*0.5

-- Display the Corona version text (build number)

local buildNum = system.getInfo( "build" )
local version = newRetinaText(buildNum, 0, 0, 15)
version:setFillColor(1, 1, 1, 50/255)
version.anchorX = 1
version.x = 1071.5
version.y = 60

-- Create tab bar


local g_tabBarBase = 80
local g_currentTab = "tab1"
local function makeTabBar( listener )
	
	local tabLabels = {"Projects"}
	local tabXs = {66, 230, 410, 551}

	local tabButtons = {}

	local function highlightTabs(selected)
		for i = 1, #tabButtons do
			tabButtons[i].highlight(selected == i)
		end
	end

	for i = 1, #tabLabels do
		local tab = {}
		local title = newRetinaText(tabLabels[i], tabXs[i], 45, fontSizeTabBar)

		local highlight = display.newGroup()
		local h = display.newImageRect(highlight, "assets/selectedTab.png", title.contentWidth, 24)
		h.x = tabXs[i]
		h.y = 78

		local l = display.newImageRect(highlight, "assets/selectedTabL.png", 10, 24)
		l.x = h.x - h.contentWidth*0.5 - l.contentWidth*0.5
		l.y = 78

		local r = display.newImageRect(highlight, "assets/selectedTabR.png", 10, 24)
		r.x = h.x + h.contentWidth*0.5 + r.contentWidth*0.5
		r.y = 78

		local tabName = "tab" .. i

		function tab.highlight( enable )
			title:setFillColor( unpack(enable and tabColorSelected or tabColorHidden) )
			highlight.isVisible = enable
		end

		local rc = display.newRect( tabXs[i], 56, highlight.contentWidth+10, 48 )
		rc.alpha = 0

		tabButtons[#tabButtons+1] = tab
	end
	highlightTabs(1)
end
makeTabBar(handleTabBarEvent)

local function newTooltip(object, text )
	local x = object.x + object.contentWidth*(0.5-object.anchorX)
	local y = object.y - object.contentHeight*object.anchorY

	local border = 2
	local triangle = display.newImageRect( "assets/tooltip.png", 15, 8 )
	triangle.anchorY = 1
	triangle.x = x
	triangle.y = y

	local label = newRetinaText(text, x, y - border - triangle.contentHeight , fontSizeTooltip)
	label:translate(0, -label.contentHeight*0.5)
	label:setFillColor( unpack(textColorHits) )

	if label.x + label.contentWidth*0.5 + border + 10 > display.contentWidth then
		label:translate(display.contentWidth-(label.x + label.contentWidth*0.5 + border + 10), 0)
	end

	local bgRc = display.newRect( label.x, label.y, label.contentWidth+border*2, label.contentHeight+border*2 )
	bgRc:setFillColor( unpack(hintsBGColor) )

	local tooltip = display.newGroup( )
	tooltip.alpha = 0
	tooltip:insert( triangle )
	tooltip:insert( bgRc )
	tooltip:insert( label )

	local function tooltipObjectHover( hover )
		tooltip.isVisible = hover
	end
	addHoverObject(object, tooltipObjectHover)

	return tooltip
end

-- Parse a HTTP header date and return the number of seconds since the epoch
local function parseHTTPDateFormat(dateStr)

	if dateStr == nil then
		-- print("parseHTTPDateFormat: missing date")
		return nil
	end

	local datePattern = '(%d+) (%a+) (%d+)'
	local dayMatch, monthMatch, yearMatch = dateStr:match(datePattern)
	local year = 0
	local day = 0
	local month = 0

	if dayMatch and monthMatch and yearMatch then

		local months = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

		for k,v in ipairs(months) do
			if monthMatch == v then
				month = k
				break
			end
		end

		day = dayMatch
		year = yearMatch
	end

	if month == 0 then
		-- print("parseHTTPDateFormat: unrecognized date format: "..tostring(dateStr))
		return nil
	end

	return os.time{year=year, month=month, day=day, hour=0}
end


-- BUTTONS
local function onNewProject()
	if not uiTouchesDisabled then
		disableTouches()
		simulator.show( "new" )
		simulator.analytics("welcome", "button", "New Project")
		enableTouches()
	end
	return true
end


local function onOpenProject()
	if not uiTouchesDisabled then
		disableTouches()
		-- Launch the actual simulator (open project)

		simulator.show( "open" )
		simulator.analytics("welcome", "button", "Open Project")
		enableTouches()
	end
	return true
end

local function onRelaunchProject()
	if not uiTouchesDisabled then
		simulator.show( "relaunchProject" )
	end
	return true
end

local bigButtons = {
	{
		title = "New Project",
		x = 125,
		y = 265,
		y2 = 341,
		w = 89,
		h = 73.5,
		image = "assets/projectNew.png",
		hover = "assets/projectNewHover.png",
		handler = onNewProject,
	},
	{
		title = "Open Project",
		x = 305,
		y = 265,
		y2 = 341,
		w = 89,
		h = 73.5,
		image = "assets/projectOpen.png",
		hover = "assets/projectOpenHover.png",
		handler = onOpenProject,
	},
	{
		title = "Relaunch Project",
		x = 485,
		y = 265,
		y2 = 341,
		w = 89,
		h = 73.5,
		image = "assets/projectRelaunch.png",
		hover = "assets/projectRelaunchHover.png",
		handler = onRelaunchProject,
	}
}


function addProjectButtons()
	for i = 1, #bigButtons do
		local info = bigButtons[i]


		local btn = display.newImageRect(info.image, info.w, info.h )
		btn.x = info.x
		btn.y = info.y

		local btnHover = display.newImageRect(info.hover, info.w, info.h )
		btnHover.isVisible = false
		btnHover.x = info.x
		btnHover.y = info.y

		local btnName = newRetinaText(info.title, info.x, info.y2, fontSizeProjectButtons, true)
		btnName:setFillColor( unpack(textColorNormal) )

		local function onHover( hover )
			btn.isVisible = not hover
			btnHover.isVisible = hover
			btnName:setFillColor( unpack(hover and textColorSelected or textColorNormal) )
		end
		
		local h = info.y2-info.y+btnName.contentHeight*0.5+info.h*0.5
		local clickRect = display.newRect(info.x, info.y-info.h*0.5 + h*0.5, math.max(info.w, btnName.contentWidth), h )
		clickRect.isVisible = false
		clickRect.isHitTestable = true

		addHoverObject(clickRect, onHover)

		clickRect:addEventListener( "touch", function( e )
			if e.phase == "ended" then
				info.handler()
			end
		end )

		g_pointerLocations.button.image[i] =
		{
			cursor = "pointingHand",
			x = clickRect.x - (clickRect.anchorX * clickRect.contentWidth),
			y = clickRect.y - (clickRect.anchorY * clickRect.contentHeight),
			width = clickRect.contentWidth,
			height = clickRect.contentHeight,
		}
		simulator.setCursorRect(g_pointerLocations.button.image[i])

	end
end

addProjectButtons()

-------------------
-- Copyright Notice
-------------------
local copyright1 = newRetinaText("© 2020 Corona Labs Inc. ", 34, 675, fontSizeCopyright)
copyright1:translate( copyright1.contentWidth*0.5, 0 )
copyright1:setFillColor( unpack(textColorCopyright) )

local copyright2 = newRetinaText("Term of service", copyright1.x + copyright1.contentWidth*0.5, copyright1.y, fontSizeCopyright)
copyright2:setFillColor( unpack(textColorCopyright) )
copyright2:translate(copyright2.contentWidth*0.5, 0)

local unlderlineY = copyright2.y+copyright2.contentHeight*0.5 - 1.5
local underline = display.newLine(copyright2.x - copyright2.contentWidth*0.5, unlderlineY, copyright2.x + copyright2.contentWidth*0.5, unlderlineY)
underline:setStrokeColor( unpack(textColorCopyright) )

local function onHover( hover )
	underline:setStrokeColor( unpack(hover and textColorSelected or textColorCopyright) )
	copyright2:setFillColor( unpack(hover and textColorSelected or textColorCopyright) )
end		

addHoverObject(copyright2, onHover)

copyright2:addEventListener( "touch", function( event )
	if event.phase == "ended" then
		OpenURL("https://solar2d.com/LICENSE.txt", "Term of service")
	end
end )

g_pointerLocations.quickLink[#g_pointerLocations.quickLink+1] =
{
	cursor = "pointingHand",
	x = copyright2.x - (copyright2.anchorX * copyright2.contentWidth),
	y = copyright2.y - (copyright2.anchorY * copyright2.contentHeight),
	width = copyright2.contentWidth,
	height = copyright2.contentHeight,
}
simulator.setCursorRect(g_pointerLocations.quickLink[#g_pointerLocations.quickLink])


local copyright3 = newRetinaText(" & ", 34, 675, fontSizeCopyright)
copyright3.x = copyright2.x + copyright2.contentWidth*0.5 + copyright3.contentWidth*0.5
copyright3:setFillColor( unpack(textColorCopyright) )



local copyright4 = newRetinaText("Privacy Policy.", copyright3.x + copyright3.contentWidth*0.5, copyright3.y, fontSizeCopyright)
copyright4:setFillColor( unpack(textColorCopyright) )
copyright4:translate(copyright4.contentWidth*0.5, 0)

local unlderlineY = copyright4.y+copyright4.contentHeight*0.5 - 1.5
local underline = display.newLine(copyright4.x - copyright4.contentWidth*0.5, unlderlineY, copyright4.x + copyright4.contentWidth*0.5, unlderlineY)
underline:setStrokeColor( unpack(textColorCopyright) )

local function onHover( hover )
	underline:setStrokeColor( unpack(hover and textColorSelected or textColorCopyright) )
	copyright4:setFillColor( unpack(hover and textColorSelected or textColorCopyright) )
end		

addHoverObject(copyright4, onHover)

copyright4:addEventListener( "touch", function( event )
	if event.phase == "ended" then
		OpenURL("https://solar2d.com/PRIVACY_POLICY.txt", "Privacy Policy")
	end
end )

g_pointerLocations.quickLink[#g_pointerLocations.quickLink+1] =
{
	cursor = "pointingHand",
	x = copyright4.x - (copyright4.anchorX * copyright4.contentWidth),
	y = copyright4.y - (copyright4.anchorY * copyright4.contentHeight),
	width = copyright4.contentWidth,
	height = copyright4.contentHeight,
}
simulator.setCursorRect(g_pointerLocations.quickLink[#g_pointerLocations.quickLink])


-------------------
--- RECENT PROJECTS
-------------------

local recentProjects = display.newImageRect("assets/groupRecent.png", 17, 17)
recentProjects.x = 694
recentProjects.y = 151

local recentProjectsTitle = newRetinaText("Recent Projects", recentProjects.x+recentProjects.contentWidth*0.5+5, recentProjects.y, fontSizeSections)
recentProjectsTitle.anchorX = 0
recentProjectsTitle:setFillColor(unpack(textColorNormal))


local recentsGroup = display.newGroup( )

local projectsButtonWidth = 325



local function createProjectActions(x, y, projectURL)

	local group = display.newGroup()
	local activeGroup = display.newGroup()

	group:insert( activeGroup )

	local mini = display.newImageRect( group, "assets/miniMenu.png", 17,17 )
	mini:translate(x,y)

	local miniActive = display.newImageRect( activeGroup, "assets/miniMenuHover.png", 17,17 )
	miniActive:translate(x,y)

	local function createActiveButton(x, img, hover, tooltipText, func)
		local btn = display.newImageRect( activeGroup, img, 17,17 )
		btn.x = x
		btn.y = y
		
		local btnHover = display.newImageRect( activeGroup, hover, 17,17 )
		btnHover.x = x
		btnHover.y = y
		btnHover.isVisible = false
		btnHover.isHitTestable = true

		local tooltip = newTooltip(btnHover, tooltipText)
		activeGroup:insert( tooltip )

		addHoverObject(btnHover, function( hover )
			btnHover.isVisible = hover
			btn.isVisible = not hover
		end)

		btnHover:addEventListener( "touch", function( event )
			if event.phase == "ended" then 
				-- howerListener{}
				func()
				return true
			end
		end )
	end
	
	x = x-32

	createActiveButton(x, "assets/miniSandbox.png", "assets/miniSandboxHover.png", "Show Project Sandbox", function()
		if not uiTouchesDisabled then
			disableTouches()
			simulator.show( "showSandbox", projectURL)
			enableTouches()
		end
	end)


	x = x-32

	createActiveButton(x, "assets/miniBrowse.png", "assets/miniBrowseHover.png", "Show Project Files", function()
		if not uiTouchesDisabled then
			disableTouches()
			simulator.show( "showFiles", projectURL)
			enableTouches()
		end
	end)

	x = x-32

	createActiveButton(x, "assets/miniEdit.png", "assets/miniEditHover.png", "Open in Editor", function()
		if not uiTouchesDisabled then
			disableTouches()
			simulator.show( "editProject", projectURL)
			enableTouches()
		end
	end)

	x = x-32

	createActiveButton(x, "assets/miniOpen.png", "assets/miniOpenHover.png", "Open", function()
		if not uiTouchesDisabled then
			disableTouches()
			simulator.show( "open", projectURL)
			enableTouches()
		end
	end)

	activeGroup.isVisible = false

	local function toggle(on)
		activeGroup.isVisible = on
		mini.isVisible = not on
	end

	return group, toggle
end

-- function hsvToRgb(h, s, v)
--   local r, g, b
--   local i = math.floor(h * 6);
--   local f = h * 6 - i;
--   local p = v * (1 - s);
--   local q = v * (1 - f * s);
--   local t = v * (1 - (1 - f) * s);
--   i = i % 6
--   if i == 0 then r, g, b = v, t, p
--   elseif i == 1 then r, g, b = q, v, p
--   elseif i == 2 then r, g, b = p, v, t
--   elseif i == 3 then r, g, b = p, q, v
--   elseif i == 4 then r, g, b = t, p, v
--   elseif i == 5 then r, g, b = v, p, q
--   end
--   return r, g, b
-- end



function showRecents()
	-- Clear the previous recents list
	recentsGroup:removeSelf( )
	recentsGroup = display.newGroup( )

	setPointers(g_pointerLocations.project, "none")

	local projects = simulator.getRecentProjects()
	local projectsItemHeight = 65


	if #projects <= 0 then
		--Project count is zero - No Projects - so show place to create one
		

		local btn = display.newImageRect("assets/projectNew.png", 89, 73.5 )
		btn.x = 867
		btn.y = 318

		local btnHover = display.newImageRect("assets/projectNewHover.png", 89, 73.5 )
		btnHover.isVisible = false
		btnHover.x = btn.x
		btnHover.y = btn.y

		local btnName = newRetinaText("Create your first Project", 867, btn.y + 76, fontSizeProjectButtons, true)
		btnName:setFillColor( unpack(textColorNormal) )

		local function onHover( hover )
			btn.isVisible = not hover
			btnHover.isVisible = hover
			btnName:setFillColor( unpack(hover and textColorSelected or textColorNormal) )
		end
		
		local h = btnName.y-btnHover.y+btnName.contentHeight*0.5+btn.contentHeight*0.5
		local clickRect = display.newRect(867, btnHover.y-btn.contentHeight*0.5 + h*0.5, math.max(btn.contentWidth, btnName.contentWidth), h )
		clickRect.isVisible = false
		clickRect.isHitTestable = true

		addHoverObject(clickRect, onHover)

		clickRect:addEventListener( "touch", function( e )
			if e.phase == "ended" then
				onNewProject()
			end
		end )


		g_pointerLocations.project[1] =
		{
			cursor = "pointingHand",
			x = (clickRect.x - (clickRect.contentWidth / 2)),
			y = (clickRect.y - (clickRect.contentHeight / 2)),
			width = clickRect.contentWidth,
			height = clickRect.contentHeight,
		}
		simulator.setCursorRect(g_pointerLocations.project[1])

		recentsGroup:insert( clickRect )
		recentsGroup:insert( btn )
		recentsGroup:insert( btnHover )
	else
		--At least 1 recent project was found. List them.
		-- recentProjectsTitle.isVisible = true

		-- Enabling and disabling the recent project scrolling and setting numbers. if <=5, scroll will be disabled.
		local numProjectsShown = 7
		if numProjectsShown > #projects then
			numProjectsShown = #projects
		end

		for i = 1,numProjectsShown do

			-- On Windows we sometimes get nil entries in the recents array
			-- so we avoid them here
			if projects[i] then
				local projectgroup = display.newGroup()

				local projectName = projects[i].formattedString
				local projectDir = projects[i].fullURLString

				if platform == "Win" then
					projectDir = projectDir .. "\\..\\."
				end
				local icon = nil

				if projectName == nil or projectName == "" then
					-- This used to happen on Windows if there aren't enough recent items
					break
				end

				local fullURLString = projects[i].fullURLString
				local function projectOpen()
					simulator.show( "open", fullURLString)
					simulator.analytics("welcome", "recents", "open-project-"..tostring(i))
				end

				-- PROJECT ICONS
				if not icon then 
					local projectIconFile = simulator.getPreference("welcomeScreenIconFile") or "Icon.png"
					local projectIcon = projectDir ..dirSeparator.. projectIconFile
					if lfs.attributes(projectIcon) ~= nil then
						simulator.setProjectResourceDirectory(projectDir)
						icon = display.newImageRect(projectIconFile, system.ProjectResourceDirectory, 32, 32)
					end
				end

				if not icon then 
					local projectIconFile = "Icon-xhdpi.png"
					local projectIcon = projectDir ..dirSeparator.. projectIconFile
					if lfs.attributes(projectIcon) ~= nil then
						simulator.setProjectResourceDirectory(projectDir)
						icon = display.newImageRect(projectIconFile, system.ProjectResourceDirectory, 32, 32)
					end
				end

				if not icon then 
					local projectIconFile = "Icon-hdpi.png"
					local projectIcon = projectDir ..dirSeparator.. projectIconFile
					if lfs.attributes(projectIcon) ~= nil then
						simulator.setProjectResourceDirectory(projectDir)
						icon = display.newImageRect(projectIconFile, system.ProjectResourceDirectory, 32, 32)
					end
				end

				if not icon then 
					local projectIconFile = "Icon-120.png"
					local iconDir = projectDir ..dirSeparator.. "Images.xcassets" ..dirSeparator.. "AppIcon.appiconset"
					local projectIcon = iconDir .. dirSeparator .. projectIconFile
					if lfs.attributes(projectIcon) ~= nil then
						simulator.setProjectResourceDirectory(iconDir)
						icon = display.newImageRect(projectIconFile, system.ProjectResourceDirectory, 32, 32)
					end
				end

				if not icon then
					-- project lacks an "Icon.png" file (or whatever pref value they set), use a default
					icon = display.newImageRect("assets/DefaultAppIcon.png", system.ResourceDirectory, 32, 32)
				end

				projectgroup:insert(icon)
				icon.anchorX = 0
				icon.anchorY = 0
				icon.x = 687
				icon.y = 214 + projectsItemHeight * (i - 1)

				local x = icon.x + icon.contentWidth + 17.5
				local y = icon.y

				-- PROJECT NAME & PATH
				local shortProjectName = limitDisplayLength(projectsButtonWidth*0.55, projectName, fontRegular, fontSizeRecetProjectName)

				local projectNameLabel = newRetinaText(shortProjectName, x, y - 6, fontSizeRecetProjectName)
				projectNameLabel:setFillColor( unpack(textColorNormal) )
				projectNameLabel.anchorX = 0
				projectNameLabel.anchorY = 0


				if shortProjectName ~= projectName then
					newTooltip(projectNameLabel, projectName)
				end

				local function onHover( hover )
					projectNameLabel:setFillColor( unpack(hover and textColorSelected or textColorNormal) )
				end
				addHoverObject(projectNameLabel, onHover)



				local prPath = projects[i].fullURLString
				if userHome then
					prPath = projects[i].fullURLString:gsub("^"..userHome, "~")
				end
				if userHome and prPath:find(userHome, 0, true) == 1 then
					prPath = "~"..projects[i].fullURLString:sub(#userHome+1)
				end
				
				local shortProjectPath = limitDisplayLength(projectsButtonWidth, prPath, fontRegular, fontSizeRecetProjectPath, true)

				local projectPathLabel = newRetinaText(shortProjectPath, x, y + icon.contentHeight + 2, fontSizeRecetProjectPath)
				projectPathLabel:setFillColor( unpack(textColorLinks))
				projectPathLabel.anchorX = 0
				projectPathLabel.anchorY = 1

				if shortProjectPath ~= prPath then
					newTooltip(projectPathLabel, prPath)
				end

				local function onHover( hover )
					projectPathLabel:setFillColor( unpack(hover and textColorSelected or textColorLinks) )
				end
				addHoverObject(projectPathLabel, onHover)

				projectgroup:insert(projectNameLabel)
				projectgroup:insert(projectPathLabel)

				recentsGroup:insert(projectgroup)

				--Making a box so to take the cursor event anywhere in the box
				local cell = display.newRect(icon.x, icon.y - 10, icon.contentWidth + 17.5 + projectsButtonWidth+10, icon.height + 18)
				cell:translate( cell.contentWidth*0.5, cell.contentHeight*0.5 )
				cell:setFillColor(0.5,0.5,0.5,0.5)
				cell.isHitTestable = true
				cell.isVisible = false
				projectgroup:insert(cell)

				local projectActionsGroup, toggleFunction = createProjectActions(x + projectsButtonWidth, projectNameLabel.y + projectNameLabel.contentHeight*0.5, projects[i].fullURLString)
				projectgroup:insert(projectActionsGroup)

				addHoverObject(cell, function( hover )
					toggleFunction(hover)
				end)

				local cellContentX, cellContentY = projectgroup:localToContent(cell.x, cell.y)
				g_pointerLocations.project[i] =
				{
					cursor = "pointingHand",
					x = cellContentX - (cell.width / 2),
					y = cellContentY - (cell.height / 2),
					width = cell.width,
					height = cell.height
				}
				simulator.setCursorRect(g_pointerLocations.project[i])

				cell:addEventListener( "touch", cell )

				function cell:touch( event )
					if event.phase == "ended" then
						projectOpen()
					end
				end
			end
		end
	end
end

showRecents()
Runtime:addEventListener( "_projectLoaded", showRecents )