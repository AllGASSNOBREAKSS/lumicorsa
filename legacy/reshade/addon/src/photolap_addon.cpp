// PHOTOLAP ReShade add-on (photolap.addon64)
// Copyright (c) 2026 Photolap contributors. MIT License.
//
// Jobs:
//  1. Bridge: the in-game CSP app (apps/lua/Photolap) writes state/control.ini; this add-on watches it and applies
//     it live: Photolap.fx techniques on/off, every PL_* uniform, and the neural pass (RenoDX DLSS 5 add-on) settings.
//  2. HUD-safe rendering: renders ReShade effects right after CSP's final composite and before AC/CSP UI is drawn,
//     so apps, chat, leaderboards and this panel itself are not graded/sharpened/fogged.
//  3. Fallback in-game panel (Alt+Shift+P) drawn with ReShade's ImGui, for when the CSP app is hidden or unavailable.
//  4. Status: writes state/status.ini so the CSP app can show what is really running (backend, HUD-safe, errors).

#define ImTextureID ImU64
#include <imgui.h>
#include <reshade.hpp>

#include <windows.h>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <map>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

#include "renodx_bridge.hpp"

using namespace reshade::api;
namespace fs = std::filesystem;

#define PL_VERSION "0.1.0"
static const char *kEffect = "Photolap.fx";
static const char *kTechniques[] = { "Photolap_Light", "Photolap_Atmos", "Photolap_Detail", "Photolap_Lens" };
static const char *kTechKeys[]   = { "light", "atmos", "detail", "lens" };

extern "C" __declspec(dllexport) const char *NAME = "Photolap";
extern "C" __declspec(dllexport) const char *DESCRIPTION = "Photoreal neural + post stack for Assetto Corsa, with live control from the in-game CSP app.";

// ------------------------------------------------------------------------------------------------ state
struct Control
{
	std::map<std::string, std::string> kv;
	long long seq = -1;
	std::string get(const std::string &k, const std::string &def = "") const { auto it = kv.find(k); return it == kv.end() ? def : it->second; }
	float f(const std::string &k, float def) const { auto it = kv.find(k); return it == kv.end() ? def : static_cast<float>(std::atof(it->second.c_str())); }
	bool b(const std::string &k, bool def) const { auto it = kv.find(k); return it == kv.end() ? def : (it->second == "1" || it->second == "true"); }
};

static std::mutex     g_mutex;
static Control        g_ctl;
static bool           g_dirty = true;           // control changed or effects reloaded -> reapply
static fs::path       g_state_dir, g_control_path, g_status_path;
static fs::file_time_type g_control_mtime{};
static DWORD          g_last_poll = 0, g_last_status = 0;
static bool           g_panel_open = false;
static std::string    g_last_error;

// HUD-safe tracking (single immediate context in D3D11, so plain statics are fine).
static effect_runtime *g_runtime = nullptr;
static bool  g_rt_is_backbuffer = false;
static resource_view g_bb_rtv = { 0 };
static uint32_t g_bb_draws = 0;
static bool  g_rendered_early = false;
static bool  g_hud_safe_hit = false;            // did the early render happen at least once recently
static uint32_t g_frames_without_hit = 0;

// ------------------------------------------------------------------------------------------------ files
static void ResolvePaths()
{
	wchar_t exe[MAX_PATH] = {};
	GetModuleFileNameW(nullptr, exe, MAX_PATH);
	const fs::path root = fs::path(exe).parent_path();           // ...\assettocorsa
	g_state_dir = root / L"apps" / L"lua" / L"Photolap" / L"state";
	std::error_code ec;
	fs::create_directories(g_state_dir, ec);
	g_control_path = g_state_dir / L"control.ini";
	g_status_path = g_state_dir / L"status.ini";
}

static bool ReadControl(Control &out)
{
	std::ifstream in(g_control_path);
	if (!in) return false;
	std::string line;
	while (std::getline(in, line))
	{
		if (!line.empty() && line.back() == '\r') line.pop_back();
		if (line.empty() || line[0] == ';' || line[0] == '#' || line[0] == '[') continue;
		const size_t eq = line.find('=');
		if (eq == std::string::npos) continue;
		auto trim = [](std::string s) { size_t a = s.find_first_not_of(" \t"), b = s.find_last_not_of(" \t"); return a == std::string::npos ? std::string() : s.substr(a, b - a + 1); };
		out.kv[trim(line.substr(0, eq))] = trim(line.substr(eq + 1));
	}
	out.seq = std::atoll(out.get("seq", "0").c_str());
	return true;
}

