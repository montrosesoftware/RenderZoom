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
    
    fileprivate let finalFrame: CGRect  //TODO: consider making it view
    fileprivate let zoomedOutView: UIView
    
    fileprivate let initialView: UIView
    fileprivate let listeningView: UIView
    fileprivate lazy var transitionView: UIView = ZoomRenders.convertForTransition(self.nonMutableTransitioningView)
    private let nonMutableTransitioningView: UIView
    fileprivate var direction: ZoomDirection = .zoomIn
    
    var toSize: CGSize {
        return direction == .zoomIn ? finalFrame.size : zoomedOutView.frame.size
    }
    
    var scale: CGFloat {
        return transitionView.w / (zoomedOutView.frame.w == 0 ? Constants.RenderZoom.minElementWidth : zoomedOutView.frame.w)
    }
    
    var finalScale: CGFloat {
        return toSize.width / (zoomedOutView.frame.w == 0 ? Constants.RenderZoom.minElementWidth : zoomedOutView.frame.w)
    }
    
    init(initialView: UIView, listeningView: UIView, transitionView: UIView, baseView: UIView, finalFrame: CGRect, direction: ZoomDirection) {
        self.initialView = initialView
        self.zoomedOutView = baseView
        self.listeningView = listeningView
        self.nonMutableTransitioningView = transitionView   //TODO consider renaming transitionView to nonMutableTransitioningView
        self.finalFrame = finalFrame
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
            let replicaContainer = UIView(frame: view.windowRelatedFrame)   //TODO make it settable
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
        let renders =  ZoomRenders(initialView: zoomInRenders.initialView, listeningView: listeningView, transitionView: zoomInRenders.transitionView, baseView: zoomInRenders.zoomedOutView, finalFrame: zoomInRenders.finalFrame, direction: .zoomOut)
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
    
    func zoomIn(view: UIView) {
        zoomIn(fromView: view, listeningView: view, transitionView: view)
    }
    
    func zoomIn(fromView: UIView, actualFrameView: UIView? = nil, listeningView: UIView, transitionView: UIView, finalFrame: CGRect = UIScreen.main.bounds) {  //TODO move actualFrameView: to the end
        isPresenting = true
        renders = ZoomRenders(initialView: fromView, listeningView: listeningView, transitionView: transitionView, baseView: actualFrameView ?? fromView, finalFrame: finalFrame, direction: .zoomIn)
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
        guard isInteractive, isTransitioning else {
            return
        }
        if gesture.state == .changed {
            renders.transitionView.transform = renders.transitionView.transform.rotated(by: gesture.rotation)
            gesture.rotation = 0
        }
    }
    
    @objc func handlePanGesture(gesture: UIPanGestureRecognizer) {
        guard let view = gesture.view, isInteractive, isTransitioning else {
            return
        }
        if gesture.state == .changed {
            let translation = gesture.translation(in: view)
            renders.transitionView.center = CGPoint(x:renders.transitionView.center.x + translation.x, y:renders.transitionView.center.y + translation.y)
            gesture.setTranslation(CGPoint.zero, in: view)      //TODO: simplyfi code related to CG
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
                print("cancel")
                cancel()
            } else {
                print("finish")
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
        self.transitionContext = transitionContext  //are we sure that is not nil
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
                //treshold was not achieved, view goes back to the normal size
                self.toViewController.view.removeFromSuperview()
                self.isPresenting = true
                self.renders.endsZoomOut()
                self.transitionContext!.completeTransition(false)
            } else {
                //treshold was achieved, zoomed in view is presented
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
        return animationController(viewController: presented, isPresenting: true)
    }
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return animationController(viewController: dismissed, isPresenting: false)
    }
    
    func animationController(viewController: UIViewController, isPresenting: Bool) -> UIViewControllerAnimatedTransitioning? {
        if viewController is RenderZoomViewController {
            self.isPresenting = isPresenting
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

open class RenderZoomViewController: UIViewController {  //this is open in order to give a possibility to subclass it TODO: discuss if it's fine
    fileprivate let bckgView = UIView.newAutoLayout()
    
    var gestureVelocity: CGFloat = 0
    var transitionManager: RenderZoomManager?
    
    var renderContainer: UIScrollView?
    
    open func calculateRenderContainer() {   //this is to make it configurable TODO ask Swift expert how to do it better
        guard let renders = self.transitionManager?.renders else {
            return
        }
        
        let rc = UIScrollView(frame: CGRect(x: 0, y: (ez.screenHeight/2) - (renders.finalFrame.size.height/2), w: ez.screenWidth, h: renders.finalFrame.size.height))
        rc.contentSize = CGSize(width: renders.finalFrame.size.width + 30, height: renders.finalFrame.size.height)  //30 is to give a vertical bounce TODO move it to a const
        rc.clipsToBounds = false
        rc.showsVerticalScrollIndicator = false
        rc.showsHorizontalScrollIndicator = false
        rc.setContentOffset(CGPoint(x: (rc.contentSize.width/2) - (rc.bounds.size.width/2), y: 0), animated: false)
        renderContainer = rc
    }
    
    override open func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.clear
        bckgView.addTapGesture { [unowned self] _ in
            self.transitionManager?.isInteractive = false
            self.dismissVC(completion: nil)
        }
        view.addSubview(bckgView)
        bckgView.autoPinEdgesToSuperviewEdges()
        bckgView.backgroundColor = UIColor.white
        
        calculateRenderContainer()
        view.addSubview(renderContainer!)
    }
    
    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if let renders = self.transitionManager?.renders {
            let verticalOffset = self.calculateVerticalOffset(forFrame: renders.initialView.frame, insideFrame: renders.finalFrame, scale: renders.finalScale)//TODO: change this initial view
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: gestureVelocity, options: UIViewAnimationOptions(), animations: {
                renders.transitionView.transform = CGAffineTransform.identity.scaledBy(x: renders.finalScale, y: renders.finalScale)
                renders.transitionView.frame = renders.finalFrame
            }, completion: { _ in
                renders.transitionView.frame = CGRect(origin: CGPoint(x: 15, y: verticalOffset), size: renders.finalFrame.size)
                self.renderContainer!.addSubview(renders.transitionView)
                self.transitionManager!.zoomOut(listeningView: renders.transitionView)
            })
        }
    }
    
    func calculateVerticalOffset(forFrame innerFrame: CGRect, insideFrame outterFrame: CGRect, scale: CGFloat ) -> Int {
        return Int((outterFrame.size.height - (innerFrame.size.height * scale)) / 2)
    }
    
    override open func viewDidDisappear(_ animated: Bool) {
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

