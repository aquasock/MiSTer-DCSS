## 1 COMMIT Unreleased ??? 2026-09-21T18:32:23-07:00

#### Coming From:

Unreleased 0986437

#### Purpose:

Add a launch-time choice between 640x480 and 800x600 display modes for DCSS.

#### Outcome:

The approved implementation will adapt MiSTer-GemRB's resolution prompt and hardware-tested modelines while retaining the existing output-mode bypass and display restoration behavior.

#### Next Steps:

Implement the prompt and resolution override, update user-facing documentation, validate both resolutions and error paths, build the bundle, and prepare both modes for hardware testing.

#### Files Modified:

- scripts/bundle.sh
- scripts/release.sh
- README.md

#### Status:

- [ ] Built
- [ ] Passed

---