static void WriteControl(const Control &c)
{
	const fs::path tmp = g_control_path.wstring() + L".tmp";
	{
		std::ofstream o(tmp, std::ios::trunc);
		o << "; written by photolap.addon64 (in-game panel)\n";
		for (const auto &[k, v] : c.kv) if (k != "seq" && k != "writer") o << k << '=' << v << '\n';
		o << "writer=addon\nseq=" << (c.seq + 1) << '\n';
	}
	MoveFileExW(tmp.c_str(), g_control_path.c_str(), MOVEFILE_REPLACE_EXISTING);
}

static std::string NeuralBackend()
{
	if (photolap::reno::api() != nullptr) return std::string("renodx-dlss5 (") + photolap::reno::g_module + ", live API)";
	struct { const wchar_t *mod; const char *name; } known[] = {
		{ L"renodx-dlss5.addon64", "renodx-dlss5 (no live API: update to v10+)" },
		{ L"deep-fried-chicken.addon64", "Deep Fried Chicken" },
		{ L"OptiScaler.dll", "OptiScaler" },
	};
	for (auto &k : known) if (GetModuleHandleW(k.mod) != nullptr) return k.name;
	if (GetModuleHandleW(L"nvngx_dlssnr.dll") != nullptr) return "neural model loaded (unknown host)";
	return "none";
}

static void WriteStatus(effect_runtime *rt)
{
	const fs::path tmp = g_status_path.wstring() + L".tmp";
	{
		std::ofstream o(tmp, std::ios::trunc);
		o << "addon_version=" << PL_VERSION << '\n';
		o << "tick=" << GetTickCount() << '\n';
		o << "applied_seq=" << g_ctl.seq << '\n';
		bool found = rt && rt->find_technique(kEffect, kTechniques[0]).handle != 0;
		o << "effects_loaded=" << (found ? 1 : 0) << '\n';
		o << "reshade_effects_enabled=" << (rt && rt->get_effects_state() ? 1 : 0) << '\n';
		o << "neural_backend=" << NeuralBackend() << '\n';
		o << "neural_live_api=" << (photolap::reno::api() ? 1 : 0) << '\n';
		o << "hud_safe_active=" << (g_hud_safe_hit ? 1 : 0) << '\n';
		o << "last_error=" << g_last_error << '\n';
	}
	MoveFileExW(tmp.c_str(), g_status_path.c_str(), MOVEFILE_REPLACE_EXISTING);
}

// ------------------------------------------------------------------------------------------------ apply
static void ApplyUniform(effect_runtime *rt, const std::string &name, const std::string &value)
{
	effect_uniform_variable var = rt->find_uniform_variable(kEffect, name.c_str());
	if (var.handle == 0) return;
	if (value == "true" || value == "false") { rt->set_uniform_value_bool(var, value == "true"); return; }
	float v[4] = {};
	size_t n = 0;
	std::stringstream ss(value);
	std::string part;
	while (n < 4 && std::getline(ss, part, ',')) v[n++] = static_cast<float>(std::atof(part.c_str()));
	if (n == 0) return;
	rt->set_uniform_value_float(var, v, n);
}

static void Apply(effect_runtime *rt)
{
	const Control c = g_ctl;
	const bool master = c.b("enabled", true);

	int found = 0;
	for (int i = 0; i < 4; ++i)
	{
		effect_technique t = rt->find_technique(kEffect, kTechniques[i]);
		if (t.handle == 0) continue;
		++found;
		rt->set_technique_state(t, master && c.b(kTechKeys[i], true));
	}
	g_last_error = found == 0 ? "Photolap.fx not loaded: check reshade-shaders/Shaders" : "";

	for (const auto &[k, v] : c.kv)
		if (k.rfind("PL_", 0) == 0) ApplyUniform(rt, k, v);

	// Neural pass (RenoDX DLSS 5). Intensity 0 is "off" because NeuralUplift is start-time only.
	if (photolap::reno::api() != nullptr)
	{
		const bool neural = master && c.b("neural", true);
		photolap::reno::set("NRIntensity", neural ? c.f("nr_intensity", 0.6f) : 0.0f);
		photolap::reno::set("NRPreset", std::floor(c.f("nr_preset", 0.0f)));
		photolap::reno::set("NRStyle", std::floor(c.f("nr_style", 0.0f)));
		photolap::reno::set("NRLocalTone", c.f("nr_tone", 1.0f));
		photolap::reno::set("NRLocalStructure", c.f("nr_structure", 1.0f));
		photolap::reno::set("NRUICorrection", c.b("nr_keep_hud", true) ? 1.0f : 0.0f);
		photolap::reno::set("NRAutoMask", 0.0f);   // no characters in a car sim: let the model touch the whole frame
	}
}

