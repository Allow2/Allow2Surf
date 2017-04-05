/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

struct ThumbnailCellUX {
    // TODO: Clean up unused constants
    
    /// Ratio of width:height of the thumbnail image.
    static let ImageAspectRatio: Float = 1.0
    static let BorderColor = UIColor.blackColor().colorWithAlphaComponent(0.15)
    static let BorderWidth: CGFloat = 0.5
    static let LabelColor = UIAccessibilityDarkerSystemColorsEnabled() ? UIColor.blackColor() : UIColor(rgb: 0x353535)
    static let LabelAlignment: NSTextAlignment = .Center
    static let SelectedOverlayColor = UIColor(white: 0.0, alpha: 0.25)
    static let InsetSize: CGFloat = 10
    static let InsetSizeCompact: CGFloat = 3
    static let ImagePaddingWide: CGFloat = 4
    static let ImagePaddingCompact: CGFloat = 2
    
    // TODO: This is absurd, remove it
    static func insetsForCollectionViewSize(size: CGSize, traitCollection: UITraitCollection) -> UIEdgeInsets {
        let largeInsets = UIEdgeInsets(
                top: ThumbnailCellUX.InsetSize,
                left: ThumbnailCellUX.InsetSize,
                bottom: ThumbnailCellUX.InsetSize,
                right: ThumbnailCellUX.InsetSize
            )
        let smallInsets = UIEdgeInsets(
                top: ThumbnailCellUX.InsetSizeCompact,
                left: ThumbnailCellUX.InsetSizeCompact,
                bottom: ThumbnailCellUX.InsetSizeCompact,
                right: ThumbnailCellUX.InsetSizeCompact
            )

        if traitCollection.horizontalSizeClass == .Compact {
            return smallInsets
        } else {
            return largeInsets
        }
    }

    // TODO: Remove
    static func imageInsetsForCollectionViewSize(size: CGSize, traitCollection: UITraitCollection) -> UIEdgeInsets {
        let largeInsets = UIEdgeInsets(
                top: ThumbnailCellUX.ImagePaddingWide,
                left: ThumbnailCellUX.ImagePaddingWide,
                bottom: ThumbnailCellUX.ImagePaddingWide,
                right: ThumbnailCellUX.ImagePaddingWide
            )

        let smallInsets = UIEdgeInsets(
                top: ThumbnailCellUX.ImagePaddingCompact,
                left: ThumbnailCellUX.ImagePaddingCompact,
                bottom: ThumbnailCellUX.ImagePaddingCompact,
                right: ThumbnailCellUX.ImagePaddingCompact
            )
        if traitCollection.horizontalSizeClass == .Compact {
            return smallInsets
        } else {
            return largeInsets // reminder: iphone landscape uses this
        }
    }

    static let LabelInsets = UIEdgeInsetsMake(0, 3, 2, 3)
    static let PlaceholderImage = UIImage(named: "defaultTopSiteIcon")
    static let CornerRadius: CGFloat = 4

    // Make the remove button look 20x20 in size but have the clickable area be 44x44
    static let RemoveButtonSize: CGFloat = 44
    static let RemoveButtonInsets = UIEdgeInsets(top: 11, left: 0, bottom: 11, right: 22)
    static let RemoveButtonAnimationDuration: NSTimeInterval = 0.4
    static let RemoveButtonAnimationDamping: CGFloat = 0.6

    static let NearestNeighbordScalingThreshold: CGFloat = 24
}

@objc protocol ThumbnailCellDelegate {
    func didRemoveThumbnail(thumbnailCell: ThumbnailCell)
    func didLongPressThumbnail(thumbnailCell: ThumbnailCell)
}

class ThumbnailCell: UICollectionViewCell {
    weak var delegate: ThumbnailCellDelegate?

    var imageInsets: UIEdgeInsets = UIEdgeInsetsZero
    var cellInsets: UIEdgeInsets = UIEdgeInsetsZero

    // TODO: Remove
    var imagePadding: CGFloat = 0

