local areLegsEnabled = CreateConVar( "cl_legs", "1", { FCVAR_ARCHIVE }, "Enable/Disable the rendering of the legs" ):GetBool()
cvars.AddChangeCallback( "cl_legs", function( _, _, new ) areLegsEnabled = tobool( new ) end )
local areVLegsEnabled = CreateConVar( "cl_vehlegs", "0", { FCVAR_ARCHIVE }, "Enable/Disable the rendering of the legs in vehicles" ):GetBool()
cvars.AddChangeCallback( "cl_legs", function( _, _, new ) areLegsEnabled = tobool( new ) end )


local Legs = {}
local g_maxseqgroundspeed = 0

local function getLegModel()
    if LocalPlayer():GetTable().enforce_model then return LocalPlayer():GetTable().enforce_model end
    return LocalPlayer():GetModel()
end

local function checkDrawVehicle()
    if LocalPlayer():InVehicle() then
        if areLegsEnabled and not areVLegsEnabled then return true end
        return false
    end
end

local function shouldDrawLegs()
    if areLegsEnabled then
        return ( LocalPlayer():Alive() or LocalPlayer():GetTable().IsGhosted and LocalPlayer():IsGhosted() ) and not checkDrawVehicle() and GetViewEntity() == LocalPlayer() and not LocalPlayer():ShouldDrawLocalPlayer() and not IsValid( LocalPlayer():GetObserverTarget() ) and not LocalPlayer():GetTable().ShouldDisableLegs
    else
        return false
    end
end

local function setupLegs()
    if not IsValid( Legs.LegEnt ) then
        Legs.LegEnt = ClientsideModel( getLegModel(), RENDER_GROUP_OPAQUE_ENTITY )
    else
        Legs.LegEnt:SetModel( getLegModel() )
    end

    Legs.LegEnt:SetNoDraw( true )
    for _, v in pairs( LocalPlayer():GetBodyGroups() ) do
        local current = LocalPlayer():GetBodygroup( v.id )
        Legs.LegEnt:SetBodygroup( v.id, current )
    end

    for k in ipairs( LocalPlayer():GetMaterials() ) do
        Legs.LegEnt:SetSubMaterial( k - 1, LocalPlayer():GetSubMaterial( k - 1 ) )
    end

    Legs.LegEnt:SetSkin( LocalPlayer():GetSkin() )
    Legs.LegEnt:SetMaterial( LocalPlayer():GetMaterial() )
    Legs.LegEnt:SetColor( LocalPlayer():GetColor() )
    Legs.LegEnt.GetPlayerColor = function() return LocalPlayer():GetPlayerColor() end
    Legs.LegEnt.Anim = nil
    Legs.PlaybackRate = 1
    Legs.Sequence = nil
    Legs.Velocity = 0
    Legs.OldWeapon = nil
    Legs.HoldType = nil
    Legs.BonesToRemove = {}
    Legs.BoneMatrix = nil
    Legs.LegEnt.LastTick = 0
    Legs.legUpdate( g_maxseqgroundspeed )
    Legs.weaponChanged()
end

Legs.PlaybackRate = 1
Legs.Sequence = nil
Legs.Velocity = 0
Legs.OldWeapon = nil
Legs.HoldType = nil
Legs.BonesToRemove = {}
Legs.BoneMatrix = nil

