//
//  ClashConfig.swift
//  ClashX
//
//  Created by CYC on 2018/7/30.
//  Copyright © 2018年 west2online. All rights reserved.
//
import Foundation

enum ClashProxyMode: String,Codable {
    case rule = "Rule"
    case global = "Global"
    case direct = "Direct"
}

class ClashConfig:Codable {
    var port:Int
    var socketPort:Int
    var allowLan:Bool
    var mode:ClashProxyMode
    var logLevel:String
    
    private enum CodingKeys : String, CodingKey {
        case port, socketPort = "socket-port", allowLan = "allow-lan", mode, logLevel = "log-level"
    }
    
    static func fromData(_ data:Data)->ClashConfig{
        let decoder = JSONDecoder()
        let model = try? decoder.decode(ClashConfig.self, from: data)
        return model!
    }
    
    func copy() -> ClashConfig? {
        guard let data = try? JSONEncoder().encode(self) else {return nil}
        let copy = try? JSONDecoder().decode(ClashConfig.self, from: data)
        return copy
    }
}
