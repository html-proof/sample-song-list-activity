# Music Hub playback and micro-UX QA checklist

Run the automated suites first, then complete the device checks on one current
Android device and one current iPhone. Repeat network cases on Wi-Fi and mobile
data. Capture the app version, OS version, route, queue, source kind, and elapsed
time for every failure. No test may expose a provider, Firebase, Supabase, Redis,
HTTP, or stack-trace error to the user.

## Playback controls and state

- [ ] 1. Tap Play twice rapidly: one request starts, the icon reacts immediately, and app/notification/lock-screen state agrees.
- [ ] 2. Tap Pause while loading or buffering: the pending play intention is cancelled and the exact position is retained.
- [ ] 3. Tap Next twice rapidly: outdated transitions do not win and the final requested queue item plays.
- [ ] 4. Make the next three URLs fail: each unavailable track is attempted once, at most three are skipped, and no infinite loop occurs.
- [ ] 5. Press Previous after 4 seconds: the current track restarts; press near 0:00: the previous queue item plays.
- [ ] 6. Drag Seek continuously: UI previews locally and sends one committed seek on release.
- [ ] 7. Fail a seek into an uncached area: the last valid position is restored and the player stays usable.
- [ ] 8. Verify progress never moves backward without a seek/track change and updates smoothly without rebuilding unrelated screens.
- [ ] 9. Use a stream with unknown duration: the UI shows `--:--`, not fake `0:00 / 0:00`.
- [ ] 10. Buffer for 5+ seconds: artwork and controls remain visible, with only a subtle control-level loader.
- [ ] 11. Finish a track: metadata changes with the source and the old song does not flash at 0:00.
- [ ] 12. Enable Repeat one/all and Shuffle, then use notification controls: modes and order remain synchronized and Previous is logical.

## Sources, network, retry, and offline

- [ ] 13. Play a downloaded track with its remote URL expired and internet disabled: the verified local file wins.
- [ ] 14. Corrupt or zero a downloaded file: it is rejected and never reported as a valid offline source.
- [ ] 15. Break a stream URL: one fresh song-detail resolution is attempted; the identical failed URL is not retried forever.
- [ ] 16. Delay the provider beyond 8 seconds: recovery times out without affecting another already playing track.
- [ ] 17. Drop internet for 1–3 seconds with buffered audio: playback continues and no noisy offline banner appears.
- [ ] 18. Stay offline past the buffer: queue and position persist; an available downloaded next track is selected.
- [ ] 19. Restore connectivity: a pending recoverable stream can resume without an app restart.
- [ ] 20. Switch Wi-Fi to mobile data and back: position and queue survive and the stored mobile/Wi-Fi quality policy is respected.
- [ ] 21. Stop the FastAPI, ML, and Redis services independently while a local/current stream plays: playback remains independent.
- [ ] 22. Return 401 once: Firebase token refreshes and the request retries once; a second 401 is surfaced as auth failure without a loop.
- [ ] 23. Return malformed request/404: no retry loop occurs. Return a temporary stream/provider error: retry remains bounded.
- [ ] 24. Verify user messages are actionable: “This track isn't available”, “Couldn't load this”, or “You're offline”.

## Queue, autoplay, and session restoration

- [ ] 25. Navigate across every tab, rotate, change theme, and resize: one audio engine and one queue remain alive.
- [ ] 26. Reorder the queue during background playback: the notification follows the same order immediately.
- [ ] 27. Remove the current item: playback moves to the next valid item; removing the last item chooses the prior item or stops safely.
- [ ] 28. Use Play next: the item is inserted exactly after current, including from Home/Search/Library.
- [ ] 29. Feed accidental consecutive duplicate provider variants: they collapse; enable user duplicates: intentional copies remain.
- [ ] 30. Reach queue end with Autoplay off: stop cleanly. With Autoplay on: recommendations append before the final transition.
- [ ] 31. Make recommendation generation fail: current playback and queue remain untouched and fallback content is offered.
- [ ] 32. Kill and reopen the app: current song, queue order, index, position, repeat, and shuffle restore without autoplaying unexpectedly.
- [ ] 33. Restore an expired persisted URL: it is treated as a hint, refreshed on failure, and never destroys the queue.
- [ ] 34. Reinstall/sign in as an existing user: backend preferences, likes, playlists, and history restore without onboarding again.
- [ ] 35. Confirm queues remain device-local when the same account plays on two devices.

## Audio focus, devices, and background controls

- [ ] 36. Minimize and lock the app for 10 minutes: playback continues and metadata remains current.
- [ ] 37. Swipe-kill/open under each platform's allowed behavior: restoration is safe and no duplicate notification appears.
- [ ] 38. Receive/end a phone call while playing: pause/duck follows the platform and resumes only if playback was previously intended.
- [ ] 39. Receive navigation/alarm audio: transient focus loss ducks/pauses and restores correctly.
- [ ] 40. Unplug wired headphones: playback pauses before speaker output begins.
- [ ] 41. Disconnect Bluetooth: no speaker blast. Reconnect: a manually paused session stays paused.
- [ ] 42. Use Bluetooth Play/Pause/Next/Previous/Seek: the app, lock screen, and notification show the same state.
- [ ] 43. Verify Android media notification and iOS lock screen show correct artwork, title, artist, duration, and actions for every transition.
- [ ] 44. Tap a normal recommendation notification: deep-link without recreating the audio engine or resetting the queue.

