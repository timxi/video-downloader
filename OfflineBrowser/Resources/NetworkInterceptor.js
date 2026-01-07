(function() {
    'use strict';

    // Wrap console.log to forward to Swift for debugging
    const originalConsoleLog = console.log;
    console.log = function(...args) {
        originalConsoleLog.apply(console, args);
        try {
            const message = args.map(arg =>
                typeof arg === 'object' ? JSON.stringify(arg) : String(arg)
            ).join(' ');
            if (message.includes('[OfflineBrowser]')) {
                window.webkit.messageHandlers.consoleLog.postMessage(message);
            }
        } catch (e) {}
    };

    console.log('[OfflineBrowser] Stream interceptor initializing...');

    // Track detected URLs to avoid duplicates
    const detectedURLs = new Set();

    // Track MP4 URLs by domain to limit spam
    const mp4ByDomain = new Map();

    // YouTube HLS capture state
    let youtubeHLSCaptureActive = false;
    let youtubeHLSCaptureTimeout = null;

    // YouTube HLS detection patterns
    const YOUTUBE_HLS_PATTERNS = [
        /googlevideo\.com.*\.m3u8/i,
        /youtube\.com\/api\/manifest\/hls/i,
        /manifest\.googlevideo\.com/i,
        /\.googlevideo\.com\/videoplayback.*itag=.*mime=/i,
        /ytimg\.com.*\.m3u8/i
    ];

    // Check if current page is YouTube
    function isYouTubePage() {
        const host = window.location.hostname.toLowerCase();
        return host.includes('youtube.com') || host.includes('youtu.be');
    }

    // Check if URL is a YouTube HLS manifest
    function isYouTubeHLS(url) {
        if (!url) return false;
        return YOUTUBE_HLS_PATTERNS.some(pattern => pattern.test(url));
    }

    // Check if URL is a YouTube direct video (MP4)
    function isYouTubeDirectVideo(url) {
        if (!url) return false;
        // YouTube videoplayback URLs with mp4 mime type
        return url.includes('googlevideo.com/videoplayback') &&
               (url.includes('mime=video%2Fmp4') || url.includes('mime=video/mp4'));
    }

    // Determine if YouTube URL is HLS or direct MP4
    function getYouTubeStreamType(url) {
        if (!url) return null;
        if (url.includes('.m3u8')) return 'hls';
        if (isYouTubeDirectVideo(url)) return 'direct';
        if (isYouTubeHLS(url)) return 'hls';
        return null;
    }

    // Start aggressive HLS capture for YouTube (called when video plays)
    function startYouTubeHLSCapture() {
        if (youtubeHLSCaptureActive) return;

        youtubeHLSCaptureActive = true;
        console.log('[OfflineBrowser] YouTube HLS capture started');

        // Clear any existing timeout
        if (youtubeHLSCaptureTimeout) {
            clearTimeout(youtubeHLSCaptureTimeout);
        }

        // Stop capture after 10 seconds
        youtubeHLSCaptureTimeout = setTimeout(function() {
            youtubeHLSCaptureActive = false;
            console.log('[OfflineBrowser] YouTube HLS capture ended');
        }, 10000);
    }

    // Send YouTube stream to native with special handling
    function sendYouTubeStreamToNative(url) {
        if (!url || detectedURLs.has(url)) return;

        // Determine the correct stream type
        const streamType = getYouTubeStreamType(url) || 'hls';

        detectedURLs.add(url);
        console.log('[OfflineBrowser] YouTube ' + streamType + ' detected:', url.substring(0, 100) + '...');

        try {
            window.webkit.messageHandlers.streamDetector.postMessage({
                type: 'streamDetected',
                url: url,
                streamType: streamType,
                source: 'youtube-intercept',
                timestamp: Date.now()
            });
        } catch (e) {
            console.log('[OfflineBrowser] Failed to send YouTube stream to native:', e);
        }
    }

    // Alias for backward compatibility
    const sendYouTubeHLSToNative = sendYouTubeStreamToNative;

    // Expose a function to clear detected URLs (called from native on refresh/navigation)
    window.__offlineBrowserClearDetected = function() {
        detectedURLs.clear();
        mp4ByDomain.clear();
        console.log('[OfflineBrowser] Cleared detected URLs');
    };

    // Also clear on page unload/beforeunload
    window.addEventListener('beforeunload', function() {
        detectedURLs.clear();
    });

    window.addEventListener('pagehide', function() {
        detectedURLs.clear();
    });

    // Ad-related domains and URL patterns to filter out
    const adPatterns = [
        // Common ad networks
        /doubleclick\.net/i,
        /googlesyndication\.com/i,
        /googleadservices\.com/i,
        /googleads\./i,
        /adnxs\.com/i,
        /adsrvr\.org/i,
        /advertising\.com/i,
        /adform\.net/i,
        /criteo\.com/i,
        /taboola\.com/i,
        /outbrain\.com/i,
        /facebook\.com\/tr/i,
        /fbcdn.*video/i,
        // Ad keywords in URL
        /\/ads?\//i,
        /\/advert/i,
        /\/banner/i,
        /\/preroll/i,
        /\/midroll/i,
        /\/postroll/i,
        /\/sponsor/i,
        /[?&]ad[_-]?/i,
        /[?&]advert/i,
        /ad[-_]?server/i,
        /ad[-_]?tag/i,
        // Common ad video patterns
        /\.adsrvr\./i,
        /advert.*\.mp4/i,
        /promo.*video/i,
        /commercial/i,
        // Video ad specific
        /vpaid/i,
        /vast.*\.xml/i,
        /ima3/i,
        /imasdk/i,
        // iyf.tv specific ad patterns
        /adx\.m3u8/i,
        /ad_.*\.m3u8/i,
        /.*_ad\.m3u8/i,
        /advertisement/i,
        // Common Chinese video site ad patterns
        /guanggao/i,    // Chinese for advertisement
        /qianpian/i,    // pre-roll
        /tiepian/i,     // post-roll
        // Ad CDN domains
        /global-cdn\.me/i,
        /s1-a1\.global-cdn/i
    ];

    function isAdURL(url) {
        if (!url) return false;
        return adPatterns.some(pattern => pattern.test(url));
    }

    // Patterns that indicate video segments (not full videos)
    const segmentPatterns = [
        /seg-\d+/i,           // seg-1, seg-2, etc
        /segment[\-_]?\d+/i,  // segment1, segment-1
        /frag[\-_]?\d+/i,     // frag1, frag-1
        /chunk[\-_]?\d+/i,    // chunk1, chunk-1
        /part[\-_]?\d+/i,     // part1, part-1
        /\d+\.ts$/i,          // numbered .ts files
        /init\.mp4/i,         // initialization segment
        /\-\d{5,}\.mp4/i,     // long numbered mp4 (like -00001.mp4)
        /\/\d+\/\d+\.mp4/i,   // /1/2.mp4 pattern
    ];

    function isVideoSegment(url) {
        if (!url) return false;
        return segmentPatterns.some(pattern => pattern.test(url));
    }

    function sendToNative(url, type) {
        if (!url || typeof url !== 'string') return;
        if (url.startsWith('data:') || url.startsWith('blob:')) return;
        if (detectedURLs.has(url)) return;

        // Filter out ad-related URLs
        if (isAdURL(url)) {
            console.log('[OfflineBrowser] Filtered ad URL:', url);
            return;
        }

        // Filter out video segments for direct videos
        if (type === 'direct' && isVideoSegment(url)) {
            console.log('[OfflineBrowser] Filtered segment URL:', url);
            return;
        }

        // For direct MP4, limit to 3 per domain to avoid spam
        if (type === 'direct') {
            try {
                const domain = new URL(url).hostname;
                const count = mp4ByDomain.get(domain) || 0;
                if (count >= 3) {
                    console.log('[OfflineBrowser] Filtered excess MP4 from domain:', domain);
                    return;
                }
                mp4ByDomain.set(domain, count + 1);
            } catch (e) {}
        }

        detectedURLs.add(url);
        console.log('[OfflineBrowser] Detected stream:', type, url);

        try {
            window.webkit.messageHandlers.streamDetector.postMessage({
                type: 'streamDetected',
                url: url,
                streamType: type,
                timestamp: Date.now()
            });
        } catch (e) {
            console.log('[OfflineBrowser] Failed to send to native:', e);
        }
    }

    function checkForStream(url) {
        if (!url || typeof url !== 'string') return;

        // Normalize URL
        let normalizedUrl = url;
        try {
            if (!url.startsWith('http') && !url.startsWith('//')) {
                normalizedUrl = new URL(url, window.location.href).href;
            } else if (url.startsWith('//')) {
                normalizedUrl = window.location.protocol + url;
            }
        } catch (e) {
            normalizedUrl = url;
        }

        // Check for YouTube streams first (special handling)
        if (isYouTubeHLS(normalizedUrl) || isYouTubeDirectVideo(normalizedUrl)) {
            console.log('[OfflineBrowser] YouTube URL intercepted');
            sendYouTubeStreamToNative(normalizedUrl);
            return;
        }

        let type = null;

        // Check for HLS
        if (normalizedUrl.includes('.m3u8') ||
            normalizedUrl.includes('m3u8') ||
            normalizedUrl.includes('/hls/') ||
            normalizedUrl.includes('playlist.m3u8') ||
            normalizedUrl.includes('/manifest/') ||
            normalizedUrl.includes('index.m3u8') ||
            normalizedUrl.includes('master.m3u8')) {
            type = 'hls';
        }
        // Check for DASH
        else if (normalizedUrl.includes('.mpd') || normalizedUrl.includes('/dash/')) {
            type = 'dash';
        }
        // Check for direct video files
        else if (normalizedUrl.match(/\.(mp4|webm|m4v|mov|avi|mkv|flv|f4v)(\?|$|#)/i)) {
            type = 'direct';
        }
        // Check for common video CDN patterns (segment files indicate HLS)
        else if (normalizedUrl.includes('/video/') &&
                 (normalizedUrl.includes('.ts') || normalizedUrl.includes('seg')) &&
                 !normalizedUrl.includes('/api/')) {
            type = 'hls';
        }
        // Note: Removed overly broad /play/ pattern - was detecting API endpoints

        if (type) {
            sendToNative(normalizedUrl, type);
        }
    }

    // Extract URLs from text/JSON response
    function extractStreamURLsFromText(text) {
        if (!text || typeof text !== 'string') return;

        // YouTube-specific: Look for hlsManifestUrl in JSON responses
        if (isYouTubePage() || text.includes('googlevideo.com')) {
            // Match YouTube HLS manifest URL pattern
            const ytHlsPattern = /https?:\/\/[^\s"'<>]*googlevideo\.com[^\s"'<>]*\.m3u8[^\s"'<>]*/gi;
            const ytMatches = text.match(ytHlsPattern);
            if (ytMatches) {
                ytMatches.forEach(function(url) {
                    // Clean up escaped URLs from JSON
                    url = url.replace(/\\u0026/g, '&')
                             .replace(/\\\//g, '/')
                             .replace(/[\\'"]/g, '')
                             .split('\\u')[0];
                    if (isYouTubeHLS(url)) {
                        sendYouTubeHLSToNative(url);
                    }
                });
            }

            // Also look for hlsManifestUrl key in JSON
            const hlsManifestPattern = /"hlsManifestUrl"\s*:\s*"([^"]+)"/gi;
            let match;
            while ((match = hlsManifestPattern.exec(text)) !== null) {
                let url = match[1]
                    .replace(/\\u0026/g, '&')
                    .replace(/\\\//g, '/');
                if (url.includes('.m3u8')) {
                    sendYouTubeHLSToNative(url);
                }
            }
        }

        // Match m3u8 URLs
        const m3u8Pattern = /https?:\/\/[^\s"'<>]+\.m3u8[^\s"'<>]*/gi;
        const matches = text.match(m3u8Pattern);
        if (matches) {
            matches.forEach(function(url) {
                // Clean up the URL
                url = url.replace(/[\\'"]/g, '').split('\\u')[0];
                // Check if YouTube HLS (already handled above, but double-check)
                if (isYouTubeHLS(url)) {
                    sendYouTubeHLSToNative(url);
                } else {
                    sendToNative(url, 'hls');
                }
            });
        }

        // Match mp4 URLs
        const mp4Pattern = /https?:\/\/[^\s"'<>]+\.mp4[^\s"'<>]*/gi;
        const mp4Matches = text.match(mp4Pattern);
        if (mp4Matches) {
            mp4Matches.forEach(function(url) {
                url = url.replace(/[\\'"]/g, '').split('\\u')[0];
                sendToNative(url, 'direct');
            });
        }

        // Match mpd URLs
        const mpdPattern = /https?:\/\/[^\s"'<>]+\.mpd[^\s"'<>]*/gi;
        const mpdMatches = text.match(mpdPattern);
        if (mpdMatches) {
            mpdMatches.forEach(function(url) {
                url = url.replace(/[\\'"]/g, '').split('\\u')[0];
                sendToNative(url, 'dash');
            });
        }
    }

    // Intercept XMLHttpRequest
    const originalXHROpen = XMLHttpRequest.prototype.open;
    const originalXHRSend = XMLHttpRequest.prototype.send;

    XMLHttpRequest.prototype.open = function(method, url, ...args) {
        this._url = url;
        this._method = method;
        checkForStream(url);
        return originalXHROpen.apply(this, [method, url, ...args]);
    };

    XMLHttpRequest.prototype.send = function(...args) {
        const xhr = this;
        if (xhr._url) {
            checkForStream(xhr._url);
        }

        // Listen for response to extract URLs from body
        xhr.addEventListener('load', function() {
            try {
                if (xhr.responseText) {
                    extractStreamURLsFromText(xhr.responseText);
                }
            } catch (e) {}
        });

        return originalXHRSend.apply(this, args);
    };

    // Intercept fetch
    const originalFetch = window.fetch;
    window.fetch = function(input, init) {
        const url = typeof input === 'string' ? input : (input && input.url);
        if (url) {
            checkForStream(url);
        }

        // Also check response body
        return originalFetch.apply(this, arguments).then(function(response) {
            // Clone response to read body without consuming it
            const clone = response.clone();
            clone.text().then(function(text) {
                extractStreamURLsFromText(text);
            }).catch(function() {});
            return response;
        });
    };

    // Intercept video element src
    function checkVideoElement(video) {
        if (!video) return;

        if (video.src) {
            checkForStream(video.src);
        }
        if (video.currentSrc) {
            checkForStream(video.currentSrc);
        }

        // Check source elements
        const sources = video.querySelectorAll('source');
        sources.forEach(function(source) {
            if (source.src) {
                checkForStream(source.src);
            }
        });
    }

    // Monitor for video elements
    const observer = new MutationObserver(function(mutations) {
        mutations.forEach(function(mutation) {
            // Check added nodes
            mutation.addedNodes.forEach(function(node) {
                if (node.nodeType !== 1) return;

                if (node.tagName === 'VIDEO') {
                    checkVideoElement(node);
                    observeVideoSrc(node);
                } else if (node.tagName === 'SOURCE') {
                    checkForStream(node.src);
                } else if (node.tagName === 'IFRAME') {
                    try {
                        if (node.contentDocument) {
                            injectIntoDocument(node.contentDocument);
                        }
                    } catch (e) {}
                }

                // Check for nested videos
                if (node.querySelectorAll) {
                    node.querySelectorAll('video').forEach(checkVideoElement);
                    node.querySelectorAll('source').forEach(function(s) {
                        checkForStream(s.src);
                    });
                }
            });

            // Check attribute changes
            if (mutation.type === 'attributes') {
                const target = mutation.target;
                if (target.tagName === 'VIDEO' || target.tagName === 'SOURCE') {
                    if (mutation.attributeName === 'src') {
                        checkForStream(target.src);
                    }
                }
            }
        });
    });

    observer.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['src']
    });

    // Observe individual video elements for src changes
    function observeVideoSrc(video) {
        const videoObserver = new MutationObserver(function(mutations) {
            mutations.forEach(function(mutation) {
                if (mutation.attributeName === 'src') {
                    checkForStream(video.src);
                    checkForStream(video.currentSrc);
                }
            });
        });
        videoObserver.observe(video, { attributes: true, attributeFilter: ['src'] });

        // Also listen for loadedmetadata event
        video.addEventListener('loadedmetadata', function() {
            checkForStream(video.src);
            checkForStream(video.currentSrc);
        });

        video.addEventListener('loadstart', function() {
            checkForStream(video.src);
            checkForStream(video.currentSrc);
        });

        video.addEventListener('play', function() {
            checkForStream(video.src);
            checkForStream(video.currentSrc);
        });
    }

    // Check existing video elements
    document.querySelectorAll('video').forEach(function(video) {
        checkVideoElement(video);
        observeVideoSrc(video);
    });

    // Intercept createElement to catch dynamically created videos
    const originalCreateElement = document.createElement.bind(document);
    document.createElement = function(tagName, options) {
        const element = originalCreateElement(tagName, options);
        if (tagName.toLowerCase() === 'video') {
            setTimeout(function() {
                checkVideoElement(element);
                observeVideoSrc(element);
            }, 100);
        }
        return element;
    };

    // Hook into hls.js if present
    function hookHLS() {
        if (window.Hls) {
            console.log('[OfflineBrowser] HLS.js detected, hooking...');
            const OriginalHls = window.Hls;
            window.Hls = function(config) {
                const instance = new OriginalHls(config);
                const originalLoadSource = instance.loadSource.bind(instance);
                instance.loadSource = function(url) {
                    console.log('[OfflineBrowser] HLS.js loading source:', url);
                    sendToNative(url, 'hls');
                    return originalLoadSource(url);
                };
                return instance;
            };
            // Copy static properties
            Object.keys(OriginalHls).forEach(function(key) {
                window.Hls[key] = OriginalHls[key];
            });
            window.Hls.prototype = OriginalHls.prototype;
        }
    }

    // Hook into video.js if present
    function hookVideoJS() {
        if (window.videojs) {
            console.log('[OfflineBrowser] video.js detected, hooking...');
            const originalVideojs = window.videojs;
            window.videojs = function(id, options, ready) {
                const player = originalVideojs(id, options, ready);
                player.on('loadedmetadata', function() {
                    const src = player.currentSrc();
                    if (src) {
                        checkForStream(src);
                    }
                });
                return player;
            };
            Object.keys(originalVideojs).forEach(function(key) {
                window.videojs[key] = originalVideojs[key];
            });
        }
    }

    // Intercept Media Source Extensions
    if (window.MediaSource) {
        const originalAddSourceBuffer = MediaSource.prototype.addSourceBuffer;
        MediaSource.prototype.addSourceBuffer = function(mimeType) {
            console.log('[OfflineBrowser] MediaSource addSourceBuffer:', mimeType);
            return originalAddSourceBuffer.apply(this, arguments);
        };
    }

    // Intercept URL.createObjectURL for blob URLs
    const originalCreateObjectURL = URL.createObjectURL;
    URL.createObjectURL = function(obj) {
        const url = originalCreateObjectURL.apply(this, arguments);
        if (obj instanceof MediaSource) {
            console.log('[OfflineBrowser] MediaSource blob URL created');
        }
        return url;
    };

    // Periodically scan for videos and check for player libraries
    setInterval(function() {
        // Check videos
        document.querySelectorAll('video').forEach(function(video) {
            if (video.src && !detectedURLs.has(video.src)) {
                checkForStream(video.src);
            }
            if (video.currentSrc && !detectedURLs.has(video.currentSrc)) {
                checkForStream(video.currentSrc);
            }
        });

        // Try to hook player libraries if they appeared
        hookHLS();
        hookVideoJS();
    }, 2000);

    // Inject into document helper
    function injectIntoDocument(doc) {
        try {
            doc.querySelectorAll('video').forEach(checkVideoElement);
        } catch (e) {}
    }

    // Check page source for embedded video URLs
    setTimeout(function() {
        try {
            const pageHTML = document.documentElement.innerHTML;
            extractStreamURLsFromText(pageHTML);
        } catch (e) {}
    }, 1000);

    // Initial hook attempts
    hookHLS();
    hookVideoJS();

    // YouTube-specific playback detection
    if (isYouTubePage()) {
        console.log('[OfflineBrowser] YouTube page detected, enabling HLS interception');

        // Listen for video play events (capture phase to catch before YouTube handles)
        document.addEventListener('play', function(e) {
            if (e.target && e.target.tagName === 'VIDEO') {
                console.log('[OfflineBrowser] YouTube video play event detected');
                startYouTubeHLSCapture();

                // Check the video element for HLS source
                const video = e.target;
                if (video.src && isYouTubeHLS(video.src)) {
                    sendYouTubeHLSToNative(video.src);
                }
                if (video.currentSrc && isYouTubeHLS(video.currentSrc)) {
                    sendYouTubeHLSToNative(video.currentSrc);
                }
            }
        }, true);

        // Also listen for loadeddata which fires when video is ready
        document.addEventListener('loadeddata', function(e) {
            if (e.target && e.target.tagName === 'VIDEO') {
                const video = e.target;
                console.log('[OfflineBrowser] YouTube video loadeddata:', video.src || video.currentSrc);
                if (video.src && isYouTubeHLS(video.src)) {
                    sendYouTubeHLSToNative(video.src);
                }
                if (video.currentSrc && isYouTubeHLS(video.currentSrc)) {
                    sendYouTubeHLSToNative(video.currentSrc);
                }
            }
        }, true);

        // Monitor YouTube's video player for source changes
        function monitorYouTubePlayer() {
            const videos = document.querySelectorAll('video');
            videos.forEach(function(video) {
                // Check current source
                if (video.src && isYouTubeHLS(video.src)) {
                    sendYouTubeHLSToNative(video.src);
                }
                if (video.currentSrc && isYouTubeHLS(video.currentSrc)) {
                    sendYouTubeHLSToNative(video.currentSrc);
                }

                // Check source elements
                video.querySelectorAll('source').forEach(function(source) {
                    if (source.src && isYouTubeHLS(source.src)) {
                        sendYouTubeHLSToNative(source.src);
                    }
                });
            });
        }

        // Run YouTube monitor periodically
        setInterval(monitorYouTubePlayer, 1000);

        // Also run on DOM changes (YouTube is a SPA)
        const youtubeObserver = new MutationObserver(function() {
            monitorYouTubePlayer();
        });
        youtubeObserver.observe(document.body, {
            childList: true,
            subtree: true
        });
    }

    console.log('[OfflineBrowser] Stream interceptor initialized successfully');
})();
