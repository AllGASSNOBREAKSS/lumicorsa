# Linux CI / cross-build. Windows release builds use addon/build.bat (MSVC).
RESHADE_SRC ?= ../ref/reshade-src
MINGW ?= x86_64-w64-mingw32-g++

all: check addon

fxcheck: tools/fxcheck/fxcheck
tools/fxcheck/fxcheck: tools/fxcheck/fxcheck.cpp
	g++ -std=c++20 -O1 -w -I$(RESHADE_SRC)/source -I$(RESHADE_SRC)/deps/spirv/include/spirv/unified1 $< \
	  $(addprefix $(RESHADE_SRC)/source/,effect_codegen_hlsl.cpp effect_codegen_spirv.cpp effect_expression.cpp effect_lexer.cpp \
	  effect_parser_exp.cpp effect_parser_stmt.cpp effect_preprocessor.cpp effect_symbol_table.cpp) -o $@

addon: bin/photolap.addon64
bin/photolap.addon64: addon/src/photolap_addon.cpp addon/src/renodx_bridge.hpp
	@mkdir -p bin
	$(MINGW) -std=c++20 -O2 -shared -static -static-libgcc -static-libstdc++ -fpermissive -w \
	  -Itools/mingw-shim -Ithird_party/reshade/include -Ithird_party/imgui $< -o $@ -lpsapi

check: fxcheck
	tools/fxcheck/fxcheck shaders/Photolap.fx shaders
	luajit tools/lua_mock_test.lua /tmp/photolap_mock > /dev/null && echo "lua mock test: OK"
	python3 tools/check_consistency.py /tmp/photolap_mock/Photolap/state/control.ini

package: all
	rm -rf dist && mkdir -p dist/Photolap/installer dist/Photolap/bin dist/Photolap/shaders
	cp -r csp-app installer/Install-Photolap.ps1 installer/Install.bat dist/Photolap/ 2>/dev/null; mv dist/Photolap/Install-Photolap.ps1 dist/Photolap/installer/; mv dist/Photolap/Install.bat dist/Photolap/
	cp bin/photolap.addon64 dist/Photolap/bin/ && cp shaders/Photolap.fx dist/Photolap/shaders/
	cp README.md LICENSE THIRD-PARTY-NOTICES.md dist/Photolap/
	cd dist && zip -qr Photolap-$(shell git describe --tags --always 2>/dev/null || echo dev).zip Photolap

.PHONY: all check addon package fxcheck
