// YouTube Extraction Script for OfflineBrowser
// This script runs in a hidden WKWebView and extracts HLS manifest URLs from YouTube

(function() {
    'use strict';

    // YouTube Innertube API configuration
    // Using iOS client which returns HLS manifests without signature deciphering
    const INNERTUBE_API_KEY = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
    const IOS_CLIENT_VERSION = '19.29.1';
    const IOS_CLIENT_NAME = 'IOS';

    /**
     * Build cookie header string from cookie array
     */
    function buildCookieHeader(cookies) {
        if (!cookies || !cookies.length) return '';
        return cookies
            .filter(c => c.name && c.value)
            .map(c => `${c.name}=${c.value}`)
            .join('; ');
    }

    /**
     * Extract YouTube video information and HLS manifest URL
     * @param {string} videoId - The YouTube video ID
     * @param {Array} cookies - Array of cookie objects from the browser
     */
    async function extractYouTube(videoId, cookies) {
        try {
            console.log('[YouTubeExtract] Starting extraction for video:', videoId);
            console.log('[YouTubeExtract] Cookies available:', cookies?.length || 0);

            // Build cookie header for authenticated requests
            const cookieHeader = buildCookieHeader(cookies);

            // Build the request body for iOS client
            // iOS client returns HLS manifests without needing signature deciphering
            const requestBody = {
                videoId: videoId,
                context: {
                    client: {
                        clientName: IOS_CLIENT_NAME,
                        clientVersion: IOS_CLIENT_VERSION,
                        deviceMake: 'Apple',
                        deviceModel: 'iPhone16,2',
                        osName: 'iOS',
                        osVersion: '17.5.1',
                        userAgent: 'com.google.ios.youtube/' + IOS_CLIENT_VERSION + ' (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X)',
                        hl: 'en',
                        gl: 'US',
                        utcOffsetMinutes: 0
                    },
                    user: {
                        lockedSafetyMode: false
                    }
                },
                contentCheckOk: true,
                racyCheckOk: true,
                playbackContext: {
                    contentPlaybackContext: {
                        html5Preference: 'HTML5_PREF_WANTS',
                        signatureTimestamp: 0
                    }
                }
            };

            // Build headers
            const headers = {
                'Content-Type': 'application/json',
                'X-Youtube-Client-Name': '5', // iOS = 5
                'X-Youtube-Client-Version': IOS_CLIENT_VERSION,
                'Origin': 'https://www.youtube.com',
                'User-Agent': 'com.google.ios.youtube/' + IOS_CLIENT_VERSION + ' (iPhone16,2; U; CPU iOS 17_5_1 like Mac OS X)'
            };

            // Add cookies if available (for authenticated requests)
            if (cookieHeader) {
                headers['Cookie'] = cookieHeader;
                console.log('[YouTubeExtract] Using authenticated request with cookies');
            }

            // Make the API request
            const response = await fetch('https://www.youtube.com/youtubei/v1/player?key=' + INNERTUBE_API_KEY, {
                method: 'POST',
                headers: headers,
                body: JSON.stringify(requestBody),
                credentials: 'include' // Include cookies from the webview
            });

            if (!response.ok) {
                throw new Error('API request failed with status: ' + response.status);
            }

            const data = await response.json();
            console.log('[YouTubeExtract] Received response from API');

            // Check playability status
            const playabilityStatus = data.playabilityStatus;
            if (!playabilityStatus) {
                throw new Error('No playability status in response');
            }

            // Handle different playability statuses
            if (playabilityStatus.status !== 'OK') {
                const reason = playabilityStatus.reason ||
                              playabilityStatus.messages?.[0] ||
                              'Video unavailable';

                // Provide more helpful error messages
                if (reason.includes('bot')) {
                    throw new Error('BOT_PROTECTION: YouTube requires sign-in for this video. Try signing into YouTube in the browser first.');
                } else if (reason.includes('age')) {
                    throw new Error('AGE_RESTRICTED: This video is age-restricted. Sign in with an adult account.');
                } else if (reason.includes('private')) {
                    throw new Error('PRIVATE_VIDEO: This video is private.');
                } else if (reason.includes('unavailable')) {
                    throw new Error('UNAVAILABLE: This video is not available in your region.');
                }

                throw new Error(reason);
            }

            // Get streaming data
            const streamingData = data.streamingData;
            if (!streamingData) {
                throw new Error('No streaming data available - video may be restricted');
            }

            // Get HLS manifest URL (preferred for iOS playback)
            const hlsManifestUrl = streamingData.hlsManifestUrl;
            if (!hlsManifestUrl) {
                // iOS client should return HLS, if not the video might be restricted
                throw new Error('NO_HLS: Video does not support HLS streaming. May require different extraction method.');
            }

            // Extract video details
            const videoDetails = data.videoDetails || {};
            const title = videoDetails.title || 'YouTube Video';
            const duration = parseInt(videoDetails.lengthSeconds, 10) || 0;

            // Get best thumbnail
            const thumbnails = videoDetails.thumbnail?.thumbnails || [];
            const thumbnail = thumbnails.length > 0 ?
                             thumbnails[thumbnails.length - 1].url : null;

            console.log('[YouTubeExtract] Successfully extracted HLS URL');
            console.log('[YouTubeExtract] Title:', title);
            console.log('[YouTubeExtract] Duration:', duration, 'seconds');
            console.log('[YouTubeExtract] HLS URL:', hlsManifestUrl.substring(0, 100) + '...');

            // Send result back to Swift
            window.webkit.messageHandlers.streamExtracted.postMessage({
                type: 'hls',
                url: hlsManifestUrl,
                title: title,
                duration: duration,
                thumbnail: thumbnail
            });

        } catch (error) {
            console.error('[YouTubeExtract] Extraction failed:', error.message);

            // Send error back to Swift with categorized message
            window.webkit.messageHandlers.extractionError.postMessage({
                message: error.message || 'Unknown extraction error'
            });
        }
    }

    // Expose function globally
    window.extractYouTube = extractYouTube;

    // Signal that the script is ready
    console.log('[YouTubeExtract] Script loaded and ready');

})();
