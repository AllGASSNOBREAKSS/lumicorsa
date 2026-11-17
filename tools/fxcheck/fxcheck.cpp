// fxcheck: compiles a ReShade FX file with ReShade's own effect compiler (preprocessor -> parser -> codegen)
// so shader errors are caught in CI without Windows. Usage: fxcheck <file.fx> [include_dir] [out.hlsl]
#include "effect_parser.hpp"
#include "effect_codegen.hpp"
#include "effect_preprocessor.hpp"
#include <cstdio>
#include <fstream>
#include <memory>

int main(int argc, char **argv)
{
	if (argc < 2) { std::fprintf(stderr, "usage: fxcheck <file.fx> [include_dir] [out.hlsl]\n"); return 2; }
	int failures = 0;
	for (const auto [w, h] : { std::pair{ 1920, 1080 }, std::pair{ 3840, 2160 }, std::pair{ 2560, 1440 } })
	{
		reshadefx::preprocessor pp;
		pp.add_macro_definition("__RESHADE__", "60500");
		pp.add_macro_definition("__RENDERER__", "0xb000"); // D3D11
		pp.add_macro_definition("__VENDOR__", "0x10de");
		pp.add_macro_definition("BUFFER_WIDTH", std::to_string(w));
		pp.add_macro_definition("BUFFER_HEIGHT", std::to_string(h));
		pp.add_macro_definition("BUFFER_RCP_WIDTH", "(1.0 / BUFFER_WIDTH)");
		pp.add_macro_definition("BUFFER_RCP_HEIGHT", "(1.0 / BUFFER_HEIGHT)");
		pp.add_macro_definition("BUFFER_COLOR_BIT_DEPTH", "8");
		if (argc > 2) pp.add_include_path(argv[2]);
		if (!pp.append_file(argv[1])) { std::fprintf(stderr, "[%dx%d] preprocessor:\n%s\n", w, h, pp.errors().c_str()); return 1; }

		for (int backend = 0; backend < 2; ++backend)
		{
			std::unique_ptr<reshadefx::codegen> cg(backend == 0
				? reshadefx::create_codegen_hlsl(50, false, false)
				: reshadefx::create_codegen_spirv(false, false, false));
			reshadefx::parser parser;
			const bool ok = parser.parse(pp.output(), cg.get());
			const char *name = backend == 0 ? "HLSL SM5.0 (D3D11)" : "SPIR-V";
			if (!parser.errors().empty()) std::fprintf(stderr, "[%dx%d %s]\n%s", w, h, name, parser.errors().c_str());
			if (!ok) { ++failures; continue; }
			const reshadefx::effect_module &mod = cg->module();
			std::printf("[%dx%d %s] OK: %zu techniques, %zu textures, %zu uniforms, %zu entry points\n",
				w, h, name, mod.techniques.size(), mod.textures.size(), mod.uniforms.size(), mod.entry_points.size());
			if (backend == 0 && w == 1920 && argc > 3)
			{
				std::string code;
				for (const auto &ep : mod.entry_points) { code += "// entry: " + ep.first + "\n"; }
				code += cg->finalize_code();
				std::ofstream(argv[3]) << code;
			}
		}
	}
	return failures == 0 ? 0 : 1;
}