local weaponChangedRemoveBones = { "ValveBiped.Bip01_Head1", "ValveBiped.Bip01_L_Hand", "ValveBiped.Bip01_L_Forearm", "ValveBiped.Bip01_L_Upperarm", "ValveBiped.Bip01_L_Clavicle", "ValveBiped.Bip01_R_Hand", "ValveBiped.Bip01_R_Forearm", "ValveBiped.Bip01_R_Upperarm", "ValveBiped.Bip01_R_Clavicle", "ValveBiped.Bip01_L_Finger4", "ValveBiped.Bip01_L_Finger41", "ValveBiped.Bip01_L_Finger42", "ValveBiped.Bip01_L_Finger3", "ValveBiped.Bip01_L_Finger31", "ValveBiped.Bip01_L_Finger32", "ValveBiped.Bip01_L_Finger2", "ValveBiped.Bip01_L_Finger21", "ValveBiped.Bip01_L_Finger22", "ValveBiped.Bip01_L_Finger1", "ValveBiped.Bip01_L_Finger11", "ValveBiped.Bip01_L_Finger12", "ValveBiped.Bip01_L_Finger0", "ValveBiped.Bip01_L_Finger01", "ValveBiped.Bip01_L_Finger02", "ValveBiped.Bip01_R_Finger4", "ValveBiped.Bip01_R_Finger41", "ValveBiped.Bip01_R_Finger42", "ValveBiped.Bip01_R_Finger3", "ValveBiped.Bip01_R_Finger31", "ValveBiped.Bip01_R_Finger32", "ValveBiped.Bip01_R_Finger2", "ValveBiped.Bip01_R_Finger21", "ValveBiped.Bip01_R_Finger22", "ValveBiped.Bip01_R_Finger1", "ValveBiped.Bip01_R_Finger11", "ValveBiped.Bip01_R_Finger12", "ValveBiped.Bip01_R_Finger0", "ValveBiped.Bip01_R_Finger01", "ValveBiped.Bip01_R_Finger02", "ValveBiped.Bip01_Spine4", "ValveBiped.Bip01_Spine2", }
local function weaponChanged()
    local legEnt = Legs.LegEnt
    if legEnt then
        for i = 0, legEnt:GetBoneCount() do
            legEnt:ManipulateBoneScale( i, Vector( 1, 1, 1 ) )
            legEnt:ManipulateBonePosition( i, vector_origin )
        end

        Legs.BonesToRemove = weaponChangedRemoveBones
        if LocalPlayer():InVehicle() then Legs.BonesToRemove = { "ValveBiped.Bip01_Head1", } end
        for _, v in pairs( Legs.BonesToRemove ) do
            local bone = legEnt:LookupBone( v )
            if bone then
                legEnt:ManipulateBoneScale( bone, Vector( 0, 0, 0 ) )
                if not LocalPlayer():InVehicle() then
                    legEnt:ManipulateBonePosition( bone, Vector( 0, -100, 0 ) )
                    legEnt:ManipulateBoneAngles( bone, Angle( 0, 0, 0 ) )
                end
            end
        end
    end
end
Legs.weaponChanged = weaponChanged

hook.Add( "PlayerSwitchWeapon", "GML:PlayerSwitchWeapon", function( ply, old, new )
    if ply ~= LocalPlayer() then return end
    weaponChanged( old, new )
end )

local function legUpdate( maxseqgroundspeed )
    if IsValid( Legs.LegEnt ) then
        Legs.Velocity = LocalPlayer():GetVelocity():Length2D()
        Legs.PlaybackRate = 1
        if Legs.Velocity > 0.5 then
            if maxseqgroundspeed < 0.001 then
                Legs.PlaybackRate = 0.01
            else
                Legs.PlaybackRate = Legs.Velocity / maxseqgroundspeed
                Legs.PlaybackRate = math.Clamp( Legs.PlaybackRate, 0.01, 10 )
            end
        end

        Legs.LegEnt:SetPlaybackRate( Legs.PlaybackRate )
        Legs.Sequence = LocalPlayer():GetSequence()
        if Legs.LegEnt.Anim ~= Legs.Sequence then
            Legs.LegEnt.Anim = Legs.Sequence
            Legs.LegEnt:ResetSequence( Legs.Sequence )
        end

        if LocalPlayer():IsOnGround() then
            Legs.LegEnt:FrameAdvance( CurTime() - Legs.LegEnt.LastTick )
        end

        Legs.LegEnt.LastTick = CurTime()
        Legs.BreathScale = sharpeye and sharpeye.GetStamina and math.Clamp( math.floor( sharpeye.GetStamina() * 5 * 10 ) / 10, 0.5, 5 ) or 0.5
        if Legs.NextBreath <= CurTime() then
            Legs.NextBreath = CurTime() + 1.95 / Legs.BreathScale
            Legs.LegEnt:SetPoseParameter( "breathing", Legs.BreathScale )
        end

        Legs.LegEnt:SetPoseParameter( "move_x", LocalPlayer():GetPoseParameter( "move_x" ) * 2 - 1 ) -- Translate the walk x direction
        Legs.LegEnt:SetPoseParameter( "move_y", LocalPlayer():GetPoseParameter( "move_y" ) * 2 - 1 ) -- Translate the walk y direction
        Legs.LegEnt:SetPoseParameter( "move_yaw", LocalPlayer():GetPoseParameter( "move_yaw" ) * 360 - 180 ) -- Translate the walk direction
        Legs.LegEnt:SetPoseParameter( "body_yaw", LocalPlayer():GetPoseParameter( "body_yaw" ) * 180 - 90 ) -- Translate the body yaw
        Legs.LegEnt:SetPoseParameter( "spine_yaw", LocalPlayer():GetPoseParameter( "spine_yaw" ) * 180 - 90 ) -- Translate the spine yaw
        if LocalPlayer():InVehicle() then
            Legs.LegEnt:SetPoseParameter( "vehicle_steer", LocalPlayer():GetVehicle():GetPoseParameter( "vehicle_steer" ) * 2 - 1 ) -- Translate the vehicle steering
        end
    end
