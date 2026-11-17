# Rattatee

Record a bike ride in Tallinn with the phone in your pocket. The iPhone app
that saves rides to [Tallinn Tastebuds](https://tallinntastebuds.ee), where
they are collected to become a map of confirmed bike routes, per street and
per direction.

*Rattatee* is Estonian for a bike path.

SwiftUI, iOS 17 and later, iPhone only, no third-party dependencies.

---

## Why it exists

The website records rides too, from the bike button on its map. But a web
page stops being told where it is the moment the screen locks, so its
recorder asks you to keep the page open and the screen on, and pauses when
you do not. An app can ask iOS to keep hearing its position in the
background. That is this app's one job: Start, lock the phone, ride, Finish,
Save.

**It is an interface.** Rattatee has no server and no database of its own,
the same as Kohuke (`etibarhasanov/kohuke`) and the map app
(`etibarhasanov/TallinnTasteBudsApp`). It saves through the same Function
the website's recorder does, `POST /api/rides`. Its project structure,
sign-in and networking are copied from Kohuke.

**Nobody has to sign in.** What the rides are for is their points. People
ride, press Save, and that is it: the ride is kept with no account on it.
Signing in is there for whoever wants it, on the **Account** tab, and buys one
thing — the ride is also listed on their account page on the website.

## What it does

Three tabs.

- **Record.** A map and a card at its foot, which is one of:
  - *Ready* — one big **Start** and nothing to read. **Where to?** over
    the map is optional: see **Search and go** below.
  - *Location is off* — what to choose in Settings, and a button to it.
  - *Recording* — the screen changes. Across the top, large enough to
    read off a handlebar, three numbers and no more: distance, average
    speed, and when the ride began — no running clock, no speed right now
    and no top speed, since an average over the whole ride is the one a
    phone gets right. Under them, how much of the way is left where there
    is somewhere to go. The map with the line drawn so far takes the
    middle, and **Pause** and **Finish** the foot. It carries on with the
    screen off and the app in the background; iOS shows its blue location
    pill while it does.
  - *Paused* — the same, greyed; nothing is recorded and the clock the
    average is taken over stops. **Resume**, Finish.
  - *Nice ride* — when it began and ended, and the ride's own numbers:
    distance, riding time, average speed and top speed. Then an optional
    name (60 characters), **Save ride** and **Throw it away** (asked twice),
    and the two things worth knowing first: no name is ever shown with a
    ride, and the first and last 200 m are left off. There are no totals
    across rides, on purpose: the app is for recording a ride and sending
    it. Top speed is the fastest half-minute, not the fastest pair of
    points, so one GPS jump cannot claim 60 km/h.
  - *Too short to keep* — under 700 m, with **Keep riding**.
  - *Saved*, with the same numbers, or *Kept on this phone* when the server could not be reached,
    or *Not kept* when it refused the ride for good.
- **My rides.** Every ride recorded on this phone, newest first, under the
  month it was ridden in: name, distance, time, date, and **Saved**,
  **Waiting** or **Not kept · why**. A banner says how many are waiting,
  with **Try now**. A ride the server has answered can be swiped off the
  phone; a waiting one cannot.
- **Account.** **Create account** or **Sign in** with a username and a
  password, as in Kohuke, or continue with Apple or Google where the
  website offers them — the same accounts as the site and Kohuke, made on
  the spot the first time — or, signed in, sign out and delete the
  account. **Language**: the phone's, or English, Eesti or Русский for this
  app alone, switched at once. Under **Look**,
  the colour, one of the website's four (Red, Green, Blue, Plum), and the
  background: **Like the phone**, which is where a new install starts,
  **Light** or **Dark**. Then Privacy.

### Search and go

A ride needs no destination, but it can have one. **Where to?** opens on
where the rider has been — the last five places they chose, kept on the
phone and nowhere else (`Core/Recents.swift`; swipe one away to forget it)
— and under that the five places nearest them, or, before the phone has
said where it is, five of the places on the map. Those come out of a copy
the phone keeps of every place the website's search knows: a name and a pin
each, and nothing else (`Core/Venues.swift`). The copy is the website's
whole roll, `GET /api/places` with no query, about 75 KB, asked for when
the app opens if the phone's is missing or a week old — one request a week
a phone, which is what lets opening the sheet and typing a first letter ask
the website for nothing at all. One letter is answered by the phone alone,
the rider's own places first. From the second the website's own search is
asked and replaces those rows when it answers: its places first, then
streets and districts, each with how far it is. From five letters a last row offers **Look for "…" on
Google Maps**, exactly as the website's find bar does; what Google answers
with goes to the top of the list, and the website keeps it, so the next
search — here, in the map app or on the site — finds it without asking
Google.

Or tap the map. A place Apple's map names is somewhere to go under that
name — and if the phone's copy of the website's places has it within a
street's width, it is the website's place, under the website's id. A tap
anywhere else drops a pin, whose street the phone works out for itself.
Neither asks Google or the website for anything but the way there; taps do
nothing once a ride has begun.

A tap leaves the map where it was: the pin lands under the finger, and a
dotted straight line runs to it from the rider while the website is asked
for the way. When the way arrives the map moves once, to the whole of it,
from where the rider is to the pin. A place chosen in the search that is
off the screen is framed straight away instead, rider and place.

Where the website finds more than one way — up to three — the card has a
small button for each, *9 min · 2.1 km*, as the website's own route bar
does. The one chosen is the solid line and the others are faint under it;
pressing another changes which is solid, and the map stays where it is.
**Go** starts with the one chosen, and how much is left while riding is
measured along it. The buttons say how long and how far and nothing about
which is nicer, because the router does not say.

Choosing a place puts it on the map with a suggested way by bike, in blue,
how far it is and about how long, and **Go**, which is Start. While riding,
the blue line stays under the line actually ridden and the card says how
much of the way is left. The way is a suggestion and is not re-drawn when
the rider leaves it; there are no spoken or turn-by-turn directions; and
arriving finishes nothing — Finish is still a button. What is saved is the
way really ridden, never the suggestion and never the destination.

**Add to a list.** Signed in, the card of somewhere to go has **Add to a
list** beside Go: the rider's lists on the website, a press each, and a new
one made on the spot. A place the website does not have — one only Apple's
map names, or a pin — goes on as the rider's own place, under a name they
can change, which the website keeps for their lists alone. The lists are
kept on the phone as last read, and an add with no signal waits on the
phone and goes when the rides go (`Core/Lists.swift`). Signed out, the card
says an account is what this needs.

Streets, addresses and Google need a connection, and the search says there
is none only when the phone's copy has nothing for the letters either.
Recording never needs one.

English, Estonian and Russian, following the one chosen under Account, or
until somebody chooses, the phone's language or the one chosen for the app
in Settings.

Every colour has a day and a night. Red and Blue by day, and Green and Plum
by night, are the website's own styles to the value; the other four were
drawn to sit beside them (`Palette` in `Views/Theme.swift`). The choice is
kept on the phone, as the website keeps its style in the browser.

## The rules of a recording

The website's, from `assets/ride.js` there, so a ride recorded here is the
same kind of line:

- A point is kept when it is at least **12 m** from the last kept point and
  the fix is accurate to **30 m** or better.
- A jump faster than **60 km/h** between two kept points is dropped.
- Coordinates are rounded to **5 decimals**.
- Every kept point also carries its **time** and its **accuracy**.
- Core Location is asked for the `fitness` activity and the best accuracy,
  and never to pause on its own. The permission is **While Using the App**
  with the `location` background mode; "Always" is never asked for.
  `Core/Recorder.swift` says why that is enough.
- There is no auto-pause. Pause is a button.

## A ride is never lost

A ride is a file on the phone from the moment Start is pressed
(`Core/Disk.swift`, Application Support, one JSON file a ride). It is
rewritten every five points, about sixty metres, and at every pause.

- **The app is killed mid-ride**, or the battery dies: the ride comes back
  **Paused** the next time the app opens, with everything up to its last
  written point and the riding time it had there. Resume or Finish.
- **No signal at Save**: Save marks the ride *waiting* on disk before
  anything is sent. It is sent again when the app comes to the front, when
  the network comes back, and on **Try now**. Only the server's answer moves
  it on.
- **The server refuses it**: `short`, `fast` and `malformed` are final and
  the ride is listed as *Not kept*, still on the phone. `often` (the day's
  cap) waits for the next UTC midnight. Anything else is tried again.

One known gap, accepted for the first version: `/api/rides` has no request
id, so if the server stores a ride and its answer is lost on the way back,
the next try stores it a second time. The fix is an optional field on the
route that the server uses to recognise a repeat.

## What it asks the website for

All of it is in `Rattatee/Core/API.swift`, `Store.swift` and
`Account.swift`. These are promises the website keeps to an installed app
that cannot be updated in a day, and they are listed in the website
repository's `CLAUDE.md` under **What the app reads**.

| | |
|---|---|
| `POST /api/rides` | `{ action: "save", anon: true, name, seconds, line }`, answered `{ ride: { id, meters, seconds } }`. `line` is `[lat, lng, t, acc]` a point: five decimals, whole seconds since the ride began, whole metres. `anon` is what lets a save with no session through; with a session the ride is on the account |
| `GET /api/places` | the whole roll, with no query, once a week: the copy Where to? takes its few nearby places and its answer to a first letter from, keeping `id`, `name`, `lat`, `lng` and `map` |
| `GET /api/places?q=&near=&limit=` | the search: the website's places and the city's venues, reading `id`, `name`, `address`, `category`, `lat`, `lng` and `map` |
| `GET /api/geocode?q=` | streets, addresses and districts: `results` with `label`, `where`, `lat`, `lng` |
| `GET /api/lookup`, `POST /api/lookup` | **Look for it on Google Maps**: `ready`, then `{ q }` answered by `ok`, `why` and `places` in the search's rows. The button goes away on `why: "no-key"` and says it is resting on any other refusal |
| `GET /api/route?from=&to=&mode=bike` | the suggested way: `meters`, `seconds`, `line`, and `others`, up to two more ways in the same three fields |
| `GET /api/lists` | the signed-in rider's lists: `lists` with `id`, `title` and `n` |
| `POST /api/lists` | `create` (`title`, answered `id`), `place` (`name`, `address`, `lat`, `lng`, answered `place.id`) and `add` (`id`, `place`), and the errors `signed-out`, `full`, `too-many` and `title` |
| `GET /api/account` | who the session is, and `appGoogle` / `appApple`, which draw the two sign-in buttons |
| `POST /api/account` | `create` and `login` with `username` and `password`, answered with `user` or the errors `taken`, `username`, `password`, `no-match` and `slow-down`; `ticket`, `logout`, `delete` |
| `GET /api/google?app=<challenge>` | the Google round trip, ending at `tallinntastebuds://signin` |
| `POST /api/apple` | Apple's token and its nonce, answered as a sign-in |

A line longer than 3,500 points, about forty kilometres, is thinned evenly
before it is sent, and points outside the box the server accepts are left
out (`Geo.line` in `Core/Ride.swift`).

**Sign in with Apple needs the website to know this app.** Apple signs its
token for a bundle id, and `functions/api/_apple.js` there lists the ids it
accepts; this app's is `ee.tallinntastebuds.rattatee`.

**The words are compiled in**, unlike Kohuke's, because the app has to say
"Recording" with no signal. `Rattatee/Seed/strings.json` holds every string
in the three languages; the ones the website has too (`ride*`, `account*`)
were copied from its `data/ui.json` under the same keys. CI fails on a key
missing a language, a key the code asks for that is not there, and a key
nothing asks for.

### What the website does not have yet

- **A request id on a save**, so a retry after a lost answer is not a second
  ride. See above.
- **The server's list in My rides.** `GET /api/rides?mine=1` answers a
  signed-in account's rides; the app lists only what is on the phone, so
  rides do not follow an account to a new phone yet.
- **Everybody's rides on the map.** `GET /api/rides?bbox=` answers them; the
  record map does not draw them yet.

---

## The code

```
Rattatee/
  App/      RattateeApp.swift   the app and its two tabs
            LaunchScript.swift  launch arguments, for CI's screenshots
  Core/     API.swift           the one door to the website
            Recorder.swift      Core Location, in the background too
            Ride.swift          a ride, a point, and the sums
            Store.swift         every ride on the phone, and sending them
            Search.swift        places, streets, Google, and the way there
            Venues.swift        the places kept on the phone, a name and a pin each
            Recents.swift       where the rider has gone before, newest first
            Lists.swift         the rider's lists, and adds waiting for signal
            Account.swift       signing in and out
            SocialSignIn.swift  Google and Apple, Kohuke's file unchanged
            Disk.swift          the ride files, and where the other copies live
            Strings.swift       the words, the language chosen, and how a distance is said
  Views/    RecordTab.swift     the map and its taps, Ready, Recording, Paused
            SearchSheet.swift   Where to?
            ListPicker.swift    Add to a list
            FinishCards.swift   Save, Too short, and what came of it
            RidesTab.swift      My rides
            AccountView.swift   the Account tab, the colours, deleting an account
            SignIn.swift        the username form and the Apple and Google buttons
            Theme.swift         the website's colours
  Seed/     strings.json        every string, in en, et and ru
  *.lproj/  InfoPlist.strings   the location question, in each language
  PrivacyInfo.xcprivacy         the privacy manifest
Config/     Info.plist          the background mode and the languages
            Rattatee.entitlements  Sign in with Apple, Release only
docs/       icon.html           the icon, drawn
```

The project uses a synchronised folder, as Kohuke's does: a file added
under `Rattatee/` is in the build with no change to the project file.

## Building it

Open `Rattatee.xcodeproj` in Xcode 16 or later, choose a team under
**Signing & Capabilities**, and run it on a phone. The simulator builds and
shows every screen, but only a phone on a bike records a ride.

- **Debug** is signed without the Sign in with Apple entitlement, so it
  installs from Xcode with an ordinary Apple ID. The Apple button then fails
  when pressed; Google and riding without an account both work.
- **Release** carries the entitlement, so archiving needs the paid developer
  team, with the **Sign in with Apple** capability on the app id
  `ee.tallinntastebuds.rattatee`.

**Every push is built on GitHub**, `.github/workflows/ios.yml`: the strings
are checked, the app is built for the simulator, the built `Info.plist` is
checked for the permission text and the background mode, and the app is
launched in each state and photographed. The pictures are the run's
`screens` artifact and, shrunk, the `ci-screens` branch.

### To TestFlight

1. In App Store Connect, make the app: bundle id
   `ee.tallinntastebuds.rattatee`, name Rattatee.
2. In Xcode: **Product → Archive** with the Release configuration, then
   **Distribute App → App Store Connect**.
3. Fill in what review asks for, below.

### What App Store review asks for

- **The location purpose string** is `NSLocationWhenInUseUsageDescription`,
  in the project's build settings in English and in
  `Rattatee/<lang>.lproj/InfoPlist.strings` for each language.
- **Background location** has to be justified in the review notes. In one
  line: *the app records a bike ride the user starts with a button, with the
  screen locked, until they press Finish; nothing is recorded otherwise.* A
  screen recording of a ride being started and the phone locked is what
  reviewers ask for when they ask.
- **App Privacy**, matching `PrivacyInfo.xcprivacy`:
  - *Precise Location* — collected, for App Functionality, not used for
    tracking. Linked to the user only when they are signed in.
  - *User ID* — collected only when signed in, for App Functionality,
    linked, not used for tracking.
  - Nothing else: no analytics, no advertising, no third-party code. What
    is typed into the search, and where the phone is when a way is asked
    for, go to the website to be answered and are not kept with anything
    that says who asked.
- **Privacy policy URL**: `https://tallinntastebuds.ee/privacy`, which says
  what is kept of a ride.
- **Account deletion** is in the app, under Account, as review requires of
  an app that can make an account.
- **Sign-in is optional**, so review needs no demo account.

### The icon

`docs/icon.html` is the icon as a page. Photograph it at 1024 × 1024 into
`Rattatee/Assets.xcassets/AppIcon.appiconset/icon-1024.png` with any
headless browser.

## Done when

- A ride recorded on a real iPhone with the screen locked for the whole
  ride saves and comes back from `GET /api/rides?bbox=`.
- Killing the app mid-ride, or losing signal at Save, does not lose the
  ride.
- The project archives for TestFlight with the permission texts and the
  privacy details above.

None of the three can be checked from a cloud session. CI proves the app
compiles and draws its screens; the ride itself needs a phone and a bike.