    static func imageWithSize(image: UIImage, size:CGSize, maxScale: CGFloat) -> UIImage {
        var scaledImageRect = CGRect.zero;
        var aspectWidth:CGFloat = size.width / image.size.width;
        var aspectHeight:CGFloat = size.height / image.size.height;
        if aspectWidth > maxScale || aspectHeight > maxScale {
            let m = max(maxScale / aspectWidth, maxScale / aspectHeight)
            aspectWidth *= m
            aspectHeight *= m
        }
        let aspectRatio:CGFloat = min(aspectWidth, aspectHeight);
        scaledImageRect.size.width = image.size.width * aspectRatio;
        scaledImageRect.size.height = image.size.height * aspectRatio;
        scaledImageRect.origin.x = (size.width - scaledImageRect.size.width) / 2.0;
        scaledImageRect.origin.y = (size.height - scaledImageRect.size.height) / 2.0;
        UIGraphicsBeginImageContextWithOptions(size, false, 0);
        image.drawInRect(scaledImageRect);
        let scaledImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return scaledImage!;
    }

    var image: UIImage? = nil {
        didSet {
            struct ContainerSize {
                static var size: CGSize = CGSizeZero
                static func scaledDown() -> CGSize {
                    return CGSizeMake(size.width * 0.75, size.height * 0.75)
                }
            }

            if imageView.frame.size.width > 0 {
                ContainerSize.size = imageView.frame.size
            }

            if var image = image {
                if image.size.width <= 32 && ContainerSize.size != CGSizeZero {
                    var maxScale = CGFloat(image.size.width < 24 ? 3.0 : 1.5)
                    if ContainerSize.size.width > 170 {
                        // we are on iPad pro. Fragile, but no other way to detect this on simulator.
                        maxScale *= 2.0
                    }
                    image = ThumbnailCell.imageWithSize(image, size: ContainerSize.scaledDown(), maxScale: maxScale)
                    imageView.contentMode = .Center
                }
                else if image.size.width > 32 {
                    imageView.contentMode = .ScaleAspectFit
                }
                imageView.image = image
            } else {
                imageView.image = ThumbnailCellUX.PlaceholderImage
                imageView.contentMode = .Center
            }
        }
    }

    lazy var longPressGesture: UILongPressGestureRecognizer = {
        return UILongPressGestureRecognizer(target: self, action: #selector(ThumbnailCell.SELdidLongPress))
    }()

    lazy var textLabel: UILabel = {
        let textLabel = UILabel()
        textLabel.setContentHuggingPriority(1000, forAxis: UILayoutConstraintAxis.Vertical)
        textLabel.font = DynamicFontHelper.defaultHelper.DefaultSmallFont
        textLabel.textColor = ThumbnailCellUX.LabelColor
        textLabel.textAlignment = ThumbnailCellUX.LabelAlignment
        return textLabel
    }()

    lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .ScaleAspectFit

        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = ThumbnailCellUX.CornerRadius
        imageView.layer.borderColor = ThumbnailCellUX.BorderColor.CGColor
        imageView.layer.minificationFilter = kCAFilterTrilinear
        imageView.layer.magnificationFilter = kCAFilterNearest
        return imageView
    }()


    // TODO: Remove
    lazy var imageWrapper: UIView = {
        let imageWrapper = UIView()
        imageWrapper.layer.cornerRadius = ThumbnailCellUX.CornerRadius
        imageWrapper.clipsToBounds = true
        return imageWrapper
    }()

