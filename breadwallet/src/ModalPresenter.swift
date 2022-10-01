//
//  ModalPresenter.swift
//  breadwallet
//
//  Created by Adrian Corscadden on 2016-10-25.
//  Copyright © 2016-2019 Breadwinner AG. All rights reserved.
//

import UIKit
import LocalAuthentication
import SwiftUI
import WalletKit

// swiftlint:disable type_body_length
// swiftlint:disable cyclomatic_complexity

class ModalPresenter: Subscriber, Trackable {

    // MARK: - Public
    let keyStore: KeyStore
    lazy var supportCenter: SupportCenterContainer = {
        return SupportCenterContainer(walletAuthenticator: keyStore)
    }()
    
    init(keyStore: KeyStore, system: CoreSystem, window: UIWindow, alertPresenter: AlertPresenter?) {
        self.system = system
        self.window = window
        self.alertPresenter = alertPresenter
        self.keyStore = keyStore
        self.modalTransitionDelegate = ModalTransitionDelegate(type: .regular)
        self.wipeNavigationDelegate = StartNavigationDelegate()
        addSubscriptions()
    }
    
    deinit {
        Store.unsubscribe(self)
    }
    
    // MARK: - Private
    private let window: UIWindow
    private var alertPresenter: AlertPresenter?
    private let modalTransitionDelegate: ModalTransitionDelegate
    private let messagePresenter = MessageUIPresenter()
    private let securityCenterNavigationDelegate = SecurityCenterNavigationDelegate()
    private let verifyPinTransitionDelegate = PinTransitioningDelegate()
    private var currentRequest: PaymentRequest?
    private let wipeNavigationDelegate: StartNavigationDelegate

    private var menuNavController: UINavigationController?
    
    private let system: CoreSystem
    
    private func addSubscriptions() {

        Store.lazySubscribe(self,
                            selector: { $0.rootModal != $1.rootModal },
                            callback: { [weak self] in self?.presentModal($0.rootModal) })

        //Subscribe to prompt actions
        Store.subscribe(self, name: .promptUpgradePin, callback: { [weak self] _ in
            self?.presentUpgradePin()
        })
        Store.subscribe(self, name: .promptPaperKey, callback: { [weak self] _ in
            self?.presentWritePaperKey()
        })
        Store.subscribe(self, name: .promptBiometrics, callback: { [weak self] _ in
            self?.presentBiometricsMenuItem()
        })
        Store.subscribe(self, name: .openFile(Data()), callback: { [weak self] in
            guard let trigger = $0 else { return }
            if case .openFile(let file) = trigger {
                self?.handleFile(file)
            }
        })

        //URLs
        Store.subscribe(self, name: .receivedPaymentRequest(nil), callback: { [weak self] in
            guard let trigger = $0 else { return }
            if case let .receivedPaymentRequest(request) = trigger {
                if let request = request {
                    self?.handlePaymentRequest(request: request)
                }
            }
        })
        Store.subscribe(self, name: .scanQr, callback: { [weak self] _ in
            self?.handleScanQrURL()
        })
        Store.subscribe(self, name: .authenticateForPlatform("", true, {_ in}), callback: { [weak self] in
            guard let trigger = $0 else { return }
            if case .authenticateForPlatform(let prompt, let allowBiometricAuth, let callback) = trigger {
                self?.authenticateForPlatform(prompt: prompt, allowBiometricAuth: allowBiometricAuth, callback: callback)
            }
        })
        Store.subscribe(self, name: .confirmTransaction(nil, nil, nil, .regular, "", {_ in}), callback: { [weak self] in
            guard let trigger = $0 else { return }
            if case .confirmTransaction(let currency?, let amount?, let fee?, let displayFeeLevel, let address, let callback) = trigger {
                self?.confirmTransaction(currency: currency, amount: amount, fee: fee, displayFeeLevel: displayFeeLevel, address: address, callback: callback)
            }
        })
        Store.subscribe(self, name: .lightWeightAlert(""), callback: { [weak self] in
            guard let trigger = $0 else { return }
            if case let .lightWeightAlert(message) = trigger {
                self?.showLightWeightAlert(message: message)
            }
        })
        Store.subscribe(self, name: .showCurrency(nil), callback: { [weak self] in
            guard let trigger = $0 else { return }
            if case .showCurrency(let currency?) = trigger {
                self?.showAccountView(currency: currency, animated: true, completion: nil)
            }
        })
        
        // Push Notifications Permission Request
        Store.subscribe(self, name: .registerForPushNotificationToken) { [weak self]  _ in
            guard let top = self?.topViewController else { return }
            NotificationAuthorizer().requestAuthorization(fromViewController: top, completion: { granted in
                DispatchQueue.main.async {
                    if granted {
                        print("[PUSH] notification authorization granted")
                    } else {
                        // TODO: log event
                        print("[PUSH] notification authorization denied")
                    }
                }
            })
        }
        
        // in-app notifications
        Store.subscribe(self, name: .showInAppNotification(nil)) { [weak self] (trigger) in
            guard let `self` = self else { return }
            guard let topVC = self.topViewController else { return }
            
            if case let .showInAppNotification(notification?)? = trigger {
                let display: (UIImage?) -> Void = { (image) in
                    let notificationVC = InAppNotificationViewController(notification, image: image)
                    
                    let navigationController = ModalNavigationController(rootViewController: notificationVC)
                    navigationController.setClearNavbar()
                    
                    topVC.present(navigationController, animated: true, completion: nil)
                }
                
                // Fetch the image first so that it's ready when we display the notification
                // screen to the user.
                if let imageUrl = notification.imageUrl, !imageUrl.isEmpty {
                    UIImage.fetchAsync(from: imageUrl) { (image) in
                        display(image)
                    }
                } else {
                    display(nil)
                }
                
            }
        }
        
        Store.subscribe(self, name: .openPlatformUrl("")) { [weak self] in
            guard let trigger = $0 else { return }
            if case let .openPlatformUrl(url) = trigger {
                self?.presentPlatformWebViewController(url)
            }
        }
        
        Store.subscribe(self, name: .handleGift(URL(string: "foo.com")!)) { [weak self] in
            guard let trigger = $0, let `self` = self else { return }
            if case let .handleGift(url) = trigger {
                if let gift = QRCode(url: url, viewModel: nil) {
                    let eventName = self.makeEventName([EventContext.gift.name, Event.redeem.name])
                    self.saveEvent(eventName, attributes: ["\(eventName).method": "link"])
                    self.handleGift(qrCode: gift)
                }
            }
        }
        
        Store.subscribe(self, name: .reImportGift(nil)) { [weak self] in
            guard let trigger = $0, let `self` = self else { return }
            if case let .reImportGift(viewModel) = trigger {
                guard let gift = viewModel?.gift else { return assertionFailure() }
                let code = QRCode(url: URL(string: gift.url!)!, viewModel: viewModel)
                guard let wallet = Currencies.btc.instance?.wallet else { return assertionFailure() }
                let eventName = self.makeEventName([EventContext.gift.name, Event.redeem.name])
                self.saveEvent(eventName, attributes: ["\(eventName).method": "reclaim"])
                self.presentKeyImport(wallet: wallet, scanResult: code)
            }
        }
    }
    
