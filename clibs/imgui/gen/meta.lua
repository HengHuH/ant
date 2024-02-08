local BlackList <const> = {
    ImGui_GetCurrentContext = true,
    ImGui_SetCurrentContext = true,
    ImGui_GetStyle = true,
    ImGui_GetDrawData = true,
    ImGui_ShowDemoWindow = true,
    ImGui_ShowMetricsWindow = true,
    ImGui_ShowDebugLogWindow = true,
    ImGui_ShowIDStackToolWindow = true,
    ImGui_ShowIDStackToolWindowEx = true,
    ImGui_ShowAboutWindow = true,
    ImGui_ShowStyleEditor = true,
    ImGui_ShowStyleSelector = true,
    ImGui_ShowFontSelector = true,
    ImGui_ShowUserGuide = true,
    ImGui_StyleColorsDark = true,
    ImGui_StyleColorsLight = true,
    ImGui_StyleColorsClassic = true,

    ImGui_Columns = true,
    ImGui_ColumnsEx = true,
    ImGui_NextColumn = true,
    ImGui_GetColumnIndex = true,
    ImGui_GetColumnWidth = true,
    ImGui_SetColumnWidth = true,
    ImGui_GetColumnOffset = true,
    ImGui_SetColumnOffset = true,
    ImGui_GetColumnsCount = true,

    ImGui_LogToTTY = true,
    ImGui_LogToFile = true,
    ImGui_LogToClipboard = true,
    ImGui_LogFinish = true,
    ImGui_LogButtons = true,
    ImGui_LogText = true,
    ImGui_LogTextUnformatted = true,
    ImGui_LogTextV = true,

    ImGui_SetAllocatorFunctions = true,
    ImGui_GetAllocatorFunctions = true,
    ImGui_MemAlloc = true,
    ImGui_MemFree = true,

    ImGui_DebugTextEncoding = true,
    ImGui_DebugFlashStyleColor = true,
    ImGui_DebugCheckVersionAndDataLayout = true,

    ImGui_GetPlatformIO = true,
    ImGui_RenderPlatformWindowsDefaultEx = true,
    ImGui_DestroyPlatformWindows = true,
    ImGui_FindViewportByPlatformHandle = true,

    ImGui_TextUnformatted = true,
    ImGui_TextUnformattedEx = true,
    ImGui_TextV = true,
    ImGui_TextColoredUnformatted = true,
    ImGui_TextColoredV = true,
    ImGui_TextDisabledUnformatted = true,
    ImGui_TextDisabledV = true,
    ImGui_TextWrappedUnformatted = true,
    ImGui_TextWrappedV = true,
    ImGui_LabelTextUnformatted = true,
    ImGui_LabelTextV = true,
    ImGui_BulletTextUnformatted = true,
    ImGui_BulletTextV = true,

    ImGui_SetTooltipUnformatted = true,
    ImGui_SetTooltipV = true,
    ImGui_SetItemTooltipUnformatted = true,
    ImGui_SetItemTooltipV = true,
    ImGui_TreeNodeStrUnformatted = true,
    ImGui_TreeNodePtrUnformatted = true,
    ImGui_TreeNodeV = true,
    ImGui_TreeNodeVPtr = true,
    ImGui_TreeNodeExStrUnformatted = true,
    ImGui_TreeNodeExPtrUnformatted = true,
    ImGui_TreeNodeExV = true,
    ImGui_TreeNodeExVPtr = true,

    ImGui_ColorConvertRGBtoHSV = true,
    ImGui_ColorConvertHSVtoRGB = true,
}

local TodoList <const> = {
    ImGui_TableGetSortSpecs = true,
    ImGui_SetNextWindowClass = true,
    ImGui_DockSpaceOverViewportEx = true,
    ImGui_GetBackgroundDrawList = true,
    ImGui_GetForegroundDrawList = true,
    ImGui_GetBackgroundDrawListImGuiViewportPtr = true,
    ImGui_GetForegroundDrawListImGuiViewportPtr = true,
    ImGui_GetDrawListSharedData = true,
    ImGui_SetStateStorage = true,
    ImGui_GetStateStorage = true,
    ImGui_IsMousePosValid = true,

    ImGui_PlotLines = true,
    ImGui_PlotLinesEx = true,
    ImGui_PlotLinesCallback = true,
    ImGui_PlotLinesCallbackEx = true,
    ImGui_PlotHistogram = true,
    ImGui_PlotHistogramEx = true,
    ImGui_PlotHistogramCallback = true,
    ImGui_PlotHistogramCallbackEx = true,

    ImGui_ListBox = true,
    ImGui_ListBoxCallback = true,
    ImGui_ListBoxCallbackEx = true,

    ImGui_ColorPicker4 = true,

    ImGui_InputScalar = true,
    ImGui_InputScalarEx = true,
    ImGui_InputScalarN = true,
    ImGui_InputScalarNEx = true,
    ImGui_DragScalar = true,
    ImGui_DragScalarEx = true,
    ImGui_DragScalarN = true,
    ImGui_DragScalarNEx = true,
    ImGui_SliderScalar = true,
    ImGui_SliderScalarEx = true,
    ImGui_SliderScalarN = true,
    ImGui_SliderScalarNEx = true,
    ImGui_VSliderScalar = true,
    ImGui_VSliderScalarEx = true,
    ImGui_VSliderScalarN = true,
    ImGui_VSliderScalarNEx = true,

    ImGui_GetWindowDrawList  = true,
    ImGui_SetNextWindowSizeConstraints = true,
    ImGui_ComboChar = true,
    ImGui_ComboCharEx = true,
    ImGui_ComboCallback = true,
    ImGui_ComboCallbackEx = true,
    ImFontAtlas_GetTexDataAsAlpha8 = true,
    ImFontAtlas_GetTexDataAsRGBA32 = true,
    ImFontAtlas_GetCustomRectByIndex = true,
}

