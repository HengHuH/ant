local fs = require "filesystem.local"

local subprocess = require "utility.sp_util"
local fs_local = require "utility.fs_local"

local function convert(filename, outfile)
	local toolexe = fs_local.valid_tool_exe_path "FBX2glTF-windows-x64"
	outfile = outfile or filename
	outfile = fs.path(outfile):replace_extension("")	-- should not pass filename with extension, just filename without any extension
	local commands = {
		toolexe:string(),
		"-i", filename:string(),
		"-o", outfile:string(),
		"-b", 
		"--compute-normals", "missing",
		"--pbr-metallic-roughness",
		stdout = true,
		stderr = true,
		hideWindow = true,
	}
	local notwait<const> = true
	return subprocess.spawn_process(commands, nil, notwait)
end

return function(files, postconvert)
	local progs = {}
	for _, filepair in ipairs(files) do
		local inputfile, outfile = filepair[1], filepair[2]
		if fs.is_regular_file(inputfile) then
			progs[#progs+1] = {convert(inputfile, outfile), inputfile}
		end
	end

	local results = {}
	for _, prog in ipairs(progs) do
		local pp, f = prog[1], prog[2]
		local success, msg = pp.wait()
		print("convert file:", f:string(), success and "success" or "failed")
		print(msg)

		if success then
			if postconvert then
				local glbloader = require "glTF.glb"
				local glbfilepath = fs.path(f):replace_extension("glb")
				local glbfilename = glbfilepath:string()
				local glbdata = glbloader.decode(glbfilename)
				local scene = glbdata.info

				postconvert(glbfilepath, scene)

				glbloader.encode(glbfilename, glbdata)
			end

			results[#results+1] = f
		end
	end

	return results
end