--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Utils = ReplicatedStorage:WaitForChild("Utils")
local SignalModule = require(Utils:WaitForChild("Signal"))
local StateMachineModule = require(Utils:WaitForChild("StateMachine"))
local Janitor = require(Utils:WaitForChild("Janitor"))

local Assets = ReplicatedStorage:WaitForChild("Assets")
local GrappleMarker = Assets:WaitForChild("GrappleMarker")
local CanGrappleMarker = Assets:WaitForChild("CanGrappleMarker")

local Camera = workspace.Camera

local Grapple = {}
Grapple.__index = Grapple	-- Setting up metatable. It helps to manipulate object with class methods

export type Signals = {		-- export type helps to auto complete names in this script or other scripts than call it
	GrappleStarted: SignalModule.Signal,
	GrappleEnded: SignalModule.Signal,
}

export type Config = {
	GRAPPLE_MAX_DISTANCE: number,
	GRAPPLE_FORCE: number,
	GRAPPLE_VELOCITY_LIMIT: number,
	DISTANCE_BETWEEN_GROUND: number,
	AIR_FORCE: number,
	AIR_VELOCITY_LIMIT: number,
	GRAPPLE_KEY: Enum.UserInputType,
}

export type Detection = {
	RaycastFilter: RaycastParams,
	GrapplePosition: Vector3,
	isGrounded: boolean,
}

export type Flags = {
	_grappleRequested: boolean,
}

export type Grapple = typeof(	 -- This is a type of object that this class returns and it autocomplete names of new methodes without need to write them here 
	setmetatable({} :: {
		Character: Model,
		HumanoidRootPart: BasePart,
		Humanoid: Humanoid,
		GrappleMarker: BasePart,
		CanGrappleMarker: BasePart,
		UImarker: ImageLabel,
		
		Janitor: Janitor.Janitor,	-- example of export type. Janitor object in this script relay and autocomplete names like in a Janitor module script 
		StateMachine: StateMachineModule.StateMachine,
		Signals: Signals,
		Config: Config,
		Detection: Detection,
		Flags: Flags,
	}, 
	Grapple
	)
)

function Grapple.new(Character: Model): Grapple
	local HRP = Character:WaitForChild("HumanoidRootPart") :: BasePart
	local Humanoid = Character:WaitForChild("Humanoid") :: Humanoid
	
	local grappleMarker = GrappleMarker:Clone()
	local canGrappleMarker = CanGrappleMarker:Clone()
	local uiMarker = canGrappleMarker.BillboardGui.ImageLabel
	
	local self = setmetatable({}, Grapple) :: Grapple
	self.Character = Character
	self.HumanoidRootPart = HRP
	self.Humanoid = Humanoid
	self.GrappleMarker = grappleMarker
	self.CanGrappleMarker = canGrappleMarker
	self.UImarker = uiMarker
	self.Janitor = Janitor.new()	-- Module that cleans signals, instances and fires functions
	self.StateMachine = StateMachineModule.new("Idle")	--	Module that helps handle states change without bugs
	
	self.Signals = {	--	Module that fires custom events that can be used with outside scritps
		GrappleEnded = SignalModule.new(),
		GrappleStarted = SignalModule.new(),
	}
	
	self.Config = {		-- Constant values that help easily modify script smoothness
		GRAPPLE_MAX_DISTANCE = 250,
		GRAPPLE_FORCE = 100000,
		GRAPPLE_VELOCITY_LIMIT = 300,
		DISTANCE_BETWEEN_GROUND = 4,
		AIR_FORCE = 80,
		AIR_VELOCITY_LIMIT = 100,
		GRAPPLE_KEY = Enum.UserInputType.MouseButton1,
	}
	
	self.Detection = {		-- dictonary that contains information about environment and character states
		RaycastFilter = RaycastParams.new(),
		GrapplePosition = Vector3.zero,
		isGrounded = false,
	}
	
	self.Flags = {		-- Values that changes in different functions and using in runservice
		_grappleRequested = false,
	}
	
	--Assigment
	self.GrappleMarker.Parent = workspace
	self.CanGrappleMarker.Parent = workspace
	
	self.Detection.RaycastFilter.FilterType = Enum.RaycastFilterType.Exclude
	self.Detection.RaycastFilter.FilterDescendantsInstances = {Character}
	
	self.StateMachine:AddTransition("Idle", "Grapple")
	self.StateMachine:AddTransition("Grapple", "Idle")
	
	self.Janitor:Add(self.GrappleMarker)
	self.Janitor:Add(self.CanGrappleMarker)
	
	self.Janitor:Add(UserInputService.InputBegan:Connect(function(input, procces)
		if procces then 
			return 
		end
		
		if input.UserInputType == self.Config.GRAPPLE_KEY then
			self.Flags._grappleRequested = true	-- Allows update function to procces grapple request
		end
	end))
	
	self.Janitor:Add(UserInputService.InputEnded:Connect(function(input, procces)
		if procces then 
			return 
		end

		if input.UserInputType == self.Config.GRAPPLE_KEY then
			self.Flags._grappleRequested = false -- Disables grapple request
		end
	end))
	
	self.Janitor:Add(RunService.Heartbeat:Connect(function(deltaTime: number)	-- Using Heartbeat because it fires after physics step (best for physics based systems)
		self:Update(deltaTime)
	end))
	
	self.Janitor:Add(self.Humanoid.Died:Connect(function()	-- disconnecting all connections and deleting instances on player died
		self.Janitor:Cleanup()
	end))
	
	return self
