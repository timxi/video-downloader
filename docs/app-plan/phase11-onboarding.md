# Phase 11: Onboarding - Contextual Hints

**Status**: ✅ Complete

## Overview

Complete Phase 11 by implementing the 2 remaining contextual hints.

**Current State** (100% complete):
- ✅ ThemeManager - fully implemented
- ✅ HintManager - singleton with tooltip UI
- ✅ Hint 1: Download pill hint (first video detection)
- ✅ Hint 2: Gesture controls hint (first video play) - GestureHintView
- ✅ Hint 3: Folder organization hint (after 5 downloads) - FolderHintView

---

## Hint 2: Gesture Controls (First Video Play)

**Trigger**: First time a video starts playing

**Message**: "Swipe horizontally to seek • Swipe vertically for brightness/volume"

### Implementation

1. **Add state to PlayerView**:
   ```swift
   @State private var showGestureHint = false
   ```

2. **Check in PlayerView.onAppear** (after play starts):
   ```swift
   .onAppear {
       setOrientation(.landscape)
       if !viewModel.hasError {
           viewModel.play()
       }
       // Show gesture hint on first play
       if !PreferenceRepository.shared.hasSeenGestureHint {
           DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
               showGestureHint = true
           }
       }
       // ... existing sleepTimer setup
   }
   ```

3. **Add overlay in body**:
   ```swift
   // After subtitle overlay
   if showGestureHint {
       GestureHintView(onDismiss: {
           showGestureHint = false
           PreferenceRepository.shared.hasSeenGestureHint = true
       })
   }
   ```

4. **Create GestureHintView component**:
   - Full screen semi-transparent overlay
   - Display gesture instructions with SF Symbols
   - Tap anywhere to dismiss
   - Auto-dismiss after 5 seconds

### Files

**Create**: `OfflineBrowser/Features/Player/Components/GestureHintView.swift`

```swift
import SwiftUI

struct GestureHintView: View {
    var onDismiss: () -> Void
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Gesture Controls")
                    .font(.title2.bold())
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 16) {
                    gestureRow(icon: "hand.draw.fill", text: "Swipe left/right to seek")
                    gestureRow(icon: "sun.max.fill", text: "Swipe up/down on left for brightness")
                    gestureRow(icon: "speaker.wave.2.fill", text: "Swipe up/down on right for volume")
                    gestureRow(icon: "hand.tap.fill", text: "Double-tap to play/pause")
                }

                Text("Tap anywhere to dismiss")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .opacity(opacity)
        .onTapGesture { dismiss() }
        .onAppear {
            withAnimation(.easeIn(duration: 0.3)) { opacity = 1 }
            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { dismiss() }
        }
    }

    private func gestureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 30)
            Text(text)
                .foregroundColor(.white)
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) { opacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDismiss() }
    }
}
```

**Modify**: `OfflineBrowser/Features/Player/PlayerView.swift`
- Add `@State private var showGestureHint = false`
- Add hint check in `.onAppear`
- Add `GestureHintView` overlay in body

---

## Hint 3: Folder Organization (After 5 Downloads)

**Trigger**: When user opens Library after completing 5+ downloads

**Message**: "Organize your videos into folders for easy access"

### Implementation

1. **Add preference key for download count** (if missing):
   ```swift
   // In Preference.swift
   case totalDownloadsCount = "stats.downloadCount"
   ```

2. **Add getInt/setInt to PreferenceRepository** (if missing):
   ```swift
   func getInt(_ key: PreferenceKey) -> Int {
       Int(getString(key) ?? "0") ?? 0
   }

   func setInt(_ key: PreferenceKey, value: Int) {
       setString(key, value: String(value))
   }
   ```

3. **Track download count in DownloadManager**:
   ```swift
   // In completeDownload(), after: try videoRepository.save(video)
   let count = PreferenceRepository.shared.getInt(.totalDownloadsCount)
   PreferenceRepository.shared.setInt(.totalDownloadsCount, value: count + 1)
   ```

4. **Add hint check in LibraryView**:
   ```swift
   @State private var showFolderHint = false

   .onAppear {
       viewModel.loadData()
       checkFolderHint()
   }

   private func checkFolderHint() {
       let count = PreferenceRepository.shared.getInt(.totalDownloadsCount)
       if count >= 5 && !PreferenceRepository.shared.hasSeenFolderHint {
           DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
               showFolderHint = true
           }
       }
   }
   ```

5. **Add hint overlay in LibraryView**:
   ```swift
   .overlay {
       if showFolderHint {
           FolderHintView(onDismiss: {
               showFolderHint = false
               PreferenceRepository.shared.hasSeenFolderHint = true
           })
       }
   }
   ```

### Files

**Create**: `OfflineBrowser/Features/Library/Components/FolderHintView.swift`

```swift
import SwiftUI

struct FolderHintView: View {
    var onDismiss: () -> Void
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)

                Text("Organize Your Videos")
                    .font(.headline)

                Text("Create folders to group your downloads by topic, series, or any way you like.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button("Got it!") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(32)
        }
        .opacity(opacity)
        .onTapGesture { dismiss() }
        .onAppear {
            withAnimation(.easeIn(duration: 0.3)) { opacity = 1 }
        }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) { opacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDismiss() }
    }
}
```

**Modify**:
- `OfflineBrowser/Core/Database/Models/Preference.swift` - Add `totalDownloadsCount` key
- `OfflineBrowser/Core/Database/Repositories/PreferenceRepository.swift` - Add `getInt`/`setInt`
- `OfflineBrowser/Features/Download/Engine/DownloadManager.swift` - Increment count
- `OfflineBrowser/Features/Library/LibraryView.swift` - Add hint check and overlay

---

## Implementation Order

| Step | Task | File | Complexity |
|------|------|------|------------|
| 1 | Add `totalDownloadsCount` preference key | Preference.swift | Low |
| 2 | Add `getInt`/`setInt` methods | PreferenceRepository.swift | Low |
| 3 | Track download count | DownloadManager.swift | Low |
| 4 | Create GestureHintView | GestureHintView.swift (new) | Medium |
| 5 | Add gesture hint to PlayerView | PlayerView.swift | Low |
| 6 | Create FolderHintView | FolderHintView.swift (new) | Medium |
| 7 | Add folder hint to LibraryView | LibraryView.swift | Low |

---

## Summary

| Aspect | Details |
|--------|---------|
| **Files to Create** | 2 (GestureHintView.swift, FolderHintView.swift) |
| **Files to Modify** | 4 (Preference.swift, PreferenceRepository.swift, DownloadManager.swift, PlayerView.swift, LibraryView.swift) |
| **Est. Lines** | ~150 |
| **Hint 2 Trigger** | First video playback |
| **Hint 3 Trigger** | Library open after 5+ downloads |
