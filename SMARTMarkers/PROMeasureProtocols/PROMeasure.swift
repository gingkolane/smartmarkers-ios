//
//  PROMeasure.swift
//  EASIPRO
//
//  Created by Raheel Sayeed on 6/27/18.
//  Copyright © 2018 Boston Children's Hospital. All rights reserved.
//

import Foundation
import SMART
import ResearchKit


public protocol InstrumentResolver: class {
    
    func resolveInstrument(from pro: PROMeasure) -> Instrument?
}

public protocol PROMeasureProtocol : class {
    
    associatedtype RequestType

    var request: RequestType? { get set }
    
    var instrument: Instrument? { get set }
    
    func instrument(callback: @escaping ((_ instrument: Instrument?, _ error: Error?) -> Void))
 
    var server: Server? { get }
    
    var patient: Patient? { get set }
    
    func fetchReports(from server: Server, callback : ((_ success: Bool, _ error: Error?) -> Void)?)
    
    var sessionDelegate: SessionControllerTaskDelegate? { get set }
    
    func prepareSession(callback: @escaping ((ORKTaskViewController?, Error?) -> Void))
    
}

open class PROMeasure : NSObject, PROMeasureProtocol {
    
    public weak var instrumentResolver: InstrumentResolver?

    public typealias RequestType = RequestProtocol
    
    public var patient: Patient?
    
    public var request: RequestType?
    
    public var oauthSettings: [String:Any]? 
    
    public var instrument: Instrument? {
        didSet {
            reports = Reports(resultRelations: instrument?.ip_resultingFhirResourceType, patient, instrument: instrument, request: request)
        }
    }
    
    public var reports: Reports?
    
    public lazy var schedule: Schedule? = {
        return request?.rq_schedule
    }()
    
    public var teststatus: String = ""
    
    public weak var sessionDelegate: SessionControllerTaskDelegate?
    
    public weak var server: Server?
    
    public static var instrumentLibrary: [Instrument]?
    
    public var onSessionCompletion: ((_ reports: SMART.Bundle?, _ error: Error?) -> Void)?

    
    public var newReports: [SMART.Bundle]? {
        return reports?.newBundles
    }
    
    public convenience init(request: RequestProtocol) {
        self.init()
        self.request = request
    }
    
    
    
    open func instrument(callback: @escaping ((_ instrument: Instrument?, _ error: Error?) -> Void)) {
        
        if let instr = self.instrument {
            callback(instr, nil)
            return
        }
        
        if let instrumentResolver = instrumentResolver, let instr = instrumentResolver.resolveInstrument(from: self) {
            callback(instr, nil)
            return
        }
        
        request?.rq_instrumentResolve(callback: callback)
    }
    
    public convenience init(instrument: Instrument?) {
        self.init()
        self.instrument = instrument
        self.reports = Reports(resultRelations: instrument?.ip_resultingFhirResourceType, patient, instrument: instrument, request: request)


    }
    
    public override init() { }
    
    

    /// Class functions to build `PROMeasure`s
    public class func Fetch<T:DomainResource & RequestProtocol>(requestType: T.Type, server: Server, options: [String:String]? = nil, instrumentResolver: InstrumentResolver? = nil, callback: @escaping (([PROMeasure]? , Error?) -> Void)) {

        var searchParams =  T.rq_fetchParameters ?? [String:String]()
        
        if let options = options {
            for (k,v) in options {
                searchParams[k] = v
            }
        }
      
        T.Requests(from: server, options: searchParams) { (requests, error) in
            if let requests = requests {
                let proMeasures = requests.map({ (request) -> PROMeasure in
                    let pro = PROMeasure(request: request)
                    pro.instrumentResolver = instrumentResolver
                    return pro
                })
                callback(proMeasures, nil)
            }
            callback(nil, error)
        }
    }
    
    public class func Fetch<T:DomainResource & Instrument>(instrumentType: T.Type, server: Server, options: [String:String]? = nil, callback: @escaping (([PROMeasure]? , Error?) -> Void)) {
        
        T.Instruments(from: server, options: options) { (instruments, error) in
            if let instruments = instruments {
                let proMeasures = instruments.map { PROMeasure(instrument: $0) }
                callback(proMeasures, nil)
            }
            callback(nil, error)
        }
    }
    
