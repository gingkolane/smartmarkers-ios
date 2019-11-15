//
//  PROMeasure.swift
//  SMARTMarkers
//
//  Created by Raheel Sayeed on 6/27/18.
//  Copyright © 2018 Boston Children's Hospital. All rights reserved.
//

import Foundation
import SMART
import ResearchKit

/**
Instrument resolving delegate protocol

Optional instrument resolving delegate for `PDController`. Delegates can construct a custom `Instrument` for a given `PDController`.  
*/
public protocol InstrumentResolver: class {
   
    /// Optional: Create an `Instrument` compliant task from the `PDController`
    func resolveInstrument(in controller: PDController) -> Instrument?
    
}

/** 
PDController is the central class for managing PGHD

Each controller class can read a FHIR `Request` resource, resolve the embedded reference to its `Instrument` and fetch historical `Reports` from the `Server. Through the `Instrument` protocol, it also manages `ResearchKit` based task controllers for FHIR `Questionnaire`, `AdaptiveQuestionnaire`, active tasks, web fetches and other digital data
*/
public final class PDController: NSObject {
    
    /// `Request` protocol conformant FHIR resource. If present, instrument is resolved from the request. See `Request.swift`
    public var request: Request?
   
    /// PGHD Instrument 
    public var instrument: Instrument? {
        didSet {
            if instrument != nil {
                reports = Reports(instrument!, for: nil, request: request)
            }
        }
    }
   
    /// `Reports` holds all historial FHIR resources and the newly generated FHIR `Bundle(s)` after a user session. See `Reports.swift`
    public internal(set) final var reports: Reports?
   
    /// Optional: External resolver for the instrument. 
    public weak var instrumentResolver: InstrumentResolver?
   
    /// Callback; called when a PGHD user session is completed
    public var onSessionCompletion: ((_ submissionBundle: SubmissionBundle?, _ error: Error?) -> Void)?
   
    /// Schedule referenced from the receiver's request
    public lazy var schedule: Schedule? = {
        return request?.rq_schedule
    }()
   
    /**
    Initializer
    
    - parameter instrument: `Instrument` conformant class. Check `InstrumentFactory.swift` for a list of supported types out of the box.
    */
    convenience public init(instrument: Instrument) {
        self.init()
        self.instrument = instrument
        self.reports = Reports(instrument, for: nil, request: request)
    }
   
    /**
    Initializer

    - parameter request: `Request` conformant FHIR resource. 
    */
    convenience public init(_ _request: Request) {
        
        self.init()
        self.request = _request
    }

    /**
    Creates and holds `ResearchKit` based `ORKTaskViewController`. Depends on the resolved `Instrument` to pass on its task

    - parameter callback: Callback called after attempting to create a view controller for task session. 
    */
    public func prepareSession(callback: @escaping ((ORKTaskViewController?, Error?) -> Void)) {
        
        guard let instrument = self.instrument else {
            callback(nil, SMError.promeasureOrderedInstrumentMissing)
            return
        }
        
        instrument.sm_taskController { (taskViewController, error) in
            taskViewController?.delegate = self
            callback(taskViewController, error)
        }
    }
   

    /**
    Method for the receiver to resolve instrument embedded in the receiver's request or rely on an external delegate

    - parameter callback: Called when attempt to resolve is complete. Returns `SMError` when instrument is missing
    */
    public func instrument(callback: @escaping ((_ instrument: Instrument?, _ error: Error?) -> Void)) {
        
        if let instr = self.instrument {
            callback(instr, nil)
            return
        }
        
        if let resolver = instrumentResolver, let instr = resolver.resolveInstrument(in: self) {
            callback(instr, nil)
            return
        }

        request?.rq_instrumentResolve(callback: callback)
    }
   
    /// Method to update status and the request if necessary
    public func updateRequest(_ _results: [Report]?, callback: @escaping ((_ success: Bool) -> Void)) {
        
        guard request != nil, let res = _results else {
            return
        }
        
        if let completed = schedule?.update(with: res.map{ $0.rp_date }) {
            request?.rq_updated(completed, callback:callback)
        }
    }
    
    // MARK: – Fetch Requests
   
