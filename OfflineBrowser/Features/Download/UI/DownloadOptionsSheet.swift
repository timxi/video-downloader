import UIKit

protocol DownloadOptionsSheetDelegate: AnyObject {
    func downloadOptionsSheet(_ sheet: DownloadOptionsSheet, didSelectStream stream: DetectedStream)
}

class DownloadOptionsSheet: UIViewController {

    // MARK: - Properties

    weak var delegate: DownloadOptionsSheetDelegate?

    private let streams: [DetectedStream]
    private let pageTitle: String?
    private let pageURL: URL?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let headerLabel = UILabel()

    // MARK: - Initialization

    init(streams: [DetectedStream], pageTitle: String?, pageURL: URL?) {
        // Filter streams: if HLS streams exist, hide direct MP4 (they're usually segments)
        let hlsStreams = streams.filter { $0.type == .hls }
        let filteredStreams: [DetectedStream]

        if !hlsStreams.isEmpty {
            // Prefer HLS streams, only show direct if no HLS available
            filteredStreams = hlsStreams
        } else {
            // No HLS, keep direct streams but limit to reasonable number
            filteredStreams = Array(streams.prefix(5))
        }

        self.streams = filteredStreams
        self.pageTitle = pageTitle
        self.pageURL = pageURL
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .systemGroupedBackground

        // Header
        headerLabel.text = "Detected Videos"
        headerLabel.font = .systemFont(ofSize: 20, weight: .bold)

        view.addSubview(headerLabel)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        // Table view
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(VideoStreamCell.self, forCellReuseIdentifier: "VideoStreamCell")

        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            tableView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 16),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Quality Selection

    private func showQualityPicker(for stream: DetectedStream, at indexPath: IndexPath) {
        guard let qualities = stream.qualities, qualities.count > 1 else {
            // No quality options or single quality - download directly
            delegate?.downloadOptionsSheet(self, didSelectStream: stream)
            return
        }

        // Filter out 0 Mbps qualities if there are valid bandwidth options
        let qualitiesWithBandwidth = qualities.filter { $0.bandwidth > 0 }
        var filteredQualities: [StreamQuality]

        if qualitiesWithBandwidth.count > 0 {
            // Use only qualities with valid bandwidth, sorted by bandwidth descending
            filteredQualities = qualitiesWithBandwidth.sorted { $0.bandwidth > $1.bandwidth }
        } else {
            // No bandwidth info available, keep all
            filteredQualities = qualities
        }

        // Final deduplication by display string (resolution + formatted bandwidth)
        var seenDisplayStrings = Set<String>()
        filteredQualities = filteredQualities.filter { quality in
            let displayKey = "\(quality.resolution)-\(quality.formattedBandwidth)"
            if seenDisplayStrings.contains(displayKey) {
                return false
            }
            seenDisplayStrings.insert(displayKey)
            return true
        }

        // If filtering reduced to 1 quality, download directly
        guard filteredQualities.count > 1 else {
            let quality = filteredQualities.first ?? qualities.first!
            let selectedStream = DetectedStream(
                id: stream.id,
                url: quality.url,
                type: stream.type,
                detectedAt: stream.detectedAt
            )
            delegate?.downloadOptionsSheet(self, didSelectStream: selectedStream)
            return
        }

        let alert = UIAlertController(title: "Select Quality (\(filteredQualities.count) options)", message: nil, preferredStyle: .actionSheet)

        for (index, quality) in filteredQualities.enumerated() {
            let title = "\(quality.resolution)\(index == 0 ? " (Best)" : "")"
            let subtitle = quality.bandwidth > 0 ? quality.formattedBandwidth : ""
            let fullTitle = subtitle.isEmpty ? title : "\(title) - \(subtitle)"

            alert.addAction(UIAlertAction(title: fullTitle, style: .default) { [weak self] _ in
                guard let self = self else { return }
                // Create new stream with selected quality URL
                let selectedStream = DetectedStream(
                    id: stream.id,
                    url: quality.url,
                    type: stream.type,
                    detectedAt: stream.detectedAt
                )
                self.delegate?.downloadOptionsSheet(self, didSelectStream: selectedStream)
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        // For iPad
        if let popover = alert.popoverPresentationController {
            if let cell = tableView.cellForRow(at: indexPath) {
                popover.sourceView = cell
                popover.sourceRect = cell.bounds
            }
        }

        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension DownloadOptionsSheet: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        streams.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "VideoStreamCell", for: indexPath) as! VideoStreamCell

        let stream = streams[indexPath.row]

        // Format duration
        var durationStr: String? = nil
        if let duration = stream.duration {
            let hours = Int(duration) / 3600
            let minutes = Int(duration) % 3600 / 60
            let seconds = Int(duration) % 60
            if hours > 0 {
                durationStr = String(format: "%d:%02d:%02d", hours, minutes, seconds)
            } else {
                durationStr = String(format: "%d:%02d", minutes, seconds)
            }
        }

        // Quality info - filter out 0 bandwidth when counting
        let qualities = stream.qualities ?? []
        let qualitiesWithBandwidth = qualities.filter { $0.bandwidth > 0 }
        let qualityCount = qualitiesWithBandwidth.isEmpty ? qualities.count : qualitiesWithBandwidth.count
        let bestQuality = qualitiesWithBandwidth.max(by: { $0.bandwidth < $1.bandwidth })?.resolution
            ?? qualities.first?.resolution

        cell.configure(
            videoNumber: indexPath.row + 1,
            duration: durationStr,
            qualityCount: qualityCount,
            bestQuality: bestQuality,
            streamType: stream.type
        )

        return cell
    }
}

// MARK: - UITableViewDelegate

extension DownloadOptionsSheet: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let stream = streams[indexPath.row]

        // If multiple qualities, show picker. Otherwise download directly.
        if let qualities = stream.qualities, qualities.count > 1 {
            showQualityPicker(for: stream, at: indexPath)
        } else {
            delegate?.downloadOptionsSheet(self, didSelectStream: stream)
        }
    }
}