end
Legs.legUpdate = legUpdate

Legs.BreathScale = 0.5
Legs.NextBreath = 0
local function legThink( maxseqgroundspeed )
    if not LocalPlayer():Alive() then
        setupLegs()
        return
    end

    legUpdate( maxseqgroundspeed )
end

hook.Add( "UpdateAnimation", "GML:UpdateAnimation", function( ply, _, maxseqgroundspeed )
    if ply ~= LocalPlayer() then return end
    if not areLegsEnabled then return end

    if IsValid( Legs.LegEnt ) then
        legThink( maxseqgroundspeed )
        if string.lower( getLegModel() ) ~= string.lower( Legs.LegEnt:GetModel() ) then setupLegs() end
    else
        setupLegs()
    end
end )

Legs.RenderAngle = nil
Legs.BiaisAngle = nil
Legs.RadAngle = nil
Legs.RenderPos = nil
Legs.RenderColor = {}
Legs.ClipVector = vector_up * -1
Legs.ForwardOffset = -24

local function doFinalRender()
    if not Legs.LegEnt then return end

    cam.Start3D( EyePos(), EyeAngles() )
    if shouldDrawLegs() then
        if LocalPlayer():Crouching() or LocalPlayer():InVehicle() then
            Legs.RenderPos = LocalPlayer():GetPos()
        else
            Legs.RenderPos = LocalPlayer():GetPos() + Vector( 0, 0, 5 )
        end

        if LocalPlayer():InVehicle() then
            Legs.RenderAngle = LocalPlayer():GetVehicle():GetAngles()
            Legs.RenderAngle:RotateAroundAxis( Legs.RenderAngle:Up(), 90 )
        else
            Legs.BiaisAngles = sharpeye_focus and sharpeye_focus.GetBiaisViewAngles and sharpeye_focus:GetBiaisViewAngles() or LocalPlayer():EyeAngles()
            Legs.RenderAngle = Angle( 0, Legs.BiaisAngles.y, 0 )
            Legs.RadAngle = math.rad( Legs.BiaisAngles.y )
            Legs.ForwardOffset = -22
            Legs.RenderPos.x = Legs.RenderPos.x + math.cos( Legs.RadAngle ) * Legs.ForwardOffset
            Legs.RenderPos.y = Legs.RenderPos.y + math.sin( Legs.RadAngle ) * Legs.ForwardOffset
            if LocalPlayer():GetGroundEntity() == NULL then
                Legs.RenderPos.z = Legs.RenderPos.z + 8
                if LocalPlayer():KeyDown( IN_DUCK ) then Legs.RenderPos.z = Legs.RenderPos.z - 28 end
            end
        end

        Legs.RenderColor = LocalPlayer():GetColor()
        local bEnabled = render.EnableClipping( true )
        render.PushCustomClipPlane( Legs.ClipVector, Legs.ClipVector:Dot( EyePos() ) )
        render.SetColorModulation( Legs.RenderColor.r / 255, Legs.RenderColor.g / 255, Legs.RenderColor.b / 255 )
        render.SetBlend( Legs.RenderColor.a / 255 )
        Legs.LegEnt:SetRenderOrigin( Legs.RenderPos )
        Legs.LegEnt:SetRenderAngles( Legs.RenderAngle )
        Legs.LegEnt:SetupBones()
        Legs.LegEnt:DrawModel()
        Legs.LegEnt:SetRenderOrigin()
        Legs.LegEnt:SetRenderAngles()
        render.SetBlend( 1 )
        render.SetColorModulation( 1, 1, 1 )
        render.PopCustomClipPlane()
        render.EnableClipping( bEnabled )
    end

    cam.End3D()
end

hook.Add( "PostDrawTranslucentRenderables", "GML:Render::Foot", function( _, skybox, skybox3d )
    if skybox and skybox3d then return end
    if not LocalPlayer():InVehicle() then
        doFinalRender()
    end
end )

hook.Add( "RenderScreenspaceEffects", "GML:Render::Vehicle", function()
    if LocalPlayer():InVehicle() then
        doFinalRender()
    end
end )

concommand.Add( "cl_togglelegs", function()
    if areLegsEnabled then
        RunConsoleCommand( "cl_legs", "0" )
    else
        RunConsoleCommand( "cl_legs", "1" )
    end
end )

concommand.Add( "cl_togglevlegs", function()
    if areVLegsEnabled then
        RunConsoleCommand( "cl_vehlegs", "0" )
    else
        RunConsoleCommand( "cl_vehlegs", "1" )
    end
end )

concommand.Add( "cl_refreshlegs", setupLegs )