static void PollControl()
{
	const DWORD now = GetTickCount();
	if (now - g_last_poll < 150) return;
	g_last_poll = now;
	std::error_code ec;
	const auto mt = fs::last_write_time(g_control_path, ec);
	if (ec || mt == g_control_mtime) return;
	Control c;
	if (!ReadControl(c)) return;
	g_control_mtime = mt;
	std::lock_guard<std::mutex> lock(g_mutex);
	g_ctl = std::move(c);
	g_dirty = true;
}

// ------------------------------------------------------------------------------------------------ events
static void OnInitRuntime(effect_runtime *rt) { g_runtime = rt; g_dirty = true; }
static void OnDestroyRuntime(effect_runtime *rt) { if (g_runtime == rt) g_runtime = nullptr; }
static void OnReloaded(effect_runtime *) { g_dirty = true; }

static void OnBeginEffects(effect_runtime *rt, command_list *, resource_view, resource_view)
{
	PollControl();
	if (g_dirty) { std::lock_guard<std::mutex> lock(g_mutex); Apply(rt); g_dirty = false; }
	const DWORD now = GetTickCount();
	if (now - g_last_status > 500) { g_last_status = now; WriteStatus(rt); }
}

static void OnBindRT(command_list *cmd, uint32_t count, const resource_view *rtvs, resource_view)
{
	if (g_runtime == nullptr || count == 0 || rtvs[0].handle == 0) { g_rt_is_backbuffer = false; return; }
	device *dev = cmd->get_device();
	const resource r = dev->get_resource_from_view(rtvs[0]);
	g_rt_is_backbuffer = (r == g_runtime->get_current_back_buffer());
	if (g_rt_is_backbuffer) g_bb_rtv = rtvs[0];
}

// Called before every draw. CSP's final composite is the first draw on the back buffer; UI follows.
static bool BeforeDraw(command_list *cmd)
{
	if (!g_rt_is_backbuffer || g_rendered_early || g_runtime == nullptr) return false;
	if (!g_ctl.b("hud_safe", true)) return false;
	const uint32_t draw_index = static_cast<uint32_t>(g_ctl.f("hud_draw_index", 1.0f));
	if (g_bb_draws++ < draw_index) return false;
	g_rendered_early = true;
	g_hud_safe_hit = true;
	g_runtime->render_effects(cmd, g_bb_rtv, g_bb_rtv);  // shaders do their own sRGB, so the UNORM view is right for both
	return false;
}
static bool OnDraw(command_list *cmd, uint32_t, uint32_t, uint32_t, uint32_t) { return BeforeDraw(cmd); }
static bool OnDrawIndexed(command_list *cmd, uint32_t, uint32_t, uint32_t, int32_t, uint32_t) { return BeforeDraw(cmd); }

static void OnPresent(command_queue *, swapchain *, const rect *, const rect *, uint32_t, const rect *)
{
	if (!g_rendered_early && ++g_frames_without_hit > 120) g_hud_safe_hit = false;   // fell back to normal present-time rendering
	if (g_rendered_early) g_frames_without_hit = 0;
	g_rendered_early = false;
	g_bb_draws = 0;
}

