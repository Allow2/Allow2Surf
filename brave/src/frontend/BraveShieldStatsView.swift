//
//  BraveShieldStatsView.swift
//  Client
//

import Foundation

class BraveShieldStatsView: UIView {
    private let millisecondsPerItem = 50
    private let line = UIView()
    
    lazy var adsStatView: StatView = {
        let statView = StatView(frame: CGRectZero)
        statView.title = "Ads \rBlocked"
        statView.color = UIColor(red: 242/255.0, green: 142/255.0, blue: 45/255.0, alpha: 1.0)
        return statView
    }()

    lazy var trackersStatView: StatView = {
        let statView = StatView(frame: CGRectZero)
        statView.title = "Trackers \rBlocked"
        statView.color = UIColor(red: 234/255.0, green: 58/255.0, blue: 58/255.0, alpha: 1.0)
        return statView
    }()

    lazy var httpsStatView: StatView = {
        let statView = StatView(frame: CGRectZero)
        statView.title = "HTTPS \rUpgrades"
        statView.color = UIColor(red: 25/255.0, green: 152/255.0, blue: 252/255.0, alpha: 1.0)
        return statView
    }()

    lazy var timeStatView: StatView = {
        let statView = StatView(frame: CGRectZero)
        statView.title = "Est. Time \rSaved"
        // Color dynamically set in controller: TopSitesPanel, should be abstracted
        statView.color = PrivateBrowsing.singleton.isOn ? .whiteColor() : .blackColor()
        return statView
    }()
    
    lazy var stats: [StatView] = {
        return [self.adsStatView, self.trackersStatView, self.httpsStatView, self.timeStatView]
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        addSubview(line)
        line.backgroundColor = UIColor(white: 0.0, alpha: 0.2)
        line.snp_makeConstraints { (make) in
            make.bottom.equalTo(0).offset(-0.5)
            make.height.equalTo(0.5)
            make.left.equalTo(0)
            make.right.equalTo(0)
        }
        
        for s: StatView in stats {
            addSubview(s)
        }
        
        update()
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(update), name: BraveGlobalShieldStats.DidUpdateNotification, object: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    override func layoutSubviews() {
        let width: CGFloat = frame.width / CGFloat(stats.count)
        var offset: CGFloat = 0
        for s: StatView in stats {
            var f: CGRect = s.frame
            f.origin.x = offset
            f.size = CGSizeMake(width, frame.height)
            s.frame = f
            offset += width
        }
    }
    
    func update() {
        adsStatView.stat = BraveGlobalShieldStats.singleton.adblock.formatUsingAbbrevation()
        trackersStatView.stat = BraveGlobalShieldStats.singleton.trackingProtection.formatUsingAbbrevation()
        httpsStatView.stat = BraveGlobalShieldStats.singleton.httpse.formatUsingAbbrevation()
        timeStatView.stat = timeSaved
    }
    
    var timeSaved: String {
        get {
            let estimatedMillisecondsSaved = (BraveGlobalShieldStats.singleton.adblock + BraveGlobalShieldStats.singleton.trackingProtection) * millisecondsPerItem
            let hours = estimatedMillisecondsSaved < 1000 * 60 * 60 * 24
            let minutes = estimatedMillisecondsSaved < 1000 * 60 * 60
            let seconds = estimatedMillisecondsSaved < 1000 * 60
            var counter: Double = 0
            var text = ""
            
            if seconds {
                counter = ceil(Double(estimatedMillisecondsSaved / 1000))
                text = "s"
            }
            else if minutes {
                counter = ceil(Double(estimatedMillisecondsSaved / 1000 / 60))
                text = "min"
            }
            else if hours {
                counter = ceil(Double(estimatedMillisecondsSaved / 1000 / 60 / 60))
                text = "h"
            }
            else {
                counter = ceil(Double(estimatedMillisecondsSaved / 1000 / 60 / 60 / 24))
                text = "d"
            }
            
            return "\(Int(counter))\(text)"
        }
    }
}

class StatView: UIView {
    var color: UIColor = UIColor.blackColor() {
        didSet {
            statLabel.textColor = color
        }
    }
    
    var stat: String = "" {
        didSet {
            statLabel.text = "\(stat)"
        }
    }
    
    var title: String = "" {
        didSet {
            titleLabel.text = "\(title)"
        }
    }
    
    private var statLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .Center
        label.numberOfLines = 0
        label.font = UIFont.systemFontOfSize(24, weight: UIFontWeightBold)
        return label
    }()
    
    private var titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = BraveUX.TopSitesStatTitleColor
        label.textAlignment = .Center
        label.numberOfLines = 0
        label.font = UIFont.systemFontOfSize(12, weight: UIFontWeightMedium)
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        addSubview(statLabel)
        addSubview(titleLabel)
        
        statLabel.snp_makeConstraints(closure: { (make) in
            make.left.equalTo(0)
            make.right.equalTo(0)
            make.centerY.equalTo(self).offset(-(statLabel.sizeThatFits(CGSizeMake(CGFloat.max, CGFloat.max)).height)-10)
        })
        
        titleLabel.snp_makeConstraints(closure: { (make) in
            make.left.equalTo(0)
            make.right.equalTo(0)
            make.top.equalTo(statLabel.snp_bottom).offset(5)
        })
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