end

function Grapple.isGrounded(self: Grapple): boolean	-- Checks if player is standing on something with a help of Raycast
	local Origing = self.HumanoidRootPart.Position
	local Direction = Vector3.new(0, -1, 0) * self.Config.DISTANCE_BETWEEN_GROUND
	
	local RaycastResult = workspace:Raycast(Origing, Direction, self.Detection.RaycastFilter)	-- Raycast is a beam with start position and projection direction that return information about what it hits 
	
	if RaycastResult then
		return true
	end
	
	return false
end

function Grapple.CanGrapple(self: Grapple): (boolean, Vector3)		-- function that checks if player can grapple and returns if it can and where is the wall 
	if not self.StateMachine:CanTransition("Grapple") then
		return false, Vector3.zero
	end
	
	local Origin = Camera.CFrame.Position
	local Direction = Camera.CFrame.LookVector * self.Config.GRAPPLE_MAX_DISTANCE	-- Canera.CFrame.LookVector return vector that points to the direction where camera is facing
	
	local RaycastResult = workspace:Raycast(Origin, Direction, self.Detection.RaycastFilter)	-- Ñhecking if any surface in front of player and return true and position if it exist
	
	if not RaycastResult then
		return false, Vector3.zero
	end
	
	local HitPosition = RaycastResult.Position
	
	return true, HitPosition
end

function Grapple.StartGrapple(self: Grapple)	-- function that changes state to grapple allowing Update function to use GrappleUpdate function
	self.StateMachine:ChangeState("Grapple")
	self.Signals.GrappleStarted:Fire()
	
	self.GrappleMarker.Transparency = 0 
	self.GrappleMarker.Position = self.Detection.GrapplePosition	
end

