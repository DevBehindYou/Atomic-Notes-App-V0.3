# Controlled mascot playback

The renderer plays one original GIF cycle at a time and selects four variations with a shuffled bag. Touch and keyboard activation switch variation within the chosen character. Lifecycle, route visibility, TickerMode and reduced motion stop advancement; static presentation closes its decoder after the first frame.

The controller serializes frame work and coalesces restarts. Generations reject stale images, painted handles retire after a frame, and asynchronous cleanup errors retain ownership for bounded retry instead of poisoning the queue. Rendering never downloads assets or starts note, auth or wallet operations.

Verification: 16 focused tests passed, including full native GIF cycle duration, shuffle boundaries, interruption/disposal, queue bounds and cleanup-rejection recovery; targeted fatal-info analysis passed. Independent concurrency review accepted the cleanup fix.

SDK limitation: this Flutter test engine returns native 480px animated GIF buffers despite a smaller requested decode target. The adapter requests target sizing without per-frame resampling. Real Android/browser memory, CPU/GPU and accessibility acceptance remain unmeasured; these unit/widget results do not establish platform release readiness.
