--[[
  Copyright 2017-2019 Stefano Mazzucco <stefano AT curso DOT re>

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.

  This program was inspired by the
  [Awesome Pulseaudio Widget (APW)](https://github.com/mokasin/apw)
]]
local awful   = require("awful")
local gears   = require("gears")
local wibox   = require("wibox")
local naughty = require("naughty")

local pulse   = require("pulseaudio_dbus")

local widget = {}
widget.widget = wibox.widget {
  {
    id = 'sink',
    widget = wibox.widget.textbox
  },
  {
    id = 'source',
    widget = wibox.widget.textbox
  },
  spacing = 5,
  layout = wibox.layout.fixed.horizontal
}

awful.tooltip { text = "pulse(sink)"  , objects = { widget.widget.sink   } }
awful.tooltip { text = "pulse(source)", objects = { widget.widget.source } }

function widget:refresh(device)
    local color = self[device]:is_muted() and 'dimgray' or 'darkgray'
    self.widget[device].markup = string.format("<span foreground='%s'>%d</span>", color, self[device]:get_volume_percent()[1])
end

function widget:notify(v)
  local msg = tonumber(v) and string.format("%d%%", v) or v
  if self.notification then
    naughty.destroy(self.notification, naughty.notificationClosedReason.dismissedByCommand)
  end
  self.notification = naughty.notify({text=msg, timeout=self.notify_timeout_sec})
end

function widget:update_sink(object_path)
  self.sink = pulse.get_device(self.connection, object_path, 5, 100)
end

function widget:update_sources(sources)
  for _, source_path in ipairs(sources) do
    local s = pulse.get_device(self.connection, source_path, 5, 100)
    if s.Name and not s.Name:match("%.monitor$") then
      self.source = s
      break
    else
      self.source = nil
    end
  end
end

function widget.volume_up(device)
  if widget[device] then
    widget[device]:volume_up()
  end
end

function widget.volume_down(device)
  if widget[device] then
    widget[device]:volume_down()
  end
end

function widget.toggle_muted(device)
  if widget[device] then
    widget[device]:toggle_muted()
  end
end

for _,device in pairs({'sink', 'source'}) do
  widget.widget[device]:buttons(
    gears.table.join(
      awful.button({ }, 1, function() widget.toggle_muted(device) end),
      awful.button({ }, 3, function() awful.spawn(widget.mixer)   end),
      awful.button({ }, 4, function() widget.volume_up(device)    end),
      awful.button({ }, 5, function() widget.volume_down(device)  end)
    )
  )
end

function widget:connect_device(device)
  if not device then
    return
  end

  if device.signals.VolumeUpdated then
    device:connect_signal(
      function (this, volume)
        -- FIXME: BaseVolume for sources (i.e. microphones) won't give the correct percentage
        -- local v = math.ceil(tonumber(volume[1]) / this.BaseVolume * 100)
        if this.object_path == self.sink.object_path then
          self:refresh('sink')
        elseif self.source and this.object_path == self.source.object_path then
          self:refresh('source')
        end
      end,
      "VolumeUpdated"
    )
  end

  if device.signals.MuteUpdated then
    device:connect_signal(
      function (this, is_mute)
        if this.object_path == self.sink.object_path then
          self:refresh('sink')
        elseif self.source and this.object_path == self.source.object_path then
          self:refresh('source')
        end
      end,
      "MuteUpdated"
    )
  end
end

function widget:init()
  local status, address = pcall(pulse.get_address)
  if not status then
    naughty.notify(
      {
        title="Error while loading the PulseAudio widget",
        text=address,
        preset=naughty.config.presets.critical
      }
    )
    return self
  end

  self.mixer = "pavucontrol"
  self.notify_timeout_sec = 5

  self.connection = pulse.get_connection(address)
  self.core = pulse.get_core(self.connection)

  -- listen on ALL objects as sinks and sources may change
  self.core:ListenForSignal("org.PulseAudio.Core1.Device.VolumeUpdated", {})
  self.core:ListenForSignal("org.PulseAudio.Core1.Device.MuteUpdated", {})

  self.core:ListenForSignal("org.PulseAudio.Core1.NewSink", {self.core.object_path})
  self.core:connect_signal(
    function (_, newsink)
      self:update_sink(newsink)
      self:connect_device(self.sink)
      self:refresh('sink')
    end,
    "NewSink"
  )

  self.core:ListenForSignal("org.PulseAudio.Core1.NewSource", {self.core.object_path})
  self.core:connect_signal(
    function (_, newsource)
      self:update_sources({newsource})
      self:connect_device(self.source)
      self:refresh('source')
    end,
    "NewSource"
  )

  self:update_sources(self.core:get_sources())
  self:connect_device(self.source)
  self:refresh('source')

  local sink_path = assert(self.core:get_sinks()[1], "No sinks found")
  self:update_sink(sink_path)
  self:connect_device(self.sink)
  self:refresh('sink')

  self.__index = self

  return self
end

return widget:init()

