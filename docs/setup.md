# Spex Glance — setup guide (wiki copy)

Who this is for: you already trade sports on Kalshi and you want your open bets visible
without opening the app. Non-sports positions are deliberately not shown. You have a Mac with Xcode. You can follow a short recipe.

Who this is not for: anyone who wants trading from a widget. This is read-only on purpose.

## 1. One-time build

1. `brew install xcodegen`
2. `git clone <this repo> && cd spex-glance`
3. `scripts/gen.sh` — enter your Team ID when asked (it's kept in an untracked `.team` file).
4. `open SpexGlance.xcodeproj`
5. Select the SpexGlance scheme → My Mac → Run.
   Or: `scripts/install-mac.sh` builds Release straight into /Applications.

If Xcode complains about signing: Signing & Capabilities → both targets → tick "Automatically manage signing" and pick your team. App Groups and Keychain Sharing are already declared; Xcode will register them on first build.

## 2. Connect (two minutes)

Kalshi offers no in-app sign-in for third-party apps, so this is a one-time manual step on
their website. Follow the in-app wizard. Short version:

1. Leave "Create the key on Kalshi" selected.
2. Open Kalshi (your browser) → Create New API Key → **Read only** → name it → save. Kalshi downloads a .txt. In the app: Open file… → pick it.
3. Copy the Key ID Kalshi shows (a UUID, not the long MC…/BEGIN… blob) → back in the app → Test → Finish.

## 3. Add the widget

Right-click the desktop → Edit Widgets → search "Spex" → pick a size. (The app must have
been launched at least once.) The menu bar item is there from first launch.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Widget says "Open Spex Glance to connect" after you connected | Both targets must sign with the same (paid) team so they share the keychain access group. On macOS a free Personal Team can't do App Groups at all. |
| Menu bar dot says "socket: …" | Kalshi rejected the subscription (usually a settled ticker). It clears on the next 5-minute refresh. |
| 401 on Test connection | The Key ID doesn't belong to the private key you imported. Make sure you opened the .txt for *that* key. |
| A position you hold isn't listed | It's not a sports market. The footer says how many were skipped. |
| Widget stale for an hour | Normal WidgetKit budgeting. Open the app to force a refresh. Low Power Mode slows it further. |
| Sides/prices on resting orders look wrong | Kalshi order schema drift — see README "Known gaps". |

## Revoking access

App → Disconnect. Then Kalshi → Profile → API Keys → delete "Spex Glance". Both steps; the app can't delete the key on Kalshi for you (that would need write scope).
