//
//  ViewController.swift
//  SwiftyUIDemo
//
//  Created by Haochen Wang on 10/5/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit
import SwiftyUI

class ViewController: UIViewController {

    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        let myView : UIView = UIView().addTo(view)
        myView.frame = CGRect.init(x: 50, y: 50, width: 100, height: 100)
        myView.backgroundColor = .black
        
        let myImage : UIImage? = UIImage.load("btnBG")
        let myImageView : SwiftyImageView = SwiftyImageView.load(myImage).addTo(view)
        myImageView.frame = CGRect.init(x: 50, y: 150 + 20, width: 100, height: 100)

        
        let myLable : SwiftyLabel = SwiftyLabel.load("Label", .white, .blue).addTo(view)
        myLable.frame = CGRect.init(x: 50, y: 300 + 20 + 20, width: 100, height: 100)

        let myBtn : SwiftyButton = SwiftyButton.load("Button", myImage, ClosureWrapper({ [weak self] (btn) in

            guard let strongSelf = self, let btn = btn else { return }
            print("BtnTaped")
            strongSelf.btnTappedSelector(btn)
        })).addTo(view)
        myBtn.frame = CGRect(x: 50, y: 450 + 20 + 20 + 20, width: 100, height: 100)
        myBtn.titleLabel.textColor = .white
    }
    
    func btnTappedSelector(_ sender: SwiftyButton)
    {
        print("btnTappedSelector")
    }
}

