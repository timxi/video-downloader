# Phase 13: Polish & Edge Cases

**Status**: Ready for implementation

## Overview

Complete Phase 13 by addressing remaining polish items: storage handling, loading states, memory management, and accessibility.

**Current State** (50% complete - updated after audit):
- ✅ Error messages for download failures
- ✅ Network unreachable handling (NetworkMonitor)
- ✅ Library empty state
- ✅ Search no results state
- ✅ Download queue empty state (already in DownloadsView!)
- ✅ Progress indicator for downloads
- ✅ Weak self captures in closures
- ✅ AVPlayer released when not in use
- ⚠️ Muxing progress - badge shows "Processing" but no percentage
- ❌ Storage full scenario handling
- ❌ Skeleton/shimmer loading states
- ❌ Memory warning handling
- ❌ Thumbnail cache limiting
- ❌ Accessibility (VoiceOver, Dynamic Type, Reduce Motion)

---

## Part 1: Storage Full Handling

### Step 1.1: Check Available Storage Before Download

**Modify**: `OfflineBrowser/Features/Download/Engine/DownloadManager.swift`

Add storage check before starting download:

```swift
// Add to DownloadManager
private func hasEnoughStorage(estimatedSize: Int64 = 500_000_000) -> Bool {
    guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
          let values = try? documentsURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
          let available = values.volumeAvailableCapacityForImportantUsage else {
        return true // Assume OK if we can't check
    }
    // Require at least 500MB free (or estimated size + buffer)
    return available > estimatedSize + 100_000_000
}

// In createAndQueueDownload():
guard hasEnoughStorage() else {
    notificationManager.showStorageFull()
    return
}
```

### Step 1.2: Add Storage Full Notification

**Modify**: `OfflineBrowser/Shared/Utilities/NotificationManager.swift`

```swift
func showStorageFull() {
    let content = UNMutableNotificationContent()
    content.title = "Storage Full"
    content.body = "Not enough space to download. Free up storage and try again."
    content.sound = .default

    let request = UNNotificationRequest(
        identifier: "storage_full",
        content: content,
        trigger: nil
    )

    UNUserNotificationCenter.current().add(request)
}
```

### Step 1.3: Show In-App Alert for Storage Full

**Modify**: `OfflineBrowser/Features/Download/UI/DownloadOptionsSheet.swift`

Add alert when user tries to download with insufficient storage.

---

## Part 2: Loading States

### Step 2.1: Add Loading State to LibraryView

**Modify**: `OfflineBrowser/Features/Library/LibraryView.swift`

```swift
struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @State private var isLoading = true
    // ... existing state

    var body: some View {
        ZStack {
            NavigationView {
                Group {
                    if isLoading {
                        loadingView
                    } else if viewModel.videos.isEmpty && viewModel.folders.isEmpty {
                        emptyStateView
                    } else {
                        contentView
                    }
                }
                // ... existing modifiers
                .onAppear {
                    loadData()
                }
            }
            // ... existing overlays
        }
    }

    private func loadData() {
        isLoading = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            viewModel.loadData()
            withAnimation(.easeOut(duration: 0.2)) {
                isLoading = false
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading library...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
```

### Step 2.2: Skeleton Placeholder for Video Grid (Optional Enhancement)

Create shimmer effect for video thumbnails while loading:

**Create**: `OfflineBrowser/Shared/Components/ShimmerView.swift`

```swift
import SwiftUI

struct ShimmerView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(.secondary.opacity(0.2))
            .overlay(
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.3), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: phase)
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 300
                }
            }
    }
}

struct VideoRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            ShimmerView()
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                ShimmerView()
                    .frame(height: 16)
                    .frame(maxWidth: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                ShimmerView()
                    .frame(height: 12)
                    .frame(maxWidth: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
```

---

## Part 3: Memory Management

### Step 3.1: Handle Memory Warnings

**Modify**: `OfflineBrowser/App/AppDelegate.swift`

```swift
func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
    // Clear thumbnail cache
    URLCache.shared.removeAllCachedResponses()

    // Clear image cache
    ImageCache.shared.clearCache()

    print("[AppDelegate] Memory warning - cleared caches")
}
```

### Step 3.2: Create Simple Image Cache

**Create**: `OfflineBrowser/Shared/Utilities/ImageCache.swift`

