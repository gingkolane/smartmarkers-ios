//
//  InstrumentFactory.swift
//  EASIPRO
//
//  Created by Raheel Sayeed on 3/15/19.
//  Copyright © 2019 Boston Children's Hospital. All rights reserved.
//

import Foundation


public class Instruments {
    
    public static func OMRONBloodPressure(settings: [String:Any]) -> Instrument? {
        
        let omron = OMRON(authSettings: settings)
        return omron
    }
    
    public static var AmslerGrid: Instrument {
        return AmslerGridPRO()
    }
    
    public static var HolePegTestPRO: Instrument {
        return NineHolePegTestPRO()
    }
    
    public static var PASATPRO: Instrument {
        return PSATPRO()
    }
    
    public static var LeftKneeRangeOfMotion: Instrument {
        return SMARTMarkers.KneeRangeOfMotion(limbOption: .left)
    }
    
    public static var RightKneeRangeOfMotion: Instrument {
        return SMARTMarkers.KneeRangeOfMotion(limbOption: .right)
    }
    
    public static var LeftShoulderRangeOfMotion: Instrument {
        return SMARTMarkers.ShoulderRangeOfMotion(limbOption: .left)
    }
    
    public static var RightShoulderRangeOfMotion: Instrument {
        return SMARTMarkers.ShoulderRangeOfMotion(limbOption: .right)
    }
    
    public static var SpatialSpanMemory: Instrument {
        return SpatialSpanMemoryPRO()
    }
    
    public static var iOSHealthRecords: Instrument {
        return SMHealthKitRecords()
    }
    
}

