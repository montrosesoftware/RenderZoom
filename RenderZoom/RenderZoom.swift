//
//  RenderZoomViewController.swift
//  Bond
//
//  Created by Marek Krzynowek on 12/09/2017.
//  Copyright © 2017 bond.co. All rights reserved.
//

import Foundation
import EZSwiftExtensions

@objc protocol RenderZoomDelegate {     //TODO rename
    func zoomIn(view: UIView) -> RenderZoomManager?
}

enum ZoomDirection {
    case zoomIn, zoomOut
}
class ZoomRenders {
    private static let REPLICA = 439 //Need to store this so we dont replicate the replica.
    
    fileprivate static let ZOOMED_IN_SIZE: CGSize = CGSize(width: 700, height: 500)   //TODO: make
    fileprivate static var finalFrame = CGRect(origin: CGPoint(x: (ez.screenWidth/2) - (ZoomRenders.ZOOMED_IN_SIZE.width/2), y: (ez.screenHeight/2) - (ZoomRenders.ZOOMED_IN_SIZE.height/2)), size: ZoomRenders.ZOOMED_IN_SIZE)   //TODO change it to let
    fileprivate let zoomedOutView: UIView
    
    fileprivate let initialView: UIView
    fileprivate let listeningView: UIView
    fileprivate lazy var transitionView: UIView = ZoomRenders.convertForTransition(self.nonMutableTransitioningView)
    private let nonMutableTransitioningView: UIView
    fileprivate var direction: ZoomDirection = .zoomIn
    
    var toSize: CGSize {
        return direction == .zoomIn ? ZoomRenders.ZOOMED_IN_SIZE : zoomedOutView.frame.size
    }
    
    var scale: CGFloat {
        return transitionView.w / (zoomedOutView.frame.w == 0 ? Constants.RenderZoom.minElementWidth : zoomedOutView.frame.w)
    }
    
    var finalScale: CGFloat {
        return toSize.width / (zoomedOutView.frame.w == 0 ? Constants.RenderZoom.minElementWidth : zoomedOutView.frame.w)
    }
    
    init(initialView: UIView, listeningView: UIView, transitionView: UIView, baseView: UIView, direction: ZoomDirection) {
        self.initialView = initialView
        self.zoomedOutView = baseView
        self.listeningView = listeningView
        self.nonMutableTransitioningView = transitionView
        self.direction = direction
    }
    
    func removeListeners() {
        listeningView.gestureRecognizers?.forEach { gr in
            listeningView.removeGestureRecognizer(gr)
        }
    }
    
    func startsZoomIn() {
        let _ = transitionView // Temporary to ensure lazy var is initiated before the zoom
        initialView.isHidden = true
    }
    
    func endsZoomIn() {
        removeListeners()
    }
    
    func endsZoomOut() {
        removeListeners()
        initialView.isHidden = false
    }
    
    private static func convertForTransition(_ view: UIView) -> UIView {
        if view.tag == REPLICA {
            view.frame = view.windowRelatedFrame
            return view
        } else {
            let replica = view.snapshotView(afterScreenUpdates: false)!
            let replicaContainer = ShadedView(frame: view.windowRelatedFrame)
            replicaContainer.clipsToBounds = false
            replica.frame = view.bounds
            replicaContainer.addSubview(replica)
            replicaContainer.tag = REPLICA
            return replicaContainer
        }
    }
    
    static func zoomOut(zoomInRenders: ZoomRenders, listeningView: UIView) -> ZoomRenders {
        guard zoomInRenders.direction == .zoomIn else {
            return zoomInRenders
        }
        let renders =  ZoomRenders(initialView: zoomInRenders.initialView, listeningView: listeningView, transitionView: zoomInRenders.transitionView, baseView: zoomInRenders.zoomedOutView, direction: .zoomOut)
        return renders
    }
}

class RenderZoomManager: UIPercentDrivenInteractiveTransition, UIGestureRecognizerDelegate {
    weak var fromViewController: UIViewController!    //it's weak in order to not create a cycle
    var toViewController: RenderZoomViewController!
    
    fileprivate var transitionContext: UIViewControllerContextTransitioning?
    fileprivate var renders: ZoomRenders!
    fileprivate var isPresenting: Bool = true
    fileprivate var shouldCompleteTransition: Bool = false
    fileprivate var completionThreshold: CGFloat { return isPresenting ? Constants.RenderZoom.zoomInThreshold : Constants.RenderZoom.zoomOutThreshold }
    fileprivate var isInteractive: Bool = true
    var onDismiss: (() -> Void)?
    