    /**
    Constructor class method for fetching and creating PDController objects from the FHIR server.

    Creates an array of PDController fetched from the FHIR server. Also resolves instrument and fetches historical reports specific to the request and instrument.

    - parameter requestType:        FHIR `Request` conformant resource type to fetch
    - parameter for:                FHIR `Patient` resource to which the requests were dispatched
    - parameter server:             FHIR `Server` to query for the requests
    - parameter instrumentResolver: Optional, delegate to assign an external class to resolve instrument from the request
    - parameter options:            Optional, search parameter options for request FHIR resources
    - parameter callback:           An array of PDController objects
    */
    public class func Get<T: DomainResource & Request>(requestType: T.Type, for patient: Patient, server: Server, instrumentResolver: InstrumentResolver?, options: [String: String]? = nil, callback: @escaping ([PDController]?, Error?) -> Void) {
        
        var searchParams =  T.rq_fetchParameters ?? [String:String]()
        searchParams["subject"] = patient.id!.string
        
        if let options = options {
            for (k,v) in options {
                searchParams[k] = v
            }
        }
        
        T.Requests(from: server, options: searchParams) { (requests, error) in
            if let requests = requests {
                let controllers = requests.map({ (request) -> PDController in
                    let controller = PDController(request)
                    controller.instrumentResolver = instrumentResolver
                    return controller
                })
                
                let group = DispatchGroup()
                for i in 0..<controllers.count {
                    let controller = controllers[i]

                    group.enter()
                    controller.instrument(callback: { (instr, error) in
                        controller.instrument = instr
                        group.leave()
                    })
                    
                    
                    group.enter()
                    controller.reports(for: patient, server: server, callback: { (_, _) in
                        group.leave()
                    })
                }

                group.notify(queue: DispatchQueue.global(qos: .background)) {
                    callback(controllers, nil)
                }

            }
            else {
                callback(nil, error)
            }
        }
    }
    
    // MARK: Report Collection
   
    /**
    Fetches historical reports (FHIR resources) based on the receiver's instrument and request

    - parameter for:        FHIR `Patient` resource
    - parameter server:     FHIR `Server` to query for the reports
    - parameter callback:   Callback with a Boolean to indicate fetch success or failure
    */
    public func reports(for patient: Patient, server: Server, callback : ((_ success: Bool, _ error: Error?) -> Void)?) {
        
        guard let reports = reports else {
            callback?(false, SMError.promeasureFetchLinkedResources)
            return
        }
        
        
        reports.fetch(for: patient, server: server, searchParams: nil) { (results, error) in
            callback?(results != nil, error)
        }
    }
    

    

}


/// Extension for PDController's ResearchKit session delegation
extension PDController: ORKTaskViewControllerDelegate {
   
    /// Custom dismissal method. Checks if task controller is within a session controller or standalonen
    func dismiss(taskViewController: ORKTaskViewController) {
        
        if let navigationController = taskViewController.navigationController {
            if navigationController.viewControllers.count > 1 {
                navigationController.popViewController(animated: true)
            }
        }
        else {
            taskViewController.dismiss(animated: true, completion: nil)
        }
    }
   
    // MARK: Report Generation

    // After each task session, the controller generates `SubmissionBundle` holding a FHIR `Bundle` to be sent to the FHIR server. See `Instrument.sm_generateResponse(from:task:)` for more info.
    public func taskViewController(_ taskViewController: ORKTaskViewController, didFinishWith reason: ORKTaskViewControllerFinishReason, error: Error?) {
        
        // ***
        // Bug :Premature firing before conclusion step
        // ***
        let stepIdentifier = taskViewController.currentStepViewController!.step!.identifier
        if stepIdentifier.contains("range.of.motion") { return }
        // ***
        
        if reason == .discarded, reason == .failed  {

        }
        
        if reason == .completed {
            
            if let bundle = instrument?.sm_generateResponse(from: taskViewController.result, task: taskViewController.task!) {
                let gr = reports?.addNewReports(bundle, taskId: taskViewController.taskRunUUID.uuidString)
                onSessionCompletion?(gr, nil)
            }
            else {
                onSessionCompletion?(nil, SMError.instrumentResultBundleNotCreated)
            }
        }
        
        dismiss(taskViewController: taskViewController)
    }
}
