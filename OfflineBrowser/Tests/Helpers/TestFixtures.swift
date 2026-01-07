import Foundation
@testable import OfflineBrowser

/// Factory methods for creating test data
enum TestFixtures {

    // MARK: - HLS Manifests

    /// Master playlist with 2 quality variants
    static let masterPlaylist = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="avc1.64001f,mp4a.40.2"
        1080p.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720,CODECS="avc1.4d001f,mp4a.40.2"
        720p.m3u8
        """

    /// Master playlist with subtitles and audio tracks
    static let masterPlaylistWithSubtitles = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",DEFAULT=YES,LANGUAGE="en",URI="subs_en.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,SUBTITLES="subs"
        1080p.m3u8
        """

    /// Media playlist with 3 segments (VOD)
    static let mediaPlaylist = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:10
        #EXT-X-MEDIA-SEQUENCE:0
        #EXTINF:10.0,
        segment_0.ts
        #EXTINF:10.0,
        segment_1.ts
        #EXTINF:8.5,
        segment_2.ts
        #EXT-X-ENDLIST
        """

    /// Live stream (no EXT-X-ENDLIST)
    static let livePlaylist = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:10
        #EXT-X-MEDIA-SEQUENCE:100
        #EXTINF:10.0,
        segment_100.ts
        #EXTINF:10.0,
        segment_101.ts
        """

    /// AES-128 encrypted playlist
    static let encryptedPlaylist = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:10
        #EXT-X-KEY:METHOD=AES-128,URI="key.bin"
        #EXTINF:10.0,
        segment_0.ts
        #EXTINF:10.0,
        segment_1.ts
        #EXT-X-ENDLIST
        """

    /// DRM-protected playlist (SAMPLE-AES)
    static let drmProtectedPlaylist = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:10
        #EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://license.example.com"
        #EXTINF:10.0,
        segment_0.ts
        #EXT-X-ENDLIST
        """

    /// fMP4/CMAF playlist with EXT-X-MAP
    static let fmp4Playlist = """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:10
        #EXT-X-MAP:URI="init.mp4"
        #EXTINF:10.0,
        segment_0.m4s
        #EXTINF:10.0,
        segment_1.m4s
        #EXTINF:8.5,
        segment_2.m4s
        #EXT-X-ENDLIST
        """

