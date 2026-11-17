# Linux CI. The native CSP shaders are compile-checked on Windows (tools/hlslcheck.py, needs d3dcompiler_47).
# The legacy ReShade path (legacy/reshade) builds with legacy/reshade/addon/build.bat (MSVC) or `make legacy-addon`.
RESHADE_SRC ?= ../ref/reshade-src
MINGW ?= x86_64-w64-mingw32-g++
LEGACY = legacy/reshade

all: check legacy-addon package

# ---------------------------------------------------------------- native CSP app (the product)
check: legacy-fxcheck
	luajit tools/lua_mock_test.lua
	python3 tools/check_consistency.py

package:
	python3 tools/package.py dist

# ---------------------------------------------------------------- legacy ReShade path (optional)
fxcheck: tools/fxcheck/fxcheck
tools/fxcheck/fxcheck: tools/fxcheck/fxcheck.cpp
	g++ -std=c++20 -O1 -w -I$(RESHADE_SRC)/source -I$(RESHADE_SRC)/deps/spirv/include/spirv/unified1 $< \
	  $(addprefix $(RESHADE_SRC)/source/,effect_codegen_hlsl.cpp effect_codegen_spirv.cpp effect_expression.cpp effect_lexer.cpp \
	  effect_parser_exp.cpp effect_parser_stmt.cpp effect_preprocessor.cpp effect_symbol_table.cpp) -o $@

legacy-fxcheck: fxcheck
	tools/fxcheck/fxcheck $(LEGACY)/Photolap.fx $(LEGACY)

legacy-addon: bin/photolap.addon64
bin/photolap.addon64: $(LEGACY)/addon/src/photolap_addon.cpp $(LEGACY)/addon/src/renodx_bridge.hpp
	@mkdir -p bin
	$(MINGW) -std=c++20 -O2 -shared -static -static-libgcc -static-libstdc++ -fpermissive -w \
	  -Itools/mingw-shim -Ithird_party/reshade/include -Ithird_party/imgui $< -o $@ -lpsapi

.PHONY: all check package fxcheck legacy-fxcheck legacy-addon
