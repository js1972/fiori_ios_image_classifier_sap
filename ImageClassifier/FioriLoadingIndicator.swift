//
// SAPFioriLoadingIndicator.swift
// Customer
//
// Created by SAP Cloud Platform SDK for iOS Assistant application on 17/11/17
//

import Foundation
import SAPFiori

protocol FioriLoadingIndicator: class {
    var loadingIndicator: FUILoadingIndicatorView? { get set }
}

extension FioriLoadingIndicator where Self: UIViewController {
    
    func showFioriLoadingIndicator(_ message: String = "") {
        OperationQueue.main.addOperation({
            let indicator = FUILoadingIndicatorView(frame: self.view.frame)
            indicator.text = message
            self.view.addSubview(indicator)
            indicator.show()
            self.loadingIndicator = indicator
        })
    }
    
    func hideFioriLoadingIndicator() {
        OperationQueue.main.addOperation({
            guard let loadingIndicator = self.loadingIndicator else {
                return
            }
            loadingIndicator.dismiss()
        })
    }
}

