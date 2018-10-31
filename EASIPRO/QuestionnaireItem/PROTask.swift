//
//  File.swift
//  EASIPRO
//
//  Created by Raheel Sayeed on 7/7/18.
//  Copyright © 2018 Boston Children's Hospital. All rights reserved.
//

import Foundation
import ResearchKit


public protocol RKTaskViewControllerProtocol where Self : ORKTaskViewController {
    var measure: (PROMeasure)? { get set }
}

public class PROTask : ORKNavigableOrderedTask {
    
    public weak var measure: (PROMeasure)?
    
    public override init(identifier: String, steps: [ORKStep]?) {
        super.init(identifier: identifier, steps: steps)
       
        
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

public class PROTaskViewController : ORKTaskViewController, RKTaskViewControllerProtocol {
    
    public weak var measure: PROMeasure?
    
}