local TodoClass <const> = {
    ImFont = true,
    ImFontGlyphRangesBuilder = true,
    ImFontAtlasCustomRect = true,
    ImDrawData = true,
    ImDrawList = true,
    ImDrawCmd = true,
    ImDrawListSplitter = true,
    ImGuiTextBuffer = true,
    ImGuiTextFilter = true,
    ImGuiTextFilter_ImGuiTextRange = true,
    ImGuiListClipper = true,
    ImGuiPayload = true,
    ImGuiStorage = true,
    ImGuiStyle = true,
    ImColor = true,
}

local function conditionals(t)
    local cond = t.conditionals
    if not cond then
        return true
    end
    assert(#cond == 1)
    cond = cond[1]
    if cond.condition == "ifndef" then
        cond = cond.expression
        if cond == "IMGUI_DISABLE_OBSOLETE_KEYIO" then
            return
        end
        if cond == "IMGUI_DISABLE_OBSOLETE_FUNCTIONS" then
            return
        end
    elseif cond.condition == "ifdef" then
        cond = cond.expression
        if cond == "IMGUI_DISABLE_OBSOLETE_KEYIO" then
            return true
        end
        if cond == "IMGUI_DISABLE_OBSOLETE_FUNCTIONS" then
            return true
        end
    end
    assert(false, t.name)
end

local function allow(func_meta)
    if func_meta.is_internal then
        return
    end
    if func_meta.is_manual_helper then
        return
    end
    if not conditionals(func_meta) then
        return
    end
    if BlackList[func_meta.name] then
        return
    end
    if TodoList[func_meta.name] then
        return
    end
    if func_meta.original_class then
        if TodoClass[func_meta.original_class] then
            return
        end
        return true
    end
    return true
end

local function cimgui_json(AntDir)
    local json = dofile(AntDir.."/pkg/ant.json/main.lua")
    local function readall(path)
        local f <close> = assert(io.open(path, "rb"))
        return f:read "a"
    end
    return json.decode(readall(AntDir.."/clibs/imgui/dear_bindings/cimgui.json"))
end

local m = {}

function m.init(status)
    local meta = cimgui_json(status.AntDir)
    local types = {}
    local flags = {}
    local enums = {}
    local funcs = {}
    local struct_funcs = {}
    for _, typedef_meta in ipairs(meta.typedefs) do
        types[typedef_meta.name] = typedef_meta
    end
    for _, struct_meta in ipairs(meta.structs) do
        types[struct_meta.name] = struct_meta
    end
    for _, enum_meta in ipairs(meta.enums) do
        if not conditionals(enum_meta) then
            goto continue
        end
        local realname = enum_meta.name:match "(.-)_?$"
        if enum_meta.is_flags_enum then
            local elements = {}
            local name = realname:match "^ImGui(%a+)$" or realname:match "^Im(%a+)$"
            local flag = {
                name = name,
                realname = realname,
                elements = elements,
                comments = enum_meta.comments,
            }
            flags[realname] = flag
            flags[#flags+1] = flag
            for _, element in ipairs(enum_meta.elements) do
                if not element.is_internal and not element.is_count and not element.conditionals then
                    local enum_name = element.name:match "^%w+_(%w+)$"
                    elements[#elements+1] = {
                        name = enum_name,
                        value = element.value,
                        comments = element.comments,
                    }
                end
            end
        else
            local elements = {}
            local name = realname:match "^ImGui(%a+)$"
            local enum = {
                name = name,
                realname = realname,
                elements = elements,
                comments = enum_meta.comments,
            }
            enums[realname] = enum
            enums[#enums+1] = enum
            for _, element in ipairs(enum_meta.elements) do
                if not element.is_internal and not element.is_count and not element.conditionals then
                    local enum_type, enum_name = element.name:match "^(%w+)_(%w+)$"
                    if enum_type ~= realname then
                        local t = enums[enum_type]
                        if t then
                            t.elements[#t.elements+1] = {
                                name = enum_name,
                                value = element.value,
                                comments = element.comments,
                            }
                        else
                            local name = enum_type:match "^ImGui(%a+)$" or realname:match "^Im(%a+)$"
                            local enum = {
                                name = name,
                                realname = enum_type,
                                elements = {{
                                    name = enum_name,
                                    value = element.value,
                                    comments = element.comments,
                                }},
                            }
                            enums[enum_type] = enum
                            enums[#enums+1] = enum
                        end
                    else
                        elements[#elements+1] = {
                            name = enum_name,
                            value = element.value,
                            comments = element.comments,
                        }
                    end
                end
            end
        end
        ::continue::
    end
    for _, func_meta in ipairs(meta.functions) do
        if allow(func_meta) then
            if func_meta.original_class then
                local v = struct_funcs[func_meta.original_class]
                if v then
                    v[#v+1] = func_meta
                else
                    struct_funcs[func_meta.original_class] = { func_meta }
                end
            else
                funcs[#funcs+1] = func_meta
            end
        end
    end
    status.types = types
    status.flags = flags
    status.enums = enums
    status.funcs = funcs
    status.struct_funcs = struct_funcs
end

return m