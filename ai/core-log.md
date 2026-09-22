## 1 COMMIT Unreleased 6ade4ab 2026-09-21T18:32:23-07:00

#### Coming From:

Unreleased 0986437

#### Purpose:

Add a launch-time choice between 640x480 and 800x600 display modes for DCSS.

#### Outcome:

The launcher now prompts for 640x480 or 800x600, accepts numbered and literal responses, supports a validated `MISTER_RESOLUTION` override, selects the corresponding modeline, and retains the output-mode bypass and display restoration behavior. Documentation and generated installation instructions describe the new choice, and shell-path tests plus bundle generation completed successfully.

#### Next Steps:

Deploy commit `6ade4ab` to the MiSTer, launch DCSS at both resolutions, verify input and rendering, exit normally from each mode, and confirm that the prior display mode is restored.

#### Files Modified:

- scripts/bundle.sh
- scripts/release.sh
- README.md

#### Status:

- [x] Built
- [ ] Passed

---
