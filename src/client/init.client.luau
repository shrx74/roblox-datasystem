--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ReplicaDataService = require(Shared:WaitForChild("Services"):WaitForChild("ReplicaDataService")) :: any

ReplicaDataService:init()

-- Cmdr console (F2). Only shown to admins; the server-side BeforeRun hook is the real check.
local player = Players.LocalPlayer
local CmdrClient = require(ReplicatedStorage:WaitForChild("CmdrClient")) :: any
CmdrClient:SetActivationKeys({ Enum.KeyCode.F2 })

local function refreshCmdr()
	CmdrClient:SetEnabled(player:GetAttribute("IsAdmin") == true)
end

refreshCmdr()
player:GetAttributeChangedSignal("IsAdmin"):Connect(refreshCmdr)