// MARK: - VideoStreamCell

class VideoStreamCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let qualityBadge = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        titleLabel.font = .systemFont(ofSize: 16, weight: .medium)

        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel

        qualityBadge.font = .systemFont(ofSize: 11, weight: .semibold)
        qualityBadge.textColor = .white
        qualityBadge.backgroundColor = .systemBlue
        qualityBadge.layer.cornerRadius = 4
        qualityBadge.clipsToBounds = true
        qualityBadge.textAlignment = .center

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 4

        let mainStack = UIStackView(arrangedSubviews: [textStack, UIView(), qualityBadge])
        mainStack.axis = .horizontal
        mainStack.spacing = 8
        mainStack.alignment = .center

        contentView.addSubview(mainStack)
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            mainStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            qualityBadge.heightAnchor.constraint(equalToConstant: 22)
        ])

        accessoryType = .disclosureIndicator
    }

    func configure(videoNumber: Int, duration: String?, qualityCount: Int, bestQuality: String?, streamType: StreamType) {
        // Title
        let typeStr = streamType == .direct ? "MP4" : "HLS"
        titleLabel.text = "Video \(videoNumber) (\(typeStr))"

        // Subtitle with duration
        if let duration = duration {
            subtitleLabel.text = "Duration: \(duration)"
            subtitleLabel.isHidden = false
        } else {
            subtitleLabel.isHidden = true
        }

        // Quality badge
        if qualityCount > 1 {
            qualityBadge.text = "  \(qualityCount) qualities  "
            qualityBadge.backgroundColor = .systemBlue
            qualityBadge.isHidden = false
        } else if let quality = bestQuality {
            qualityBadge.text = "  \(quality)  "
            qualityBadge.backgroundColor = .systemGreen
            qualityBadge.isHidden = false
        } else {
            qualityBadge.isHidden = true
        }
    }
}
