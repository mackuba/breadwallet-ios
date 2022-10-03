//
//  HomeScreenViewController.swift
//  breadwallet
//
//  Created by Adrian Corscadden on 2017-11-27.
//  Copyright © 2017-2019 Breadwinner AG. All rights reserved.
//

import UIKit

class HomeScreenViewController: UIViewController, Subscriber, Trackable {

    private let walletAuthenticator: WalletAuthenticator
    private let widgetDataShareService: WidgetDataShareService
    private let assetList = AssetListTableView()
    private let subHeaderView = UIView()
    private let logo = UIImageView(image: UIImage(named: "LogoGradientSmall"))
    private let total = UILabel(font: Theme.h1Title, color: Theme.primaryText)
    private let totalAssetsLabel = UILabel(font: Theme.caption, color: Theme.tertiaryText)
    private let debugLabel = UILabel(font: .customBody(size: 12.0), color: .transparentWhiteText) // debug info
    private let prompt = UIView()
    private var promptHiddenConstraint: NSLayoutConstraint!
    private let toolbar = UIToolbar()

    var didSelectCurrency: ((Currency) -> Void)?
    var didTapManageWallets: (() -> Void)?
    var didTapMenu: (() -> Void)?
    
    var okToShowPrompts: Bool {
        //Don't show any prompts on the first couple launches
        guard UserDefaults.appLaunchCount > 2 else { return false }
        
        // On the initial display we need to load the wallets in the asset list table view first.
        // There's already a lot going on, so don't show the home-screen prompts right away.
        return !Store.state.wallets.isEmpty
    }
    