    private func handleGift(qrCode: QRCode) {
        guard let wallet = Currencies.btc.instance?.wallet else { return }
        guard case .gift(let key, _) = qrCode else { return }
        guard let privKey = Key.createFromString(asPrivate: key) else { return }
        wallet.createSweeper(forKey: privKey) { result in
            DispatchQueue.main.async {
                let giftView = RedeemGiftViewController(qrCode: qrCode, wallet: wallet, sweeperResult: result)
                self.topViewController?.present(giftView, animated: true, completion: nil)
            }
        }
    }

    private func presentModal(_ type: RootModal) {
        guard let vc = rootModalViewController(type) else {
            Store.perform(action: RootModalActions.Present(modal: .none))
            return
        }
        vc.transitioningDelegate = modalTransitionDelegate
        vc.modalPresentationStyle = .overFullScreen
        vc.modalPresentationCapturesStatusBarAppearance = true
        topViewController?.present(vc, animated: true) {
            Store.perform(action: RootModalActions.Present(modal: .none))
            Store.trigger(name: .hideStatusBar)
        }
    }

    private func rootModalViewController(_ type: RootModal) -> UIViewController? {
        switch type {
        case .none:
            return nil
        case .send(let currency):
            return makeSendView(currency: currency)
        case .receive(let currency):
            return makeReceiveView(currency: currency, isRequestAmountVisible: (currency.urlSchemes?.first != nil))
        case .loginScan:
            presentLoginScan()
            return nil
        case .requestAmount(let currency, let address):
            let requestVc = RequestAmountViewController(currency: currency, receiveAddress: address)
            
            requestVc.shareAddress = { [weak self] uri, qrCode in
                self?.messagePresenter.presenter = self?.topViewController
                self?.messagePresenter.presentShareSheet(text: uri, image: qrCode)
            }
                        
            return ModalViewController(childViewController: requestVc)
        case .receiveLegacy:
            guard let btc = Currencies.btc.instance else { return nil }
            return makeReceiveView(currency: btc, isRequestAmountVisible: false, isBTCLegacy: true)
        case .gift :
            guard let currency = Currencies.btc.instance else { return nil }
            guard let wallet = system.wallet(for: currency),
                let kvStore = Backend.kvStore else { assertionFailure(); return nil }
            let sender = Sender(wallet: wallet, authenticator: keyStore, kvStore: kvStore)
            let giftView = GiftViewController(sender: sender, wallet: wallet, currency: currency)
            
            giftView.presentVerifyPin = { [weak self, weak giftView] bodyText, success in
                guard let `self` = self else { return }
                let vc = VerifyPinViewController(bodyText: bodyText,
                                                 pinLength: Store.state.pinLength,
                                                 walletAuthenticator: self.keyStore,
                                                 pinAuthenticationType: .transactions,
                                                 success: success)
                vc.transitioningDelegate = self.verifyPinTransitionDelegate
                vc.modalPresentationStyle = .overFullScreen
                vc.modalPresentationCapturesStatusBarAppearance = true
                giftView?.view.isFrameChangeBlocked = true
                giftView?.present(vc, animated: true, completion: nil)
            }
            giftView.onPublishSuccess = { [weak self] in
                self?.saveEvent("gift.send")
                self?.alertPresenter?.presentAlert(.sendSuccess, completion: {})
            }
            
            topViewController?.present(giftView, animated: true, completion: {
                Store.perform(action: RootModalActions.Present(modal: .none))
            })
            return nil
        }
    }

