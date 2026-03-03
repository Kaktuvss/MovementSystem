local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local Camera = workspace.CurrentCamera

local Movement = {}
Movement.__index = Movement

function Movement.Init()
	local self = setmetatable({}, Movement) -- setting up metatable for more comfortable way of programming. If lua couldn't find an function or value in self table - than it will look in metatable

	self.Character = script.Parent.Parent	-- im using self just because it have cool color, name of is is optional
	self.Humanoid = self.Character:WaitForChild("Humanoid")
	self.Animator = self.Humanoid:WaitForChild("Animator")
	self.HumanoidRootPart = self.Character:WaitForChild("HumanoidRootPart")
	self.Acceleration = 0
	self.Speed = 0
	self.LiftForce = 0
	self.AirBornTime = 0
	self.LastTimeSlide = tick()
	self.KeyDirection = Vector3.new(0,0,0)
	self.Direction = Vector3.new(0,0,0)
	self.IsGrounded = true
	self.IsSlop = true
	self.State = "Idle"
	self.Connections = {}
	
	self.Force = Instance.new("LinearVelocity", self.HumanoidRootPart) -- i gonna use linear velocity for changing player position
	self.Force.Attachment0 = self.HumanoidRootPart.RootAttachment
	self.Force.MaxForce = 100000
	self.Force.VelocityConstraintMode = Enum.VelocityConstraintMode.Line -- i gonna use Line VelocityConstraintMode in order to easier changing force of velocity. Because now force relate of number, in base form it relate from vector
	self.Force.Enabled = false
	self.Force.Name = "HorizontalForce"
	
	self.VerticalForce = Instance.new("LinearVelocity", self.HumanoidRootPart)
	self.VerticalForce.Attachment0 = self.HumanoidRootPart.RootAttachment
	self.VerticalForce.MaxForce = 100000
	self.VerticalForce.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
	self.VerticalForce.LineDirection = Vector3.new(0,1,0)
	self.VerticalForce.Enabled = false
	self.VerticalForce.Name = "VerticalForce"
	
	self.RayCastFilter = RaycastParams.new()
	self.RayCastFilter.FilterType = Enum.RaycastFilterType.Exclude
	self.RayCastFilter.FilterDescendantsInstances = {self.Character}
	
	self.Humanoid.JumpPower = 0
	self.Humanoid.CameraOffset = Vector3.new(2, 0, 0)
	self.Character.PrimaryPart = self.HumanoidRootPart
	self.Humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	self.Humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false) 
	
	self.Config = {	-- just constant values for easier script manipulating
		BaseJumpPower = 9,
		JumpDuration = 0.25,
		Friction = 100,
		FrictionAir = 30,
		MaxAcceleration = math.huge,
		DashVelocity = 100,
		DashDuration = 0.35,
		DashJumpForce = 9,
		MinSpeedToSlide = 30,
		MinSlideSpeed = 10,
		AirStrafeSpeed = 0.07,
		GravitationalAcceleration = 9.8 * 4,
		MaxFallSpeed = -100,
		SlopHeight = 12.5,
		SlopSnapDistance = 4.2,
		SlopOffset = {
			Slide = 0.8,
			Dash = 3,
			Idle = 3,
		},
	}
	self.Animations = {
		Slide = "rbxassetid://137356969852774",
		Dash = "rbxassetid://90918609210082",
		Jump = "rbxassetid://125750702",
	}
	
	for i, animation in pairs(self.Animations) do
		local anim = Instance.new("Animation")
		anim.Name = i
		anim.AnimationId = animation
		self.Animations[i] = self.Animator:LoadAnimation(anim)
	end
	
	local listenToInput = function(Action : string, UserInputState, InputObject)
		if Action == "Dash" and UserInputState ~= Enum.UserInputState.End then
			self:Dash()
		elseif Action == "Sit" and self.State ~= "Dash" then
			self:Sit(UserInputState)
		end
	end
	
	ContextActionService:BindAction("Dash", listenToInput, false, Enum.KeyCode.LeftShift) -- binding buttons in order to make them work only for listenToInput function
	ContextActionService:BindAction("Sit", listenToInput, false, Enum.KeyCode.LeftControl)
	
	self.Connections[1] = RunService.Heartbeat:Connect(function(deltaTime)
		self:Update(deltaTime)
	end)
	self.Connections[2] = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.Space then
			self:Jump()
		elseif input.UserInputType == Enum.UserInputType.Keyboard then
			self:KeyPressed(input.KeyCode, Enum.UserInputState.Begin)
		end
	end)
	self.Connections[3] = UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			self:KeyPressed(input.KeyCode, Enum.UserInputState.End)
		end
	end)
	
	return self