    /// Playlist with absolute URLs
    static let absoluteURLPlaylist = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:10
        #EXTINF:10.0,
        https://cdn.example.com/segment_0.ts
        #EXTINF:10.0,
        https://cdn.example.com/segment_1.ts
        #EXT-X-ENDLIST
        """

    // MARK: - HLS Segment Factories

    static func makeSegments(count: Int, baseDuration: Double = 10.0) -> [HLSSegment] {
        (0..<count).map { index in
            HLSSegment(
                url: "https://example.com/segment_\(index).ts",
                duration: index == count - 1 ? 8.5 : baseDuration, // Last segment slightly shorter
                index: index
            )
        }
    }

    static func makeFMP4Segments(count: Int, baseDuration: Double = 10.0) -> [HLSSegment] {
        (0..<count).map { index in
            HLSSegment(
                url: "https://example.com/segment_\(index).m4s",
                duration: index == count - 1 ? 8.5 : baseDuration,
                index: index
            )
        }
    }

    // MARK: - StreamQuality Factories

    static func makeStreamQuality(
        id: UUID = UUID(),
        resolution: String = "1080p",
        bandwidth: Int = 5_000_000,
        url: String = "https://example.com/stream.m3u8",
        codecs: String? = "avc1.64001f,mp4a.40.2"
    ) -> StreamQuality {
        StreamQuality(
            id: id,
            resolution: resolution,
            bandwidth: bandwidth,
            url: url,
            codecs: codecs
        )
    }

    static func makeQualities() -> [StreamQuality] {
        [
            makeStreamQuality(resolution: "1080p", bandwidth: 5_000_000, url: "https://example.com/1080.m3u8"),
            makeStreamQuality(resolution: "720p", bandwidth: 2_500_000, url: "https://example.com/720.m3u8"),
            makeStreamQuality(resolution: "480p", bandwidth: 1_000_000, url: "https://example.com/480.m3u8"),
            makeStreamQuality(resolution: "360p", bandwidth: 500_000, url: "https://example.com/360.m3u8")
        ]
    }

    // MARK: - Video Factories

    static func makeVideo(
        id: UUID = UUID(),
        title: String = "Test Video",
        sourceURL: String = "https://example.com/video",
        sourceDomain: String = "example.com",
        filePath: String = "videos/test/video.mp4",
        thumbnailPath: String? = "videos/test/thumbnail.jpg",
        subtitlePath: String? = nil,
        duration: Int = 3661, // 1:01:01
        fileSize: Int64 = 1_500_000_000, // 1.5 GB
        quality: String = "1080p",
        folderID: UUID? = nil,
        createdAt: Date = Date(),
        lastPlayedAt: Date? = nil,
        playbackPosition: Int = 0
    ) -> Video {
        Video(
            id: id,
            title: title,
            sourceURL: sourceURL,
            sourceDomain: sourceDomain,
            filePath: filePath,
            thumbnailPath: thumbnailPath,
            subtitlePath: subtitlePath,
            duration: duration,
            fileSize: fileSize,
            quality: quality,
            folderID: folderID,
            createdAt: createdAt,
            lastPlayedAt: lastPlayedAt,
            playbackPosition: playbackPosition
        )
    }

    // MARK: - Download Factories

    static func makeDownload(
        id: UUID = UUID(),
        videoURL: String = "https://example.com/video.m3u8",
        manifestURL: String? = "https://example.com/manifest.m3u8",
        pageTitle: String? = "Test Page",
        pageURL: String? = "https://example.com/page",
        sourceDomain: String? = "example.com",
        status: DownloadStatus = .pending,
        progress: Double = 0.0,
        segmentsDownloaded: Int = 0,
        segmentsTotal: Int = 100,
        retryCount: Int = 0,
        errorMessage: String? = nil,
        quality: String? = "1080p",
        encryptionKeyURL: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) -> Download {
        Download(
            id: id,
            videoURL: videoURL,
            manifestURL: manifestURL,
            pageTitle: pageTitle,
            pageURL: pageURL,
            sourceDomain: sourceDomain,
            status: status,
            progress: progress,
            segmentsDownloaded: segmentsDownloaded,
            segmentsTotal: segmentsTotal,
            retryCount: retryCount,
            errorMessage: errorMessage,
            quality: quality,
            encryptionKeyURL: encryptionKeyURL,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - DASH Manifests

    /// Basic VOD MPD with two video qualities
    static let dashVODManifest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MPD xmlns="urn:mpeg:dash:schema:mpd:2011"
             type="static"
             mediaPresentationDuration="PT1H30M0S"
             minBufferTime="PT2S">
          <Period>
            <AdaptationSet contentType="video" mimeType="video/mp4">
              <Representation id="1080p" bandwidth="5000000" width="1920" height="1080" codecs="avc1.640028">
                <BaseURL>video/1080p/</BaseURL>
                <SegmentTemplate initialization="init.mp4" media="seg-$Number$.m4s" startNumber="1" duration="4" timescale="1"/>
              </Representation>
              <Representation id="720p" bandwidth="2500000" width="1280" height="720" codecs="avc1.64001f">
                <BaseURL>video/720p/</BaseURL>
                <SegmentTemplate initialization="init.mp4" media="seg-$Number$.m4s" startNumber="1" duration="4" timescale="1"/>
              </Representation>
            </AdaptationSet>
            <AdaptationSet contentType="audio" mimeType="audio/mp4" lang="en">
              <Representation id="audio-en" bandwidth="128000" codecs="mp4a.40.2">
                <BaseURL>audio/en/</BaseURL>
                <SegmentTemplate initialization="init.mp4" media="seg-$Number$.m4s" startNumber="1" duration="4" timescale="1"/>
              </Representation>
            </AdaptationSet>
          </Period>
        </MPD>
        """

