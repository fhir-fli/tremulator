# Why this copy of flutter_webrtc 1.6.3 exists

Vendored 2026-11-25 from pub.dev flutter_webrtc 1.6.3 (without `example/`
and without the libwebrtc prebuilt, which CMake fetches from
`third_party/libwebrtc_version.ini`). One change: the desktop `initialize()`
option `fieldTrials`, a list of whole libwebrtc field trial entries
("Key/Value/") passed to `LibWebRTC::InitializeWithFieldTrials` beside the
plugin's own two. Files: `common/cpp/src/flutter_webrtc.cc`,
`common/cpp/src/flutter_webrtc_base.cc`,
`common/cpp/include/flutter_webrtc_base.h`, `lib/src/native/utils.dart`
(doc only).

Used by the lab (E5g, `docs/GATE2-CALLS-PLAN.md`) to turn off the
loss-based estimator's padding (`lab/e5/PADDING.md`). Proof it reaches
libwebrtc: `packages/tremulator_calls/example/integration_test/field_trials_test.dart`,
failed on the stock plugin (`lab/tool/results/field_trials_without.log`).
Diff against the pub.dev copy to see the whole change.