end

function Movement:Dash()
	if self.State == "Dash" then return end
	self.State = "Dash"
	self:StopAllAnimations()
	
	local DashDirection = Vector3.new(self.HumanoidRootPart.CFrame.LookVector.X, 0, self.HumanoidRootPart.CFrame.LookVector.Z).Unit	-- getting direction if which our humanoidrootpart looking without y axis in unit values (it,s mean that values in vector can be larger then 1 or smaller then -1)
	local IsGrounded = workspace:Raycast(self.HumanoidRootPart.Position, Vector3.new(0, -self.Config.SlopSnapDistance, 0), self.RayCastFilter) ~= nil -- checking is player on the ground with raycast. Ray have start position and direction in which it cast. If there something between start and end of cast it will return it, otherwise it gonna return nil
	
	local Slop = workspace:Raycast(self.HumanoidRootPart.Position, Vector3.new(0,-3,0), self.RayCastFilter) -- checking if player is on slop and looking down that gonna be useful in future
	if Slop then
		local isSlopDown = workspace:Raycast(self.HumanoidRootPart.Position + self.HumanoidRootPart.CFrame.LookVector.Unit * 5.5, Vector3.new(0, -self.Config.SlopHeight - 3, 0), self.RayCastFilter)

		if isSlopDown and Slop.Instance == isSlopDown.Instance and (Slop.Position.Y - isSlopDown.Position.Y) > 0 then
			self.IsSlop = true
		end
	end

	self.Force.LineDirection = DashDirection -- Applying force to player
	self.Force.LineVelocity = self.Config.DashVelocity
	self.VerticalForce.LineVelocity = 0
	self.VerticalForce.Enabled = true
	self.Force.Enabled = true
	self.LiftForce = 0
	self.AirBornTime = 0
	
	self.Humanoid.AutoRotate = false
	self.Animations["Dash"]:Play(0,1,1)
	task.wait()
	self.Animations["Dash"]:AdjustSpeed(0)
	task.wait(self.Config.DashDuration)
	self.LastTimeSlide = tick()
	if self.State ~= "Dash" then return end
	self.Humanoid.AutoRotate = true
	self.Animations["Dash"]:Stop()
	self.Speed = 100 -- Applying speed that gonna be useful in future

	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) and IsGrounded then -- checking if player hold left control in order to slide after dash 
		self:Slide()	
	else
		self.State = "Idle"
		if self.IsSlop then
			self:StopPlayerMomentum()
		end
	end
end

function Movement:Sit(UserInputState) -- i made this function in order if i gonna have sit mechanic, but i didin't made it yet - so i will use it only for slide nechanic
	if self.Speed >= self.Config.MinSpeedToSlide then	
		self:Slide(UserInputState)
	end 
	
	local Slop = workspace:Raycast(self.HumanoidRootPart.Position, Vector3.new(0,-3,0), self.RayCastFilter)
	
	if Slop and UserInputState == Enum.UserInputState.Begin then
		local isSlopDown = workspace:Raycast(self.HumanoidRootPart.Position + self.HumanoidRootPart.CFrame.LookVector.Unit * 5.5, Vector3.new(0, -self.Config.SlopHeight - 3, 0), self.RayCastFilter) 
		
		if isSlopDown and Slop.Instance == isSlopDown.Instance and (Slop.Position.Y - isSlopDown.Position.Y) > 0 then -- if slop is down then player gonna slide
			self.Speed = self.Config.MinSpeedToSlide + 10
			self:Slide()
		end
	end
end

function Movement:KeyPressed(Key, UserInputState) -- this function needing for air strafe mechanic. It checking in what direction player pressing keys
	local KeyValue = Vector3.zero
	if Key == Enum.KeyCode.W then
		KeyValue = Vector3.new(0, 0, -1)
		elseif Key == Enum.KeyCode.S then
		KeyValue = Vector3.new(0, 0, 1)
		elseif Key == Enum.KeyCode.A then
		KeyValue = Vector3.new(-1, 0, 0)
		elseif Key == Enum.KeyCode.D then
		KeyValue = Vector3.new(1, 0, 0)
	end

	if KeyValue == Vector3.zero then return end
	
	if UserInputState == Enum.UserInputState.End then KeyValue = -KeyValue end
	
	self.KeyDirection += KeyValue
