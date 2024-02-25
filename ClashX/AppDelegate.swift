//
//  AppDelegate.swift
//  ClashX
//
//  Created by 称一称 on 2018/6/10.
//  Copyright © 2018年 west2online. All rights reserved.
//

import Cocoa
import LetsMove
import Alamofire
import RxCocoa
import RxSwift

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!

    @IBOutlet weak var statusMenu: NSMenu!
    @IBOutlet weak var proxySettingMenuItem: NSMenuItem!
    @IBOutlet weak var autoStartMenuItem: NSMenuItem!
    
    @IBOutlet weak var proxyModeGlobalMenuItem: NSMenuItem!    
    @IBOutlet weak var proxyModeDirectMenuItem: NSMenuItem!
    @IBOutlet weak var proxyModeRuleMenuItem: NSMenuItem!
    
    @IBOutlet weak var proxyModeMenuItem: NSMenuItem!
    @IBOutlet weak var showNetSpeedIndicatorMenuItem: NSMenuItem!
    @IBOutlet weak var separatorLineTop: NSMenuItem!
    @IBOutlet weak var sepatatorLineEndProxySelect: NSMenuItem!
    
    var disposeBag = DisposeBag()
    let ssQueue = DispatchQueue(label: "com.w2fzu.ssqueue", attributes: .concurrent)
    var statusItemView:StatusItemView!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        signal(SIGPIPE, SIG_IGN)
        fail_launch_protect()
        _ = ProxyConfigManager.install()
        PFMoveToApplicationsFolderIfNecessary()
        self.startProxy()
        statusItemView = StatusItemView.create(statusItem: nil,statusMenu: statusMenu)
        statusItemView.onPopUpMenuAction = {
            [weak self] in
            guard let `self` = self else {return}
            self.syncConfig() {
                self.updateProxyList()
            }
        }
        setupData()
    }
    

    func applicationWillTerminate(_ aNotification: Notification) {
        if ConfigManager.shared.proxyPortAutoSet {
            _ = ProxyConfigManager.setUpSystemProxy(port: nil,socksPort: nil)
        }
    }

    func setupData() {
        NotificationCenter.default.rx.notification(kShouldUpDateConfig).bind {
            [unowned self] (note)  in
            self.syncConfig(){
                self.resetStreamApi()
            }
            }.disposed(by: disposeBag)
        
        
        ConfigManager.shared
            .showNetSpeedIndicatorObservable
            .bind {[unowned self] (show) in
                self.showNetSpeedIndicatorMenuItem.state = (show ?? true) ? .on : .off
                self.statusItem = NSStatusBar.system.statusItem(withLength: (show ?? true) ? 65 : 25)
                self.statusItem.view = self.statusItemView
                self.statusItemView.showSpeedContainer(show: (show ?? true))
                self.statusItemView.statusItem = self.statusItem
            }.disposed(by: disposeBag)
        
        ConfigManager.shared
            .proxyPortAutoSetObservable
            .distinctUntilChanged()
            .bind{ [unowned self]
                en in
                let enable = en ?? false
                self.proxySettingMenuItem.state = enable ? .on : .off
            }.disposed(by: disposeBag)
        
        ConfigManager.shared
            .currentConfigVariable
            .asObservable()
            .filter{$0 != nil}
            .bind {[unowned self] (config) in
                self.proxyModeDirectMenuItem.state = .off
                self.proxyModeGlobalMenuItem.state = .off
                self.proxyModeRuleMenuItem.state = .off
                
                switch config!.mode {
                case .direct:self.proxyModeDirectMenuItem.state = .on
                case .global:self.proxyModeGlobalMenuItem.state = .on
                case .rule:self.proxyModeRuleMenuItem.state = .on
                }
                
                self.sepatatorLineEndProxySelect.isHidden = (config!.mode == .direct)
                
                self.proxyModeMenuItem.title = "Proxy Mode (\(config!.mode.rawValue))"
                
                self.updateProxyList()
                
                if (ConfigManager.shared.proxyPortAutoSet) {
                    _ = ProxyConfigManager.setUpSystemProxy(port: config!.port,socksPort: config!.socketPort)
                }
        }.disposed(by: disposeBag)
        
        LaunchAtLogin.shared
            .isEnableVirable
            .asObservable()
            .subscribe(onNext: { (enable) in
                self.autoStartMenuItem.state = enable ? .on : .off
            }).disposed(by: disposeBag)
        
  
    }
    
    func fail_launch_protect(){
        let x = UserDefaults.standard
        var launch_fail_times:Int = 0
        if let xx = x.object(forKey: "launch_fail_times") as? Int {launch_fail_times = xx }
        launch_fail_times += 1
        x.set(launch_fail_times, forKey: "launch_fail_times")
        if launch_fail_times > 3{
            //发生连续崩溃
            let path = (NSHomeDirectory() as NSString).appendingPathComponent("/.config/clash/")
            let documentDirectory = URL(fileURLWithPath: path)
            let originPath = documentDirectory.appendingPathComponent("config.ini")
            let destinationPath = documentDirectory.appendingPathComponent("config.ini.bak")
            try? FileManager.default.moveItem(at: originPath, to: destinationPath)
            try? FileManager.default.removeItem(at: documentDirectory.appendingPathComponent("Country.mmdb"))
            NSUserNotificationCenter.default.post(title: "Fail on launch protect", info: "You origin Config has been rename to config.ini.bak")

        }
        DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + Double(Int64(1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC), execute: {
            x.set(0, forKey: "launch_fail_times")
        });
    }
    
    func selectProxyGroupWithMemory(){
        for item in ConfigManager.selectedProxyMap {
            ApiRequest.updateProxyGroup(group: item.key, selectProxy: item.value) { (success) in
                if (!success) {
                    ConfigManager.selectedProxyMap[item.key] = nil
                }
            }
        }
    }
    
    func updateProxyList() {
        ProxyMenuItemFactory.menuItems { [unowned self] (menus) in
            let startIndex = self.statusMenu.items.index(of: self.separatorLineTop)! + 1
            let endIndex = self.statusMenu.items.index(of: self.sepatatorLineEndProxySelect)! - 1
            var items = self.statusMenu.items

            items.removeSubrange(ClosedRange(uncheckedBounds: (lower: startIndex, upper: endIndex)))
            
            for each in menus {
                items.insert(each, at: startIndex)
            }
            self.statusMenu.removeAllItems()
            for each in items.reversed() {
                self.statusMenu.insertItem(each, at: 0)
            }
        }
    }
    
    
    func startProxy() {
        ssQueue.async {
            run()
        }
        syncConfig(){
            self.selectProxyGroupWithMemory()
            DispatchQueue.main.asyncAfter(deadline:DispatchTime.now() + 1, execute: {
                self.resetStreamApi()
            })
        }
    }
    
    func syncConfig(completeHandler:(()->())?=nil){
        ApiRequest.requestConfig{ (config) in
            guard config.port > 0 else {return}
            ConfigManager.shared.currentConfig = config
            completeHandler?()
        }
    }
    
    func resetStreamApi() {
        ApiRequest.shared.requestTrafficInfo(){ [weak self] up,down in
            guard let `self` = self else {return}
            ((self.statusItem.view) as! StatusItemView).updateSpeedLabel(up: up, down: down)
        }
        
        ApiRequest.shared.requestLog { (type, msg) in
            Logger.log(msg: msg)
        }
    }

    
