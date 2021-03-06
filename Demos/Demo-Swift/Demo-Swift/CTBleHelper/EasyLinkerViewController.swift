//
//  EasyLinkerViewController.swift
//  Demo-Swift
//
//  Created by 胡文峰 on 2019/1/12.
//  Copyright © 2019 XIAOFUTECH. All rights reserved.
//

import Foundation

class EasyLinkerViewController: UIViewController {

    var startScan: UIButton = UIButton()
    var stopScan: UIButton = UIButton()
    var startBind: UIButton = UIButton()
    var disConnect: UIButton = UIButton()
    var getInfo: UIButton = UIButton()
    var autoLink: UIButton = UIButton()
    var startCamera: UIButton = UIButton()
    var startBleUpgrade: UIButton = UIButton()
    var startCoreUpgrade: UIButton = UIButton()
    var setWiredMode: UIButton = UIButton()
    var calibration: UIButton = UIButton()
    var shutdown: UIButton = UIButton()
    var maskView: UIView = UIView()

    var bleActived: Bool = false
    var isAutoBind: Bool = true  // 搜索完成后，是否自动连接设备蓝牙

    var log: NSMutableString = NSMutableString()
    var textView: UITextView = UITextView()

    var autoByRSSI: Bool = true  // 根据设备的信号强度判定连接，20cm -> -60 rssi
    var autoBindTimer: Timer = Timer()  // 不根据设备的信号强度判定连接的时候，设定搜索超时时长
    var autoBindStartTime: TimeInterval = 0.0

    var devices: Array = [Dictionary<String, AnyObject>]() // 已扫描到的附近设备列表
    var targetDevice: Dictionary<String, AnyObject> = [: ]  // 目标连接设备

    var apLinkCheck: Bool = false
    var apLinkSSID: NSString = NSString()
    var ip: NSString = NSString()

    var upgradeValue: Int32 = 0
    var shouldReset: Bool = false  // 用于判定是否进入图像采集控制器