    public func fetchReports(from server: Server, callback : ((_ success: Bool, _ error: Error?) -> Void)?) {
        
//        guard let srv = server else {
//            callback?(false, SMError.promeasureServerNotSet)
//            return
//        }
        
        guard let reports = reports else {
            
            callback?(false, SMError.promeasureFetchLinkedResources)
            return
        }
        
        reports.fetch(server: server, searchParams: nil) { (results, error) in
            callback?(results != nil, error)
        }
    }
    
    public func prepareSession(callback: @escaping ((ORKTaskViewController?, Error?) -> Void)) {
        
        guard let instrument = self.instrument else {
            callback(nil, SMError.promeasureOrderedInstrumentMissing)
            return
        }
        
        instrument.ip_taskController(for: self) { (taskViewController, error) in
            taskViewController?.delegate = self
            callback(taskViewController, error)
        }
    }


    public func updateRequest(_ _results: [ReportType]?, callback: @escaping ((_ success: Bool) -> Void)) {
        
        guard request != nil, let res = _results else {
            return
        }
        if let completed = schedule?.update(with: res.map{ $0.rp_date }) {
            request?.rq_updated(completed, callback:callback)
        }
    }
    
    
    
   
    
}




extension PROMeasure : ORKTaskViewControllerDelegate {
    
    public func dismiss(_ taskViewController: ORKTaskViewController) {
        
        taskViewController.navigationController?.popViewController(animated: true)
    }
    
    public func taskViewController(_ taskViewController: ORKTaskViewController, didFinishWith reason: ORKTaskViewControllerFinishReason, error serror: Error?) {
        
        // ***
        // Bug :Premature firing before conclusion step
        // ***
        let stepIdentifier = taskViewController.currentStepViewController!.step!.identifier
        if stepIdentifier.contains("range.of.motion") { return }
        // ***
        
        sessionDelegate?.sessionEnded(taskViewController, reason: reason, error: serror)

        
        if reason == .discarded {
            
            taskViewController.navigationController?.popViewController(animated: true)
            return
        }
        
        if reason == .failed {
            
            taskViewController.navigationController?.popViewController(animated: true)
            return
        }
        
        if reason == .completed {
            
            if let bundle = instrument?.ip_generateResponse(from: taskViewController.result, task: taskViewController.task!) {
                
                reports?.addNewReports(bundle)
                onSessionCompletion?(bundle, nil)
            }
            else {
                onSessionCompletion?(nil, SMError.instrumentResultBundleNotCreated)
            }
            taskViewController.navigationController?.popViewController(animated: true)
        }
        

        
        
        
        
        
        /*
        guard
            reason == .completed,
            let bundle = instrument?.ip_generateResponse(from: taskViewController.result, task: taskViewController.task!),
            let patient = patient,
            let server = server
            else
        {
            print("error: One or All of: No-patient/No-server/NotCompleted")
            self.taskDelegate?.sessionEnded(taskViewController, reason: reason, error: serror)
            taskViewController.navigationController?.popViewController(animated: true)
            return
        }
        
        let group = DispatchGroup()
        group.enter()
        results?.submitBundle(bundle, server: server, consent: true, patient: patient, request: request, callback: { [weak self] (submitted, error) in
            self?.updateRequest(self?.results!.reports, callback: { (updatedstatus) in
                if updatedstatus {
                    print("successfully updated status")
                }
                group.leave()
            })
        })
        
        group.notify(queue: .main) { [weak self] in
            self?.taskDelegate?.sessionEnded(taskViewController, reason: reason, error: nil)
            taskViewController.navigationController?.popViewController(animated: true)

        }
        */
    }
    
    public func taskViewController(_ taskViewController: ORKTaskViewController, recorder: ORKRecorder, didFailWithError error: Error) {
    }
    
    public func taskViewControllerShouldConfirmCancel(_ taskViewController: ORKTaskViewController) -> Bool {
        return true
    }
    
    open func taskViewController(_ taskViewController: ORKTaskViewController, shouldPresent step: ORKStep) -> Bool {
        return true
    }
    
    public func taskViewController(_ taskViewController: ORKTaskViewController, stepViewControllerWillAppear stepViewController: ORKStepViewController) {
        if stepViewController.title == nil {
            stepViewController.title = patient?.humanName ?? "Session #\(taskViewController.task!.identifier)"
        }
    }
    
    
    
}


open class PROController: PROMeasure {
    
    
}
