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
    self.Tracking[UnitName] = {
      unit = Unit,
      enter_time = EventData.time or timer.getTime(),
      enter_altitude = Unit:GetAltitude(),
      enter_speed = Unit:GetVelocityKMH(),
    }

    return
  end

  if EventData.subtype == SubtypeLeave then
    local Track = self.Tracking[UnitName]
    if not Track then
      return
    end

    local ExitTime = EventData.time or timer.getTime()
    local Duration = ExitTime - Track.enter_time
    local ExitAltitude = Unit:GetAltitude()
    local ExitSpeed = Unit:GetVelocityKMH()

    local MessageText = string.format(
      "%s bombing run summary:\n  Entry Altitude: %.0f m\n  Entry Speed: %.0f km/h\n  Exit Altitude: %.0f m\n  Exit Speed: %.0f km/h\n  Time in Zone: %.1f s",
      UnitName,
      Track.enter_altitude,
      Track.enter_speed,
      ExitAltitude,
      ExitSpeed,
      Duration
    )

    MESSAGE:New( MessageText, 15 ):ToAll()

    self.Tracking[UnitName] = nil
  end
end

