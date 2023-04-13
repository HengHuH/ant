local ecs = ...
local world = ecs.world
local w = world.w

local bgfx = require "bgfx"
local math3d = require "math3d"

local renderpkg = import_package "ant.render"
local sampler = renderpkg.sampler
local viewidmgr = renderpkg.viewidmgr

local icompute = ecs.import.interface "ant.render|icompute"
local iexposure = ecs.import.interface "ant.camera|iexposure"

local setting = import_package "ant.settings".setting
local irradianceSH_bandnum<const> = setting:get "graphic/ibl/irradiance_bandnum"

local ibl_viewid                = viewidmgr.get "ibl"
local ibl_SH_readback_viewid    = viewidmgr.get "ibl_SH_readback"

local thread_group_size<const> = 8

local imaterial = ecs.import.interface "ant.asset|imaterial"

local ibl_sys = ecs.system "ibl_system"

local flags<const> = sampler {
    MIN="LINEAR",
    MAG="LINEAR",
    U="CLAMP",
    V="CLAMP",
    BLIT="BLIT_COMPUTEWRITE",
}

local cubemap_flags<const> = sampler {
    MIN="LINEAR",
    MAG="LINEAR",
    MIP="LINEAR",
    U="CLAMP",
    V="CLAMP",
    W="CLAMP",
    BLIT="BLIT_COMPUTEWRITE",
}

local IBL_INFO = {
    source = {facesize = 0, stage=0, value=nil},
    irradiance   = {
        value = nil,
        size = 0,
        --enable_readback = true,
    },
    irradianceSH = {
        value = nil,
        readback_value = nil,
        readback_memory = nil,
        bandnum = irradianceSH_bandnum,
    },
    prefilter    = {
        value = nil,
        size = 0,
        mipmap_count = 0,
    },
    LUT             = {
        value = nil,
        size = 0,
    }
}

local function create_irradiance_entity()
    local size = IBL_INFO.irradiance.size
    local dispatchsize = {
        size / thread_group_size, size / thread_group_size, 6
    }
    icompute.create_compute_entity(
        "irradiance_builder", "/pkg/ant.resources/materials/ibl/build_irradiance.material", dispatchsize)
end

local function create_irradianceSH_entity()
    local size = IBL_INFO.source.facesize
    local dispatchsize = {
        size / thread_group_size, size / thread_group_size, 6
    }

    icompute.create_compute_entity("irradianceSH_builder", "/pkg/ant.resources/materials/ibl/build_irradianceSH.material", dispatchsize)
end

local function create_prefilter_entities()
    local size = IBL_INFO.prefilter.size

    local mipmap_count = IBL_INFO.prefilter.mipmap_count
    local dr = 1 / (mipmap_count-1)
    local r = 0

    local function create_prefilter_compute_entity(dispatchsize, prefilter)
        ecs.create_entity {
            policy = {
                "ant.render|compute_policy",
                "ant.render|prefilter",
                "ant.general|name",
            },
            data = {
                name        = "prefilter_builder",
                material    = "/pkg/ant.resources/materials/ibl/build_prefilter.material",
                dispatch    ={
                    size    = dispatchsize,
                },
                prefilter = prefilter,
                compute     = true,
                prefilter_builder      = true,
            }
        }
    end


    for i=1, mipmap_count do
        local s = size >> (i-1)
        local dispatchsize = {
            math.floor(s / thread_group_size), math.floor(s / thread_group_size), 6
        }

        local prefilter = {
            roughness = r,
            sample_count = s,
            mipidx = i-1,
        }
        create_prefilter_compute_entity(dispatchsize, prefilter)

        r = r + dr
    end
end

local function create_LUT_entity()
    local size = IBL_INFO.LUT.size
    local dispatchsize = {
        size / thread_group_size, size / thread_group_size, 1
    }
   icompute.create_compute_entity(
        "LUT_builder", "/pkg/ant.resources/materials/ibl/build_LUT.material", dispatchsize)
end

local ibl_mb = world:sub{"ibl_changed"}
local exp_mb = world:sub{"exposure_changed"}

local function update_ibl_param(intensity)
    local sa = imaterial.system_attribs()
    local mq = w:first("main_queue camera_ref:in")
    local camera <close> = w:entity(mq.camera_ref)
    local ev = iexposure.exposure(camera)

    intensity = intensity or 1
    intensity = intensity * IBL_INFO.intensity * ev
    sa:update("u_ibl_param", math3d.vector(IBL_INFO.prefilter.mipmap_count, intensity, 0.0 ,0.0))
end

function ibl_sys:data_changed()
    for _, enable in ibl_mb:unpack() do
        update_ibl_param(enable and 1.0 or 0.0)
    end

    for _ in exp_mb:each() do
        update_ibl_param()
    end
end

local sample_count<const> = 512


