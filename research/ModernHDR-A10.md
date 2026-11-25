# iPhone 8-style ("modern") HDR on the iPhone 7 - removed experiment (Nov 2026)

Got as far as real merged HDR photos (highlights recovered), but the output looked worse than the iPhone 7's own
legacy HDR, so the experiment was removed from 11Cam. The full source of the last attempt is in
Tweak-modernhdr-attempt.x (build with EXP=MODERNHDR, DIAG=DIAG_LOG for the logging). Findings, for anyone picking it up:

- Client: AVGQCameraHDR2Capability=1, AVGQCameraHDRVersion=2. Daemon: GNRHDRSupported on the wide 12MP/Square formats,
  the X's GNR LTMHDRParameters (Fusion + NoiseModel) added to the 7's back sensor tuning.
- With Auto HDR off and HDR On, the resolver picks captureType 3; the A10 takes pre-bracket EV0 + EV0/EV-2/EV+2.
- GNR.videoprocessor (iOS 15.8.x) needs per-frame LTMLookUpTables / GlobalLTMLookUpTable (error 17 -> status -17400 otherwise).
  H9ISP only exports them when com.apple.coremedia EnableLTMLuts + H9ISPRawMetaInDict are set, and then only inside
  RawMetaData ("Shared LTM LUTs" section: 8x6 grid of 33-pt curves; the global LTM curve is the 33-pt AverageLTM).
- GNR LTMLookUpTables blob v1: u16 version=1, xPadded, yPadded, rowStride, entriesPerLUT, top, bottom, left, right, 2 reserved,
  curves at +0x16. GlobalLTM/GTC: u16 count 257 + 257 u16.
- With the tables, the merge works but stays at the dark frame's exposure (HDRExposureRatio is 256 on every A10 frame).
  Setting the measured ratio on bracket frames (hdrfix4) made the result look worse than stock, at which point it was dropped.
