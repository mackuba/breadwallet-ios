# Forked BRD iOS Bitcoin wallet

This is a forked repository of a slightly older version of the BRD (Breadwallet) Bitcoin wallet app for iOS, available at <https://github.com/breadwallet/breadwallet-ios>. I've updated it to make it work again after the app broke when the BRD backend was suddenly turned off after the company was bought by Coinbase.

This is based on a version of the app from ~ the spring of 2021. The current App Store version is a partially multiplatform app which uses Kotlin for shared code between platforms, available at <https://github.com/breadwallet/brd-mobile>.

Behind the scenes, the app uses the [WalletKit](https://github.com/blockset-corp/walletkit) library from Blockset (a slightly old version of it), which has also been abandoned for the same reason.


## ⚠️⚠️⚠️ WARNING IMPORTANT ⚠️⚠️⚠️

I made this updated version mostly for myself, because the Coinbase wallet app which I was forced to migrate to is crap, and I want the old BRD app back and it stopped working.

I do not provide any support or warranty for this project, and I do not take responsibility for any possible problems you may have using it, including lost funds. I am not an expert in security, cryptography or Bitcoin internals; I am a Mac/iOS app developer with past experience in backend/frontend web dev and *some* knowledge of how Bitcoin works. I am mostly relying on the existing code written by the BRD team and simply ripping out things from it that don't work or that I don't need. The app works for me and I use it on my phone, but if you decide to use it, don't put too much money into it because something may go wrong.


## Current status

I've removed most code that was calling the no longer existing backend, including things like analytics tracking, feature flags or server-side image asset updating. I've also removed most non-ETH coins including Bitcoin Cash, Tezos, Hedera, Ripple and staking code.

Bitcoin currently seems to be working, using the P2P (SPV) mode which fortunately was kept in the app as an option, so now it's the only option. Segwit is enabled by default, legacy addresses are available in the menu.

**Note**: the Coinbase wallet uses a different (standard) key derivation path for addresses than the non-standard one that BRD uses for both legacy and Segwit addresses. If you've migrated the wallet to the Coinbase app and made some transactions there, the transactions after the migration will not currently appear in this app.

ETH and ERC20 coins are available in the wallet manager, but they don't currently work because they're trying to sync from the backend. I don't know if it's possible to sync them via P2P or from some other source, and it's not my priority at the moment.

The next things I'd like to do are:

- get rid of any remaining code that calls non-existing backend services, possibly replacing it with other alternative APIs
- get rid of some other features that I don't need or don't like
- update to the latest version of WalletKit

I'm not planning to make this into a real product on the App Store or to provide any developer builds, so if you want to try it, you need to build it yourself on your machine.


## Development Setup

To build the app you will need a Mac (obviously), Xcode and a developer account (might be a free one, although IIRC with the free accounts you need to reinstall the app from the Mac to your phone fairly often).

1. Clone the repo: `git clone https://github.com/mackuba/breadwallet-ios.git`
2. Update submodules: `git submodule update --recursive`
3. Open the `breadwallet.xcworkspace` file
4. Select the main breadwallet project entry in the Project Navigator. For the "breadwallet", "breadwalletWidgetExtension" and "breadwalletIntentHandler" targets, under "Signing and capabilities", change the team setting to your account and change the bundle identifiers to something different.
5. Build & run.


## License & credits

The BRD app project is available under the terms of the MIT license.

Original code © Aaron Voisine, Adrian Corscadden and the BRD team. Updates by [Kuba Suder](https://mackuba.eu).