// ------------------------------------------------------------------------------------------------ panel (Alt+Shift+P)
static void PanelEdit(Control &c, bool &changed)
{
	auto check = [&](const char *label, const char *key, bool def) {
		bool v = c.b(key, def);
		if (ImGui::Checkbox(label, &v)) { c.kv[key] = v ? "1" : "0"; changed = true; }
	};
	auto slider = [&](const char *label, const char *key, float def, float lo, float hi) {
		float v = c.f(key, def);
		if (ImGui::SliderFloat(label, &v, lo, hi, "%.2f")) { char buf[32]; snprintf(buf, sizeof(buf), "%.4f", v); c.kv[key] = buf; changed = true; }
	};
	check("PHOTOLAP ON", "enabled", true);
	ImGui::Separator();
	ImGui::TextUnformatted("NEURAL (DLSS 5 neural rendering)");
	check("Neural pass", "neural", true);
	slider("Neural intensity", "nr_intensity", 0.6f, 0.0f, 1.0f);
	ImGui::Separator();
	ImGui::TextUnformatted("EFFECTS");
	check("Light (HDR bloom + filmic)", "light", true);
	check("Atmosphere (depth haze)", "atmos", true);
	check("Detail (clarity + sharpen)", "detail", true);
	check("Lens (CA, vignette, grain)", "lens", true);
	slider("Exposure", "PL_Exposure", 0.0f, -2.0f, 2.0f);
	slider("Bloom", "PL_BloomIntensity", 0.22f, 0.0f, 1.0f);
	slider("Sharpen", "PL_Sharpen", 0.35f, 0.0f, 1.0f);
	slider("Master mix", "PL_Mix", 1.0f, 0.0f, 1.0f);
	ImGui::Separator();
	check("Keep HUD/apps untouched", "hud_safe", true);
	ImGui::TextDisabled("Backend: %s", NeuralBackend().c_str());
	ImGui::TextDisabled("HUD-safe: %s", g_hud_safe_hit ? "active" : "fallback (present)");
	if (!g_last_error.empty()) ImGui::TextColored(ImVec4(1, 0.4f, 0.3f, 1), "%s", g_last_error.c_str());
}

static void OnOverlay(effect_runtime *rt)
{
	if (rt->is_key_down(VK_MENU) && rt->is_key_down(VK_SHIFT) && rt->is_key_pressed('P')) g_panel_open = !g_panel_open;
	if (!g_panel_open) return;
	rt->block_input_next_frame();
	ImGui::SetNextWindowPos(ImVec2(40, 120), ImGuiCond_FirstUseEver);
	ImGui::SetNextWindowSize(ImVec2(360, 0), ImGuiCond_Always);
	ImGui::PushStyleColor(ImGuiCol_WindowBg, ImVec4(0.06f, 0.065f, 0.08f, 0.94f));
	ImGui::PushStyleColor(ImGuiCol_CheckMark, ImVec4(1.0f, 0.24f, 0.36f, 1.0f));
	ImGui::PushStyleColor(ImGuiCol_SliderGrab, ImVec4(1.0f, 0.24f, 0.36f, 1.0f));
	if (ImGui::Begin("PHOTOLAP  //  Alt+Shift+P", &g_panel_open, ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoSavedSettings))
	{
		Control c;
		{ std::lock_guard<std::mutex> lock(g_mutex); c = g_ctl; }
		bool changed = false;
		PanelEdit(c, changed);
		if (changed)
		{
			WriteControl(c);
			std::lock_guard<std::mutex> lock(g_mutex);
			c.seq += 1; g_ctl = c; g_dirty = true;
			std::error_code ec; g_control_mtime = fs::last_write_time(g_control_path, ec);
		}
	}
	ImGui::End();
	ImGui::PopStyleColor(3);
}

// ------------------------------------------------------------------------------------------------ entry
BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID)
{
	switch (reason)
	{
	case DLL_PROCESS_ATTACH:
		if (!reshade::register_addon(module)) return FALSE;
		ResolvePaths();
		{ Control c; if (ReadControl(c)) g_ctl = c; }
		reshade::register_event<reshade::addon_event::init_effect_runtime>(OnInitRuntime);
		reshade::register_event<reshade::addon_event::destroy_effect_runtime>(OnDestroyRuntime);
		reshade::register_event<reshade::addon_event::reshade_reloaded_effects>(OnReloaded);
		reshade::register_event<reshade::addon_event::reshade_begin_effects>(OnBeginEffects);
		reshade::register_event<reshade::addon_event::bind_render_targets_and_depth_stencil>(OnBindRT);
		reshade::register_event<reshade::addon_event::draw>(OnDraw);
		reshade::register_event<reshade::addon_event::draw_indexed>(OnDrawIndexed);
		reshade::register_event<reshade::addon_event::present>(OnPresent);
		reshade::register_event<reshade::addon_event::reshade_overlay>(OnOverlay);
		break;
	case DLL_PROCESS_DETACH:
		reshade::unregister_addon(module);
		break;
	}
	return TRUE;
}
