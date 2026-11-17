// renodx_bridge.hpp -- live control of the RenoDX DLSS 5 neural-rendering add-on (renodx-dlss5.addon64).
//
// Adapted from DLSS5-Feeder's feed_renodx_api.h, Copyright (c) 2026 Jean-Laurent ROUZIES, MIT License.
// The control table (RenoDX_NR_GetControlApi, version 1) was documented there from the 10.8.0 binary.
//
// What can be changed while the game runs (10.8.0): NRIntensity, NRPreset, NRStyle, NRLocalTone, NRGlobalTone,
// NRLocalStructure, NRSkinStructure, NRAutoMask, NRUICorrection and the NRLook* group. NeuralUplift (on/off),
// NRPasses and NRResolutionScale are read at start only, so "Neural off" in Photolap is NRIntensity = 0.
#pragma once
#include <windows.h>
#include <cstdint>
#include <cstring>

#define PL_RENO_EXPORT "RenoDX_NR_GetControlApi"

struct PlRenoInfo  { const char *key; float lo, hi; uint32_t kind; uint32_t reserved; };
struct PlRenoValue { const char *key; float value; uint32_t reserved; };
struct PlRenoApi
{
	uint32_t size, version;
	int (*describe)(uint32_t index, PlRenoInfo *out);
	int (*get)(const char *key, float *out);
	int (*set)(const PlRenoValue *items, uint32_t count);
	void *register_external, *unregister_external;
};
static_assert(sizeof(PlRenoInfo) == 24 && sizeof(PlRenoValue) == 16, "layout read off the 10.8.0 binary");

#if defined(_MSC_VER)
	#define PL_TRY __try
	#define PL_EXCEPT __except (EXCEPTION_EXECUTE_HANDLER)
#else
	#define PL_TRY if (true)
	#define PL_EXCEPT else
#endif

namespace photolap::reno
{
	inline char g_module[64] = "";

	// Interface of whichever loaded module exports it; retried until found (ReShade loads add-ons lazily).
	inline const PlRenoApi *api()
	{
		static const PlRenoApi *cached = nullptr;
		static DWORD last_scan = 0;
		if (cached != nullptr) return cached;
		const DWORD now = GetTickCount();
		if (now - last_scan < 2000) return nullptr;   // cheap: rescan at most every 2 s
		last_scan = now;

		typedef BOOL (WINAPI *PFN_Enum)(HANDLE, HMODULE *, DWORD, LPDWORD);
		typedef const PlRenoApi *(*PFN_Get)(int);
		HMODULE k32 = GetModuleHandleW(L"kernel32.dll");
		auto enum_mods = k32 ? reinterpret_cast<PFN_Enum>(reinterpret_cast<void *>(GetProcAddress(k32, "K32EnumProcessModules"))) : nullptr;
		static HMODULE mods[1024];
		DWORD need = 0;
		if (enum_mods == nullptr || !enum_mods(GetCurrentProcess(), mods, sizeof(mods), &need)) return nullptr;
		for (DWORD i = 0; i < need / sizeof(HMODULE) && i < 1024; ++i)
		{
			FARPROC f = GetProcAddress(mods[i], PL_RENO_EXPORT);
			if (f == nullptr) continue;
			const PlRenoApi *a = nullptr;
			bool ok = false;
			PL_TRY { a = reinterpret_cast<PFN_Get>(reinterpret_cast<void *>(f))(1);
			         ok = a && a->version == 1 && a->size >= 0x20 && a->describe && a->get && a->set; }
			PL_EXCEPT { ok = false; }
			if (!ok) continue;
			cached = a;
			char path[MAX_PATH] = {};
			GetModuleFileNameA(mods[i], path, MAX_PATH);
			const char *s = strrchr(path, '\\');
			strncpy(g_module, s ? s + 1 : path, sizeof(g_module) - 1);
			break;
		}
		return cached;
	}

	// 1 taken, 0 refused (unknown key / out of range), -1 no interface.
	inline int set(const char *key, float value)
	{
		const PlRenoApi *a = api();
		if (a == nullptr) return -1;
		PlRenoValue v = { key, value, 0 };
		int r = -1;
		PL_TRY { r = a->set(&v, 1) != 0 ? 1 : 0; }
		PL_EXCEPT { r = -1; }
		return r;
	}

	inline bool get(const char *key, float *out)
	{
		const PlRenoApi *a = api();
		if (a == nullptr) return false;
		bool ok = false;
		PL_TRY { ok = a->get(key, out) != 0; }
		PL_EXCEPT { ok = false; }
		return ok;
	}
}