```swift
import UIKit

final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private let maxCacheSize = 50 // Maximum number of images

    private init() {
        cache.countLimit = maxCacheSize

        // Listen for memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func setImage(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }

    @objc func clearCache() {
        cache.removeAllObjects()
        print("[ImageCache] Cache cleared")
    }
}
```

### Step 3.3: Limit Thumbnail Directory Size

**Modify**: `OfflineBrowser/Core/Storage/FileStorageManager.swift`

```swift
// Add thumbnail cleanup method
func cleanupOldThumbnails(keepCount: Int = 100) {
    guard let files = try? fileManager.contentsOfDirectory(
        at: thumbnailsDirectory,
        includingPropertiesForKeys: [.creationDateKey]
    ) else { return }

    let jpgFiles = files.filter { $0.pathExtension == "jpg" }
    guard jpgFiles.count > keepCount else { return }

    // Sort by creation date, oldest first
    let sorted = jpgFiles.sorted { file1, file2 in
        let date1 = (try? file1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
        let date2 = (try? file2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
        return date1 < date2
    }

    // Remove oldest files
    let toRemove = sorted.prefix(jpgFiles.count - keepCount)
    for file in toRemove {
        try? fileManager.removeItem(at: file)
    }

    print("[FileStorageManager] Cleaned up \(toRemove.count) old thumbnails")
}
```

Call this periodically (e.g., on app launch):

```swift
// In AppDelegate didFinishLaunchingWithOptions:
FileStorageManager.shared.cleanupOldThumbnails()
```

---

## Part 4: Accessibility

### Step 4.1: VoiceOver Labels for Browser

**Modify**: `OfflineBrowser/Features/Browser/BrowserViewController.swift`

Add accessibility labels to key UI elements:

```swift
// URL text field
urlTextField.accessibilityLabel = "URL address bar"
urlTextField.accessibilityHint = "Enter a website address"

// Back button
backButton.accessibilityLabel = "Go back"
backButton.accessibilityHint = "Navigate to previous page"

// Forward button
forwardButton.accessibilityLabel = "Go forward"
forwardButton.accessibilityHint = "Navigate to next page"

// Refresh button
refreshButton.accessibilityLabel = "Refresh"
refreshButton.accessibilityHint = "Reload current page"

// Download pill
floatingPill.accessibilityLabel = "\(streamCount) videos detected"
floatingPill.accessibilityHint = "Double tap to see download options"
```

### Step 4.2: VoiceOver for SwiftUI Views

**Modify**: `OfflineBrowser/Features/Library/LibraryView.swift`

```swift
// In VideoRow
var body: some View {
    HStack(spacing: 12) {
        // ... existing content
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(video.title), \(video.formattedDuration), \(video.formattedFileSize)")
    .accessibilityHint("Double tap to play")
}

// In FolderRow
var body: some View {
    HStack {
        // ... existing content
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(folder.name), \(videoCount) videos")
    .accessibilityHint("Double tap to open folder")
}
```

**Modify**: `OfflineBrowser/Features/Library/DownloadsView.swift`

```swift
// In DownloadRow
var body: some View {
    VStack(alignment: .leading, spacing: 8) {
        // ... existing content
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityDescription)
    .accessibilityValue("\(Int(download.progress * 100)) percent complete")
}

private var accessibilityDescription: String {
    let title = download.pageTitle ?? "Video"
    switch download.status {
    case .pending: return "\(title), queued for download"
    case .downloading: return "\(title), downloading"
    case .muxing: return "\(title), processing"
    case .paused: return "\(title), paused"
    case .completed: return "\(title), completed"
    case .failed: return "\(title), failed: \(download.errorMessage ?? "unknown error")"
    }
}
```

### Step 4.3: Dynamic Type Support

**Modify**: SwiftUI views to use scaled fonts where needed.

Most SwiftUI `.font()` modifiers already support Dynamic Type. For custom sizes, use `@ScaledMetric`:

```swift
// Example for thumbnail size that scales with Dynamic Type
@ScaledMetric(relativeTo: .body) private var thumbnailWidth: CGFloat = 120

// In VideoRow
AsyncImage(url: video.thumbnailURL) { ... }
    .frame(width: thumbnailWidth, height: thumbnailWidth * 9/16)
```

