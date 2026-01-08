-- Hammerspoon configuration

-- Enable CLI (hs command)
require("hs.ipc")

-- Apps to auto-centre when windows are created
local centredApps = {
	"Ghostty",
	"Arc",
	"Dia",
	"GoLand",
	"WebStorm",
	"PyCharm",
	"Rider",
}

for _, appName in ipairs(centredApps) do
	hs.window.filter.new(appName):subscribe(hs.window.filter.windowCreated, function(window)
		window:centerOnScreen()
	end)
end

-- Reload config notification
hs.alert.show("Hammerspoon config loaded")