    fileprivate var isTransitioning = false
    
    init(from: UIViewController) {
        self.fromViewController = from
    }
    
    func zoomIn(fromView: UIView, actualFrameView: UIView? = nil, listeningView: UIView, transitionView: UIView) {
        isPresenting = true
        renders = ZoomRenders(initialView: fromView, listeningView: listeningView, transitionView: transitionView, baseView: actualFrameView ?? fromView, direction: .zoomIn)
        listen()
    }
    
    func zoomOut(listeningView: UIView) {
        isPresenting = false
        renders = ZoomRenders.zoomOut(zoomInRenders: renders, listeningView: listeningView)
        listen()
    }
    
    private func listen() {
        guard let renders = renders else {
            return
        }
        renders.removeListeners()
        
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinchGesture(gesture:)))
        pinch.delegate = self
        renders.listeningView.addGestureRecognizer(pinch)
        
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotationGesture(gesture:)))
        rotate.delegate = self
        renders.listeningView.addGestureRecognizer(rotate)
        
        let pan = UIPanGestureRecognizer(target:self, action: #selector(handlePanGesture(gesture:)))
        pan.delegate = self
        pan.minimumNumberOfTouches = 2
        renders.listeningView.addGestureRecognizer(pan)
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    @objc func handleRotationGesture(gesture: UIRotationGestureRecognizer) {  //it's @objc so it can be used in selector
        if isInteractive && isTransitioning {
            if gesture.state == .changed {
                renders.transitionView.transform = renders.transitionView.transform.rotated(by: gesture.rotation)
                gesture.rotation = 0
            }
        }
    }
    
    @objc func handlePanGesture(gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view, isInteractive, isTransitioning else {
            return
        }
        if gesture.state == .changed {
            let translation = gesture.translation(in: view)
            renders.transitionView.center = CGPoint(x:renders.transitionView.center.x + translation.x, y:renders.transitionView.center.y + translation.y)
            gesture.setTranslation(CGPoint.zero, in: view)
        }
    }
    
    @objc func handlePinchGesture(gesture: UIPinchGestureRecognizer) {
        switch (gesture.state) {
        case .began:
            self.isInteractive = true;
            if isPresenting {
                fromViewController.transitioningDelegate = self
                toViewController = RenderZoomViewController()
                toViewController.transitionManager = self
                toViewController.transitioningDelegate = self
                toViewController.modalPresentationStyle = .overCurrentContext
                renders.startsZoomIn()
                fromViewController.presentVC(self.toViewController)
            } else {
                toViewController.dismissVC(completion: nil)
            }
        case .changed:
            renders.transitionView.transform = renders.transitionView.transform.scaledBy(x: gesture.scale, y: gesture.scale)
            gesture.scale = 1.0
            
            let scale = renders.scale
            if isPresenting {
                shouldCompleteTransition = (scale > completionThreshold)
                let progress = scale < 2 ? scale - 1 : 1
                update(progress)
            } else {
                self.shouldCompleteTransition = (scale < completionThreshold)
                let progress = 1/scale > 1 ? 1 : 1/scale
                update(progress)
            }
        case .ended, .cancelled:
            let cancelAnimation = shouldCompleteTransition == false || gesture.state == .cancelled
            if cancelAnimation {
                cancel()
            } else {
                finish()
            }
            // calculate current scale of transitionView
            let delta = renders.finalScale - renders.scale
            var normalizedVelocity = gesture.velocity / (delta == 0 ? 0.1 : delta)
            
            normalizedVelocity = normalizedVelocity.clamped(to: -20...20)
            if abs(gesture.velocity) < 3 {
                normalizedVelocity = gesture.velocity
            }
            toViewController.gestureVelocity = normalizedVelocity
            
        default: ()
        }
    }
}