end

function Movement:Slide(UserInputState)
	local IsGrounded = workspace:Raycast(self.HumanoidRootPart.Position, Vector3.new(0, -self.Config.SlopSnapDistance, 0), self.RayCastFilter) ~= nil
	
	if (UserInputState == Enum.UserInputState.End and self.State == "Slide") or IsGrounded == false then -- stoping slide if player release left control
		self.State = "Idle"
		self.Animations["Slide"]:Stop()
		if self.IsSlop then
			self:StopPlayerMomentum()
		end
		return
	end

	if self.State == "Slide" or IsGrounded == false then return end
	
	self.State = "Slide"
	self:StopAllAnimations()
	
	local SlideDirection = Vector3.new(self.HumanoidRootPart.CFrame.LookVector.X, 0, self.HumanoidRootPart.CFrame.LookVector.Z).Unit
	
	self.Force.LineDirection = SlideDirection 
	self.Force.LineVelocity = self.Speed * self.Acceleration
	self.Force.Enabled = true
	self.Animations["Slide"]:Play(0,1,1)
end

function Movement:Jump()
	local IsGrounded = workspace:Raycast(self.HumanoidRootPart.Position, Vector3.new(0, -self.Config.SlopSnapDistance, 0), self.RayCastFilter) ~= nil
	
	if self.State == "Dash" and self.IsGrounded == true then -- making dash jump
		self.Humanoid.AutoRotate = true
		self.Animations["Dash"]:Stop()
		self.State = "Jump"
		self.Animations["Jump"]:Play()
		self.LiftForce = self.Config.DashJumpForce
		self.Speed = 100
		task.wait(self.Config.JumpDuration)
		if self.State == "Jump" then 
			self.State = "Idle"
		end
	elseif self.State == "Idle" and IsGrounded == true then -- making regular jump
		self.State = "Jump"
		self.Animations["Jump"]:Play()
		self.LiftForce = self.Config.BaseJumpPower
		task.wait(self.Config.JumpDuration)
		if self.State == "Jump" then 
			self.State = "Idle"
		end
	end
end

