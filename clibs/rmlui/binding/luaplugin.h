#pragma once

#include <binding/luabind.h>
#include <core/Interface.h>
#include <databinding/DataVariant.h>
#include "luaref.h"

namespace Rml {
class Node;
class Element;
class EventListener;
class Document;
class Event;
}

enum class LuaEvent : uint8_t {
	OnLoadInlineScript = 2,
	OnLoadExternalScript,
	OnCreateElement,
	OnDestroyNode,
	OnEvent,
	OnEventAttach,
	OnEventDetach,
	OnRealPath,
	OnLoadTexture,
	OnParseText,
};

class lua_plugin final : public Rml::Plugin {
public:
	lua_plugin(lua_State* L);
	~lua_plugin();
	Rml::EventListener* OnCreateEventListener(Rml::Element* element, const std::string& type, const std::string& code, bool use_capture) override;
	void OnLoadInlineScript(Rml::Document* document, const std::string& content, const std::string& source_path, int source_line) override;
	void OnLoadExternalScript(Rml::Document* document, const std::string& source_path) override;
	void OnCreateElement(Rml::Document* document, Rml::Element* element, const std::string& tag) override;
	void OnDestroyNode(Rml::Document* document, Rml::Node* node) override;
	std::string OnRealPath(const std::string& path) override;
	void OnLoadTexture(Rml::Document* document, Rml::Element* element, const std::string& path, Rml::Rect rect, bool isRT) override;
	void OnParseText(const std::string& str,std::vector<Rml::group>& groups,std::vector<int>& layoutMap,std::string& ctext,Rml::group& default_group) override;

	void register_event(lua_State* L);
	luaref_box ref(lua_State* L);
	void callref(lua_State* L, int ref, size_t argn = 0, size_t retn = 0);
	void call(lua_State* L, LuaEvent eid, size_t argn = 0, size_t retn = 0);
	void pushevent(lua_State* L, const Rml::Event& event);

	luaref reference = 0;
};

lua_plugin* get_lua_plugin();
void lua_pushvariant(lua_State *L, const Rml::DataVariant &v);
void lua_getvariant(lua_State *L, int index, Rml::DataVariant* variant);