extension RenderZoomManager: UIViewControllerAnimatedTransitioning { 
    public func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return isInteractive ? 0.7 : 0.5
    }
    
    public func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        isTransitioning = true
        self.transitionContext = transitionContext
        renders.initialView.isHidden = true
        
        // make sure toViewController is layed out
        toViewController.view.frame = transitionContext.finalFrame(for: toViewController)
        toViewController.updateViewConstraints()
        
        let container = self.transitionContext!.containerView;
        
        // add toViewController to Transition Container
        if let view = toViewController.view {
            if isPresenting {
                container.addSubview(view)
            } else {
                container.insertSubview(view, belowSubview: fromViewController.view)
            }
        }
        toViewController.view.layoutIfNeeded()
        container.addSubview(renders.transitionView)
        if isPresenting {
            animateZoomInTransition()
        } else {
            animateZoomOutTransition()
        }
    }
    
    func animateZoomInTransition(){
        toViewController.bckgView.alpha = 0
        UIView.animate(withDuration: transitionDuration(using: transitionContext!), animations: { () -> Void in
            self.toViewController.bckgView.alpha = 0.8
        }) { _ -> Void in
            if self.transitionContext!.transitionWasCancelled {
                self.toViewController.view.removeFromSuperview()
                self.isPresenting = true
                self.renders.endsZoomOut()
                self.transitionContext!.completeTransition(false)
            } else {
                self.isPresenting = false
                self.renders.endsZoomIn()
                self.transitionContext!.completeTransition(true)
            }
            self.isTransitioning = false
        }
    }
    
    func animateZoomOutTransition(){
        self.renders.transitionView.animateTo(frame: ( isInteractive ? self.renders.transitionView.frame : self.renders.zoomedOutView.windowRelatedFrame ), withDuration: transitionDuration(using: transitionContext!), animations: {
            self.toViewController.view.alpha = 0
        }, completion: { _ in
            if self.transitionContext!.transitionWasCancelled { //Cancelled
                self.renders.endsZoomIn()
                self.isPresenting = false
                self.renders.direction = .zoomIn
                self.isTransitioning = false
                self.transitionContext!.completeTransition(false)
            } else { // Completed
                UIView.animate(withDuration: 0.2, animations: {
                    self.renders.transitionView.transform = CGAffineTransform.identity
                    self.renders.transitionView.frame = self.renders.zoomedOutView.windowRelatedFrame
                }) { _ in
                    self.toViewController.view.removeFromSuperview()
                    self.toViewController = nil
                    self.renders.endsZoomOut()
                    self.isPresenting = true
                    self.isTransitioning = false
                    self.transitionContext!.completeTransition(true)
                }
            }
        })
    }
}

extension RenderZoomManager: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        if presented is RenderZoomViewController {
            isPresenting = true
            return self
        }
        return nil
    }
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        if dismissed is RenderZoomViewController {
            isPresenting = false
            return self
        }
        return nil
    }
    
    func interactionControllerForPresentation(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        return self
    }
    
    func interactionControllerForDismissal(using animator: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        return isInteractive ? self : nil
    }
}

class RenderZoomViewController: UIViewController {
    fileprivate let bckgView = UIView.newAutoLayout()
    private let renderContainer: UIScrollView = UIScrollView(frame: CGRect(x: 0, y: (ez.screenHeight/2) - (ZoomRenders.ZOOMED_IN_SIZE.height/2), w: ez.screenWidth, h: ZoomRenders.ZOOMED_IN_SIZE.height))
    
    var gestureVelocity: CGFloat = 0
    var transitionManager: RenderZoomManager?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.clear
        bckgView.addTapGesture { [unowned self] _ in
            self.transitionManager?.isInteractive = false
            self.dismissVC(completion: nil)
        }
        view.addSubview(bckgView)
        bckgView.autoPinEdgesToSuperviewEdges()
        bckgView.backgroundColor = Color.WHITE
        
        renderContainer.contentSize = CGSize(width: ZoomRenders.ZOOMED_IN_SIZE.width + 30, height: ZoomRenders.ZOOMED_IN_SIZE.height)
        renderContainer.clipsToBounds = false
        renderContainer.showsVerticalScrollIndicator = false
        renderContainer.showsHorizontalScrollIndicator = false
        renderContainer.setContentOffset(CGPoint(x: (renderContainer.contentSize.width/2) - (renderContainer.bounds.size.width/2), y: 0), animated: false)
        view.addSubview(renderContainer)
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let renders = self.transitionManager?.renders {
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: gestureVelocity, options: UIViewAnimationOptions(), animations: {
                renders.transitionView.transform = CGAffineTransform.identity.scaledBy(x: renders.finalScale, y: renders.finalScale)
                renders.transitionView.frame = ZoomRenders.finalFrame
            }, completion: { _ in
                renders.transitionView.frame = CGRect(origin: CGPoint(x: 15, y: 0), size: ZoomRenders.ZOOMED_IN_SIZE)
                self.renderContainer.addSubview(renders.transitionView)
                self.transitionManager!.zoomOut(listeningView: renders.transitionView)
            })
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        transitionManager?.onDismiss?()
    }
}

