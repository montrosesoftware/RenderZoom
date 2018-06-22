//
//  ViewController.swift
//  RenderZoom
//
//  Created by Filip Korski on 12/06/2018.
//  Copyright © 2018 Filip Korski. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    
    @IBOutlet weak var backView: UIView!
    
    private var zoomBack: RenderZoomManager?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.zoomBack = RenderZoomManager(from: self)
        self.zoomBack!.zoomIn(fromView: self.backView, listeningView: self.backView, transitionView: self.backView)
        self.zoomBack!.onDismiss = {
            self.zoomBack!.zoomIn(fromView: self.backView, listeningView: self.backView, transitionView: self.backView, finalFrame: self.backView.frame)
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    
}