function Movement:Update(dT)
	self.Character:PivotTo(self.HumanoidRootPart.CFrame * CFrame.Angles(-math.rad(self.HumanoidRootPart.Orientation.X),0, -math.rad(self.HumanoidRootPart.Orientation.Z))) -- setting player orientation of x and z axis to 0 in order to prevent player from jiggling if player dash to end of a slop
	local IsGrounded = workspace:Raycast(self.HumanoidRootPart.Position, Vector3.new(0, -self.Config.SlopSnapDistance, 0), self.RayCastFilter) ~= nil
	
	if self.State ~= "Dash" or (IsGrounded == false and self.State ~= "Dash") then
		local Direction = Vector3.new(Camera.CFrame.LookVector.X, 0, Camera.CFrame.LookVector.Z).Unit 
		local Friction = self.Config.Friction -- friction using for lowering line velocity force
		
		if self.State ~= "Slide" and self.KeyDirection == Vector3.zero then -- if player in air and dosen't pressing any wasd keys then i don't changing direction of line velocity
			Direction = self.Force.LineDirection
		elseif self.State ~= "Slide" then  -- if player in air
			local dDirectionMagnitude = (Direction - self.Direction).Magnitude -- delta of previous and current direction of player
	
			if self.KeyDirection.Z == 0 and dDirectionMagnitude < self.Config.AirStrafeSpeed then -- if player doesn't press w or s key and delta of player direction is less then constant value then we changing velocity direction
				Direction = Direction + self.HumanoidRootPart.CFrame:VectorToWorldSpace(self.KeyDirection).Unit 
			else
				Direction = self.Force.LineDirection 
			end
			
			Friction = self.Config.FrictionAir -- changing friction if player in air
		end
	
		self.Force.LineDirection = Direction
		self.Speed = math.clamp(self.Speed - (Friction - self.Acceleration) * dT, 0, math.huge) -- changing speed relating from friction and acceleration. Math.clamp returning min value if main value is less then min value, max if main value bigger then max value and otherwise it return main value
		self.Force.LineVelocity = self.Speed -- changing velocity force
		if self.Force.LineVelocity == 0 or (IsGrounded == true and self.State ~= "Slide") then
			self.Force.Enabled = false
		else
			self.Force.Enabled = true
		end
		
		if IsGrounded == false or self.State == "Jump" then -- turning vertical velocity if player is jumping or in air
			self.VerticalForce.Enabled = true
			self.LiftForce = math.clamp(self.LiftForce - dT * self.AirBornTime * self.Config.GravitationalAcceleration, self.Config.MaxFallSpeed, math.huge)
			self.VerticalForce.LineVelocity = self.LiftForce
			self.AirBornTime += dT
		else
			self.VerticalForce.Enabled = false
			self.VerticalForce.LineVelocity = 0
			self.LiftForce = 0
			self.AirBornTime = 0
		end

		self.Direction = Direction
	end
	
	if self.IsGrounded == true and self.State == "Idle" then -- turning off force if player is standing on the ground and in idle state
		self.Force.Enabled = false
	end
	
	if self.Speed < self.Config.MinSlideSpeed and self.State == "Slide" then -- turning off slide state if speed is less then minimum slide speed
		self:ChangeStateToIdle()
	end																					
	
	if self.IsGrounded == false and IsGrounded then -- if player was in air and now standing on the ground and player holding control button then we making player slide
		if self.Speed >= self.Config.MinSpeedToSlide and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			self:Slide()
		end
	elseif self.IsGrounded and IsGrounded == false then -- if player was standing on the ground and now in air then we turning off slide or dash state
		self:ChangeStateToIdle()
	end
	
	self.IsGrounded = IsGrounded
	
	local Slop = workspace:Raycast(self.HumanoidRootPart.Position + Vector3.new(0,5,0), Vector3.new(0,-30,0), self.RayCastFilter) -- checking if player is standing on the slop
	if Slop then
		local isSlopDown = workspace:Raycast(self.HumanoidRootPart.Position + Vector3.new(0,5,0) + self.HumanoidRootPart.CFrame.LookVector.Unit * 5.5, Vector3.new(0, -self.Config.SlopHeight - 30, 0), self.RayCastFilter) -- self.Config.SlopHeight

		if isSlopDown and (self.State == "Slide" or self.State == "Dash" or (self.State == "Idle" and self.AirBornTime <= 0)) and (self.HumanoidRootPart.Position.Y - Slop.Position.Y < self.Config.SlopSnapDistance or self.IsSlop) then
			local SlopDif = Slop.Position.Y - isSlopDown.Position.Y
			
			if SlopDif == 0 and self.State == "Idle" then
				self.IsSlop = false
				return
			end
			
			self.Character:PivotTo(self.HumanoidRootPart.CFrame - Vector3.new(0, self.HumanoidRootPart.Position.Y - Slop.Position.Y - self.Config.SlopOffset[self.State], 0)) -- snapping player to the slop. Because otherwise player gonna fly off the slpo
			
			self.IsSlop = true
			
			if self.State == "Slide" and SlopDif ~= 0 then  -- adding or decreasing acceleration if player is on the slop and diffrence between upper slop and lower slop ~= 0
				self.Acceleration = (SlopDif) * 100
			elseif self.State == "Slide" and SlopDif == 0 then
				self.Acceleration = 0
				self.IsSlop = false
			end
		else
			self.IsSlop = false
			self.Acceleration = 0 
		end
	else
		self.IsSlop = false
		self.Acceleration = 0 
	end
end

function Movement:ChangeStateToIdle()
	if self.State == "Slide" then
		self:Slide(Enum.UserInputState.End)
		elseif self.State == "Dash" then
		self.Humanoid.AutoRotate = true
		self.Animations["Dash"]:Stop()
		self.Speed = 100
	end
end

function Movement:StopPlayerMomentum()
	self.HumanoidRootPart.AssemblyLinearVelocity = Vector3.new(0,0,0)
	self.HumanoidRootPart.AssemblyAngularVelocity = Vector3.new(0,0,0)
	self.Speed = 0
	self.Force.Enabled = false
end

function Movement:StopAllAnimations()
	for i, animation in pairs(self.Animations) do
		animation:Stop()
	end
end

return Movement