struct Constants {
    struct RenderZoom {
        static let zoomInThreshold: CGFloat = 1.3
        static let zoomOutThreshold: CGFloat = 1.9
        static let minElementWidth: CGFloat = 0.1
    }
}

extension UIView {
    
    var windowRelatedFrame: CGRect {
        var superview = self.superview
        var frame = self.frame
        while superview != nil && superview?.superview != nil {
            let hiperview = superview!.superview!
            frame = superview!.convert(frame, to: hiperview)
            superview = hiperview
        }
        return frame
    }
}

class Color {
    //Brand Colors
    static let GOLD = UIColor(r: 168, g: 153, b: 110)
    static let BLUE = UIColor(r: 26, g: 53, b: 100)
    
    //Utility Colors
    static let WHITE = UIColor.white
    static let LIGHT_GOLD = UIColor(r:246, g:244, b:240)
    static let DARK_GREY = UIColor(r: 228, g: 228, b: 228)
    static let DARKER_GREY = UIColor(r: 119, g: 119 , b: 119)
    static let DARKER_GREY_07 = UIColor(r: 119, g: 119 , b: 119).withAlphaComponent(0.7)
    static let DARK_GREY_2 = UIColor(r: 151, g: 151, b: 151)
    static let BLACK = UIColor(r: 51, g: 51, b: 51)
    
    //Secondary Colors
    static let TEAL = UIColor(r:0, g: 127, b: 122)
    static let DARK_RED = UIColor(r: 111, g: 56, b: 38)
    static let PURPLE = UIColor(r: 125, g: 61, b: 99)
    static let BLUE_SEC = UIColor(r: 6, g: 86 , b: 144)
    static let TURQUOISE = UIColor(r: 32, g: 166, b: 193)
    static let RED = UIColor(r: 223, g: 66, b: 66)
    static let PEACH = UIColor(r: 230, g: 158, b: 115)
    
    //Styleguide pretendents
    static let NAVY = UIColor(r: 4, g: 25, b: 53)
    static let ORANGE = UIColor(r: 243, g: 165, b: 54)
    static let NAVY_BLUE = UIColor(r: 47, g: 85, b: 143)
    
    //Helpers
    static let SEPARATOR = Color.DARK_GREY
    static let GREY = UIColor(r: 153, g: 153, b: 153)
    static let LIGHT_GREY = UIColor(r: 216, g: 216, b: 216).withAlphaComponent(0.2)
    static let HIGHLIGHT_RED = UIColor(r: 158, g: 33, b: 31).withAlphaComponent(0.2)
    
    @available(*, deprecated: 1.0)
    static let NEPAL = UIColor(hexString: "#98AAC7")!
    @available(*, deprecated: 1.0)
    static let INDIGO = UIColor(hexString: "#5B7606")!
    @available(*, deprecated: 1.0)
    static let ALUMINUM = UIColor(hexString: "#9b9b9b")!
    
    static let GREEN = UIColor(r: 42, g: 205, b: 71)
    static let NOTIFICATION_GREEN = UIColor(r: 49, g: 164, b: 99)
    
    static let C249_249_249 = UIColor(r: 249, g: 249, b: 249)
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

extension UIView {
    
    func animateTo(frame: CGRect, withDuration duration: TimeInterval, animations: (() -> Void)?, completion: ((Bool) -> Void)? = nil) {
        guard let _ = superview else {
            return
        }
        
        let xScale = frame.size.width / max(self.frame.size.width, 1.0)
        let yScale = frame.size.height / max(self.frame.size.height, 1.0)
        let x = frame.origin.x + (self.frame.width * xScale) * self.layer.anchorPoint.x
        let y = frame.origin.y + (self.frame.height * yScale) * self.layer.anchorPoint.y
        
        UIView.animate(withDuration: duration, delay: 0, options: .curveLinear, animations: {
            self.layer.position = CGPoint(x: x, y: y)
            self.transform = self.transform.scaledBy(x: xScale, y: yScale)
            animations?()
        }, completion: completion)
    }
}