## Downloads, cache, and storage

- [ ] 45. Observe download states: Waiting, Downloading, Paused, Completed, and Failed are distinct and Retry works.
- [ ] 46. Interrupt a download: a safe partial remains; completion is marked only after non-zero file verification.
- [ ] 47. Fill device storage during download: stop cleanly with “Not enough storage” and no completed/corrupt record.
- [ ] 48. Delete a download: Like, playlist membership, and history remain. A current local source follows the defined wait/switch behavior.
- [ ] 49. Clear metadata/cache during playback: current and next playback do not crash or disappear.
- [ ] 50. Exceed cache limits: old entries evict, while current, prefetched, active-download, and required metadata entries remain.
- [ ] 51. Verify audio prefetch targets only current plus the next one or two tracks and respects mobile data/battery limits.
- [ ] 52. Load artwork offline/failing: cached art or a stable placeholder appears and never blocks audio.

## Search, Home, recommendations, and content

- [ ] 53. Type rapidly (`patta` → `pattalam`): debounce runs once and old responses cannot overwrite the latest query.
- [ ] 54. Fail search after results exist: query/results/scroll position remain and Retry is available.
- [ ] 55. Play a search result then go Back: the same query and scroll position return.
- [ ] 56. Tap songs A, B, C rapidly: metadata reacts immediately and only C ultimately owns playback.
- [ ] 57. Refresh Home while playing: current audio/queue stay unchanged; cached sections show before quiet refresh.
- [ ] 58. Trigger pagination repeatedly near the end: one cursor request runs and results deduplicate by song identity.
- [ ] 59. Refresh recommendations repeatedly: impressions prevent the same fixed set; seen and played histories remain separate.
- [ ] 60. Fast-skip once versus repeatedly: one skip adjusts gradually; repeated fast skips reduce score without a permanent ban.
- [ ] 61. Complete new-user language/artist onboarding: the first Home response is immediately relevant without ML history.
- [ ] 62. Disable ML/Redis: fallback uses language, selected artists, trending, and new releases rather than an empty Home.
- [ ] 63. Toggle explicit/language settings while playing: only future candidates/cache change; current audio follows the documented policy.
- [ ] 64. Fail lyrics or return wrong/missing lyrics: playback is untouched and timestamped lyrics follow Seek when available.

## User actions, privacy, and lifecycle

- [ ] 65. Tap Like repeatedly offline/online: one optimistic visual change persists and sync retries without duplicate requests.
- [ ] 66. Add to playlist during playback: audio does not pause; uniqueness and retry rules are respected.
- [ ] 67. Log out: the chosen playback policy executes, private cache/queue clears, and navigation goes to Login rather than Splash.
- [ ] 68. Delete account: reauthentication/confirmation occurs, private data clears, playback stops, and the first-install splash flag remains intact.
- [ ] 69. Clear history/downloads/account: destructive controls require confirmation and are not adjacent to transport controls.
- [ ] 70. Change the device wall clock during playback: listening duration and analytics remain plausible because elapsed timing is monotonic.

## Accessibility, presentation, and error hygiene

- [ ] 71. Screen-reader every transport/action control: labels state Play/Pause, Next, Previous, Queue, Repeat, Shuffle, Like, and Download.
- [ ] 72. Test maximum text scaling and smallest supported screen: titles do not clip controls and touch targets remain at least platform minimums.
- [ ] 73. Verify selected/disabled/buffering/error states do not rely on color alone.
- [ ] 74. Confirm haptics occur for key controls/Like/reorder but never during scroll or every progress tick.
- [ ] 75. Animate mini-player to full player repeatedly: presentation never restarts or seeks the audio engine.
- [ ] 76. Flap network/provider errors 20 times: banners/snackbars deduplicate and only actionable messages are surfaced.

## Analytics and performance gates

- [ ] 77. Tap a song that never starts: no `play` event is sent. Start it successfully: exactly one `play` event is sent after Ready + Playing.
- [ ] 78. Press Next versus fail a provider URL: events are `user_pressed_next` versus `track_failed_to_play`; only user intent affects skip learning.
- [ ] 79. Scroll recommendation cards partially/fully: only actually presented cards create impression events.
- [ ] 80. Record tap-to-audio latency, search latency, buffer count/time, failed-start rate, transition gap, Home first-content, crash-free sessions, cache hit rate, and network-interrupted sessions.

## Release gates

- [ ] `flutter analyze` has no errors.
- [ ] `flutter test` passes all state-machine, queue-policy, source-selection, model, startup, and settings tests.
- [ ] Backend tests pass, including the playback event separation contract.
- [ ] Database migration `005_playback_reliability_events.sql` is applied before a client using the new event types is released.
- [ ] Android background playback, notification controls, headset unplug, and Bluetooth cases pass on a physical device.
- [ ] iOS background playback, Control Center, interruption, route-change, and Bluetooth cases pass on a physical device.
