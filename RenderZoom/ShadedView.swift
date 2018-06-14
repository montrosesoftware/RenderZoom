//
//  ShadedView.swift
//  Bond
//
//  Created by Marek Krzynowek on 7/9/16.
//  Copyright © 2016 bond.co. All rights reserved.
//

import Foundation
import UIKit
import PureLayout

class ShadedView: UIView {
    
    fileprivate var constraintsSet: Bool = false
    var radius: CGFloat = 4
    
    var content: UIView? {
        didSet {
            removeSubviews()
            if let content = content {
                addSubview(content)
            }
            setNeedsUpdateConstraints()
        }
    }
    
    var dropShadow: Bool = true {
        didSet {
            if !dropShadow {
                layer.shadowPath = nil
            }
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        sharedInit()
    }  
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        sharedInit()
    }
    
    func sharedInit() {
        backgroundColor = Color.WHITE
        if let content = content {
            addSubview(content)
        }
    }
    
    override func setNeedsUpdateConstraints() {
        constraintsSet = false
        super.setNeedsUpdateConstraints()
    }
    
    override func updateConstraints() {
        guard !constraintsSet else {
            super.updateConstraints()
            return
        }
        content?.autoPinEdgesToSuperviewEdges()
        content?.layer.cornerRadius = radius
        content?.layer.masksToBounds = true
        
        constraintsSet = true
        super.updateConstraints()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        if dropShadow {
            let shadowPath = UIBezierPath(rect: bounds)
            layer.masksToBounds = false
            layer.shadowColor = Color.BLACK.cgColor
            layer.shadowOffset = CGSize(width: 0.0, height: 3.0)
            layer.shadowOpacity = 0.2
            layer.shadowRadius = 5
            layer.shadowPath = shadowPath.cgPath
        }
    }
}
