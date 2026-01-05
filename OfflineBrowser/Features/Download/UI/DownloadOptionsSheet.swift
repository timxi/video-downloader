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
        self.streams = streams
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
        tableView.register(StreamCell.self, forCellReuseIdentifier: "StreamCell")

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
}

// MARK: - UITableViewDataSource

extension DownloadOptionsSheet: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        streams.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let stream = streams[section]
        // If stream has quality options, show them
        if let qualities = stream.qualities, !qualities.isEmpty {
            return qualities.count
        }
        // Otherwise show single option
        return 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let stream = streams[section]
        let typeLabel: String
        switch stream.type {
        case .hls: typeLabel = "HLS Stream"
        case .dash: typeLabel = "DASH Stream"
        case .direct: typeLabel = "Direct Video"
        case .unknown: typeLabel = "Video"
        }
        return "Video \(section + 1) - \(typeLabel)"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "StreamCell", for: indexPath) as! StreamCell

        let stream = streams[indexPath.section]

        if let qualities = stream.qualities, !qualities.isEmpty {
            let quality = qualities[indexPath.row]
            cell.configure(
                title: quality.resolution,
                subtitle: quality.formattedBandwidth,
                isRecommended: indexPath.row == 0
            )
        } else {
            cell.configure(
                title: stream.type == .direct ? "Download Video" : "Best Quality",
                subtitle: URL(string: stream.url)?.host ?? "",
                isRecommended: true
            )
        }

        return cell
    }
}

// MARK: - UITableViewDelegate

extension DownloadOptionsSheet: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        var stream = streams[indexPath.section]

        // If qualities are available, update the stream URL to the selected quality
        if let qualities = stream.qualities, !qualities.isEmpty {
            let selectedQuality = qualities[indexPath.row]
            // Create new stream with selected quality URL
            stream = DetectedStream(
                id: stream.id,
                url: selectedQuality.url,
                type: stream.type,
                detectedAt: stream.detectedAt
            )
        }

        delegate?.downloadOptionsSheet(self, didSelectStream: stream)
    }
}

// MARK: - StreamCell

class StreamCell: UITableViewCell {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let recommendedBadge = UILabel()

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

        recommendedBadge.text = "Best"
        recommendedBadge.font = .systemFont(ofSize: 11, weight: .semibold)
        recommendedBadge.textColor = .white
        recommendedBadge.backgroundColor = .systemGreen
        recommendedBadge.layer.cornerRadius = 4
        recommendedBadge.clipsToBounds = true
        recommendedBadge.textAlignment = .center

        let stackView = UIStackView(arrangedSubviews: [titleLabel, recommendedBadge, UIView(), subtitleLabel])
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center

        contentView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),

            recommendedBadge.widthAnchor.constraint(equalToConstant: 36),
            recommendedBadge.heightAnchor.constraint(equalToConstant: 18)
        ])

        accessoryType = .disclosureIndicator
    }

    func configure(title: String, subtitle: String, isRecommended: Bool) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        recommendedBadge.isHidden = !isRecommended
    }
}