### Step 4.4: Reduce Motion Support

**Modify**: Views with animations to respect Reduce Motion setting.

**Create**: `OfflineBrowser/Shared/Extensions/Animation+Extensions.swift`

```swift
import SwiftUI

extension Animation {
    static var adaptiveFade: Animation {
        if UIAccessibility.isReduceMotionEnabled {
            return .linear(duration: 0.01) // Instant
        }
        return .easeInOut(duration: 0.3)
    }

    static var adaptiveSpring: Animation {
        if UIAccessibility.isReduceMotionEnabled {
            return .linear(duration: 0.01)
        }
        return .spring(response: 0.3, dampingFraction: 0.8)
    }
}
```

Update animations in hint views:

```swift
// In GestureHintView and FolderHintView
.onAppear {
    withAnimation(.adaptiveFade) { opacity = 1 }
}

private func dismiss() {
    withAnimation(.adaptiveFade) { opacity = 0 }
    // ...
}
```

---

## Implementation Order

| Step | Task | File(s) | Complexity |
|------|------|---------|------------|
| 1 | Add storage check before download | DownloadManager.swift | Low |
| 2 | Add storage full notification | NotificationManager.swift | Low |
| 3 | Add loading state to LibraryView | LibraryView.swift | Low |
| 4 | Create ImageCache utility | ImageCache.swift (new) | Medium |
| 5 | Handle memory warnings | AppDelegate.swift | Low |
| 6 | Add thumbnail cleanup | FileStorageManager.swift | Low |
| 7 | Add VoiceOver to Browser | BrowserViewController.swift | Medium |
| 8 | Add VoiceOver to SwiftUI views | LibraryView.swift, DownloadsView.swift | Medium |
| 9 | Add Reduce Motion support | Animation+Extensions.swift (new), hint views | Low |
| 10 | Add Dynamic Type scaling | Various SwiftUI views | Low |

---

## Testing Checklist

### Storage Handling
- [ ] Download blocked when storage < 500MB
- [ ] User sees notification/alert about storage full
- [ ] Download works normally when sufficient storage

### Loading States
- [ ] Loading indicator shows briefly when opening Library
- [ ] Smooth transition to content

### Memory Management
- [ ] Memory warning clears image cache
- [ ] Old thumbnails cleaned up on app launch
- [ ] App doesn't crash under memory pressure

### Accessibility
- [ ] VoiceOver reads all interactive elements
- [ ] VoiceOver announces video title, duration, size
- [ ] VoiceOver announces download status and progress
- [ ] Dynamic Type scales text appropriately
- [ ] Reduce Motion disables animations

---

## Files Summary

| Action | File | Description |
|--------|------|-------------|
| **Create** | `Shared/Utilities/ImageCache.swift` | In-memory image cache with limit |
| **Create** | `Shared/Extensions/Animation+Extensions.swift` | Reduce Motion adaptive animations |
| **Create** | `Shared/Components/ShimmerView.swift` | Skeleton loading placeholders (optional) |
| **Modify** | `Features/Download/Engine/DownloadManager.swift` | Storage check |
| **Modify** | `Shared/Utilities/NotificationManager.swift` | Storage full notification |
| **Modify** | `Features/Library/LibraryView.swift` | Loading state + accessibility |
| **Modify** | `Features/Library/DownloadsView.swift` | Accessibility labels |
| **Modify** | `Features/Browser/BrowserViewController.swift` | VoiceOver labels |
| **Modify** | `Core/Storage/FileStorageManager.swift` | Thumbnail cleanup |
| **Modify** | `App/AppDelegate.swift` | Memory warning handler |
| **Modify** | `Features/Player/Components/GestureHintView.swift` | Reduce Motion |
| **Modify** | `Features/Library/Components/FolderHintView.swift` | Reduce Motion |

---

## Notes

### Accessibility Testing
- Enable VoiceOver in iOS Settings > Accessibility > VoiceOver
- Enable Dynamic Type in Settings > Display & Brightness > Text Size
- Enable Reduce Motion in Settings > Accessibility > Motion > Reduce Motion

### Memory Testing
- Use Xcode's Debug Navigator to monitor memory usage
- Simulate memory warnings: Debug > Simulate Memory Warning

### Storage Testing
- Fill device storage to near capacity
- Verify app handles low storage gracefully
