# Changelog

## 2.0.1

- Fixed flicker: haze, mist and depth of field could invert from one frame to the next in cockpit view. The depth
  direction is now decided from sky pixels and kept, instead of guessed from the average depth every frame.
- Fixed popping: look presets (and auto look) crossfade over 1.5 s, sun shafts fade in and out, auto look holds a look
  for at least 60 s and no longer flips at the time and rain boundaries, and grain changes at a steady 24 Hz.
- Fixed effects flashing when first switched on: an effect stays off until its shader has compiled.
- Fixed the HUD showing only some of the time: the cluster is now drawn every game frame instead of inside its app
  window, so AC or other apps hiding windows no longer hides it, and it waits until all its layers are loaded. Drag the
  "Lumicorsa HUD" window to move it. "Show in" is reset to All views once (it was easy to leave on Chase).
