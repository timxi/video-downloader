# Phase 9: Video Player - Implementation Plan

**Status**: ✅ Complete

## Overview

Complete Phase 9 by implementing the 6 missing video player features. Current state is 70% complete.

**Current State**:
- Single file: `OfflineBrowser/Features/Player/PlayerView.swift` (455 lines)
- Contains: PlayerView (SwiftUI), VideoPlayerView (UIKit wrapper), PlayerViewModel
- Working: play/pause, seek slider, 10s skip, playback speed, brightness/volume gestures, position saving

**Missing Features**:
1. Picture-in-Picture (PiP) ✅
2. Subtitle Renderer (WebVTT) ✅
3. Sleep Timer ✅
4. Horizontal Pan Seek Gesture ✅
5. "Continue from X:XX?" Prompt ✅
6. Orientation Handling ✅

---

## Implementation Summary

### Files Created

| File | Purpose |
|------|---------|
| `Features/Player/Services/SubtitleParser.swift` | WebVTT parsing with SubtitleCue struct |
| `Features/Player/Services/SleepTimerManager.swift` | Timer logic with durations (15/30/45/60min, end of video) |
| `Features/Player/Components/SubtitleView.swift` | Caption display overlay |
| `Features/Player/Components/SleepTimerSheet.swift` | Timer selection UI |
| `Features/Player/Components/SeekPreviewView.swift` | Horizontal seek feedback |

### Files Modified

| File | Changes |
|------|---------|
| `Features/Player/PlayerView.swift` | Added PiP, subtitles overlay, sleep timer, seek preview, resume prompt, orientation |
| `Core/Database/Models/Video.swift` | Added `subtitleFileURL` computed property |

---

## Feature Details

### 1. Picture-in-Picture
- AVPictureInPictureController with delegate pattern
- Coordinator class in VideoPlayerView manages PiP controller
- Toggle via menu button

### 2. Subtitle Renderer
- WebVTT parser supporting HH:MM:SS.mmm and MM:SS.mmm formats
- HTML tag stripping and entity decoding
- Time-synced display via time observer
- Toggle via menu button

### 3. Sleep Timer
- SleepTimerManager with 15/30/45/60min + end of video options
- Sheet UI for selection
- Auto-pause when timer fires
- Displayed in menu with remaining time

### 4. Horizontal Pan Seek
- Threshold-based direction detection (horizontal vs vertical)
- 100px = 1 second seek
- Preview overlay showing offset and target time
- Applied on drag end

### 5. Continue Prompt
- Triggered when playbackPosition > 10 seconds
- Alert with "Resume from X:XX" and "Start Over" options
- Auto-seek for positions <= 10 seconds

### 6. Orientation Handling
- Force landscape on appear
- Force portrait on disappear
- iOS 16+ uses requestGeometryUpdate, older uses UIDevice setValue

---

## Test Results

**All existing tests pass**: 317 tests ✅

Note: Unit tests for SubtitleParser and SleepTimerManager can be added as a follow-up.
