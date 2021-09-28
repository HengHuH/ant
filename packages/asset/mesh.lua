local ecs = ...
local world = ecs.world
local m = ecs.component "mesh"

local assetmgr = require "asset"
local ext_meshbin = require "ext_meshbin"

local function init_mesh(self)
	if type(self) == "string" then
		return assetmgr.resource(self)
	end
	self.procedural_mesh = true
    return ext_meshbin.init(self)
end

m.init = init_mesh

function m:delete()
	if self.procedural_mesh then
		ext_meshbin.delete(self)
	end
end

local mbt = ecs.transform "mesh_bounding_transform"
function mbt.process_entity(e)
	local m = e.mesh
	if m.bounding and m.bounding.aabb then
		e._bounding.aabb = m.bounding.aabb
	end
end

local mpt = ecs.transform "mesh_prefab_transform"

local function create_rendermesh(mesh)
	if mesh then
		local handles = {}
		local vb = {
			start   = mesh.vb.start,
			num     = mesh.vb.num,
			handles = handles,
		}
		for _, v in ipairs(mesh.vb) do
			handles[#handles+1] = v.handle
		end
		local ib
		if mesh.ib then
			ib = {
				start	= mesh.ib.start,
				num 	= mesh.ib.num,
				handle	= mesh.ib.handle,
			}
		end

		return vb, ib
	end
end

function mpt.process_prefab(e)
	local mesh = e.mesh
	local c = e._cache_prefab
	if mesh then
		c.vb, c.ib = create_rendermesh(mesh)
	end
end

local mt = ecs.transform "mesh_transform"

function mt.process_entity(e)
	local rc = e._rendercache
	local c = e._cache_prefab

	rc.vb = c.vb
	rc.ib = c.ib
end

local smt = ecs.transform "simple_mesh_transform"
function smt.process_entity(e)
	local s = e.simplemesh
	local rc = e._rendercache
	rc.vb = s.vb
	rc.ib = s.ib
end


local imesh = ecs.interface "imesh"
function imesh.create_vb(vb)
	return ext_meshbin.proxy_vb(vb)
end

function imesh.create_ib(ib)
	return ext_meshbin.proxy_ib(ib)
end

imesh.create_rendermesh = create_rendermesh

----mesh_v2
local w = world.w
local m = ecs.system "mesh_system"
function m:entity_init()
    for e in w:select "INIT mesh:in render_object:in" do
		--TODO: e.mesh must string or mesh with vb/ib
		if 	type(e.mesh) == "string" or 
			(type(e.mesh) == "table" and e.mesh._data == nil) then
			local ro = e.render_object
			local mm = init_mesh(e.mesh)
			ro.vb, ro.ib = create_rendermesh(mm)
			if mm.procedural_mesh then
				e.procedural_mesh = true
				w:sync("procedural_mesh?out", e)
			end
		end
	end

	for e in w:select "INIT simplemesh:in render_object:in" do
		local ro, sm = e.render_object, e.simplemesh
		ro.vb, ro.ib = create_rendermesh(sm)
		if sm.procedural_mesh then
			e.procedural_mesh = true
			w:sync("procedural_mesh?out", e)
		end
	end
end

function m:end_frame()
	for e in w:select "REMOVED procedural_mesh render_object:in mesh:in" do
		if e.procedural_mesh then
			ext_meshbin.delete(e.render_object)
		end
	end
end