    /// Live DASH manifest (dynamic type)
    static let dashLiveManifest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MPD xmlns="urn:mpeg:dash:schema:mpd:2011"
             type="dynamic"
             availabilityStartTime="2024-01-01T00:00:00Z"
             minimumUpdatePeriod="PT5S"
             minBufferTime="PT2S">
          <Period start="PT0S">
            <AdaptationSet contentType="video" mimeType="video/mp4">
              <Representation id="720p" bandwidth="2500000" width="1280" height="720">
                <SegmentTemplate media="chunk-$Time$.m4s" timescale="90000"/>
              </Representation>
            </AdaptationSet>
          </Period>
        </MPD>
        """

    /// DRM-protected DASH manifest with Widevine
    static let dashDRMManifest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MPD xmlns="urn:mpeg:dash:schema:mpd:2011"
             xmlns:cenc="urn:mpeg:cenc:2013"
             type="static"
             mediaPresentationDuration="PT30M0S">
          <Period>
            <AdaptationSet contentType="video" mimeType="video/mp4">
              <ContentProtection schemeIdUri="urn:mpeg:dash:mp4protection:2011" value="cenc"/>
              <ContentProtection schemeIdUri="urn:uuid:edef8ba9-79d6-4ace-a3c8-27dcd51d21ed">
              </ContentProtection>
              <Representation id="1080p" bandwidth="5000000" width="1920" height="1080">
                <SegmentTemplate initialization="init.mp4" media="seg-$Number$.m4s"/>
              </Representation>
            </AdaptationSet>
          </Period>
        </MPD>
        """

    /// DASH with subtitles
    static let dashWithSubtitlesManifest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" mediaPresentationDuration="PT1H0M0S">
          <Period>
            <AdaptationSet contentType="video" mimeType="video/mp4">
              <Representation id="720p" bandwidth="2500000" width="1280" height="720"/>
            </AdaptationSet>
            <AdaptationSet contentType="text" mimeType="application/ttml+xml" lang="en">
              <Representation id="sub-en" bandwidth="1000">
                <BaseURL>subtitles/en.ttml</BaseURL>
              </Representation>
            </AdaptationSet>
          </Period>
        </MPD>
        """

    /// DASH with SegmentList instead of SegmentTemplate
    static let dashSegmentListManifest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" mediaPresentationDuration="PT10M0S">
          <Period>
            <AdaptationSet contentType="video" mimeType="video/mp4">
              <Representation id="720p" bandwidth="2500000" width="1280" height="720">
                <SegmentList duration="4">
                  <Initialization sourceURL="init.mp4"/>
                  <SegmentURL media="segment1.m4s"/>
                  <SegmentURL media="segment2.m4s"/>
                  <SegmentURL media="segment3.m4s"/>
                </SegmentList>
              </Representation>
            </AdaptationSet>
          </Period>
        </MPD>
        """

    /// DASH with multiple audio tracks
    static let dashMultiAudioManifest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" mediaPresentationDuration="PT1H0M0S">
          <Period>
            <AdaptationSet contentType="video" mimeType="video/mp4">
              <Representation id="1080p" bandwidth="5000000" width="1920" height="1080"/>
            </AdaptationSet>
            <AdaptationSet contentType="audio" mimeType="audio/mp4" lang="en" label="English">
              <Representation id="audio-en" bandwidth="128000" codecs="mp4a.40.2"/>
            </AdaptationSet>
            <AdaptationSet contentType="audio" mimeType="audio/mp4" lang="es" label="Spanish">
              <Representation id="audio-es" bandwidth="128000" codecs="mp4a.40.2"/>
            </AdaptationSet>
          </Period>
        </MPD>
        """

    /// Minimal DASH manifest for duration parsing tests
    static let dashMinimalManifest = """
        <?xml version="1.0" encoding="UTF-8"?>
        <MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" mediaPresentationDuration="PT2H15M30.5S"/>
        """

    // MARK: - DASH Quality Factories

    static func makeDASHQualities() -> [StreamQuality] {
        [
            makeStreamQuality(resolution: "1080p", bandwidth: 5_000_000, url: "https://example.com/video/1080p/init.mp4", codecs: "avc1.640028"),
            makeStreamQuality(resolution: "720p", bandwidth: 2_500_000, url: "https://example.com/video/720p/init.mp4", codecs: "avc1.64001f"),
            makeStreamQuality(resolution: "480p", bandwidth: 1_500_000, url: "https://example.com/video/480p/init.mp4", codecs: "avc1.64001e"),
            makeStreamQuality(resolution: "360p", bandwidth: 800_000, url: "https://example.com/video/360p/init.mp4", codecs: "avc1.640015")
        ]
    }

    // MARK: - Folder Factories

    static func makeFolder(
        id: UUID = UUID(),
        name: String = "Test Folder",
        isAutoGenerated: Bool = false,
        createdAt: Date = Date()
    ) -> Folder {
        Folder(
            id: id,
            name: name,
            isAutoGenerated: isAutoGenerated,
            createdAt: createdAt
        )
    }
}