local function SHindex(m, l)
    return l * (l + 1) + m + 1
end

local factorial1, factorial2; do
    local F = setmetatable({}, {__index=function (t, n)
        local v = 1.0
        if n > 1 then
            for i=1, n do
                v = v * i
            end
        end

        t[n] = v
        return v
    end})
    factorial1 = function(n) return F[n] end
    factorial2 = function(n, d) return F[n]/F[d] end
end

local function factorial(n, d)
    d = d or 1

    d = math.max(1, d)
    n = math.max(1, n)
    local r = 1.0
    if n == d then
        -- intentionally left blank 
    elseif n > d then
        while n > d do
            r = r * n
            n = n - 1
        end
    else
        while d > n do
            r = r * d
            d = d - 1
        end
        r = 1.0 / r
    end
    return r
end

local Ki; do
    --   sqrt((2*l + 1) / 4*pi) * sqrt( (l-|m|)! / (l+|m|)! )
    local function Kml(m, l)
        m = math.abs(m)
        local K = (2 * l + 1) * factorial2(l - m, l + m) * (1.0 / math.pi) * 0.25
        return math.sqrt(K)
    end

    local K = setmetatable({}, {__index=function(t, bandnum)
        local k = {}
        local sqrt2 = math.sqrt(2)
        for l=0, bandnum-1 do
            for m = -l, l do
                k[SHindex(m, l)] = sqrt2 * Kml(m, l)
            end
        end
        t[bandnum] = k
        return k
    end})
    Ki = function(bandnum) return K[bandnum] end
end

-- < cos(theta) > SH coefficients pre-multiplied by 1 / K(0,l)
local compute_cos_SH; do
    local COS = setmetatable({}, {__index=function(t, l)
        local R
        if l == 0 then
            R = math.pi
        elseif (l == 1) then
            R = 2 * math.pi / 3;
        elseif l & 1 then
            R = 0
        else
            local l_2 = l // 2;
            local A0 = ((l_2 & 1) and 1.0 and -1.0) / ((l + 2) * (l - 1))
            local A1 = factorial2(l, l_2) / (factorial2(l_2) * (1 << l))
            R = 2 * math.pi * A0 * A1
        end

        t[l] = R
        return R
    end})

    compute_cos_SH = function (l)
        return COS[l]
    end
end

local decode_Li; do
    local DECODE_FACTOR<const> = 1.0/1000000
    decode_Li = function (r, g, b)
        return math3d.mul(DECODE_FACTOR, math3d.vector(r, g, b, 0))
    end
end

