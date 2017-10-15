//
//  ViewController.swift
//  iOSExample
//
//  Created by Haochen Wang on 10/6/17.
//  Copyright © 2017 Haochen Wang. All rights reserved.
//

import UIKit
import SwiftyUI

struct SimpleError: Error {
    
}


class ViewController: UIViewController
{

    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        let myView : SwiftyView = SwiftyView.load().addTo(view)
        myView.frame = CGRect(x: 50, y: 50, width: 100, height: 100)
        myView.backgroundColor = .black
        
        let myImage : UIImage? = UIImage.load("btnBG")
        let myImageView : SwiftyImageView = SwiftyImageView.load(myImage).addTo(view)
        myImageView.frame = CGRect(x: 50, y: 150 + 20, width: 100, height: 100)
        
        let myLable : SwiftyLabel = SwiftyLabel.load("Label", .white, .blue).addTo(view)
        myLable.frame = CGRect(x: 50, y: 300 + 20 + 20, width: 100, height: 100)
        
        let myBtn : SwiftyButton = SwiftyButton.load("Button", myImage, ClosureWrapper({ [weak self] (btn) in
            
            guard let strongSelf = self, let btn = btn else { return }
            print("BtnTaped")
            strongSelf.btnTappedSelector(btn)
        })).addTo(view)
        myBtn.frame = CGRect(x: 50, y: 450 + 20 + 20 + 20, width: 100, height: 100)
        myBtn.titleLabel.textColor = .white
        
        Timer.every(1.0, ClosureWrapper({ (timer) in
            print("Timer_every")
        })).start()
        
        Timer.after(5.0, ClosureWrapper({ (timer) in
            print("Timer_after")
        })).start()
        
        Promise.firstly(on: .background, ClosureThrowWrapper({
            
            for i in 1...5
            {
                print("Task1-------\(i)")
            }
            print("task1----Thread:\(Thread.current)")
            
        })).then(on: .main, ClosureThrowWrapper({
            
            for i in 1...5
            {
                print("Task2-------\(i)")
            }
            print("task2----Thread:\(Thread.current)")
            
        })).then(ClosureThrowWrapper({
            
            throw SimpleError()
            
        })).then(ClosureThrowWrapper({
            
            for i in 1...5
            {
                print("Task3-------\(i)")
            }
            print("task3----Thread:\(Thread.current)")
            
        })).always(ClosureThrowWrapper({
            
            for i in 1...5
            {
                print("TaskAlways-------\(i)")
            }
            print("taskAlways----Thread:\(Thread.current)")
            
        })).catch(ClosureWrapper({ (error) in
            
            print(String(describing: error))
            
        }))
    }
    
    func btnTappedSelector(_ sender: SwiftyButton)
    {
        print("btnTappedSelector")
    }
}