    private func makeSendView(currency: Currency) -> UIViewController? {
        guard let wallet = system.wallet(for: currency),
            let kvStore = Backend.kvStore else { assertionFailure(); return nil }
        guard !(currency.state?.isRescanning ?? false) else {
            let alert = UIAlertController(title: S.Alert.error, message: S.Send.isRescanning, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: S.Button.ok, style: .cancel, handler: nil))
            topViewController?.present(alert, animated: true, completion: nil)
            return nil
        }

        let sender = Sender(wallet: wallet, authenticator: keyStore, kvStore: kvStore)
        let sendVC = SendViewController(sender: sender,
                                        initialRequest: currentRequest)
        currentRequest = nil

        let root = ModalViewController(childViewController: sendVC)
        sendVC.presentScan = presentScan(parent: root, currency: currency)
        sendVC.presentVerifyPin = { [weak self, weak root] bodyText, success in
            guard let `self` = self, let root = root else { return }
            let vc = VerifyPinViewController(bodyText: bodyText,
                                             pinLength: Store.state.pinLength,
                                             walletAuthenticator: self.keyStore,
                                             pinAuthenticationType: .transactions,
                                             success: success)
            vc.transitioningDelegate = self.verifyPinTransitionDelegate
            vc.modalPresentationStyle = .overFullScreen
            vc.modalPresentationCapturesStatusBarAppearance = true
            root.view.isFrameChangeBlocked = true
            root.present(vc, animated: true, completion: nil)
        }
        sendVC.onPublishSuccess = { [weak self] in
            self?.alertPresenter?.presentAlert(.sendSuccess, completion: {})
        }
        return root
    }

    private func makeReceiveView(currency: Currency, isRequestAmountVisible: Bool, isBTCLegacy: Bool = false) -> UIViewController? {
        let receiveVC = ReceiveViewController(currency: currency, isRequestAmountVisible: isRequestAmountVisible, isBTCLegacy: isBTCLegacy)
        let root = ModalViewController(childViewController: receiveVC)
        
        receiveVC.shareAddress = { [weak self, weak root] address, qrCode in
            guard let `self` = self, let root = root else { return }
            self.messagePresenter.presenter = root
            self.messagePresenter.presentShareSheet(text: address, image: qrCode)
        }
        
        return root
    }

    private func presentLoginScan() {
        guard let top = topViewController else { return }
        let present = presentScan(parent: top, currency: nil)
        present { [unowned self] scanResult in
            guard let scanResult = scanResult else { return }
            switch scanResult {
            case .paymentRequest(let request):
                let message = String(format: S.Scanner.paymentPromptMessage, request.currency.name)
                let alert = UIAlertController.confirmationAlert(title: S.Scanner.paymentPrompTitle, message: message) {
                    self.currentRequest = request
                    self.presentModal(.send(currency: request.currency))
                }
                top.present(alert, animated: true, completion: nil)
                
            case .privateKey:
                let alert = UIAlertController(title: S.Settings.importTile, message: nil, preferredStyle: .actionSheet)
                alert.addAction(UIAlertAction(title: "BTC", style: .default, handler: { _ in
                    if let wallet = Currencies.btc.instance?.wallet {
                        self.presentKeyImport(wallet: wallet, scanResult: scanResult)
                    }
                }))
                alert.addAction(UIAlertAction(title: S.Button.cancel, style: .cancel, handler: nil))
                top.present(alert, animated: true, completion: nil)
            case .deepLink(let url):
                UIApplication.shared.open(url)
            case .invalid:
                break
            case .gift:
                let eventName = makeEventName([EventContext.gift.name, Event.redeem.name])
                saveEvent(eventName, attributes: ["\(eventName).method": "scan"])
                self.handleGift(qrCode: scanResult)
            }
        }
    }
    
    // MARK: Settings
    func presentMenu() {
        let menuNav = UINavigationController()
        menuNav.setDarkStyle()
        
        // MARK: Bitcoin Menu
        var btcItems: [MenuItem] = []
        if let btc = Currencies.btc.instance, let btcWallet = btc.wallet {
            
            // Rescan
            var rescan = MenuItem(title: S.Settings.sync, callback: { [unowned self] in
                menuNav.pushViewController(ReScanViewController(system: self.system, wallet: btcWallet), animated: true)
            })
            rescan.shouldShow = { [unowned self] in
                self.system.connectionMode(for: btc) == .p2p_only
            }
            btcItems.append(rescan)
            
            // Nodes
            var nodeSelection = MenuItem(title: S.NodeSelector.title, callback: {
                let nodeSelector = NodeSelectorViewController(wallet: btcWallet)
                menuNav.pushViewController(nodeSelector, animated: true)
            })
            nodeSelection.shouldShow = { [unowned self] in
                self.system.connectionMode(for: btc) == .p2p_only
            }
            btcItems.append(nodeSelection)
            
            btcItems.append(MenuItem(title: S.Settings.importTile, callback: {
                menuNav.dismiss(animated: true, completion: { [weak self] in
                    guard let `self` = self else { return }
                    self.presentKeyImport(wallet: btcWallet)
                })
            }))

            let viewLegacyAddress = MenuItem(title: S.Settings.viewLegacyAddress, callback: {
                Store.perform(action: RootModalActions.Present(modal: .receiveLegacy))
            })

            btcItems.append(viewLegacyAddress)
        }
        var btcMenu = MenuItem(title: String(format: S.Settings.currencyPageTitle, Currencies.btc.instance?.name ?? "Bitcoin"), subMenu: btcItems, rootNav: menuNav)
        btcMenu.shouldShow = { return !btcItems.isEmpty }
        
        // MARK: Ethereum Menu
        var ethItems: [MenuItem] = []
        if let eth = Currencies.eth.instance, let ethWallet = eth.wallet {
            if system.connectionMode(for: eth) == .p2p_only {
                // Rescan
                ethItems.append(MenuItem(title: S.Settings.sync, callback: { [weak self] in
                    guard let `self` = self else { return }
                    menuNav.pushViewController(ReScanViewController(system: self.system, wallet: ethWallet), animated: true)
                }))
            }
        }
        var ethMenu = MenuItem(title: String(format: S.Settings.currencyPageTitle, Currencies.eth.instance?.name ?? "Ethereum"), subMenu: ethItems, rootNav: menuNav)
        ethMenu.shouldShow = { return !ethItems.isEmpty }

        // MARK: Preferences
        let preferencesItems: [MenuItem] = [
            // Display Currency
            MenuItem(title: S.Settings.currency, accessoryText: {
                let code = Store.state.defaultCurrencyCode
                let components: [String: String] = [NSLocale.Key.currencyCode.rawValue: code]
                let identifier = Locale.identifier(fromComponents: components)
                return Locale(identifier: identifier).currencyCode ?? ""
            }, callback: {
                menuNav.pushViewController(DefaultCurrencyViewController(), animated: true)
            }),
            
            btcMenu,
            ethMenu,

            // Reset Wallets
            MenuItem(title: S.Settings.resetCurrencies, callback: { [weak self] in
                guard let `self` = self else { return }
                menuNav.dismiss(animated: true, completion: {
                    self.system.resetToDefaultCurrencies()
                })
            }),
            
            // Notifications
            MenuItem(title: S.Settings.notifications, callback: {
                menuNav.pushViewController(PushNotificationsViewController(), animated: true)
            })
        ]
        
        // MARK: Security Settings
        var securityItems: [MenuItem] = [
            // Unlink
            MenuItem(title: S.Settings.wipe) { [weak self] in
                guard let `self` = self, let vc = self.topViewController else { return }
                RecoveryKeyFlowController.enterUnlinkWalletFlow(from: vc,
                                                                keyMaster: self.keyStore,
                                                                phraseEntryReason: .validateForWipingWallet({ [weak self] in
                                                                    self?.wipeWallet()
                                                                }))
            },
            
            // Update PIN
            MenuItem(title: S.UpdatePin.updateTitle) { [weak self] in
                guard let `self` = self else { return }
                let updatePin = UpdatePinViewController(keyMaster: self.keyStore, type: .update)
                menuNav.pushViewController(updatePin, animated: true)
            },
            
            // Biometrics
            MenuItem(title: LAContext.biometricType() == .face ? S.SecurityCenter.Cells.faceIdTitle : S.SecurityCenter.Cells.touchIdTitle) { [weak self] in
                guard let `self` = self else { return }
                self.presentBiometricsMenuItem()
            },
            
            // Paper key
            MenuItem(title: S.SecurityCenter.Cells.paperKeyTitle) { [weak self] in
                guard let `self` = self else { return }
                self.presentWritePaperKey(fromViewController: menuNav)
            },

            // Portfolio data for widget
            MenuItem(title: S.Settings.shareWithWidget,
                     accessoryText: { [weak self] in
                         self?.system.widgetDataShareService.sharingEnabled ?? false ? "ON" : "OFF"
                     },
                     callback: { [weak self] in
                         self?.system.widgetDataShareService.sharingEnabled.toggle()
                         (menuNav.topViewController as? MenuViewController)?.reloadMenu()
                     })
        ]

        // MARK: Root Menu
        var rootItems: [MenuItem] = [
            // Scan QR Code
            MenuItem(title: S.MenuButton.scan, icon: MenuItem.Icon.scan) { [weak self] in
                self?.presentLoginScan()
            },
            
            // Manage Wallets
            MenuItem(title: S.MenuButton.manageWallets, icon: MenuItem.Icon.wallet) { [weak self] in
                guard let `self` = self, let assetCollection = self.system.assetCollection else { return }
                let vc = ManageWalletsViewController(assetCollection: assetCollection, coreSystem: self.system)
                menuNav.pushViewController(vc, animated: true)
            },
            
            // Preferences
            MenuItem(title: S.Settings.preferences, icon: MenuItem.Icon.preferences, subMenu: preferencesItems, rootNav: menuNav),
            
            // Security
            MenuItem(title: S.MenuButton.security,
                     icon: #imageLiteral(resourceName: "security"),
                     subMenu: securityItems,
                     rootNav: menuNav,
                     faqButton: UIButton.buildFaqButton(articleId: ArticleIds.securityCenter)),

            // About
            MenuItem(title: S.Settings.about, icon: MenuItem.Icon.about) {
                menuNav.pushViewController(AboutViewController(), animated: true)
            },
            
            // Export Transfer History
            MenuItem(title: S.Settings.exportTransfers, icon: MenuItem.Icon.export) { [weak self] in
                self?.presentExportTransfers()
            }
        ]

        // MARK: Developer/QA Menu
        
        if E.isSimulator || E.isDebug || E.isTestFlight {
            var developerItems = [MenuItem]()
            
            developerItems.append(MenuItem(title: S.Settings.sendLogs) { [weak self] in
                self?.showEmailLogsModal()
            })

            developerItems.append(MenuItem(title: "Lock Wallet") {
                Store.trigger(name: .lock)
            })
            
            developerItems.append(MenuItem(title: "Unlink Wallet (no prompt)") {
                Store.trigger(name: .wipeWalletNoPrompt)
            })
            
            if E.isDebug { // for dev/debugging use only
                // For test wallets with a PIN of 111111, the PIN is auto entered on startup.
                developerItems.append(MenuItem(title: "Auto-enter PIN",
                                               accessoryText: { UserDefaults.debugShouldAutoEnterPIN ? "ON" : "OFF" },
                                               callback: {
                                                _ = UserDefaults.toggleAutoEnterPIN()
                                                (menuNav.topViewController as? MenuViewController)?.reloadMenu()
                }))
            }
            
            // For test wallets, suppresses the paper key prompt on the home screen.
            developerItems.append(MenuItem(title: "Suppress paper key prompt",
                                           accessoryText: { UserDefaults.debugShouldSuppressPaperKeyPrompt ? "ON" : "OFF" },
                                           callback: {
                                            _ = UserDefaults.toggleSuppressPaperKeyPrompt()
                                            (menuNav.topViewController as? MenuViewController)?.reloadMenu()
            }))
            
            // Shows a preview of the paper key.
            if UserDefaults.debugShouldAutoEnterPIN, let paperKey = keyStore.seedPhrase(pin: "111111") {
                let words = paperKey.components(separatedBy: " ")
                let timestamp = (try? keyStore.loadAccount().map { $0.timestamp }.get()) ?? Date.zeroValue()
                let preview = "\(words[0]) \(words[1])... (\(DateFormatter.mediumDateFormatter.string(from: timestamp))"
                developerItems.append(MenuItem(title: "Paper key preview",
                                               accessoryText: { UserDefaults.debugShouldShowPaperKeyPreview ? preview : "" },
                                               callback: {
                                                _ = UserDefaults.togglePaperKeyPreview()
                                                (menuNav.topViewController as? MenuViewController)?.reloadMenu()
                }))
            }
                        
            developerItems.append(MenuItem(title: "Reset User Defaults",
                                           callback: {
                                            UserDefaults.resetAll()
                                            menuNav.showAlert(title: "", message: "User defaults reset")
                                            (menuNav.topViewController as? MenuViewController)?.reloadMenu()
            }))

            developerItems.append(MenuItem(title: "Clear Core persistent storage and exit",
                                           callback: { [weak self] in
                                            guard let `self` = self else { return }
                                            self.system.shutdown {
                                                fatalError("forced exit")
                                            }
            }))
            
            developerItems.append(
                MenuItem(title: "API Host",
                         accessoryText: { Backend.apiClient.host }, callback: {
                            let alert = UIAlertController(title: "Set API Host", message: "Clear and save to reset", preferredStyle: .alert)
                            alert.addTextField(configurationHandler: { textField in
                                textField.text = Backend.apiClient.host
                                textField.keyboardType = .URL
                                textField.clearButtonMode = .always
                            })

                            alert.addAction(UIAlertAction(title: "Save", style: .default) { (_) in
                                guard let newHost = alert.textFields?.first?.text, !newHost.isEmpty else {
                                    UserDefaults.debugBackendHost = nil
                                    Backend.apiClient.host = C.backendHost
                                    (menuNav.topViewController as? MenuViewController)?.reloadMenu()
                                    return
                                }
                                let originalHost = Backend.apiClient.host
                                Backend.apiClient.host = newHost
                                Backend.apiClient.me { (success, _, _) in
                                    if success {
                                        UserDefaults.debugBackendHost = newHost
                                        (menuNav.topViewController as? MenuViewController)?.reloadMenu()
                                    } else {
                                        Backend.apiClient.host = originalHost
                                    }
                                }
                            })

                            alert.addAction(UIAlertAction(title: S.Button.cancel, style: .cancel, handler: nil))

                            menuNav.present(alert, animated: true, completion: nil)
                }))

            developerItems.append(
                MenuItem(title: "Web Platform Bundle",
                         accessoryText: { C.webBundle }, callback: {
                            let alert = UIAlertController(title: "Set bundle name", message: "Clear and save to reset", preferredStyle: .alert)
                            alert.addTextField(configurationHandler: { textField in
                                textField.text = C.webBundle
                                textField.keyboardType = .URL
                                textField.clearButtonMode = .always
                            })

                            alert.addAction(UIAlertAction(title: "Save", style: .default) { (_) in
                                guard let newBundleName = alert.textFields?.first?.text, !newBundleName.isEmpty else {
                                    UserDefaults.debugWebBundleName = nil
                                    (menuNav.topViewController as? MenuViewController)?.reloadMenu()
                                    return
                                }

                                guard let bundle = AssetArchive(name: newBundleName, apiClient: Backend.apiClient) else { return assertionFailure() }
                                bundle.update { error in
                                    DispatchQueue.main.async {
                                        guard error == nil else {
                                            let alert = UIAlertController(title: S.Alert.error,
                                                                          message: "Unable to fetch bundle named \(newBundleName)",
                                                preferredStyle: .alert)
                                            alert.addAction(UIAlertAction(title: S.Button.ok, style: .default, handler: nil))
                                            menuNav.present(alert, animated: true, completion: nil)
                                            return
                                        }
                                        UserDefaults.debugWebBundleName = newBundleName
                                        (menuNav.topViewController as? MenuViewController)?.reloadMenu()
                                    }
                                }
                            })

                            alert.addAction(UIAlertAction(title: S.Button.cancel, style: .cancel, handler: nil))

                            menuNav.present(alert, animated: true, completion: nil)
                }))

            developerItems.append(
                MenuItem(title: "Web Platform Debug URL",
                         accessoryText: { UserDefaults.platformDebugURL?.absoluteString ?? "<not set>" }, callback: {
                            let alert = UIAlertController(title: "Set debug URL", message: "Clear and save to reset", preferredStyle: .alert)
                            alert.addTextField(configurationHandler: { textField in
                                textField.text = UserDefaults.platformDebugURL?.absoluteString ?? ""
                                textField.keyboardType = .URL
                                textField.clearButtonMode = .always
                            })

                            alert.addAction(UIAlertAction(title: "Save", style: .default) { (_) in
                                guard let input = alert.textFields?.first?.text,
                                    !input.isEmpty,
                                    let debugURL = URL(string: input) else {
                                    UserDefaults.platformDebugURL = nil
                                    (menuNav.topViewController as? MenuViewController)?.reloadMenu()
                                    return
                                }
                                UserDefaults.platformDebugURL = debugURL
                                (menuNav.topViewController as? MenuViewController)?.reloadMenu()
                            })

                            alert.addAction(UIAlertAction(title: S.Button.cancel, style: .cancel, handler: nil))

                            menuNav.present(alert, animated: true, completion: nil)
                }))

            rootItems.append(MenuItem(title: "Developer Options", icon: nil, subMenu: developerItems, rootNav: menuNav, faqButton: nil))
        }
                
        let rootMenu = MenuViewController(items: rootItems,
                                          title: S.Settings.title)
        rootMenu.addCloseNavigationItem(side: .right)
        menuNav.viewControllers = [rootMenu]
        
        self.menuNavController = menuNav
        
        self.topViewController?.present(menuNav, animated: true, completion: nil)
    }
    
    private func presentScan(parent: UIViewController, currency: Currency?) -> PresentScan {
        return { [weak parent] scanCompletion in
            guard ScanViewController.isCameraAllowed else {
                self.saveEvent("scan.cameraDenied")
                if let parent = parent {
                    ScanViewController.presentCameraUnavailableAlert(fromRoot: parent)
                }
                return
            }
            
            let vc = ScanViewController(forPaymentRequestForCurrency: currency, completion: { scanResult in
                scanCompletion(scanResult)
                parent?.view.isFrameChangeBlocked = false
            })
            parent?.view.isFrameChangeBlocked = true
            parent?.present(vc, animated: true, completion: {})
        }
    }

    private func presentWritePaperKey(fromViewController vc: UIViewController) {
        RecoveryKeyFlowController.enterRecoveryKeyFlow(pin: nil,
                                                       keyMaster: self.keyStore,
                                                       from: vc,
                                                       context: .none,
                                                       dismissAction: nil)
    }

    private func presentPlatformWebViewController(_ mountPoint: String) {
        let vc = BRWebViewController(bundleName: C.webBundle,
                                     mountPoint: mountPoint,
                                     walletAuthenticator: keyStore,
                                     system: system)
        vc.startServer()
        vc.preload()
        vc.modalPresentationStyle = .overFullScreen
        self.topViewController?.present(vc, animated: true, completion: nil)
    }

    private func wipeWallet() {
        let alert = UIAlertController.confirmationAlert(title: S.WipeWallet.alertTitle,
                                                        message: S.WipeWallet.alertMessage,
                                                        okButtonTitle: S.WipeWallet.wipe,
                                                        cancelButtonTitle: S.Button.cancel,
                                                        isDestructiveAction: true) {
                                                            self.topViewController?.dismiss(animated: true, completion: {
                                                                Store.trigger(name: .wipeWalletNoPrompt)
                                                            })
        }
        topViewController?.present(alert, animated: true, completion: nil)
    }
    
    private func presentKeyImport(wallet: Wallet, scanResult: QRCode? = nil) {
        let nc = ModalNavigationController()
        nc.setClearNavbar()
        nc.setWhiteStyle()
        let start = ImportKeyViewController(wallet: wallet, initialQRCode: scanResult)
        start.addCloseNavigationItem(tintColor: .white)
        start.navigationItem.title = S.Import.title
        let faqButton = UIButton.buildFaqButton(articleId: ArticleIds.importWallet, currency: wallet.currency)
        faqButton.tintColor = .white
        start.navigationItem.rightBarButtonItems = [UIBarButtonItem.negativePadding, UIBarButtonItem(customView: faqButton)]
        nc.viewControllers = [start]
        topViewController?.present(nc, animated: true, completion: nil)
    }

    // MARK: - Prompts

    func presentExportTransfers() {
        let alert = UIAlertController(title: S.ExportTransfers.header, message: S.ExportTransfers.body, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: S.ExportTransfers.confirmExport, style: .default, handler: { (_) in
            self.topViewController?.present(BRActivityViewController(message: ""), animated: true, completion: nil)
            DispatchQueue.global(qos: .background).async {
                guard let csvFile = CsvExporter.instance.exportTransfers(wallets: self.system.wallets) else {
                    DispatchQueue.main.async {
                        self.topViewController?.dismiss(animated: true) {
                            self.topViewController?.showAlert(
                                title: S.ExportTransfers.exportFailedTitle,
                                message: S.ExportTransfers.exportFailedBody)
                        }
                    }
                    return
                }
                DispatchQueue.main.async {
                    self.topViewController?.dismiss(animated: true) {
                        let activityViewController = UIActivityViewController(activityItems: [csvFile], applicationActivities: nil)
                        self.topViewController?.present(activityViewController, animated: true, completion: nil)
                    }
                }
            }
        }))
        alert.addAction(UIAlertAction(title: S.Button.cancel, style: .cancel, handler: nil))
        topViewController?.present(alert, animated: true, completion: nil)
    }
    
    func presentBiometricsMenuItem() {
        let biometricsSettings = BiometricsSettingsViewController(self.keyStore)
        biometricsSettings.addCloseNavigationItem(tintColor: .white)
        let nc = ModalNavigationController(rootViewController: biometricsSettings)
        nc.setWhiteStyle()
        nc.isNavigationBarHidden = true
        nc.delegate = securityCenterNavigationDelegate
        topViewController?.present(nc, animated: true, completion: nil)
    }

    func presentWritePaperKey() {
        guard let vc = topViewController else { return }
        presentWritePaperKey(fromViewController: vc)
    }

    func presentUpgradePin() {
        let updatePin = UpdatePinViewController(keyMaster: keyStore, type: .update)
        let nc = ModalNavigationController(rootViewController: updatePin)
        nc.setDefaultStyle()
        nc.isNavigationBarHidden = true
        nc.delegate = securityCenterNavigationDelegate
        updatePin.addCloseNavigationItem()
        topViewController?.present(nc, animated: true, completion: nil)
    }

    private func handleFile(_ file: Data) {
        //TODO:CRYPTO payment request -- what is this use case?
        /*
        if let request = PaymentProtocolRequest(data: file) {
            if let topVC = topViewController as? ModalViewController {
                let attemptConfirmRequest: () -> Bool = {
                    if let send = topVC.childViewController as? SendViewController {
                        send.confirmProtocolRequest(request)
                        return true
                    }
                    return false
                }
                if !attemptConfirmRequest() {
                    modalTransitionDelegate.reset()
                    topVC.dismiss(animated: true, completion: {
                        Store.perform(action: RootModalActions.Present(modal: .send(currency: Currencies.btc)))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: { //This is a hack because present has no callback
                            _ = attemptConfirmRequest()
                        })
                    })
                }
            }
        } else if let ack = PaymentProtocolACK(data: file) {
            if let memo = ack.memo {
                let alert = UIAlertController(title: "", message: memo, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: S.Button.ok, style: .cancel, handler: nil))
                topViewController?.present(alert, animated: true, completion: nil)
            }
        //TODO - handle payment type
        } else {
            let alert = UIAlertController(title: S.Alert.error, message: S.PaymentProtocol.Errors.corruptedDocument, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: S.Button.ok, style: .cancel, handler: nil))
            topViewController?.present(alert, animated: true, completion: nil)
        }
 */
    }

    private func handlePaymentRequest(request: PaymentRequest) {
        self.currentRequest = request
        guard !Store.state.isLoginRequired else { presentModal(.send(currency: request.currency)); return }

        showAccountView(currency: request.currency, animated: false) {
            self.presentModal(.send(currency: request.currency))
        }
    }
    
    private func showAccountView(currency: Currency, animated: Bool, completion: (() -> Void)?) {
        let pushAccountView = {
            guard let nc = self.topViewController?.navigationController as? RootNavigationController,
                nc.viewControllers.count == 1 else { return }
            let accountViewController = AccountViewController(currency: currency, wallet: self.system.wallet(for: currency))
            nc.pushViewController(accountViewController, animated: animated)
            completion?()
        }
        
        if let accountVC = topViewController as? AccountViewController {
            if accountVC.currency == currency {
                completion?()
            } else {
                accountVC.navigationController?.popToRootViewController(animated: false)
                pushAccountView()
            }
        } else if topViewController is HomeScreenViewController {
            pushAccountView()
        } else if let presented = UIApplication.shared.keyWindow?.rootViewController?.presentedViewController {
            if let nc = presented.presentingViewController as? RootNavigationController, nc.viewControllers.count > 1 {
                // modal on top of another account screen
                presented.dismiss(animated: false) {
                    self.showAccountView(currency: currency, animated: animated, completion: completion)
                }
            } else {
                presented.dismiss(animated: true) {
                    pushAccountView()
                }
            }
        }
    }

    private func handleScanQrURL() {
        guard !Store.state.isLoginRequired else { presentLoginScan(); return }
        if topViewController is AccountViewController || topViewController is LoginViewController {
            presentLoginScan()
        } else {
            if let presented = UIApplication.shared.keyWindow?.rootViewController?.presentedViewController {
                presented.dismiss(animated: true, completion: {
                    self.presentLoginScan()
                })
            }
        }
    }

    private func authenticateForPlatform(prompt: String, allowBiometricAuth: Bool, callback: @escaping (PlatformAuthResult) -> Void) {
        if allowBiometricAuth && keyStore.isBiometricsEnabledForUnlocking {
            keyStore.authenticate(withBiometricsPrompt: prompt, completion: { result in
                switch result {
                case .success:
                    return callback(.success(nil))
                case .cancel:
                    return callback(.cancelled)
                case .failure:
                    self.verifyPinForPlatform(prompt: prompt, callback: callback)
                case .fallback:
                    self.verifyPinForPlatform(prompt: prompt, callback: callback)
                }
            })
        } else {
            self.verifyPinForPlatform(prompt: prompt, callback: callback)
        }
    }

    private func verifyPinForPlatform(prompt: String, callback: @escaping (PlatformAuthResult) -> Void) {
        let verify = VerifyPinViewController(bodyText: prompt,
                                             pinLength: Store.state.pinLength,
                                             walletAuthenticator: keyStore,
                                             pinAuthenticationType: .unlocking,
                                             success: { pin in
                                                callback(.success(pin))
        })
        verify.didCancel = { callback(.cancelled) }
        verify.transitioningDelegate = verifyPinTransitionDelegate
        verify.modalPresentationStyle = .overFullScreen
        verify.modalPresentationCapturesStatusBarAppearance = true
        topViewController?.present(verify, animated: true, completion: nil)
    }
    
    private func confirmTransaction(currency: Currency, amount: Amount, fee: Amount, displayFeeLevel: FeeLevel, address: String, callback: @escaping (Bool) -> Void) {
        let confirm = ConfirmationViewController(amount: amount,
                                                 fee: fee,
                                                 displayFeeLevel: displayFeeLevel,
                                                 address: address,
                                                 isUsingBiometrics: false,
                                                 currency: currency,
                                                 shouldShowMaskView: true)
        confirm.successCallback = {
            callback(true)
        }
        confirm.cancelCallback = {
            callback(false)
        }
        topViewController?.present(confirm, animated: true, completion: nil)
    }

    private var topViewController: UIViewController? {
        var viewController = window.rootViewController
        if let nc = viewController as? UINavigationController {
            viewController = nc.topViewController
        }
        while viewController?.presentedViewController != nil {
            viewController = viewController?.presentedViewController
        }
        return viewController
    }

    private func showLightWeightAlert(message: String) {
        let alert = LightWeightAlert(message: message)
        let view = UIApplication.shared.keyWindow!
        view.addSubview(alert)
        alert.constrain([
            alert.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            alert.centerYAnchor.constraint(equalTo: view.centerYAnchor) ])
        alert.background.effect = nil
        UIView.animate(withDuration: 0.6, animations: {
            alert.background.effect = alert.effect
        }, completion: { _ in
            UIView.animate(withDuration: 0.6, delay: 1.0, options: [], animations: {
                alert.background.effect = nil
            }, completion: { _ in
                alert.removeFromSuperview()
            })
        })
    }

    private func showEmailLogsModal() {
        self.messagePresenter.presenter = self.topViewController
        self.messagePresenter.presentEmailLogs()
    }
}

class SecurityCenterNavigationDelegate: NSObject, UINavigationControllerDelegate {
    
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {

        guard let coordinator = navigationController.topViewController?.transitionCoordinator else { return }

        if coordinator.isInteractive {
            coordinator.notifyWhenInteractionChanges { context in
                //We only want to style the view controller if the
                //pop animation wasn't cancelled
                if !context.isCancelled {
                    self.setStyle(navigationController: navigationController)
                }
            }
        } else {
            setStyle(navigationController: navigationController)
        }
    }

    func setStyle(navigationController: UINavigationController) {
        navigationController.isNavigationBarHidden = false
        navigationController.setDefaultStyle()
    }
}