//Actions:
    
    @IBAction func actionQuit(_ sender: Any) {
        NSApplication.shared.terminate(self)
    }
        
    @IBAction func actionSetSystemProxy(_ sender: Any) {
        ConfigManager.shared.proxyPortAutoSet = !ConfigManager.shared.proxyPortAutoSet
        if ConfigManager.shared.proxyPortAutoSet {
            let port = ConfigManager.shared.currentConfig?.port ?? 0
            let socketPort = ConfigManager.shared.currentConfig?.socketPort ?? 0
            _ = ProxyConfigManager.setUpSystemProxy(port: port,socksPort:socketPort)
        } else {
            _ = ProxyConfigManager.setUpSystemProxy(port: nil,socksPort: nil)
        }

    }
    
    @IBAction func actionCopyExportCommand(_ sender: Any) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let port = ConfigManager.shared.currentConfig?.port ?? 0
        pasteboard.setString("export https_proxy=http://127.0.0.1:\(port);export http_proxy=http://127.0.0.1:\(port)", forType: .string)
    }
    
    @IBAction func actionStartAtLogin(_ sender: NSMenuItem) {
        LaunchAtLogin.shared.isEnabled = !LaunchAtLogin.shared.isEnabled
    }
    
    var genConfigWindow:NSWindowController?=nil
    @IBAction func actionGenConfig(_ sender: Any) {
//        let ctrl = NSStoryboard(name: NSStoryboard.Name(rawValue: "Main"), bundle: nil)
//            .instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "sampleConfigGenerator")) as! NSWindowController
        let ctrl = PreferencesWindowController(windowNibName: NSNib.Name(rawValue: "PreferencesWindowController"))
        
        
        genConfigWindow?.close()
        genConfigWindow=ctrl
        ctrl.window?.title = ctrl.contentViewController?.title ?? ""
        ctrl.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        ctrl.window?.makeKeyAndOrderFront(self)

    }
    
    @IBAction func openConfigFolder(_ sender: Any) {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent("/.config/clash/config.ini")
        NSWorkspace.shared.openFile(path)
    }
    
    @IBAction func actionUpdateConfig(_ sender: Any) {
        ApiRequest.requestConfigUpdate() { [unowned self] success in
            if (success) {
                self.syncConfig(){self.resetStreamApi()}
                NSUserNotificationCenter
                    .default
                    .post(title: "Reload Config Succeed", info: "succees")
            } else {
                NSUserNotificationCenter
                    .default
                    .post(title: "Reload Config Fail", info: "Please Check Config Fils")
            }
            
        }
    }
    
    @IBAction func actionImportBunchJsonFile(_ sender: NSMenuItem) {
        ConfigFileFactory.importConfigFile()
    }
    @IBAction func actionSwitchProxyMode(_ sender: NSMenuItem) {
        let mode:ClashProxyMode
        switch sender {
        case proxyModeGlobalMenuItem:
            mode = .global
        case proxyModeDirectMenuItem:
            mode = .direct
        case proxyModeRuleMenuItem:
            mode = .rule
        default:
            return
        }
        let config = ConfigManager.shared.currentConfig?.copy()
        config?.mode = mode
        ApiRequest.requestUpdateConfig(newConfig: config) { (success) in
            if (success) {
                ConfigManager.shared.currentConfig = config
            }
        }
        
    }
    
    @IBAction func actionShowNetSpeedIndicator(_ sender: NSMenuItem) {
        ConfigManager.shared.showNetSpeedIndicator = !ConfigManager.shared.showNetSpeedIndicator
    }
    
    @IBAction func actionShowLog(_ sender: Any) {
        NSWorkspace.shared.openFile(Logger.shared.logFilePath())

    }
}


