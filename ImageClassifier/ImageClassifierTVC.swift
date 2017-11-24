//
//  ImageClassifierTVC.swift
//  ImageClassifier
//
//  Created by Jason Scott on 24/11/17.
//  Copyright © 2017 Jason Scott. All rights reserved.
//

import Photos
import Foundation
import SAPFoundation
import SAPCommon
import SAPFiori


class ImageClassifierTVC: UITableViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate, FioriLoadingIndicator {

    var classifications: [NSDictionary] = [NSDictionary]( )
    let picker = UIImagePickerController()
    private let appDelegate = UIApplication.shared.delegate as! AppDelegate
    private let logger: Logger = Logger.shared(named: "ImageClassifierTVC")
    var loadingIndicator: FUILoadingIndicatorView?
    

    @IBAction func photoFromLibrary(_ sender: UIBarButtonItem) {
        picker.allowsEditing = false
        picker.sourceType = .photoLibrary
        picker.mediaTypes = UIImagePickerController.availableMediaTypes(for: .photoLibrary)!
        
        // to display as popover on ipad (as per apple style guide)
        picker.modalPresentationStyle = .popover
        picker.popoverPresentationController?.barButtonItem = sender
        
        present(picker, animated: true, completion: nil)
    }
    
    @IBAction func photoFromCamera(_ sender: Any) {
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.allowsEditing = false
            picker.sourceType = UIImagePickerControllerSourceType.camera
            picker.cameraCaptureMode = .photo
            picker.modalPresentationStyle = .fullScreen
            present(picker, animated: true, completion: nil)
        } else {
            noCamera()
        }
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        Logger.root.logLevel = LogLevel.info
        picker.delegate = self
        
        self.preferredContentSize = CGSize(width: 320, height: 480)
        
        tableView.estimatedRowHeight = 98
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.backgroundColor = UIColor.preferredFioriColor(forStyle: .backgroundBase)
        tableView.separatorStyle = .none
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let numRows = classifications.count
        
        if numRows == 0 {
            let noDataLabel: UILabel = UILabel(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width - 50, height: tableView.bounds.height))
            noDataLabel.text = "Select an image or take a photo"
            noDataLabel.textColor = UIColor.lightGray
            noDataLabel.textAlignment = .center
            tableView.backgroundView = noDataLabel
        } else {
            tableView.backgroundView = nil
        }
        
        return numRows
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = classifications[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "classificationCell", for: indexPath) as! FUIObjectTableViewCell
        
        cell.headlineText   = item.value(forKey: "label") as? String
        cell.footnoteText   = "Confidence: \(String(describing: Int(round(Double(((item.value(forKey: "score") as! NSNumber) as! Double) * 100))))) %"
        
        return cell
    }

    
    // MARK: - Delegates
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        var chosenImage = UIImage()
        var filename = "<unknown>"
        
        chosenImage = info[UIImagePickerControllerOriginalImage] as! UIImage
        
        if let asset = info[UIImagePickerControllerPHAsset] as? PHAsset {
            if let f = (asset.value(forKey: "filename")) as? String {
                filename = f
            }
        }
        
        
        // SAP API Hub doesn't allow images submitted over 1MB in size.
        // Resizing the image to a width of 600px should suffice.
        let resizedImage = chosenImage.resized(toWidth: 600.0)
        
        self.sendImage(image: resizedImage!, filename: "\(filename).jpg")
        
        dismiss(animated: true, completion: nil)
        
        self.tableView.reloadData()
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: true, completion: nil)
    }
    
    
    //MARK: - Private methods
    private func noCamera(){
        let alertVC = UIAlertController(
                title: "No Camera",
                message: "Sorry, this device has no camera",
                preferredStyle: .alert)
        
        let okAction = UIAlertAction(
                title: "OK",
                style:.default,
                handler: nil)
        
        alertVC.addAction(okAction)
        
        present(
            alertVC,
            animated: true,
            completion: nil)
    }
    
    /**
     Send image to classification API as 'multipart/form-data'. Get response as JSON.
     There is probably a nice library that can do this better.
    */
    private func sendImage(image: UIImage, filename: String) {
        self.showFioriLoadingIndicator()
        
        // add request headers
        let boundary = "Boundary-\(UUID().uuidString)"
        let headers = [
            "Accept": "application/json",
            "APIKey": "qnxqdvDr1b8l69Zr1GSpljmxFnHN4f5K",
            "Content-Type": "multipart/form-data; boundary=\(boundary)"
        ]
        
        var request = URLRequest(url: URL(string: "https://sandbox.api.sap.com/ml/imageclassifier/inference_sync")!,
                                 cachePolicy: .useProtocolCachePolicy,
                                 timeoutInterval: 10.0)
        
        //setting request method
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.httpBody = self.createBody(
            boundary: boundary,
            data: UIImageJPEGRepresentation(image, 0.8)!,
            mimeType: "image/jpg",
            filename: filename)
        
        let session = SAPURLSession()

        //sending request
        let dataTask = session.dataTask(with: request) { data, response, error in
            defer {
                self.hideFioriLoadingIndicator()
            }
            
            guard let data = data, error == nil else {
                // check for fundamental networking error
                print("Network error occured calling API!")
                print(error!)
                return
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as AnyObject?
                
                if let parseJSON = json {
                    self.logger.info("response :\(parseJSON)")
                    let rootKey = parseJSON.allKeys[0]
                    let dictArray = parseJSON[rootKey] as! [NSDictionary]
                    
                    // retrieve 'results' node from JSON and store results in classifications field
                    self.classifications = dictArray[0].value(forKey: "results") as! [NSDictionary]
                }
                
                DispatchQueue.main.async(execute: { () -> Void in
                    self.tableView.reloadData()
                })
            }
            catch let error as NSError {
                print("Error in response JSON processing!")
                self.logger.error("error : \(error)")
            }
        }
        
        dataTask.resume()
    }
    
    private func createBody(boundary: String, data: Data, mimeType: String, filename: String) -> Data {
        var body = Data()
        
        let boundaryPrefix = "--\(boundary)\r\n"
        
        body.append(Data(boundaryPrefix.utf8))
        body.append(Data("Content-Disposition: form-data; name=\"files\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
        body.append(Data("--".appending(boundary.appending("--")).utf8))
        
        return body as Data
    }
    
    
    
    /*
    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    */

    /*
    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Delete the row from the data source
            tableView.deleteRows(at: [indexPath], with: .fade)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }
    */

    /*
    // Override to support rearranging the table view.
    override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {

    }
    */

    /*
    // Override to support conditional rearranging of the table view.
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}


extension UIImage {
    func resized(toWidth width: CGFloat) -> UIImage? {
        let canvasSize = CGSize(width: width, height: CGFloat(ceil(width/size.width * size.height)))
        UIGraphicsBeginImageContextWithOptions(canvasSize, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: canvasSize))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

