local ecs = ...
local world = ecs.world
local w = world.w
ecs.require "widget.base_view"
local imgui         = require "imgui"
local utils         = require "common.utils"
local math3d        = require "math3d"
local uiproperty    = require "widget.uiproperty"
local hierarchy     = require "hierarchy_edit"
local effekseer     = require "effekseer"
local BaseView      = require "widget.view_class".BaseView
local EffectView    = require "widget.view_class".EffectView
local ui_auto_play  = {false}

function EffectView:_init()
    BaseView._init(self)
    self.speed = uiproperty.Float({label = "Speed", min = 0.01, max = 10.0, speed = 0.01}, {})
end

function EffectView:set_model(eid)
    if not BaseView.set_model(self, eid) then return false end
    for e in w:select "scene:in effekseer:in effect_instance:in" do
        if e.scene == eid.scene then
            self.speed:set_getter(function() return e.effect_instance.speed end)
            self.speed:set_setter(function(v) self:on_set_speed(v) end)
        end
    end
    -- if world[eid].effekseer and world[eid].effect_instance then
    --     --local tp = hierarchy:get_template(eid)
    --     self.speed:set_getter(function() return world[eid].effect_instance.speed end)
    --     self.speed:set_setter(function(v) self:on_set_speed(v) end)
    -- end
    self:update()
    return true
end

function EffectView:update()
    BaseView.update(self)
    self.speed:update()
    local template = hierarchy:get_template(self.e)
    ui_auto_play[1] = template.template.data.auto_play
end

function EffectView:show()
    BaseView.show(self)
    self.speed:show()
    imgui.widget.PropertyLabel("auto_play")
    if imgui.widget.Checkbox("##auto_play", ui_auto_play) then
        self:on_set_auto_play(ui_auto_play[1])
    end
    -- imgui.widget.PropertyLabel("loop")
    -- if imgui.widget.Checkbox("##loop", ui_loop) then
    --     self:on_set_loop(ui_loop[1])
    -- end
    imgui.widget.PropertyLabel("Play")
    if imgui.widget.Button("Play") then
        w:sync("effect_instance:in", self.e)
        local instance = self.e.effect_instance
        instance.playid = effekseer.play(instance.handle, instance.playid)
        effekseer.set_speed(instance.handle, instance.playid, instance.speed)
    end
end

function EffectView:on_set_speed(value)
    local template = hierarchy:get_template(self.e)
    template.template.data.speed = value
    if not self.e.effect_instance then
        w:sync("effect_instance:in", self.e)
    end
    local instance = self.e.effect_instance
    instance.speed = value
    effekseer.set_speed(instance.handle, instance.playid, value)
end

function EffectView:on_set_auto_play(value)
    local template = hierarchy:get_template(self.e)
    template.template.data.auto_play = value
end

function EffectView:on_set_loop(value)
    if not self.e.effect_instance then
        w:sync("effect_instance:in", self.e)
    end
    local instance = self.e.effect_instance
    instance.loop = value
    effekseer.set_loop(instance.handle, instance.playid, value)
end

return EffectView