local function read_Lml()
    local rbm = IBL_INFO.irradianceSH.readback_memory
    if rbm == nil then
        return
    end

    local m = tostring(rbm)

    local Li = {}
    local num_coeffs = irradianceSH_bandnum * irradianceSH_bandnum
    local coeff_elemnum<const> = 3
    local elem_size<const> = 4
    local elem_bytes<const> = coeff_elemnum * elem_size
    for i=1, num_coeffs do
        local offset = (i-1) * elem_bytes+1
        local r, g, b = ('III'):unpack(m, offset)
        Li[#Li+1] = decode_Li(r, g, b)
    end
    return Li
end

local function mark_coeffs(Lml, bandnum)
    --calclate Ki value for cos(theta)
    local K = Ki(bandnum);

    local Eml = {}
    -- apply truncated cos (irradiance)
    for l=0, bandnum-1 do
        local cosSH = compute_cos_SH(l)
        for m = -l, l do
            local idx = SHindex(m, l)
            Eml[idx] = math3d.ref(math3d.mul(K[idx] * cosSH, Lml[idx]))
        end
    end

    IBL_INFO.irradianceSH.GPU = {
        Eml = Eml,
        Lml = Lml,
    }

    local sa = imaterial.system_attribs()
    sa:update("u_irradianceSH", Eml)
end

local function read_irradiance_map()
    local rbm = IBL_INFO.irradiance.readback_memory
    if rbm == nil then return end

    return {
        w = IBL_INFO.irradiance.size,
        h = IBL_INFO.irradiance.size,
        data = tostring(rbm),
    }
end

local function check_irradiance()
    local irradianceSH = IBL_INFO.irradianceSH
    if irradianceSH.endcheck then
        return
    end
    local irradiance = IBL_INFO.irradiance
    local ib = w:first "irradiance_builder"
    local iSHb = w:first "irradianceSH_builder"
    if irradianceSH.CPU and irradianceSH.GPU and not (ib or iSHb) then
        local sh = require "ibl.sh"
        local image = require "image"
        local restex = IBL_INFO.source.tex_name
        local lfs = require "filesystem.local"
        local cr = import_package "ant.compile_resource"
        local r = cr.compile(restex .. "|main.bin")
        local f<close> = lfs.open(r, "rb")
        local texinfo, texcontent = image.parse(f:read "a", true)
        local tu = require "ibl.texture"
        local texelsize = image.get_format_sizebytes "RGBA32F"
        local src_cm = tu.create_cubemap{w=texinfo.width, h=texinfo.height, data=texcontent, texelsize=texelsize}

        local Eml = sh.calc_Eml(src_cm, irradianceSH_bandnum)
        
        local N = math3d.normalize(math3d.vector(1, 0, 0, 1))

        local irrad_cm_decl = assert(irradiance.readback_irradiance_value)
        irrad_cm_decl.texelsize = texelsize
        local cm_irrad = tu.create_cubemap(irrad_cm_decl)
        local sample_result = cm_irrad:sample(N)
        local render_result = sh.render_SH(Eml, N)
        print("sample:", math3d.tostring(sample_result), "sh render:", math3d.tostring(render_result))

        irradianceSH.endcheck = true
    end
end

function ibl_sys:render_preprocess()
    local source_tex = IBL_INFO.source
    for e in w:select "irradiance_builder dispatch:in" do
        local function dispatch_irradiance_map()
            local dis = e.dispatch
            local material = dis.material
            material.s_source = source_tex
            material.u_build_ibl_param = math3d.vector(sample_count, 0, IBL_INFO.source.facesize, 0.0)
    
            -- there no binding attrib in material, but we just use this entity only once
            local mobj = material:get_material()
            mobj:set_attrib("s_irradiance", icompute.create_image_property(IBL_INFO.irradiance.value, 1, 0, "w"))
    
            icompute.dispatch(ibl_viewid, dis)
        end

        if IBL_INFO.irradiance.enable_readback then
            if not IBL_INFO.irradiance.already_readed then
                dispatch_irradiance_map()
                bgfx.blit(ibl_SH_readback_viewid, IBL_INFO.irradiance.readback_value, 0, 0, IBL_INFO.irradiance.value)
                bgfx.read_texture(IBL_INFO.irradiance.readback_value, IBL_INFO.irradiance.readback_memory)
                IBL_INFO.irradiance.already_readed = 1
            elseif IBL_INFO.irradiance.already_readed == 2 then
                IBL_INFO.irradiance.readback_irradiance_value = read_irradiance_map()
                w:remove(e)
            else
                IBL_INFO.irradiance.already_readed = IBL_INFO.irradiance.already_readed + 1
            end
        else
            dispatch_irradiance_map()
            w:remove(e)
        end
    end

    for e in w:select "irradianceSH_builder dispatch:in" do
        local irradianceSH = IBL_INFO.irradianceSH
        if not irradianceSH.already_readed then
            local dis = e.dispatch
            local material = dis.material
            material.s_source = source_tex
            material.s_irradianceSH = irradianceSH.value
            material.u_build_ibl_param = math3d.vector(irradianceSH.bandnum, 0, IBL_INFO.source.facesize, 0)
            icompute.dispatch(ibl_viewid, dis)

            bgfx.blit(ibl_SH_readback_viewid, irradianceSH.readback_value, 0, 0, irradianceSH.value)
            bgfx.read_texture(irradianceSH.readback_value, irradianceSH.readback_memory)

            irradianceSH.already_readed = 1
        elseif irradianceSH.already_readed == 2 then
            mark_coeffs(read_Lml(), IBL_INFO.irradianceSH.bandnum)
            w:remove(e)
        else
            irradianceSH.already_readed = irradianceSH.already_readed + 1
        end
    end

    if IBL_INFO.irradiance.enable_readback then
        check_irradiance()
    end

    local registered
    for e in w:select "prefilter_builder dispatch:in prefilter:in" do
        local dis = e.dispatch
        local material = dis.material
        local prefilter_stage<const> = 1
        if registered == nil then
            local matobj = material:get_material()
            matobj:set_attrib("s_prefilter", {type='i', mip=0, access='w', stage=prefilter_stage})
            registered = true
        end

        material.s_source = source_tex
        local prefilter = e.prefilter
        material.u_build_ibl_param = math3d.vector(sample_count, 0, IBL_INFO.source.facesize, prefilter.roughness)
        material.s_prefilter = icompute.create_image_property(IBL_INFO.prefilter.value, prefilter_stage, prefilter.mipidx, "w")

        icompute.dispatch(ibl_viewid, dis)
        w:remove(e)
    end

    local LUT_stage<const> = 0
    for e in w:select "LUT_builder dispatch:in" do
        local dis = e.dispatch
        local material = dis.material
        local matobj = material:get_material()
        matobj:set_attrib("s_LUT", icompute.create_image_property(IBL_INFO.LUT.value, LUT_stage, 0, "w"))
        icompute.dispatch(ibl_viewid, dis)

        w:remove(e)
    end
end

local iibl = ecs.interface "iibl"

function iibl.get_ibl()
    return IBL_INFO
end

function iibl.set_ibl_intensity(intensity)
    IBL_INFO.intensity = intensity
    update_ibl_param()
end

local function build_ibl_textures(ibl)
    local function check_destroy(handle)
        if handle then
            bgfx.destroy(handle)
        end
    end

    IBL_INFO.intensity = ibl.intensity

    IBL_INFO.source.value = assert(ibl.source.value)
    IBL_INFO.source.facesize = assert(ibl.source.facesize)
    IBL_INFO.source.tex_name = ibl.source.tex_name

    if irradianceSH_bandnum then
        IBL_INFO.irradianceSH.bandnum = irradianceSH_bandnum
        IBL_INFO.irradianceSH.CPU = ibl.irradianceSH.CPU
        check_destroy(IBL_INFO.irradianceSH.value)
        local coeffsnum = IBL_INFO.irradianceSH.bandnum * IBL_INFO.irradianceSH.bandnum
        --must be R32U since we need to use imageAtmoicAdd, it only support R32U or R32I
        local elemcount<const> = 3
        local width<const> = coeffsnum * elemcount
        IBL_INFO.irradianceSH.value = bgfx.create_texture2d(width, 1, false, 1, "R32U", sampler {
            MIN="POINT",
            MAG="POINT",
            U="CLAMP",
            V="CLAMP",
            BLIT="BLIT_COMPUTEWRITE",
        })

        check_destroy(IBL_INFO.irradianceSH.readback_value)
        IBL_INFO.irradianceSH.readback_value = bgfx.create_texture2d(width, 1, false, 1, "R32U", sampler {
            MIN="POINT",
            MAG="POINT",
            U="CLAMP",
            V="CLAMP",
            BLIT="BLIT_AS_DST|BLIT_READBACK_ON",
        })

        IBL_INFO.irradianceSH.readback_memory = bgfx.memory_texture(width*4)    -- 4 for sizeof(uint32_t)
    end

    if ibl.irradiance.size ~= IBL_INFO.irradiance.size then
        IBL_INFO.irradiance.size = ibl.irradiance.size
        check_destroy(IBL_INFO.irradiance.value)

        local fmt = IBL_INFO.irradiance.enable_readback and "RGBA32F" or "RGBA16F"

        IBL_INFO.irradiance.value = bgfx.create_texturecube(IBL_INFO.irradiance.size, false, 1, fmt, flags)

        if IBL_INFO.irradiance.enable_readback then
            local readback_flags = sampler {
                MIN="POINT",
                MAG="POINT",
                U="CLAMP",
                V="CLAMP",
                BLIT="BLIT_AS_DST|BLIT_READBACK_ON",
            }

            local face_bytes = IBL_INFO.irradiance.size * IBL_INFO.irradiance.size * 16
    
            IBL_INFO.irradiance.readback_value = bgfx.create_texturecube(IBL_INFO.irradiance.size, false, 1, fmt, readback_flags)
            IBL_INFO.irradiance.readback_memory = bgfx.memory_texture(face_bytes * 6)
        end
    end

    if ibl.prefilter.size ~= IBL_INFO.prefilter.size then
        IBL_INFO.prefilter.size = ibl.prefilter.size
        check_destroy(IBL_INFO.prefilter.value)
        IBL_INFO.prefilter.value = bgfx.create_texturecube(IBL_INFO.prefilter.size, true, 1, "RGBA16F", cubemap_flags)
        IBL_INFO.prefilter.mipmap_count = math.log(ibl.prefilter.size, 2)+1
    end

    if ibl.LUT.size ~= IBL_INFO.LUT.size then
        IBL_INFO.LUT.size = ibl.LUT.size
        check_destroy(IBL_INFO.LUT.value)
        IBL_INFO.LUT.value = bgfx.create_texture2d(IBL_INFO.LUT.size, IBL_INFO.LUT.size, false, 1, "RG16F", flags)
    end
end


local function create_ibl_entities()
    if irradianceSH_bandnum then
        create_irradianceSH_entity()
        if IBL_INFO.irradiance.enable_readback then
            create_irradiance_entity()
        end
    else
        create_irradiance_entity()
    end
    create_prefilter_entities()
    create_LUT_entity()
end

local function update_ibl_texture_info()
    local sa = imaterial.system_attribs()
    if not irradianceSH_bandnum then
        sa:update("s_irradiance", IBL_INFO.irradiance.value)
    end
    sa:update("s_prefilter", IBL_INFO.prefilter.value)
    sa:update("s_LUT",  IBL_INFO.LUT.value)

    update_ibl_param()
end

function iibl.filter_all(ibl)
    build_ibl_textures(ibl)
    create_ibl_entities()

    update_ibl_texture_info()
end