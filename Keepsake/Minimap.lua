local _, ns = ...

-- A minimap button: click opens the window, drag moves it round the minimap,
-- right-click hides it (the slash command and the settings menu bring it
-- back). The same file ships in Keepsake and Treasure Trail.
--
--   ns.CreateMinimapButton({
--     name = "KeepsakeMinimapButton", icon = "Interface\\Icons\\...",
--     angle = 225,                      -- where it starts, in degrees
--     onClick = function() end,
--     tooltip = function(tt) end,       -- adds the lines of its tooltip
--     hiddenText = "...",               -- printed when it is hidden
--   })
--
-- Position and visibility live in ns.db.minimapAngle and ns.db.minimapHide.

local button, options

-- Round minimaps put the button on the rim; square ones (Leatrix Plus and
-- others define GetMinimapShape) slide it along the edge into the corners.
local function Place(angle)
	local rad = math.rad(angle)
	local x, y = math.cos(rad), math.sin(rad)
	local w, h = Minimap:GetWidth() / 2 + 5, Minimap:GetHeight() / 2 + 5
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	if shape == "SQUARE" then
		local dw, dh = math.sqrt(2 * w * w) - 10, math.sqrt(2 * h * h) - 10
		x = math.max(-w, math.min(x * dw, w))
		y = math.max(-h, math.min(y * dh, h))
	else
		x, y = x * w, y * h
	end
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function ns.SetMinimapHidden(hidden)
	ns.db.minimapHide = hidden and true or false
	if button then button:SetShown(not hidden) end
	if hidden and options and options.hiddenText then print(options.hiddenText) end
end

function ns.CreateMinimapButton(opts)
	if button then return button end
	options = opts
	local b = CreateFrame("Button", opts.name, Minimap)
	button = b
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(24, 24)
	bg:SetPoint("CENTER")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER")
	icon:SetTexture(opts.icon)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetSize(50, 50)
	border:SetPoint("TOPLEFT")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	b:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			GameTooltip:Hide()
			ns.SetMinimapHidden(true)
		else
			opts.onClick()
		end
	end)
	b:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local scale = Minimap:GetEffectiveScale()
			local cx, cy = GetCursorPosition()
			ns.db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
			Place(ns.db.minimapAngle)
		end)
	end)
	b:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		opts.tooltip(GameTooltip)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	if ns.db.minimapAngle == nil then ns.db.minimapAngle = opts.angle or 220 end
	Place(ns.db.minimapAngle)
	b:SetShown(not ns.db.minimapHide)
	return b
end
