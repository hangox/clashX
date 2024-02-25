//
//  ConfigFileFactory.swift
//  ClashX
//
//  Created by CYC on 2018/8/5.
//  Copyright © 2018年 west2online. All rights reserved.
//
import Foundation
import AppKit
import SwiftyJSON

class ConfigFileFactory {
    static func configFile(proxies:[ProxyServerModel]) -> String {
        var proxyStr = ""
        var proxyGroupStr = ""
        for proxy in proxies {
            let targetStr = "\(proxy.remark) = ss, \(proxy.serverHost), \(proxy.serverPort), \(proxy.method), \(proxy.password)\n"
            proxyStr.append(targetStr)
            proxyGroupStr.append("\(proxy.remark),")
        }
        let sampleConfig = NSData(contentsOfFile: Bundle.main.path(forResource: "sampleConfig", ofType: "ini")!)
        var sampleConfigStr = String(data: sampleConfig! as Data, encoding: .utf8)
        

        
        if proxies.count > 1 {
            let autoGroupStr = "ProxyAuto = url-test, \(proxyGroupStr), http://www.google.com/generate_204, 300"
            sampleConfigStr = sampleConfigStr?.replacingOccurrences(of: "{{ProxyAutoGroupPlaceHolder}}", with: autoGroupStr)
            proxyGroupStr.append("ProxyAuto,")
        } else {
            sampleConfigStr = sampleConfigStr?.replacingOccurrences(of: "{{ProxyAutoGroupPlaceHolder}}", with: "")
        }
        proxyGroupStr = String(proxyGroupStr.dropLast())

        sampleConfigStr = sampleConfigStr?.replacingOccurrences(of: "{{ProxyPlaceHolder}}", with: proxyStr)
        sampleConfigStr = sampleConfigStr?.replacingOccurrences(of: "{{ProxyGroupPlaceHolder}}", with: proxyGroupStr)

        return sampleConfigStr!
    }
    
    static func saveToClashConfigFile(str:String) {
        // save to ~/.config/clash/config.ini
        let path = (NSHomeDirectory() as NSString).appendingPathComponent("/.config/clash/config.ini")
        
        if (FileManager.default.fileExists(atPath: path)) {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        }
        try? str.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        NotificationCenter.default.post(Notification(name:kShouldUpDateConfig))
    }
    
    
    static func importConfigFile() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Choose Config Json File"
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true
        openPanel.becomeKey()
        let result = openPanel.runModal()
        guard (result.rawValue == NSFileHandlingPanelOKButton && (openPanel.url) != nil) else {
            NSUserNotificationCenter.default
                .post(title: "Import Server Profile failed!",
                      info: "Invalid config file!")
            return
        }
        let fileManager = FileManager.default
        let filePath:String = (openPanel.url?.path)!
        var profiles = [ProxyServerModel]()
        
        
        if fileManager.fileExists(atPath: filePath) &&
            filePath.hasSuffix("json") {
            if let data = fileManager.contents(atPath: filePath),
                let json = try? JSON(data: data) {
                let remarkSet = Set<String>()
                for item in json["configs"].arrayValue{
                    if let host = item["server"].string,
                        let method = item["method"].string,
                        let password = item["password"].string{
                        
                        let profile = ProxyServerModel()
                        profile.serverHost = host
                        profile.serverPort = String(item["server_port"].intValue)
                        profile.method = method
                        profile.password = password
                        profile.remark = item["remarks"].stringValue
                        if remarkSet.contains(profile.remark) {
                            profile.remark.append("Dup")
                        }
                        
                        if (profile.isValid()) {
                            profiles.append(profile)
                        }
                    }
                }
                
                if (profiles.count > 0) {
                    let configStr = self.configFile(proxies: profiles)
                    self.saveToClashConfigFile(str: configStr)
                    NSUserNotificationCenter
                        .default
                        .post(title: "Import Server Profile succeed!",
                              info: "Successful import \(profiles.count) items")
                } else {
                    NSUserNotificationCenter
                        .default
                        .post(title: "Import Server Profile Fail!",
                              info: "No proxies are imported")
                }
                

            }
        }
        
    }
}
