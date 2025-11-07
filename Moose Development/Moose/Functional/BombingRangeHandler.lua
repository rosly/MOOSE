--- **Functional** - Bombing range event handler.
--
-- @module Functional.BombingRangeHandler

---
-- @type BOMBING_RANGE_HANDLER
-- @extends Core.Event#EVENTHANDLER
BOMBING_RANGE_HANDLER = {
  ClassName = "BOMBING_RANGE_HANDLER",
}

--- Create a new bombing range handler monitoring the given zone.
-- @param #BOMBING_RANGE_HANDLER self
-- @param #string ZoneName Name of the editor-defined zone representing the bombing range.
-- @return #BOMBING_RANGE_HANDLER
function BOMBING_RANGE_HANDLER:New( ZoneName )

  local self = BASE:Inherit( self, EVENTHANDLER:New() )

  self.ZoneName = ZoneName
  self.Tracking = {}
  self.BombingZone = self:_CreateBombingZone( ZoneName )

  if not self.BombingZone then
    self:E( { "Unable to locate bombing zone", ZoneName = ZoneName } )
    return self
  end

  self:HandleEvent( EVENTS.TriggerZone, self.OnEventTriggerZone )
  self:HandleEvent( EVENTS.Dead, self.OnEventDead )

  return self
end

--- Locate the bombing range zone using the global database registration.
-- @param #BOMBING_RANGE_HANDLER self
-- @param #string ZoneName
-- @return Core.Zone#ZONE_BASE|nil
function BOMBING_RANGE_HANDLER:_CreateBombingZone( ZoneName )

  local PolygonZone = ZONE_POLYGON:FindByName( ZoneName )
  if PolygonZone then
    return PolygonZone
  end

  local BaseZone = ZONE:FindByName( ZoneName )
  if BaseZone then
    return BaseZone
  end

  return nil
end

--- DCS trigger zone event hook.
-- @param #BOMBING_RANGE_HANDLER self
-- @param Core.Event#EVENTDATA EventData
function BOMBING_RANGE_HANDLER:OnEventTriggerZone( EventData )

  if not EventData or not self.BombingZone then
    return
  end

  local Unit = EventData.IniUnit
  if not Unit or not Unit:IsAir() then
    return
  end

  local UnitName = Unit:GetName()
  local SubtypeEnter = world.event.S_EVENT_TRIGGER_ZONE_ENTER or 1
  local SubtypeLeave = world.event.S_EVENT_TRIGGER_ZONE_LEAVE or 2

  local ZoneName = EventData.ZoneName or ( EventData.Zone and EventData.Zone.ZoneName )
  if ZoneName and ZoneName ~= self.BombingZone:GetName() then
    return
  end

  if EventData.subtype == SubtypeEnter then
    local Track = {
      unit = Unit,
      enter_time = EventData.time or timer.getTime(),
      enter_altitude = Unit:GetAltitude(),
      enter_speed = Unit:GetVelocityKMH(),
      pitch_sum = 0,
      speed_sum = 0,
      sample_count = 0,
      last_altitude = Unit:GetAltitude(),
      last_speed = Unit:GetVelocityKMH(),
    }

    Track.scheduler, Track.schedulerid = SCHEDULER:New(
      self,
      self._UpdateTrackedUnit,
      { UnitName },
      0,
      1
    )

    self.Tracking[UnitName] = Track

    return
  end

  if EventData.subtype == SubtypeLeave then
    self:_FinalizeTracking( UnitName, "left the zone", EventData )
  end
end

--- DCS dead event hook to stop tracking destroyed units.
-- @param #BOMBING_RANGE_HANDLER self
-- @param Core.Event#EVENTDATA EventData
function BOMBING_RANGE_HANDLER:OnEventDead( EventData )

  if not EventData then
    return
  end

  local Unit = EventData.IniUnit
  if not Unit then
    return
  end

  local UnitName = Unit:GetName()
  if not self.Tracking[UnitName] then
    return
  end

  self:_FinalizeTracking( UnitName, "was destroyed", EventData )
end

--- Periodically update the tracked unit statistics while it remains inside the zone.
-- @param #BOMBING_RANGE_HANDLER self
-- @param #string UnitName
function BOMBING_RANGE_HANDLER:_UpdateTrackedUnit( UnitName )

  local Track = self.Tracking[UnitName]
  if not Track then
    return
  end

  local Unit = Track.unit
  if not Unit or not Unit:IsAlive() then
    return
  end

  Track.last_altitude = Unit:GetAltitude()
  Track.last_speed = Unit:GetVelocityKMH()

  local Pitch = Unit:GetPitch()
  local VelocityVec3 = Unit:GetVelocityVec3()
  local Speed = VelocityVec3 and UTILS.VecNorm( VelocityVec3 ) or 0

  if Pitch and Pitch <= -10 and Speed then
    Track.pitch_sum = Track.pitch_sum + Pitch
    Track.speed_sum = Track.speed_sum + Speed
    Track.sample_count = Track.sample_count + 1
  end
end

--- Stop tracking a unit and broadcast the collected statistics.
-- @param #BOMBING_RANGE_HANDLER self
-- @param #string UnitName
-- @param #string Reason
-- @param Core.Event#EVENTDATA EventData
function BOMBING_RANGE_HANDLER:_FinalizeTracking( UnitName, Reason, EventData )

  local Track = self.Tracking[UnitName]
  if not Track then
    return
  end

  if Track.scheduler and Track.schedulerid then
    Track.scheduler:Stop( Track.schedulerid )
    Track.scheduler = nil
    Track.schedulerid = nil
  end

  local Unit = Track.unit
  local ExitTime = ( EventData and EventData.time ) or timer.getTime()
  local Duration = ExitTime - Track.enter_time

  local ExitAltitude = Track.last_altitude or 0
  local ExitSpeed = Track.last_speed or 0

  local AveragePitch
  local AverageSpeed
  if Track.sample_count > 0 then
    AveragePitch = Track.pitch_sum / Track.sample_count
    AverageSpeed = Track.speed_sum / Track.sample_count
  end

  local AveragePitchText = AveragePitch and string.format( "%.1f°", AveragePitch ) or "N/A"
  local AverageSpeedText = AverageSpeed and string.format( "%.0f km/h (%.0f m/s)", UTILS.MpsToKmph( AverageSpeed ), AverageSpeed ) or "N/A"
  local MessageText = string.format(
    "%s bombing run summary (%s):\n  Entry Altitude: %.0f m\n  Entry Speed: %.0f km/h\n  Exit Altitude: %.0f m\n  Exit Speed: %.0f km/h\n  Time in Zone: %.1f s\n  Avg Dive Pitch: %s\n  Avg Dive Speed: %s",
    UnitName,
    Reason or "completed",
    Track.enter_altitude,
    Track.enter_speed,
    ExitAltitude,
    ExitSpeed,
    Duration,
    AveragePitchText,
    AverageSpeedText
  )

  MESSAGE:New( MessageText, 15 ):ToAll()

  self.Tracking[UnitName] = nil
end