    private lazy var totalAssetsNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.isLenient = true
        formatter.numberStyle = .currency
        formatter.generatesDecimalNumbers = true
        return formatter
    }()

    // MARK: -
    
    init(walletAuthenticator: WalletAuthenticator, widgetDataShareService: WidgetDataShareService) {
        self.walletAuthenticator = walletAuthenticator
        self.widgetDataShareService = widgetDataShareService
        super.init(nibName: nil, bundle: nil)
    }

    deinit {
        Store.unsubscribe(self)
    }
    
    func reload() {
        setInitialData()
        setupSubscriptions()
        assetList.reload()
        attemptShowPrompt()
    }

    override func viewDidLoad() {
        assetList.didSelectCurrency = didSelectCurrency
        assetList.didTapAddWallet = didTapManageWallets
        addSubviews()
        addConstraints()
        setInitialData()
        setupSubscriptions()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        DispatchQueue.main.asyncAfter(deadline: .now() + promptDelay) { [unowned self] in
            self.attemptShowPrompt()
        }

        updateTotalAssets()
    }
    
    // MARK: Setup

    private func addSubviews() {
        view.addSubview(subHeaderView)
        subHeaderView.addSubview(logo)
        subHeaderView.addSubview(totalAssetsLabel)
        subHeaderView.addSubview(total)
        subHeaderView.addSubview(debugLabel)
        view.addSubview(prompt)
        view.addSubview(toolbar)
    }

    private func addConstraints() {
        let headerHeight: CGFloat = 30.0
        let toolbarHeight: CGFloat = 74.0

        subHeaderView.constrain([
            subHeaderView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            subHeaderView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 0.0),
            subHeaderView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            subHeaderView.heightAnchor.constraint(equalToConstant: headerHeight) ])

        total.constrain([
            total.trailingAnchor.constraint(equalTo: subHeaderView.trailingAnchor, constant: -C.padding[2]),
            total.centerYAnchor.constraint(equalTo: subHeaderView.topAnchor, constant: C.padding[1])])

        totalAssetsLabel.constrain([
            totalAssetsLabel.trailingAnchor.constraint(equalTo: total.trailingAnchor),
            totalAssetsLabel.bottomAnchor.constraint(equalTo: total.topAnchor)])
        
        logo.constrain([
            logo.leadingAnchor.constraint(equalTo: subHeaderView.leadingAnchor, constant: C.padding[2]),
            logo.centerYAnchor.constraint(equalTo: total.centerYAnchor)])

        debugLabel.constrain([
            debugLabel.leadingAnchor.constraint(equalTo: logo.leadingAnchor),
            debugLabel.bottomAnchor.constraint(equalTo: logo.topAnchor, constant: -4.0)])
        
        promptHiddenConstraint = prompt.heightAnchor.constraint(equalToConstant: 0.0)
        prompt.constrain([
            prompt.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            prompt.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            prompt.topAnchor.constraint(equalTo: subHeaderView.bottomAnchor),
            promptHiddenConstraint])
        
        addChildViewController(assetList, layout: {
            assetList.view.constrain([
                assetList.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                assetList.view.topAnchor.constraint(equalTo: prompt.bottomAnchor),
                assetList.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                assetList.view.bottomAnchor.constraint(equalTo: toolbar.topAnchor)])
        })
        
        toolbar.constrain([
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: -C.padding[1]),
            toolbar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: C.padding[1]),
            toolbar.heightAnchor.constraint(equalToConstant: toolbarHeight) ])
    }

    private func setInitialData() {
        view.backgroundColor = .darkBackground
        subHeaderView.backgroundColor = .darkBackground
        subHeaderView.clipsToBounds = false
        
        navigationItem.titleView = UIView()
        navigationController?.navigationBar.isTranslucent = true
        navigationController?.navigationBar.shadowImage = #imageLiteral(resourceName: "TransparentPixel")
        navigationController?.navigationBar.setBackgroundImage(#imageLiteral(resourceName: "TransparentPixel"), for: .default)
        
        logo.contentMode = .center
        
        total.textAlignment = .right
        total.text = "0"
        title = ""
        
        if E.isTestnet && !E.isScreenshots {
            debugLabel.text = "(Testnet)"
            debugLabel.isHidden = false
        } else {
            debugLabel.isHidden = true
        }
        
        totalAssetsLabel.text = S.HomeScreen.totalAssets
        
        setupToolbar()
        updateTotalAssets()
    }

    private func setupToolbar() {
        let menuButton = UIButton.vertical(title: S.HomeScreen.menu, image: #imageLiteral(resourceName: "menu"))
        menuButton.tintColor = .navigationTint
        menuButton.addTarget(self, action: #selector(menu), for: .touchUpInside)

        let menuBarButton = UIBarButtonItem(customView: menuButton)

        let paddingWidth = C.padding[2]
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        toolbar.items = [
            flexibleSpace,
            menuBarButton
        ]

        let buttonWidth = view.bounds.width - paddingWidth * 2
        let buttonHeight = CGFloat(44.0)

        menuButton.frame = CGRect(x: 0, y: 0, width: buttonWidth, height: buttonHeight)

        toolbar.isTranslucent = false
        toolbar.barTintColor = Theme.secondaryBackground
    }
    
    private func setupSubscriptions() {
        Store.unsubscribe(self)
        
        Store.subscribe(self, selector: {
            var result = false
            let oldState = $0
            let newState = $1
            $0.wallets.values.map { $0.currency }.forEach { currency in
                result = result || oldState[currency]?.balance != newState[currency]?.balance
                result = result || oldState[currency]?.currentRate?.rate != newState[currency]?.currentRate?.rate
            }
            return result
        },
                        callback: { _ in
                            self.updateTotalAssets()
                            self.updateAmountsForWidgets()
        })
        
        // prompts
        Store.subscribe(self, name: .didUpgradePin, callback: { _ in
            if self.currentPromptView?.type == .upgradePin {
                self.currentPromptView = nil
            }
        })
        Store.subscribe(self, name: .didWritePaperKey, callback: { _ in
            if self.currentPromptView?.type == .paperKey {
                self.currentPromptView = nil
            }
        })
        
        Store.subscribe(self, selector: {
            $0.wallets.count != $1.wallets.count
        }, callback: { _ in
            self.updateTotalAssets()
            self.updateAmountsForWidgets()
        })
    }
    
    private func updateTotalAssets() {
        let fiatTotal: Decimal = Store.state.wallets.values.map {
            guard let balance = $0.balance,
                let rate = $0.currentRate else { return 0.0 }
            let amount = Amount(amount: balance,
                                rate: rate)
            return amount.fiatValue
        }.reduce(0.0, +)
        
        totalAssetsNumberFormatter.currencySymbol = Store.state.orderedWallets.first?.currentRate?.currencySymbol ?? ""
        
        self.total.text = totalAssetsNumberFormatter.string(from: fiatTotal as NSDecimalNumber)
    }
    
    private func updateAmountsForWidgets() {
        let info: [CurrencyId: Double] = Store.state.wallets
            .map { ($0, $1) }
            .reduce(into: [CurrencyId: Double]()) {
                if let balance = $1.1.balance {
                    let unit = $1.1.currency.defaultUnit
                    $0[$1.0] = balance.cryptoAmount.double(as: unit) ?? 0
                }
            }

        widgetDataShareService.updatePortfolio(info: info)
        widgetDataShareService.quoteCurrencyCode = Store.state.defaultCurrencyCode
    }
    
    // MARK: Actions
    
    @objc private func menu() { didTapMenu?() }
    
    // MARK: - Prompt
    
    private let promptDelay: TimeInterval = 0.6
    
    private var currentPromptView: PromptView? {
        didSet {
            if currentPromptView != oldValue {
                var afterFadeOut: TimeInterval = 0.0
                if let oldPrompt = oldValue {
                    afterFadeOut = 0.15
                    UIView.animate(withDuration: 0.2, animations: {
                        oldValue?.alpha = 0.0
                    }, completion: { _ in
                        oldPrompt.removeFromSuperview()
                    })
                }
                
                if let newPrompt = currentPromptView {
                    newPrompt.alpha = 0.0
                    prompt.addSubview(newPrompt)
                    newPrompt.constrain(toSuperviewEdges: .zero)
                    prompt.layoutIfNeeded()
                    promptHiddenConstraint.isActive = false

                    // fade-in after fade-out and layout
                    UIView.animate(withDuration: 0.2, delay: afterFadeOut + 0.15, options: .curveEaseInOut, animations: {
                        newPrompt.alpha = 1.0
                    })
                    
                } else {
                    promptHiddenConstraint.isActive = true
                }
                
                // layout after fade-out
                UIView.animate(withDuration: 0.2, delay: afterFadeOut, options: .curveEaseInOut, animations: {
                    self.view.layoutIfNeeded()
                })
            }
        }
    }
    
    private func attemptShowPrompt() {
        guard okToShowPrompts else { return }
        guard currentPromptView == nil else { return }
        
        if let nextPrompt = PromptFactory.nextPrompt(walletAuthenticator: walletAuthenticator) {
            self.saveEvent("prompt.\(nextPrompt.name).displayed")
            
            // didSet {} for 'currentPromptView' will display the prompt view
            currentPromptView = PromptFactory.createPromptView(prompt: nextPrompt, presenter: self)
            
            nextPrompt.didPrompt()
            
            guard let prompt = currentPromptView else { return }
            
            prompt.dismissButton.tap = { [unowned self] in
                self.saveEvent("prompt.\(nextPrompt.name).dismissed")
                self.currentPromptView = nil
            }
            
            if !prompt.shouldHandleTap {
                prompt.continueButton.tap = { [unowned self] in
                    if let trigger = nextPrompt.trigger {
                        Store.trigger(name: trigger)
                    }
                    self.saveEvent("prompt.\(nextPrompt.name).trigger")
                    self.currentPromptView = nil
                }                
            }
            
        } else {
            currentPromptView = nil
        }
    }
    
    // MARK: -

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