function Grapple.GrappleUpdate(self: Grapple, deltaTime: number)
	local Velocity = self.HumanoidRootPart.AssemblyLinearVelocity -- Getting previous velocity
	local Direction = self.Detection.GrapplePosition - self.HumanoidRootPart.Position -- Calculating direction between player and object. by subtraction of 2 vectors (position - position)
	local Distance = Direction.Magnitude -- by calculating it's magnitude (distance between 2 points) wtih .Magnitude property     		                            		
	local Force = (Distance / self.Config.GRAPPLE_MAX_DISTANCE) * self.Config.GRAPPLE_FORCE * deltaTime -- Calculating force multiplier by dividing distance to max grapple distance (getting float value from 0 to 1)
																										-- multiplying it by max force and deltaTime(time between previous and current frame, it's helps to make it to not depend on fps)
	Direction = (self.Detection.GrapplePosition - self.HumanoidRootPart.Position).Unit -- Normalizing it to get clean direction vector (it's mean that all vector values can be only from -1 to 1 in float)
	
	Velocity = Velocity + Direction * Force -- Adding calculated force to previous velocity
	
	if Velocity.Magnitude > self.Config.GRAPPLE_VELOCITY_LIMIT then	-- limiting velocity to prevent infinity speed of player
		Velocity = Velocity.Unit * self.Config.GRAPPLE_VELOCITY_LIMIT 
	end
	
	self.HumanoidRootPart.AssemblyLinearVelocity = Velocity -- Applying force to player. Which is a rate of change center of mass of character in studs per second
end

function Grapple.EndGrapple(self: Grapple)  -- function that changes state to idle allowing Update function to use AirUpdate function
	self.StateMachine:ChangeState("Idle")
	self.Signals.GrappleEnded:Fire()
	
	self.GrappleMarker.Transparency = 1
end

function Grapple.AirUpdate(self: Grapple, deltaTime: number) -- function that makes player move more smoothly in air
	local velocity = self.HumanoidRootPart.AssemblyLinearVelocity
	local moveDirection = self.Humanoid.MoveDirection	-- getting player moveDirection (which is a where player walking releative world using wasd keys)
	
	if moveDirection.Magnitude == 0 then -- if player not moving at all then return BUT it preventing further execution of this function that can limit player velocity. 
		return	                         -- But because it's makes gameplay more funnier i decided to leave it as a feature 
	end
	
	moveDirection = Vector3.new(moveDirection.X, 0, moveDirection.Z).Unit	-- getting only x and z values from moveDirection and normalizing
	
	velocity = velocity + moveDirection * self.Config.AIR_FORCE * deltaTime -- adding player movement to it's velocity and multiplying it by deltaTime to make it not depend on fps
	
	if velocity.Magnitude > self.Config.AIR_VELOCITY_LIMIT then -- if velocity is more than our limit then limit it
		velocity = velocity.Unit * self.Config.AIR_VELOCITY_LIMIT
	end
	
	self.HumanoidRootPart.AssemblyLinearVelocity = velocity -- applying new velocity
end

function Grapple.CanGrappleMarkerUpdate(self: Grapple)	-- function that shows if player can grapple and where
	self.CanGrappleMarker.Position = self.Detection.GrapplePosition
	self.UImarker.Rotation = self.UImarker.Rotation + 1
end

function Grapple.Update(self: Grapple, deltaTime: number) -- function that is called every frame
	local canGrapple, hitPosition = self:CanGrapple()
	local isGrounded = self:isGrounded()

	if canGrapple and self.Flags._grappleRequested then -- setting grapple position and calling StartGrapple function if player can grapple and player holding grapple key 
		self.Detection.GrapplePosition = hitPosition
		self.Detection.isGrounded = isGrounded
		self:StartGrapple()
		
	elseif canGrapple then -- if can grapple and player NOT holding grapple key then we calling CanGrappleMarkerUpdate function
		self.Detection.GrapplePosition = hitPosition
		self.Detection.isGrounded = isGrounded
		self.UImarker.Visible = true
		self:CanGrappleMarkerUpdate()
		
	else
		self.UImarker.Visible = false
	
	end
	
	local state = self.StateMachine:GetCurrentState() 
	
	if state == "Grapple" and self.Flags._grappleRequested then -- if player holding grapple key and player state is grapple then we calling GrappleUpdate function
		self:GrappleUpdate(deltaTime)
		
	elseif state == "Grapple" and not self.Flags._grappleRequested then -- if player NOT holding grapple key and player state is grapple then we calling EndGrapple function
		self:EndGrapple()
		
	elseif state == "Idle" and not isGrounded then -- if player state is idle and player NOT standing on ground then we calling AirUpdate function
		self:AirUpdate(deltaTime)
		
	end
end

return Grapple
