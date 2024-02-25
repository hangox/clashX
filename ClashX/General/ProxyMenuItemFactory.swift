//
//  ProxyMenuItemFactory.swift
//  ClashX
//
//  Created by CYC on 2018/8/4.
//  Copyright © 2018年 west2online. All rights reserved.
//

import Cocoa
import SwiftyJSON
import RxCocoa

class ProxyMenuItemFactory {
    static func menuItems(completionHandler:@escaping (([NSMenuItem])->())){
        ApiRequest.requestProxyGroupList { (res) in
            let dataDict = JSON(res)
            var menuItems = [NSMenuItem]()
            if (ConfigManager.shared.currentConfig?.mode == .direct) {
                completionHandler(menuItems)
                return
            }
            
            for proxyGroup in dataDict.dictionaryValue {
                var menu:NSMenuItem?
                switch proxyGroup.value["type"].stringValue {
                case "Selector": menu = self.generateSelectorMenuItem(proxyGroup: proxyGroup)
                case "URLTest": menu = self.generateUrlTestMenuItem(proxyGroup: proxyGroup)
                default: continue
                }
                if (menu != nil) {menuItems.append(menu!)}
                
            }
            completionHandler(menuItems.reversed())
        }
    }
    
    static func generateSelectorMenuItem(proxyGroup:(key: String, value: JSON))->NSMenuItem? {
        if (ConfigManager.shared.currentConfig?.mode == .global) {
            if proxyGroup.key != "GLOBAL" {return nil}
        } else {
            if proxyGroup.key == "GLOBAL" {return nil}
        }
        
        let menu = NSMenuItem(title: proxyGroup.key, action: nil, keyEquivalent: "")
        let selectedName = proxyGroup.value["now"].stringValue
        let submenu = NSMenu(title: proxyGroup.key)
        for proxy in proxyGroup.value["all"].arrayValue.reversed() {
            let proxyItem = NSMenuItem(title: proxy.stringValue, action: #selector(ProxyMenuItemFactory.actionSelectProxy(sender:)), keyEquivalent: "")
            proxyItem.target = ProxyMenuItemFactory.self
            proxyItem.state = proxy.stringValue == selectedName ? .on : .off
            submenu.addItem(proxyItem)
        }
        menu.submenu = submenu
        return menu
    }
    
    static func generateUrlTestMenuItem(proxyGroup:(key: String, value: JSON))->NSMenuItem? {
        
        let menu = NSMenuItem(title: proxyGroup.key, action: nil, keyEquivalent: "")
        let selectedName = proxyGroup.value["now"].stringValue
        let submenu = NSMenu(title: proxyGroup.key)

        let nowMenuItem = NSMenuItem(title: "now:\(selectedName)", action: nil, keyEquivalent: "")
        submenu.addItem(nowMenuItem)
        menu.submenu = submenu
        return menu
    }
    
    @objc static func actionSelectProxy(sender:NSMenuItem){
        guard let proxyGroup = sender.menu?.title else {return}
        let proxyName = sender.title
        
        ApiRequest.updateProxyGroup(group: proxyGroup, selectProxy: proxyName) { (success) in
            if (success) {
                for items in sender.menu?.items ?? [NSMenuItem]() {
                    items.state = .off
                }
                sender.state = .on
                // remember select proxy
                ConfigManager.selectedProxyMap[proxyGroup] = proxyName
            }
        }
    }
    
    
}