    //MARK:- LIFE CYCLE
    deinit {
        NSLog("【dealloc】%@", self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.shouldReset = true
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        self.autoBindTimer.invalidate()

        NSObject.cancelPreviousPerformRequests(withTarget: self)
        if self.shouldReset {
            CTBleHelper.stopScan()
            CTBleHelper.disconnect()
            CTBleHelper.cleanDeviceCache()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.

        self.navigationController?.navigationBar.isTranslucent = false

        self.title = "CTEasyLinker";
        self.view.backgroundColor = UIColor.XF_f6Gray

        self.customUI()
        self.everythingIsReady()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning();
        // Dispose of any resources that can be recreated.
    }

    //MARK:- >> Sdk 基础配置 <<
    func everythingIsReady() {
        NotificationCenter.default.removeObserver(self, name: .CT_iPhone_BleUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(CT_iPhone_BleUpdate(noti:)),
                                               name: .CT_iPhone_BleUpdate, object: nil)

        if CTBleHelper.blePowerdOn() == -1 {
            self.xf_Log(logX: "等待< 用户给予蓝牙权限 >或< Sdk内部启动蓝牙模块 >.")
            self.bleActived = false
            return
        }
        self.bleActived = true

        self.startScan.isUserInteractionEnabled = true
        self.startScan.isSelected = true
        self.xf_Log(logX: "准备就绪...")

        self.isAutoBind = true
        self.autoByRSSI = true

        self.configXiaoFuSdk()

        if CTBleHelper.blePowerdOn() == 0 {
            self.xf_Log(logX: "手机蓝牙已关闭.")
            return
        }
        self.xf_Log(logX: "手机蓝牙已打开.")
    }

    func configXiaoFuSdk() {
        weak var weakSelf = self

        CTConfig.shared()?.debugEnable = true
        CTConfig.shared()?.debugLogType = 1
        CTConfig.shared()?.debugLogHandler = { (log: String?) in
            weakSelf?.xf_Log(logX: log! as NSString)
        }
        CTConfig.shared()?.blueStripDetectionHandler = { (blueStripImage:UIImage?) in
            weakSelf?.xf_Log(logX: "当前图片检测到蓝条，可选择记录日志或者图片数据。")
        }  // 1.0.17 新增，蓝条检测
        //CTConfig.shared()?.blueStripDetectionType = 1
        CTConfig.shared()?.channelSetting = -1  // 1.0.17 新增，AP模式，随机信道
        CTConfig.shared()?.splitStrings = ["!@"]

        NotificationCenter.default.addObserver(self, selector: #selector(CT_Device_ScanUpdate(noti:)),
                                               name: .CT_Device_ScanUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(CT_Device_BleUpdate(noti:)),
                                               name: .CT_Device_BleUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(CT_Device_BatteryUpdate(noti:)),
                                               name: .CT_Device_BatteryUpdate, object: nil)

        // 追加...
        CTEasyLinker.sharedEsay().smartMode = 1
        CTEasyLinker.sharedEsay().verify5GEnabled = true
        CTEasyLinker.sharedEsay().staPingEnabled = true
        CTEasyLinker.sharedEsay().staCachesStored = true
        CTEasyLinker.sharedEsay().ssidIgnored = ["CFY_"]
        CTEasyLinker.sharedEsay().hotspotEnabled = true

        CTEasyLinker.sharedEsay().preparedForAP = { (ssid, password) in
            DispatchQueue.main.async {
                weakSelf?.preparedForAP(ssid: ssid as String, password: password as String)
            }
        }

        CTEasyLinker.sharedEsay().preparedForSTA = { (ssid: String) in
            DispatchQueue.main.async {
                weakSelf?.preparedForSTA(ssid: ssid)
            }
        }

        CTEasyLinker.sharedEsay().responseForSTA = { (code: CTBleResponseCode, wifiStatus: Int32, ip: String) in
            DispatchQueue.main.async {
                weakSelf?.responseForSTA(code: code, wifiStatus: Int(wifiStatus), ip: ip)
            }
        }

        CTEasyLinker.sharedEsay().networkLinkResponse = { (code: CTBleResponseCode, type: Int32, ip: String) in
            DispatchQueue.main.async {
                weakSelf?.networkLinkResponse(code: code, type: Int(type), ip: ip)
            }
        }

        // 可选...
        CTEasyLinker.sharedEsay().staStartResponse = { () in
            weakSelf?.xf_Log(logX: "启动 STA模式 联网进程.")
        }

        CTEasyLinker.sharedEsay().verify5GResponse = { (isStart: Bool, code: CTBleResponseCode) in
            DispatchQueue.main.async {
                let log: NSString = NSString.init(format: "%@.", isStart ? "开始5G网络检测..." : "5G网络检测已结束")
                weakSelf?.xf_Log(logX: log)
            }
        }

        CTEasyLinker.sharedEsay().staPingResponse = { (isStart: Bool, code: CTBleResponseCode) in
            DispatchQueue.main.async {
                let log: NSString = NSString.init(format: "%@.", isStart ? "开始Ping网络检测..." : "Ping网络检测已结束")
                weakSelf?.xf_Log(logX: log)
            }
        }

        CTEasyLinker.sharedEsay().apStartResponse = { () in
            weakSelf?.xf_Log(logX: "启动 AP模式 联网进程.")
        }

        CTEasyLinker.sharedEsay().hotspotResponse = { (isStart: Bool, code: CTBleResponseCode) in
            DispatchQueue.main.async {
                let log: NSString = NSString.init(format: "%@.", isStart ? "开始启动Hotspot进程..." : "Hotspot进程已结束")
                weakSelf?.xf_Log(logX: log)
            }
        }
    }

    @objc func CT_iPhone_BleUpdate(noti: Notification) {
        weak var weakSelf = self
        DispatchQueue.main.async {
            objc_sync_enter(weakSelf as Any)

            if (weakSelf?.bleActived)! {
                if CTBleHelper.blePowerdOn() == 0 {
                    weakSelf?.xf_Log(logX: "手机蓝牙已关闭.")
                } else {
                    weakSelf?.xf_Log(logX: "手机蓝牙已打开.")
                }
                return
            }

            // 用户已授权 & Sdk内部蓝牙模块已启动.
            weakSelf?.bleActived = true
            weakSelf?.everythingIsReady()

            objc_sync_exit(weakSelf as Any)
        }
    }

    @objc func CT_Device_ScanUpdate(noti: Notification) {
        weak var weakSelf = self
        DispatchQueue.main.async {
            var devices: Array = [Dictionary<String, AnyObject>]()

            var list: Array = [Dictionary<String, AnyObject>]()
            list += noti.userInfo!["Devices"] as! Array
            for device: Dictionary<String, AnyObject> in list {
                if (device["Name"] != nil) && (device["BindID"] != nil) {
                    let deviceInfo: NSString = NSString.init(format: "Name:%@, BindID:%@, RSSI:%@.",
                                                             device["Name"] as! CVarArg,
                                                             device["BindID"] as! CVarArg,
                                                             device["RSSI"] as! CVarArg)
                    NSLog("%@", deviceInfo)

                    if (weakSelf?.autoByRSSI)! {
                        let rssi: Int = (device["RSSI"] as! NSNumber).intValue
                        if rssi < 0 && rssi >= -60 {  // 20cm -> -60 rssi
                            devices.append(device)
                        }
                    } else {
                        devices.append(device)
                    }
                } else {
                    weakSelf?.xf_Log(logX: "[WARNING]设备信息有空值，请反馈给开发者.")
                }
            }

            DispatchQueue.main.async {
                if !(weakSelf?.autoBindTimer.isValid)! {  // 会被触发多次..
                    weakSelf?.xf_Log(logX: "已停止扫描，放弃处理扫描结果.")
                    return
                }

                weakSelf?.devices = devices
                if (weakSelf?.autoByRSSI)! && !(weakSelf?.devices.isEmpty)! {
                    weakSelf?.xf_Log(logX: "自动停止扫描 - 来自设备的信号强度判定.")
                    CTBleHelper.stopScan()

                    weakSelf?.startScan.isUserInteractionEnabled = false
                    weakSelf?.startScan.isSelected = false

                    weakSelf?.autoBindTimer.invalidate()
                    weakSelf?.autoBind()
                }
            }
        }
    }

    @objc func CT_Device_BleUpdate(noti: Notification) {
        weak var weakSelf = self
        DispatchQueue.main.async {
            let userInfo: Dictionary = noti.userInfo!
            let status: NSNumber = userInfo["ConnectStatus"] as! NSNumber
            let info: NSString = NSString.init(format: "CT_Device_BleUpdate：%d, %@, %d",
                                               status.intValue, userInfo["Msg"] as! CVarArg,
                                               CTBleHelper.connectStatus())
            NSLog("%@", info)

            if CTBleHelper.connectStatus() == 2 {

                weakSelf?.xf_Log(logX: "设备蓝牙已连接.")

                let device: Dictionary<String, AnyObject> = CTBleHelper.deviceInfoCache() as! Dictionary<String, AnyObject>
                let deviceInfo: NSString = NSString.init(format: "%@，%@，%d，ble：%@，core：%@ .",
                                                         device["Name"] as! CVarArg,
                                                         device["BindID"] as! CVarArg,
                                                         (weakSelf?.targetDevice["RSSI"] as! NSNumber).intValue,
                                                         device["BleVersionString"] as! CVarArg,
                                                         device["CoreVersionString"] as! CVarArg)

                weakSelf?.xf_Log(logX: deviceInfo)

                weakSelf?.title = deviceInfo.components(separatedBy: "，ble").first
                weakSelf?.updateUI4BleConnected()

            } else if CTBleHelper.connectStatus() == 0 {

                weakSelf?.xf_Log(logX: "设备蓝牙已断开连接(主动).")
                weakSelf?.resetUI()

            } else if CTBleHelper.connectStatus() == -1 {

                weakSelf?.xf_Log(logX: "未成功连接设备蓝牙.")
                weakSelf?.resetUI()

            } else if CTBleHelper.connectStatus() == -2 {

                weakSelf?.xf_Log(logX: "设备蓝牙已断开连接(被动).")
                weakSelf?.resetUI()

            }
        }
    }

    @objc func CT_Device_BatteryUpdate(noti: Notification) {
        weak var weakSelf = self
        DispatchQueue.main.async {
            let batteryInfo: Dictionary<String, AnyObject> = noti.userInfo as! Dictionary<String, AnyObject>
            let success: Bool = (batteryInfo["Success"] as! NSNumber).boolValue
            let isCharge: Bool = (batteryInfo["IsCharge"] as! NSNumber).boolValue
            let battery: Int = (batteryInfo["Battery"] as! NSNumber).intValue

            if success {
                let info: NSString = NSString.init(format: "收到电量状态变化通知，设备%@，电量：%d.",
                                                   isCharge ? "正在充电" : "未充电", battery)
                weakSelf?.xf_Log(logX: info)
            } else {
                weakSelf?.xf_Log(logX: "电量信息请求失败.")
            }
        }
    }

    func preparedForAP(ssid: String, password: String) {
        self.showAPLinkAlert(ssid: ssid)
    }

    func preparedForSTA(ssid: String) {
        self.confirmShowSTALinkAlert()
    }

    func responseForSTA(code: CTBleResponseCode, wifiStatus: Int, ip: String) {
        if code == CTBleResponseCode.error {
            self.maskView.isHidden = true
            self.xf_Log(logX: "STA模式未成功联网，命令请求失败.")
            return
        }

        if wifiStatus == 0 {
            self.xf_Log(logX: "STA模式连接已完成.")
            return
        }

        /** 可见 CTEasyLinker.h 中的方法回调说明；
         注：wifiStatus -3：未搜索到ssid（设备固件版本可能过旧），-2：命令请求失败或超时，-1：密码错误，0：请求成功；
         注：较”CTBleHelper“，wifiStatus -101：5g检查，判定为5g网络，-102：ping检查，判定为公共验证类wifi；
         */
        self.maskView.isHidden = true
        if wifiStatus == -1 {

            self.xf_Log(logX: "密码错误，请重新输入.")
            self.perform(#selector(confirmShowSTALinkAlert), with: nil, afterDelay: 0.91)

        } else if wifiStatus == -3 {

            self.xf_Log(logX: "设备(固件版本旧)，未搜索到指定ssid，请使用AP模式联网.")

        } else if wifiStatus == -101 {

            let alert5G: UIAlertController = UIAlertController.init(title: "5g检查，判定为5g网络",
                                                                    message: "设备 当前“不支持”5G网络 联网，请使用AP模式联网或重试.",
                                                                    preferredStyle: UIAlertController.Style.alert)
            alert5G.addAction(UIAlertAction.init(title: "确定", style: UIAlertAction.Style.cancel, handler: nil))
            self.showAlert(alert: alert5G, sender: self.autoLink)

        } else if wifiStatus == -102 {

            let alertPing: UIAlertController = UIAlertController.init(title: "ping检查，判定为公共验证类wifi",
                                                                      message: "设备 当前“不支持”公共验证类wifi 联网，请使用AP模式联网或重试.",
                                                                      preferredStyle: UIAlertController.Style.alert)
            alertPing.addAction(UIAlertAction.init(title: "确定", style: UIAlertAction.Style.cancel, handler: nil))
            self.showAlert(alert: alertPing, sender: self.autoLink)

        }
    }

    func networkLinkResponse(code: CTBleResponseCode, type: Int, ip: String) {
        self.maskView.isHidden = true

        if code == CTBleResponseCode.error {
            self.xf_Log(logX: "设备联网失败，请重新尝试(若多次联网失败，建议先重启设备).")
            return
        }

        self.ip = ip as NSString

        self.autoLink.isUserInteractionEnabled = false
        self.autoLink.isSelected = false
        self.startCamera.isUserInteractionEnabled = true
        self.startCamera.isSelected = true
        self.startCoreUpgrade.isUserInteractionEnabled = true
        self.startCoreUpgrade.isSelected = true

        let msg: NSString = NSString.init(format: "设备已联网(%@，ip：%@).", type==1 ? "STA模式" : "AP模式", self.ip)
        self.xf_Log(logX: msg)
    }

    //MARK: > AP Mode <
    func showAPLinkAlert(ssid: String) {
        self.apLinkSSID = ssid as NSString

        weak var weakSelf = self

        let apAlert: UIAlertController = UIAlertController.init(title: "前往设置连接指定热点", message: ssid, preferredStyle: UIAlertController.Style.alert)
        apAlert.addAction(UIAlertAction.init(title: "取消", style: UIAlertAction.Style.cancel,
                                             handler: { (action: UIAlertAction) in
                                                weakSelf?.maskView.isHidden = true
                                                weakSelf?.xf_Log(logX: "已取消ap连接.")
        }))
        apAlert.addAction(UIAlertAction.init(title: "前往", style: UIAlertAction.Style.default, handler: { (action: UIAlertAction) in
            XF_ApplicationOpenSettings(type: 2)

            weakSelf?.apLinkCheck = true
            NotificationCenter.default.removeObserver(weakSelf as Any,
                                                      name: UIApplication.willEnterForegroundNotification, object: nil)
            NotificationCenter.default.addObserver(weakSelf as Any,
                                                   selector: #selector(weakSelf?.applicationWillEnterForeground),
                                                   name: UIApplication.willEnterForegroundNotification, object: nil)
        }))
        self.showAlert(alert: apAlert, sender: self.autoLink)
    }

    @objc func applicationWillEnterForeground() {
        weak var weakSelf = self
        DispatchQueue.main.async {
            if (CTConfig.getSSID()! as NSString).isEqual(to: (weakSelf?.apLinkSSID)! as String) {
                weakSelf?.apLinkCheck = false
                NotificationCenter.default.removeObserver(weakSelf as Any,
                                                          name: UIApplication.willEnterForegroundNotification, object: nil)

                CTHotspotHelper.ipAddressConfirmed({ (success: Bool) in
                    DispatchQueue.main.async {
                        weakSelf?.startNetworkConnect()
                    }
                })
            } else {
                weakSelf?.showAPLinkAlert(ssid: (weakSelf?.apLinkSSID)! as String)
            }
        }
    }

    //MARK: > STA Mode <
    @objc func confirmShowSTALinkAlert() {
        let ssid: String = CTConfig.getSSID()
        if ssid.isEmpty {
            self.xf_Log(logX: "showSTALinkAlert，启动失败，未获取到ssid.")
            return;
        }

        self.maskView.isHidden = false

        weak var weakSelf = self
        let staAlert: UIAlertController = UIAlertController.init(title: "输入wifi密码",
                                                                 message: ssid,
                                                                 preferredStyle: UIAlertController.Style.alert)
        staAlert.addTextField { (textField: UITextField) in
            //可自定义textField相关属性...
        }
        staAlert.addAction(UIAlertAction.init(title: "取消",
                                              style: UIAlertAction.Style.cancel,
                                              handler: { (action: UIAlertAction) in
                                                weakSelf?.maskView.isHidden = true
                                                weakSelf?.xf_Log(logX: "已取消sta连接.")
        }))
        staAlert.addAction(UIAlertAction.init(title: "确定",
                                              style: UIAlertAction.Style.default,
                                              handler: { (action: UIAlertAction) in
                                                let pwd: String = (staAlert.textFields?.first?.text)!
                                                weakSelf?.confirmSTAlink_SSID(ssid: ssid, pwd: pwd)
        }))
        self.showAlert(alert: staAlert, sender: self.autoLink)
    }

    func confirmSTAlink_SSID(ssid: String, pwd: String) {
        let log: NSString = NSString.init(format: "ssid：%@，pwd：%@ .", ssid, pwd)
        self.xf_Log(logX: "开始启动STA模式连接...")
        self.xf_Log(logX: log)
        CTEasyLinker.sta(ssid, password: pwd)
    }

    //MARK:- >> Additional <<
    //MARK: > for getInfo <
    func wifiStatus() {
        self.xf_Log(logX: "[仅检查]开始获取设备网络状态...")
        self.maskView.isHidden = false

        weak var weakSelf = self
        CTEasyLinker.networkStatusCheckOnly(true) { (code, type, ssid, password, ip) in
            DispatchQueue.main.async {
                weakSelf?.maskView.isHidden = true

                var logMsg: String = "wifiStatus 获取成功."
                if code == CTBleResponseCode.error {
                    logMsg = "未成功获取 wifiStatus."
                    weakSelf?.xf_Log(logX: logMsg as NSString)
                    return
                }

                weakSelf?.xf_Log(logX: logMsg as NSString)
                if type == 0 {
                    if (CTConfig.getSSID()?.isEmpty)! {
                        logMsg = "UnKnown_手机未连接wifi，可启动ap模式.";
                    } else {
                        logMsg = "UnKnown_手机已连接wifi，可启动sta模式.";
                    }
                } else if type == 1 {
                    if (CTConfig.getSSID() as NSString).isEqual(to: ssid) {
                        if ip.isEmpty {
                            logMsg = "AP_手机已连接设备热点，但未获取到设备联网ip，可启动sta模式.";
                        } else {
                            logMsg = "STA_手机与设备处于同一wifi网络，且已获取到设备联网ip，可直接启动摄像头.";
                        }
                    } else {
                        logMsg = "STA_手机已连接wifi，可启动sta模式.";
                    }
                } else if type == 2 {
                    if (CTConfig.getSSID()?.isEmpty)! {
                        logMsg = "AP_手机未连接wifi，可启动ap模式.";
                    } else {
                        if (CTConfig.getSSID() as NSString).isEqual(to: ssid) {
                            if ip.isEmpty {
                                logMsg = "AP_手机已连接设备热点，但未获取到设备联网ip，可启动ap模式.";
                            } else {
                                logMsg = "AP_手机已连接设备热点，且已获取到设备联网ip，可直接启动摄像头.";
                            }
                        } else {
                            logMsg = "AP_手机未连接当前设备热点，可启动ap模式.";
                        }
                    }
                }
                weakSelf?.xf_Log(logX: logMsg as NSString)
            }
        }
    }

    func getMAC() {
        self.xf_Log(logX: "开始获取设备的 MAC信息...")
        self.maskView.isHidden = false

        weak var weakSelf = self
        CTBleHelper.mac { (code, mac) in
            DispatchQueue.main.async {
                weakSelf?.maskView.isHidden = true
                if code == CTBleResponseCode.OK {
                    weakSelf?.xf_Log(logX: NSString.init(format: "MAC信息获取成功：%@.", mac!))
                } else {
                    weakSelf?.xf_Log(logX: "MAC信息获取失败.")
                }
            }
        }
    }

    func getVersion() {
        self.xf_Log(logX: "开始获取设备的 Version信息...")
        self.maskView.isHidden = false

        weak var weakSelf = self
        CTBleHelper.version { (code, ble, core, bleValue, coreValue) in
            DispatchQueue.main.async {
                weakSelf?.maskView.isHidden = true
                if code == CTBleResponseCode.OK {
                    let verInfo: NSString = NSString.init(format: "Version获取成功：Ble:%@[%ld], Core：%@[%ld].", ble!, bleValue, core!, coreValue)
                    weakSelf?.xf_Log(logX: verInfo)
                } else {
                    weakSelf?.xf_Log(logX: "Version信息获取失败.")
                }
            }
        }
    }

    func getBattery() {
        self.xf_Log(logX: "开始获取设备的 Battery信息...")
        self.maskView.isHidden = false

        weak var weakSelf = self
        CTBleHelper.battery { (code, isCharge, battery) in
            DispatchQueue.main.async {
                weakSelf?.maskView.isHidden = true
                if code == CTBleResponseCode.OK {
                    let batteryInfo: NSString = NSString.init(format: "Battery获取成功：isCharge：%d, battery：%d.", isCharge, battery)
                    weakSelf?.xf_Log(logX: batteryInfo)
                } else {
                    weakSelf?.xf_Log(logX: "Battery信息获取失败.")
                }
            }
        }
    }

    //MARK: > for ble upgrade <
    func bleVersionUpgradeLimitedTargetVersion(targetVersion: Int, completion: (() -> Void)?) {
        let bleVersion: Int = (CTBleHelper.deviceInfoCache()!["BleVersion"] as! NSNumber).intValue
        let coreVersion: Int = (CTBleHelper.deviceInfoCache()!["CoreVersion"] as! NSNumber).intValue

        var limited: Bool = false
        var alertMsg: String = "蓝牙固件版本受限处理."
        // 受限判定
        if bleVersion > 20000 && coreVersion > 30000 && targetVersion < 20100 {
            // ble > 2.0.0，core > 3.0.0，降级操作：目标版本2.0.0 + 3.0.0，必须先核心，后蓝牙
            limited = true
            alertMsg = "请先降级核心固件版本."
        }

        if !limited {  // 无受限
            completion?()
            return
        }

        // 显示受限警示框
        let alert: UIAlertController = UIAlertController.init(title: alertMsg, message: nil, preferredStyle: UIAlertController.Style.alert)
        alert.addAction(UIAlertAction.init(title: "知道了", style: UIAlertAction.Style.default, handler: nil))
        self .showAlert(alert: alert, sender: self.startBleUpgrade)
    }

    func startUpdateBle(verName: NSString) {
        let targetStr: NSString = verName.components(separatedBy: "_")[1] as NSString
        let bleVers: Array = targetStr.components(separatedBy: ".")
        let target: Int = Int(bleVers[0])!*10000 + Int(bleVers[1])!*100 + Int(bleVers[2])!

        weak var weakSelf = self
        self.bleVersionUpgradeLimitedTargetVersion(targetVersion: target) {
            weakSelf?.xf_Log(logX: "开始升级蓝牙固件...")
            weakSelf?.maskView.isHidden = false

            do {
                let url: URL = URL.init(fileURLWithPath: Bundle.main.path(forResource: verName as String, ofType: "bin")!)
                let bleData: Data = try Data.init(contentsOf: url, options: Data.ReadingOptions.mappedIfSafe)

                weakSelf?.upgradeValue = -1
                CTEasyLinker.updateBLE(bleData, response: { (code, value, msg) in
                    DispatchQueue.main.async {
                        if code == CTBleResponseCode.error {
                            weakSelf?.maskView.isHidden = true
                            weakSelf?.xf_Log(logX: NSString.init(format: "升级失败：%@", msg))
                            weakSelf?.resetUI()
                            return
                        }

                        if value < 100 {
                            if value < 3 || value > 97 {
                                weakSelf?.xf_Log(logX: NSString.init(format: "升级进度：%d（%@）", value, msg))
                            } else if value == 3 ||
                                value == 16 || value == 26 || value == 36 || value == 56 ||
                                value == 66 || value == 76 || value == 86 || value == 96 {
                                if weakSelf?.upgradeValue != value {
                                    weakSelf?.upgradeValue = value
                                    weakSelf?.xf_Log(logX: NSString.init(format: "升级进度：%d（%@）", value, msg))
                                }
                            }
                        } else {
                            weakSelf?.maskView.isHidden = true
                            weakSelf?.xf_Log(logX: NSString.init(format: "升级进度：%d（%@）", value, msg))
                            weakSelf?.resetUI()
                        }
                    }
                })

            } catch { }
        }
    }

    //MARK: > for core upgrade <
    func coreVersionUpgradeLimitedTargetVersion(targetVersion: Int, completion: (() -> Void)?) {
        let bleVersion: Int = (CTBleHelper.deviceInfoCache()!["BleVersion"] as! NSNumber).intValue
        //let coreVersion: Int = (CTBleHelper.deviceInfoCache()!["CoreVersion"] as! NSNumber).intValue

        var limited: Bool = false
        var alertMsg: String = "核心固件版本受限处理."
        // 受限判定
        if bleVersion < 20100 && targetVersion > 30000 {
            // ble < 2.1.0，升级操作：目标版本2.1.0 + 3.1.0，必须先蓝牙，后核心
            limited = true
            alertMsg = "请先升级蓝牙固件版本."
        }

        if !limited {  // 无受限
            completion?()
            return
        }

        // 显示受限警示框
        let alert: UIAlertController = UIAlertController.init(title: alertMsg, message: nil, preferredStyle: UIAlertController.Style.alert)
        alert.addAction(UIAlertAction.init(title: "知道了", style: UIAlertAction.Style.default, handler: nil))
        self .showAlert(alert: alert, sender: self.startBleUpgrade)
    }

    func startUpdateCore(verName: NSString) {
        let targetStr: NSString = verName.components(separatedBy: "_")[1] as NSString
        let bleVers: Array = targetStr.components(separatedBy: ".")
        let target: Int = Int(bleVers[0])!*10000 + Int(bleVers[1])!*100 + Int(bleVers[2])!

        weak var weakSelf = self
        self.coreVersionUpgradeLimitedTargetVersion(targetVersion: target) {
            weakSelf?.xf_Log(logX: "开始升级核心固件...")
            weakSelf?.maskView.isHidden = false

            do {
                let url: URL = URL.init(fileURLWithPath: Bundle.main.path(forResource: verName as String, ofType: "bin")!)
                let coreData: Data = try Data.init(contentsOf: url, options: Data.ReadingOptions.mappedIfSafe)

                weakSelf?.upgradeValue = -1
                CTEasyLinker.updateCore(coreData, response: { (code, value, msg) in
                    DispatchQueue.main.async {
                        if code == CTBleResponseCode.error {
                            weakSelf?.maskView.isHidden = true
                            weakSelf?.xf_Log(logX: NSString.init(format: "升级失败：%@", msg))
                            weakSelf?.shutdown(sender: UIButton())
                            return
                        }

                        if value < 100 {
                            if value < 6 || value > 97 {
                                weakSelf?.xf_Log(logX: NSString.init(format: "升级进度：%d（%@）", value, msg))
                            } else if value == 3 ||
                                value == 16 || value == 26 || value == 36 || value == 56 ||
                                value == 66 || value == 76 || value == 86 || value == 96 {
                                if weakSelf?.upgradeValue != value {
                                    weakSelf?.upgradeValue = value
                                    weakSelf?.xf_Log(logX: NSString.init(format: "升级进度：%d（%@）", value, msg))
                                }
                            }
                        } else {
                            weakSelf?.maskView.isHidden = true
                            weakSelf?.xf_Log(logX: NSString.init(format: "升级进度：%d（%@）", value, msg))
                            weakSelf?.shutdown(sender:UIButton())
                        }
                    }
                })

            } catch { }
        }
    }

    //MARK: > for autoLink <
    func startNetworkConnect() {
        self.xf_Log(logX: "[联网准备]开始获取设备网络状态...")
        self.maskView.isHidden = false

        CTEasyLinker.networkStatusCheckOnly(false, response: nil)
    }

    //MARK: > for calibration <
    func calibrationAction() {
        let bleVersion: Int = (CTBleHelper.deviceInfoCache()!["BleVersion"] as! NSNumber).intValue
        let coreVersion: Int = (CTBleHelper.deviceInfoCache()!["CoreVersion"] as! NSNumber).intValue

        if bleVersion < 20100 || coreVersion < 30100 {
            self.xf_Log(logX: "固件版本不符合要求，已取消.")
            return
        }

        self.xf_Log(logX: "开始检查当前校准状态...")
        self.maskView.isHidden = false

        weak var weakSelf = self
        CTBleHelper.calibrateStatusCheck { (code, status, msg) in
            DispatchQueue.main.async {
                weakSelf?.maskView.isHidden = true
                if code == CTBleResponseCode.error {
                    weakSelf?.xf_Log(logX: "获取校准状态 请求失败.")
                    return
                }

                if -1 == status {
                    weakSelf?.xf_Log(logX: "校准状态未知.")
                } else if 0 == status {
                    weakSelf?.xf_Log(logX: "当前设备不需要校准.")
                } else if 1 == status {
                    weakSelf?.xf_Log(logX: "请使用专门的 校准工具 进行校准.")
                } else if 2 == status {
                    weakSelf?.xf_Log(logX: "当前设备已校准.")
                }
            }
        }
    }

    func recalibration() {
        let bleVersion: Int = (CTBleHelper.deviceInfoCache()!["BleVersion"] as! NSNumber).intValue
        let coreVersion: Int = (CTBleHelper.deviceInfoCache()!["CoreVersion"] as! NSNumber).intValue

        if bleVersion < 20100 || coreVersion < 30100 {
            self.xf_Log(logX: "固件版本不符合要求，已取消.")
            return
        }

        self.xf_Log(logX: "开始检查当前校准状态...")
        self.maskView.isHidden = false

        weak var weakSelf = self
        CTBleHelper.calibrateStatusCheck { (code, status, msg) in
            DispatchQueue.main.async {
                if code == CTBleResponseCode.error {
                    weakSelf?.maskView.isHidden = true
                    weakSelf?.xf_Log(logX: "获取校准状态 请求失败.")
                    return
                }

                if 2 == status {
                    weakSelf?.xf_Log(logX: "设备已校准，开始执行 图像校准回滚...")
                    CTBleHelper.calibrateCommand(3, response: { (code, status, msg) in
                        DispatchQueue.main.async {
                            weakSelf?.xf_Log(logX: NSString.init(format: "图像校准回滚：%@.", msg!))
                            weakSelf?.maskView.isHidden = true
                            if code == CTBleResponseCode.OK {
                                weakSelf?.shutdown(sender: UIButton())
                            }
                        }
                    })
                    return
                }

                weakSelf?.maskView.isHidden = true
                if -1 == status {
                    weakSelf?.xf_Log(logX: "校准状态未知，回滚拒绝.")
                } else if 0 == status {
                    weakSelf?.xf_Log(logX: "当前设备不需要校准，回滚拒绝.")
                } else if 1 == status {
                    weakSelf?.xf_Log(logX: "当前设备未校准，回滚拒绝.")
                } else if 2 == status {
                    //weakSelf?.xf_Log(logX: "当前设备已校准，可以回滚.")
                }
            }
        }
    }

    func restartNVDS() {
        let bleVersion: Int = (CTBleHelper.deviceInfoCache()!["BleVersion"] as! NSNumber).intValue
        let coreVersion: Int = (CTBleHelper.deviceInfoCache()!["CoreVersion"] as! NSNumber).intValue

        if bleVersion < 20100 || coreVersion < 30100 {
            self.xf_Log(logX: "固件版本不符合要求，已取消.")
            return
        }

        self.xf_Log(logX: "开始执行 一键恢复，校准配置...")
        self.maskView.isHidden = false

        weak var weakSelf = self
        CTBleHelper.calibrateRestartNVDS { (code, status, msg) in
            DispatchQueue.main.async {
                weakSelf?.xf_Log(logX: NSString.init(format: "一键恢复，校准配置：%@", msg!))
                weakSelf?.maskView.isHidden = true
                if code == CTBleResponseCode.OK {
                    weakSelf?.shutdown(sender: UIButton())
                }
            }
        }
    }

    //MARK: > for setWireMode <
    func setWiredMode(mode: Int) {
        weak var weakSelf = self

        let alert: UIAlertController = UIAlertController.init(title: "请选择设备类型", message: nil,
                                                              preferredStyle: UIAlertController.Style.actionSheet)
        alert.addAction(UIAlertAction.init(title: "老设备", style: UIAlertAction.Style.default,
                                           handler: { (action: UIAlertAction) in
                                            CTBleHelper.setWiredModeCommand(Int32(-mode), response: { (code, msg) in
                                                DispatchQueue.main.async {
                                                    let modeDes: String = mode == 1 ? "混合" : (mode == 2 ? "无线" : "有线")
                                                    if code == CTBleResponseCode.OK {
                                                        weakSelf?.xf_Log(logX: NSString.init(format: "老设备 %@模式 设置成功.", modeDes))
                                                    } else {
                                                        weakSelf?.xf_Log(logX: NSString.init(format: "老设备 %@模式 设置失败.", modeDes))
                                                    }
                                                    weakSelf?.shutdown(sender: UIButton())
                                                }
                                            })
        }))
        alert.addAction(UIAlertAction.init(title: "新设备", style: UIAlertAction.Style.default,
                                           handler: { (action: UIAlertAction) in
                                            CTBleHelper.setWiredModeCommand(Int32(mode), response: { (code, msg) in
                                                DispatchQueue.main.async {
                                                    let modeDes: String = mode == 1 ? "混合" : (mode == 2 ? "无线" : "有线")
                                                    if code == CTBleResponseCode.OK {
                                                        weakSelf?.xf_Log(logX: NSString.init(format: "新设备 %@模式 设置成功.", modeDes))
                                                    } else {
                                                        weakSelf?.xf_Log(logX: NSString.init(format: "新设备 %@模式 设置失败.", modeDes))
                                                    }
                                                    weakSelf?.shutdown(sender: UIButton())
                                                }
                                            })
        }))
        alert.addAction(UIAlertAction.init(title: "取消", style: UIAlertAction.Style.cancel,
                                           handler:nil))
        self.showAlert(alert: alert, sender: self.setWiredMode)
    }

    //MARK:- >> Others <<
    @objc func autoBindTimerRun(timer: Timer) {
        if NSDate().timeIntervalSince1970 > self.autoBindStartTime+10.0 {
            self.xf_Log(logX: "自动停止扫描 - 来自扫描计时.")
            CTBleHelper.stopScan()

            self.stopScan.isUserInteractionEnabled = false
            self.stopScan.isSelected = false

            self.autoBindTimer.invalidate()
            self.autoBind()
        }
    }

    func autoBind() {
        if self.devices.isEmpty {
            self.xf_Log(logX: "未扫描到任何设备.")
            self.title = "CTEasyLinker"
            self.startScan.isUserInteractionEnabled = true
            self.startScan.isSelected = true
            return
        }

        // 仅连接列表中信号强度最强的那个设备
        var device: Dictionary<String, AnyObject> = self.devices.first!  // var device = self.devices.first
        for dev: Dictionary<String, AnyObject> in self.devices {
            let newValue: Int = (dev["RSSI"] as! NSNumber).intValue
            let oldValue: Int = (device["RSSI"] as! NSNumber).intValue
            if newValue > oldValue {
                device = dev
            }
        }

        self.targetDevice = device
        CTEasyLinker.connect(byName: (device["Name"] as! String), bindID: (device["BindID"] as! String))
    }

    //MARK: >> customUI <<
    func customUI() {
        var frame = CGRect.init(x: 0, y: 0, width: XFWidth(), height: XFHeight()-XFNaviBarHeight())
        let mainView: UIView = XFView(bgColor: UIColor.clear, frame: frame)
        self.view.addSubview(mainView)

        var top: CGFloat = 5.0
        frame = CGRect.init(x: 5, y: top, width: mainView.xf_Width-10, height: mainView.xf_Height/2-10)
        // NSTextStorage, NSLayoutManager, NSTextContainer
        let textView: UITextView = UITextView.init(frame: frame)
        textView.layer.borderWidth = 1.0
        textView.layer.borderColor = XFColor(rgbValue: 0x333333, alpha: 1.0).cgColor
        textView.layer.cornerRadius = 3.0
        textView.clipsToBounds = true
        textView.font = XFFont(fontSize: 11.0)
        textView.textColor = XFColor(rgbValue: 0x333333, alpha: 1.0)

        textView.isEditable = false
        //textView.isSelectable = false;  // iOS 11 + 会触发 滚动至最后一行 功能出现Bug；

        textView.layoutManager.allowsNonContiguousLayout = false
        mainView.addSubview(textView)
        top += textView.xf_Height+15
        self.textView = textView

        frame = CGRect.init(x: 5, y: top-10, width: mainView.xf_Width-10, height: mainView.xf_Height-5-(top-10))
        let maskView: UIView = XFView(bgColor: XFColor(rgbValue: 0x000000, alpha: 0.3), frame: frame)
        maskView.layer.cornerRadius = 3.0
        maskView.isHidden = true
        self.maskView = maskView


        let btnWidth: CGFloat = (XFWidth()-15*2-20*2)/3
        let btnHeight: CGFloat = 45
        let limitHeight: CGFloat = mainView.xf_Height
        var left: CGFloat = 15
        let spacing: CGFloat = 10

        frame = CGRect.init(origin: CGPoint.init(x: Int(left), y: Int(top)),
                            size: CGSize.init(width: btnWidth, height: btnHeight))
        self.startScan = self.setupButtonTitle(title: "startScan",
                                               action: #selector(startScan(sender:)), frame: frame)
        self.view.addSubview(self.startScan)
        top += btnHeight+spacing
        if top+btnHeight+spacing > limitHeight {
            left += btnWidth+20
            top = self.startScan.xf_Top
        }

        frame = CGRect.init(origin: CGPoint.init(x: Int(left), y: Int(top)),
                            size: CGSize.init(width: btnWidth, height: btnHeight))
        self.stopScan = self.setupButtonTitle(title: "stopScan",
                                              action: #selector(stopScan(sender:)), frame: frame)
        self.view.addSubview(self.stopScan)
        top += btnHeight+spacing
        if top+btnHeight+spacing > limitHeight {
            left += btnWidth+20
            top = self.startScan.xf_Top
        }

        if !self.isAutoBind {
            frame = CGRect.init(origin: CGPoint.init(x: Int(left), y: Int(top)),
                                size: CGSize.init(width: btnWidth, height: btnHeight))
            self.startBind = self.setupButtonTitle(title: "startBind",
                                                   action: #selector(startBind(sender:)), frame: frame)
            self.view.addSubview(self.startBind)
            top += btnHeight+spacing
            if top+btnHeight+spacing > limitHeight {
                left += btnWidth+20
                top = self.startScan.xf_Top
            }
        }

        frame = CGRect.init(origin: CGPoint.init(x: Int(left), y: Int(top)),
                            size: CGSize.init(width: btnWidth, height: btnHeight))
        self.disConnect = self.setupButtonTitle(title: "disConnect", action: #selector(disConnect(sender:)), frame: frame)
        self.view.addSubview(self.disConnect)
        top += btnHeight+spacing
        if top+btnHeight+spacing > limitHeight {
            left += btnWidth+20
            top = self.startScan.xf_Top
        }

        frame = CGRect.init(origin: CGPoint.init(x: Int(left), y: Int(top)),
                            size: CGSize.init(width: btnWidth, height: btnHeight))
        self.getInfo = self.setupButtonTitle(title: "getInfo", action: #selector(getInfo(sender:)), frame: frame)
        self.view.addSubview(self.getInfo)
        top += btnHeight+spacing
        if top+btnHeight+spacing > limitHeight {
            left += btnWidth+20
            top = self.startScan.xf_Top
        }

        frame = CGRect.init(origin: CGPoint.init(x: Int(left), y: Int(top)),
                            size: CGSize.init(width: btnWidth, height: btnHeight))
        self.startBleUpgrade = self.setupButtonTitle(title: "startBleUpgrade", action: #selector(startBleUpgrade(sender:)), frame: frame)
        self.view.addSubview(self.startBleUpgrade)
        top += btnHeight+spacing
        if top+btnHeight+spacing > limitHeight {
            left += btnWidth+20
            top = self.startScan.xf_Top
        }

        frame = CGRect.init(origin: CGPoint.init(x: Int(left), y: Int(top)),
                            size: CGSize.init(width: btnWidth, height: btnHeight))
        self.autoLink = self.setupButtonTitle(title: "autoLink", action: #selector(autoLink(sender:)), frame: frame)
        self.view.addSubview(self.autoLink)
        top += btnHeight+spacing
        if top+btnHeight+spacing > limitHeight {
            left += btnWidth+20
            top = self.startScan.xf_Top
        }

        frame = CGRect.init(origin: CGPoint.init(x: Int(left), y: Int(top)),
                            size: CGSize.init(width: btnWidth, height: btnHeight))
        self.startCamera = self.setupButtonTitle(title: "startCamera", action: #selector(startCamera(sender:)), frame: frame)
        self.view.addSubview(self.startCamera)
        top += btnHeight+spacing
        if top+btnHeight+spacing > limitHeight {
            left += btnWidth+20
            top = self.startScan.xf_Top
        }

        frame = CGRect.init(origin: CGPoint.init(x: Int(left), y: Int(top)),
                            size: CGSize.init(width: btnWidth, height: btnHeight))
        self.startCoreUpgrade = self.setupButtonTitle(title: "startCoreUpgrade", action: #selector(startCoreUpgrade(sender:)), frame: frame)
        self.view.addSubview(self.startCoreUpgrade)
        top += btnHeight+spacing
        if top+btnHeight+spacing > limitHeight {
            left += btnWidth+20
            top = self.startScan.xf_Top
        }

        frame = CGRect.init(origin: CGPoint.init(x: Int(left), y: Int(top)),
                            size: CGSize.init(width: btnWidth, height: btnHeight))
        self.calibration = self.setupButtonTitle(title: "calibration", action: #selector(calibrationTools(sender:)), frame: frame)
        self.view.addSubview(self.calibration)
        top += btnHeight+spacing
        if top+btnHeight+spacing > limitHeight {
            left += btnWidth+20
            top = self.startScan.xf_Top
        }

        frame = CGRect.init(origin: CGPoint.init(x: Int(left), y: Int(top)),
                            size: CGSize.init(width: btnWidth, height: btnHeight))
        self.setWiredMode = self.setupButtonTitle(title: "wiredMode", action: #selector(wiredMode(sender:)), frame: frame)
        self.view.addSubview(self.setWiredMode)
        top += btnHeight+spacing
        if top+btnHeight+spacing > limitHeight {
            left += btnWidth+20
            top = self.startScan.xf_Top
        }

        frame = CGRect.init(origin: CGPoint.init(x: Int(left), y: Int(top)),
                            size: CGSize.init(width: btnWidth, height: btnHeight))
        self.shutdown = self.setupButtonTitle(title: "shutdown", action: #selector(shutdown(sender:)), frame: frame)
        self.view.addSubview(self.shutdown)
        top += btnHeight+spacing
        if top+btnHeight+spacing > limitHeight {
            left += btnWidth+20
            top = self.startScan.xf_Top
        }

        self.view.addSubview(self.maskView)

    }

    func setupButtonTitle(title: NSString, action: Selector, frame: CGRect) -> UIButton {
        let button: UIButton = UIButton.init(type: UIButton.ButtonType.custom)
        button.frame = frame
        button.backgroundColor = UIColor.clear
        button.addTarget(self, action: action, for: UIControl.Event.touchUpInside)

        button.setTitle(title as String, for: UIControl.State.normal)
        button.titleLabel?.font = XFFont(fontSize: 15.0)
        button.titleLabel?.numberOfLines = 1
        button.titleLabel?.textAlignment = NSTextAlignment.center
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.setTitleColor(XFColor(rgbValue: 0xffffff, alpha: 1.0), for: UIControl.State.normal)

        button.xf_SetBackgroundColor(XFColor(rgbValue: 0xcecece, alpha: 1.0), for: UIControl.State.normal)
        button.xf_SetBackgroundColor(XFColor(rgbValue: 0x4d7bfe, alpha: 1.0), for: UIControl.State.selected)
        button.xf_SetBackgroundColor(XFColor(rgbValue: 0x4d7bfe, alpha: 0.75),
                                     for: [UIControl.State.selected, UIControl.State.highlighted])

        button.layer.cornerRadius = 3.0
        button.clipsToBounds = true

        button.isSelected = false
        return button
    }

    func resetUI() {
        self.maskView.isHidden = true

        self.title = "CTEasyLinker"
        self.startScan.isUserInteractionEnabled = true
        self.startScan.isSelected = true
        self.stopScan.isUserInteractionEnabled = false
        self.stopScan.isSelected = false

        self.startBind.isUserInteractionEnabled = false
        self.startBind.isSelected = false
        self.disConnect.isUserInteractionEnabled = false
        self.disConnect.isSelected = false
        self.shutdown.isUserInteractionEnabled = false
        self.shutdown.isSelected = false

        self.getInfo.isUserInteractionEnabled = false
        self.getInfo.isSelected = false
        self.autoLink.isUserInteractionEnabled = false
        self.autoLink.isSelected = false
        self.startBleUpgrade.isUserInteractionEnabled = false
        self.startBleUpgrade.isSelected = false

        self.setWiredMode.isUserInteractionEnabled = false
        self.setWiredMode.isSelected = false
        self.calibration.isUserInteractionEnabled = false
        self.calibration.isSelected = false

        self.startCamera.isUserInteractionEnabled = false
        self.startCamera.isSelected = false
        self.startCoreUpgrade.isUserInteractionEnabled = false
        self.startCoreUpgrade.isSelected = false
    }

    func updateUI4BleConnected() {
        self.startScan.isUserInteractionEnabled = false
        self.startScan.isSelected = false
        self.stopScan.isUserInteractionEnabled = false
        self.stopScan.isSelected = false

        self.startBind.isUserInteractionEnabled = true
        self.startBind.isSelected = true
        self.disConnect.isUserInteractionEnabled = true
        self.disConnect.isSelected = true
        self.shutdown.isUserInteractionEnabled = true
        self.shutdown.isSelected = true

        self.getInfo.isUserInteractionEnabled = true
        self.getInfo.isSelected = true
        self.autoLink.isUserInteractionEnabled = true
        self.autoLink.isSelected = true
        self.startBleUpgrade.isUserInteractionEnabled = true
        self.startBleUpgrade.isSelected = true

        self.setWiredMode.isUserInteractionEnabled = true
        self.setWiredMode.isSelected = true
        self.calibration.isUserInteractionEnabled = true
        self.calibration.isSelected = true

        self.startCamera.isUserInteractionEnabled = false
        self.startCamera.isSelected = false
        self.startCoreUpgrade.isUserInteractionEnabled = false
        self.startCoreUpgrade.isSelected = false
    }

    func getAlertStyle(style: UIAlertController.Style) -> UIAlertController.Style {
        if UIDevice.xf_DeviceType()==XFDeviceType.iPad {
            return UIAlertController.Style.alert
        }
        return style
    }

    func showAlert(alert: UIAlertController, sender: UIView) {
        if UIDevice.xf_DeviceType()==XFDeviceType.iPad {
            let popPresenter: UIPopoverPresentationController = alert.popoverPresentationController!
            popPresenter.sourceView = sender
            popPresenter.sourceRect = sender.bounds
        }
        self.present(alert, animated: true, completion: nil)
    }

    // MARK: >> Log <<
    func xf_Log(logX: NSString) {
        weak var weakSelf = self
        DispatchQueue.main.async {
            let formatter: DateFormatter = DateFormatter.init()
            formatter.dateFormat = "[HH:mm:ss.SSS]："
            let date: NSString = formatter.string(from: NSDate() as Date) as NSString

            weakSelf?.log.appendFormat("%@%@\r\n", date, logX)
            NSLog("%@%@\r\n", date, logX)

            weakSelf?.textView.text = weakSelf?.log as String?
            weakSelf?.textView.scrollRangeToVisible(NSRange.init(location: (weakSelf?.textView.text.count)!, length: 1))
        }
    }

    func BleLog(message: String) {
        NSLog("%@ ~> %@", #function, message)
    }

    // MARK:- >> Actions <<
    @objc func startScan(sender: UIButton) {
        if CTBleHelper.blePowerdOn() != 1 {
            let alert: UIAlertController = UIAlertController.init(title: "请打开手机蓝牙", message: "", preferredStyle: UIAlertController.Style.alert)
            alert.addAction(UIAlertAction.init(title: "确定", style: UIAlertAction.Style.cancel, handler: nil))
            self.showAlert(alert: alert, sender: self.startScan)
            return
        }

        if CTBleHelper.connectStatus() == 2 {
            CTBleHelper.disconnect()
        }

        self.xf_Log(logX: NSString.init(format: "开始扫描，已选择%@连接模式.", self.isAutoBind ? "自动" : "手动"))
        CTBleHelper.startScan()

        self.startScan.isUserInteractionEnabled = false
        self.startScan.isSelected = false
        self.stopScan.isUserInteractionEnabled = true
        self.stopScan.isSelected = true

        self.autoBindTimer.invalidate()
        self.autoBindTimer = Timer.init(timeInterval: 0.1, target: self, selector: #selector(autoBindTimerRun(timer:)), userInfo: nil, repeats: true)
        self.autoBindStartTime = Date().timeIntervalSince1970
        self.autoBindTimer.fireDate = Date()
    }

    @objc func stopScan(sender: UIButton) {
        self.xf_Log(logX: "手动停止扫描.")
        CTBleHelper.stopScan()

        self.autoBindTimer.invalidate()

        self.title = "CTEasyLinker"
        self.startScan.isUserInteractionEnabled = true
        self.startScan.isSelected = true
        self.stopScan.isUserInteractionEnabled = false
        self.stopScan.isSelected = false
    }

    @objc func startBind(sender: UIButton) {
        self.xf_Log(logX: "等待设备确认.")
        self.startBind.isUserInteractionEnabled = false
        self.startBind.isSelected = false

        weak var weakSelf = self
        let response: CTResponseHandler = { (code: CTBleResponseCode, msg: String) in
            DispatchQueue.main.async {
                weakSelf?.maskView.isHidden = true
                self.startBind.isUserInteractionEnabled = true
                self.startBind.isSelected = true
                if code==CTBleResponseCode.OK {
                    weakSelf?.xf_Log(logX: "设备已确认.")
                } else {
                    weakSelf?.xf_Log(logX: "设备确认失败.")
                }
            }
            } as! CTResponseHandler
        CTBleHelper.bind(response)
    }

    @objc func disConnect(sender: UIButton) {
        CTBleHelper.disconnect()
        CTBleHelper.cleanDeviceCache()
        self.resetUI()
    }

    @objc func getInfo(sender: UIButton) {
        weak var weakSelf = self

        let alert: UIAlertController = UIAlertController.init(title: "请选择要获取的信息", message: nil, preferredStyle: UIAlertController.Style.actionSheet)
        alert.addAction(UIAlertAction.init(title: "wifiStatus", style: UIAlertAction.Style.default,
                                           handler: { (action: UIAlertAction) in
                                            weakSelf?.wifiStatus()
        }))
        alert.addAction(UIAlertAction.init(title: "MAC", style: UIAlertAction.Style.default,
                                           handler: { (action: UIAlertAction) in
                                            weakSelf?.getMAC()
        }))
        alert.addAction(UIAlertAction.init(title: "Version", style: UIAlertAction.Style.default,
                                           handler: { (action: UIAlertAction) in
                                            weakSelf?.getVersion()
        }))
        alert.addAction(UIAlertAction.init(title: "Battery", style: UIAlertAction.Style.default,
                                           handler: { (action: UIAlertAction) in
                                            weakSelf?.getBattery()
        }))
        alert.addAction(UIAlertAction.init(title: "取消", style: UIAlertAction.Style.cancel,
                                           handler:nil))
        self.showAlert(alert: alert, sender: self.getInfo)
    }

    @objc func startBleUpgrade(sender: UIButton) {
        let alertTitle: String = "选择蓝牙固件版本"
        let bleVerTitles: Array = ["Release_Ble_2.0.0（归一化）", "Release_Ble_2.1.0（支持有线）"]
        let bleVersions: Array = ["BLE_2.0.0_20000", "BLE_2.1.0_20100"]

        weak var weakSelf = self
        let bleAlert: UIAlertController = UIAlertController.init(title: alertTitle, message: nil, preferredStyle: UIAlertController.Style.actionSheet)
        for i in 0..<bleVerTitles.count {
            let title: String = bleVerTitles[i]
            let version: String = bleVersions[i]
            bleAlert.addAction(UIAlertAction.init(title: title, style: UIAlertAction.Style.default,
                                                  handler: { (action: UIAlertAction) in
                                                    weakSelf?.xf_Log(logX: NSString.init(format: "当前选择版本：%@", title))
                                                    weakSelf?.startUpdateBle(verName: version as NSString)
            }))
        }
        bleAlert.addAction(UIAlertAction.init(title: "取消", style: UIAlertAction.Style.cancel, handler: nil))
        self.showAlert(alert: bleAlert, sender: self.startBleUpgrade)
    }

    @objc func autoLink(sender: UIButton) {
        if (CTConfig.getSSID()?.isEmpty)! {
            self.startNetworkConnect()
            return
        }

        weak var weakSelf = self
        let alert: UIAlertController = UIAlertController.init(title: "请选择网络连接类型", message: nil, preferredStyle: UIAlertController.Style.alert)
        alert.addAction(UIAlertAction.init(title: "STA", style: UIAlertAction.Style.default, handler: { (action: UIAlertAction) in
            CTEasyLinker.sharedEsay().smartMode = 1
            weakSelf?.startNetworkConnect()
        }))
        alert.addAction(UIAlertAction.init(title: "AP", style: UIAlertAction.Style.default, handler: { (action: UIAlertAction) in
            CTEasyLinker.sharedEsay().smartMode = 2
            weakSelf?.startNetworkConnect()
        }))
        alert.addAction(UIAlertAction.init(title: "取消", style: UIAlertAction.Style.default, handler: nil))
        self.showAlert(alert: alert, sender: self.autoLink)
    }

    @objc func startCamera(sender: UIButton) {
        self.xf_Log(logX: NSString.init(format: "开始启动摄像头[ip：%@]...", self.ip))

        weak var weakSelf = self

        //let cameraCtr: CameraHelperViewController = CameraHelperViewController()
        let cameraCtr: EasyCameraViewController = EasyCameraViewController()
        cameraCtr.ip = self.ip as String
        cameraCtr.handler_log = { (log: NSString) in
            weakSelf?.xf_Log(logX: log)
        }

        self.shouldReset = false
        self.navigationController?.present(cameraCtr, animated: true, completion: nil)
    }

    @objc func startCoreUpgrade(sender: UIButton) {
        let alertTitle: String = "选择核心固件版本"
        let kernelVerTitles: Array = ["Release_Core_3.0.0（归一化）", "Release_Core_3.1.0（有线支持）"]
        let kernelVersions: Array = ["Core_3.0.0_30000", "Core_3.1.0_30100"]

        weak var weakSelf = self
        let coreAlert: UIAlertController = UIAlertController.init(title: alertTitle, message: nil, preferredStyle: UIAlertController.Style.actionSheet)
        for i in 0..<kernelVerTitles.count {
            let title: String = kernelVerTitles[i]
            let version: String = kernelVersions[i]
            coreAlert.addAction(UIAlertAction.init(title: title, style: UIAlertAction.Style.default,
                                                   handler: { (action: UIAlertAction) in
                                                    weakSelf?.xf_Log(logX: NSString.init(format: "当前选择版本：%@", title))
                                                    weakSelf?.startUpdateCore(verName: version as NSString)
            }))
        }
        coreAlert.addAction(UIAlertAction.init(title: "取消", style: UIAlertAction.Style.cancel, handler: nil))
        self.showAlert(alert: coreAlert, sender: self.startCoreUpgrade)
    }

    @objc func calibrationTools(sender: UIButton) {
        weak var weakSelf = self

        let alert: UIAlertController = UIAlertController.init(title: "请选择 校准 选项", message: nil,
                                                              preferredStyle: UIAlertController.Style.actionSheet)
        alert.addAction(UIAlertAction.init(title: "calibration（校准）",
                                           style: UIAlertAction.Style.default,
                                           handler: { (action: UIAlertAction) in
                                            weakSelf?.calibrationAction()
        }))
        alert.addAction(UIAlertAction.init(title: "recalibration（回滚）",
                                           style: UIAlertAction.Style.default,
                                           handler: { (action: UIAlertAction) in
                                            weakSelf?.recalibration()
        }))
        alert.addAction(UIAlertAction.init(title: "restartNVDS（恢复配置）",
                                           style: UIAlertAction.Style.default,
                                           handler: { (action: UIAlertAction) in
                                            weakSelf?.restartNVDS()
        }))
        alert.addAction(UIAlertAction.init(title: "取消", style: UIAlertAction.Style.cancel,
                                           handler:nil))
        self.showAlert(alert: alert, sender: self.calibration)
    }

    @objc func wiredMode(sender: UIButton) {
        let bleVersion: Int = (CTBleHelper.deviceInfoCache()!["BleVersion"] as! NSNumber).intValue
        let coreVersion: Int = (CTBleHelper.deviceInfoCache()!["CoreVersion"] as! NSNumber).intValue

        if bleVersion < 20100 || coreVersion < 30100 {
            self.xf_Log(logX: "固件版本不符合要求，已取消.")
            return
        }

        weak var weakSelf = self

        let alert: UIAlertController = UIAlertController.init(title: "请选择设备模式", message: nil,
                                                              preferredStyle: UIAlertController.Style.actionSheet)
        alert.addAction(UIAlertAction.init(title: "混合 模式",
                                           style: UIAlertAction.Style.default,
                                           handler: { (action: UIAlertAction) in
                                            weakSelf?.setWiredMode(mode: 1)
        }))
        alert.addAction(UIAlertAction.init(title: "[仅]无线 模式",
                                           style: UIAlertAction.Style.default,
                                           handler: { (action: UIAlertAction) in
                                            weakSelf?.setWiredMode(mode: 2)
        }))
        alert.addAction(UIAlertAction.init(title: "[仅]有线 模式",
                                           style: UIAlertAction.Style.default,
                                           handler: { (action: UIAlertAction) in
                                            weakSelf?.setWiredMode(mode: 3)
        }))
        alert.addAction(UIAlertAction.init(title: "取消", style: UIAlertAction.Style.cancel,
                                           handler:nil))
        self.showAlert(alert: alert, sender: self.setWiredMode)
    }

    @objc func shutdown(sender: UIButton) {
        CTBleHelper.shutdown(nil)
        if !sender.isEqual(self.shutdown) {
            self.xf_Log(logX: "设备已自动关机.")
        }
    }

}