    lazy var removeButton: UIButton = {
        let removeButton = UIButton()
        removeButton.exclusiveTouch = true
        let removeButtonImage = UIImage(named: "TileCloseButton")
        removeButton.setImage(removeButtonImage, forState: UIControlState.Normal)
        removeButton.addTarget(self, action: #selector(ThumbnailCell.SELdidRemove), forControlEvents: UIControlEvents.TouchUpInside)
        removeButton.accessibilityLabel = Strings.Remove_page
        removeButton.hidden = true
        removeButton.sizeToFit()
        let buttonCenterX = floor(removeButton.bounds.width/2)
        let buttonCenterY = floor(removeButton.bounds.height/2)
        removeButton.center = CGPoint(x: buttonCenterX, y: buttonCenterY)
        return removeButton    }()

    // TODO: Should be no longer needed
    lazy var backgroundImage: UIImageView = {
        let backgroundImage = UIImageView()
        backgroundImage.contentMode = UIViewContentMode.ScaleAspectFill
        return backgroundImage
    }()

    // TODO: Remove
    lazy var selectedOverlay: UIView = {
        let selectedOverlay = UIView()
        selectedOverlay.backgroundColor = ThumbnailCellUX.SelectedOverlayColor
        selectedOverlay.hidden = true
        return selectedOverlay
    }()

    override var selected: Bool {
        didSet { updateSelectedHighlightedState() }
    }
    
    override var highlighted: Bool {
        didSet { updateSelectedHighlightedState() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        layer.shouldRasterize = true
        layer.rasterizationScale = UIScreen.mainScreen().scale

        isAccessibilityElement = true
        addGestureRecognizer(longPressGesture)

        contentView.addSubview(imageView)
        contentView.addSubview(textLabel)
        contentView.addSubview(removeButton)

        textLabel.snp_remakeConstraints { make in
            // TODO: relook at insets
            make.left.right.equalTo(self.contentView).inset(ThumbnailCellUX.LabelInsets)
            make.top.equalTo(imageView.snp_bottom).offset(5)
        }

        // Prevents the textLabel from getting squished in relation to other view priorities.
        textLabel.setContentCompressionResistancePriority(1000, forAxis: UILayoutConstraintAxis.Vertical)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        backgroundImage.image = nil
        removeButton.hidden = true
        textLabel.font = DynamicFontHelper.defaultHelper.DefaultSmallFont
        textLabel.textColor = PrivateBrowsing.singleton.isOn ? UIColor(rgb: 0xDBDBDB) : UIColor(rgb: 0x2D2D2D)
    }
    
    private func updateSelectedHighlightedState() {
        let activated = selected || highlighted
        self.imageView.alpha = activated ? 0.7 : 1.0
    }

    func SELdidRemove() {
        delegate?.didRemoveThumbnail(self)
    }

    func SELdidLongPress() {
        delegate?.didLongPressThumbnail(self)
    }

    func toggleRemoveButton(show: Bool) {
        // Only toggle if we change state
        if removeButton.hidden != show {
            return
        }

        if show {
            removeButton.hidden = false
        }

        let scaleTransform = CGAffineTransformMakeScale(0.01, 0.01)
        removeButton.transform = show ? scaleTransform : CGAffineTransformIdentity
        UIView.animateWithDuration(ThumbnailCellUX.RemoveButtonAnimationDuration,
            delay: 0,
            usingSpringWithDamping: ThumbnailCellUX.RemoveButtonAnimationDamping,
            initialSpringVelocity: 0,
            options: [UIViewAnimationOptions.AllowUserInteraction, UIViewAnimationOptions.CurveEaseInOut],
            animations: {
                self.removeButton.transform = show ? CGAffineTransformIdentity : scaleTransform
            }, completion: { _ in
                if !show {
                    self.removeButton.hidden = true
                }
            })
    }
    
    func showBorder(show: Bool) {
        imageView.layer.borderWidth = show ? ThumbnailCellUX.BorderWidth : 0
    }

    /**
     Updates the insets and padding of the cell based on the size of the container collection view

     - parameter size: Size of the container collection view
     */
    func updateLayoutForCollectionViewSize(size: CGSize, traitCollection: UITraitCollection, forSuggestedSite: Bool) {
        
        // Find out if our image is going to have fractional pixel width.
        // If so, we inset by a tiny extra amount to get it down to an integer for better
        // image scaling.
        let parentWidth = self.imageWrapper.frame.width
        let width = (parentWidth - imagePadding)
        let fractionalW = width - floor(width)
        let additionalW = fractionalW / 2
        
        // TODO: Should not remade on every layout call
        imageView.snp_remakeConstraints { make in
            make.top.equalTo(self.contentView).inset(8)
            make.right.left.equalTo(self.contentView).inset(16 + additionalW)
            make.height.equalTo(imageView.snp_width)
        }
        imageView.setNeedsUpdateConstraints()
    }
}
