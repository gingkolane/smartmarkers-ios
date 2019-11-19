TaskController
===========

Controller class that can be instantiated from either a `Request` conformant FHIR resource or an `Instrument` type with three main functions.

1. Controller handles `ResearchKit` user session for generating patient generated data producing an output FHIR `Bundle`.
2. `Controller.reports` holds historical FHIR resources generated as a response to the `Instrument` fetched from the FHIR `Server`, relying on the `Instrument` specified code and search parameters.
3. `Controller` enqueues newly generated FHIR output to be "ready" for submission. 


For a given `Instrument`

```swift
let instrument = Instruments.ActiveTasks.AmslerGrid.instrument

// Instantiate TaskController; An instance or type should hold onto the variable

self.controller = TaskController(instrument: instrument)

// prepare User Session Task Controller; powered by ResearchKit
controller.prepareSession() { taskViewController, error in 

    if let taskViewController = taskViewController { 
        self.present(taskViewController, animated: true, completion: nil)
    } 
    else { 
        // check error:
        print(error)
    } 
} 

// Session Completion; Note: Completion does not mean successful completion
controller.onSessionCompletion = { submissionBundle, error in 
    if let submissionBundle = submissionBundle { 
        // Output: FHIR Bundle 
        print(submissionBundle.bundle)
    } 
    else { 
        print(error)
    }
}
```

Multiple PGHD Sessions
----------------------------

An array of PDControllers can be passed onto `SessionController` to create a unified session for multiple back to back task. Also included is a `SubmissionsController`– a `ResearchKit` based `ORKTaskViewController` module to seek explicit permission before submitted the generated data to the `FHIR Server`.

Check [`SessionController`](sessioncontroller)

Also relevant: Protocols For Reference
--------------------------------------------

1. [Instrument](#): All types must conform to this protocol to be used by `TaskController`
2. [Request](#): FHIR Requests (eg. [ServiceRequest](#)) must conform to this protocol
3. [Report](#): Resulting FHIR resources (eg. [QuestionnaireResponse](#), etc) must conform to this protocol
