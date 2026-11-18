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
    distance, riding time, average speed and top speed — or, where a walk
    or a drive was set aside (**Only the riding is sent**), distance ridden,
    active and total time, and the average over the active time. Then an optional
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

  **How far, at the top.** A card over the list adds up the kilometres,
  the rides and the riding time for **Today**, **Week**, **Month** or
  **All**, with a bar a day for the week (`Views/StatsCard.swift`). A week
  starts on Monday and a month on its 1st, in the phone's time zone. Saved
  and waiting rides count; a ride Not kept does not. It is added up on the
  phone from the rides already there, so it asks the website for nothing
  and works with no signal — the server could not say it better anyway,
  since a ride saved with no account is nobody's there from the next day.

  **A ride, opened.** A row opens its ride on a page of its own
  (`Views/RideView.swift`): the map framed to it, the riding solid, a walk
  set aside dotted and a train or a drive dashed, a small grey dot where
  the rider stopped, a ring where it began and a dot where it ended; the
  save card's numbers; the ride **part by part** (below); the fastest kilometre and how long was
  spent standing; the speed along the way as a line; and each kilometre's
  time, with a bar for its speed and the fastest one in full colour. All of
  it is the phone's own ride, so it opens with no signal and for a ride saved
  with no account. The sums are the website's — `rideInsight()` in its
  `functions/api/_rides.js`, ported step for step to `Core/Insight.swift` —
  so a ride reads the same here, on the website and in the map app, less the
  website's top speed over 200 m, since the save card's over half a minute is
  already on the page.

  What the website has of it is on the page too. Signed in, a saved ride is
  asked for by its id, `GET /api/rides/<id>`, and the line the website keeps
  is drawn solid over the phone's, which goes faint: what is left of the
  phone's at each end is the 200 m that was never kept. A ride saved with no
  account cannot be asked for — the website answers a ride only to the
  account it is under — so its page says how much was kept, from the
  answer to its save. Waiting and Not kept are in the pill under the title.
  **Remove from this phone** is at the foot, as the swipe is, and never for
  a ride still waiting.
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

A ride needs no destination, but it can have one. **Where to?** opens with
the keyboard up and the last three places the rider chose — kept on the
phone and nowhere else (`Core/Recents.swift`; swipe one away to forget it)
— and nothing else. Typing takes those away. One letter or two are answered
by the phone alone, the rider's own places first and then a copy the phone
keeps of every place the website's search knows: a name and a pin each, and
nothing else (`Core/Venues.swift`). The copy is the website's whole roll,
`GET /api/places` with no query, about 75 KB, asked for when the app opens
if the phone's is missing or a week old — one request a week a phone, which
is what lets opening the sheet and the first letters ask the website for
nothing at all. From the third letter the website's own search is asked and
replaces those rows when it answers: its places first, then
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
the rider leaves it; and arriving finishes nothing — Finish is still a
button. What is saved is the way really ridden, never the suggestion and
never the destination.

**Or by train.** An Elron train takes a bike, and from the right corner of
the city it is quicker: ride to Ülemiste, the train two stops, ride on. Where
the website finds one that is — `trains` in `GET /api/v1/route`, counted
from setting off and leaving within the hour — it is one more button after
the bike ways, *15 min · train 09:31*, and the card says *Leave at 09:25:
ride to Ülemiste, the RE34 at 09:31 to Kitseküla, ride on*. The rides are
the solid line and the rail dashed. While riding, the station is a corner
like any other, with a train in the row in place of an arrow — *Train RE34
at 09:31 to Kitseküla* — read once by the phone's own voice on the platform,
since no recording says which train. On the train nothing is recorded: a
point on the rail stretch of the way is not kept, so a saved ride is never
a railway, and it goes on from the far station. The clock keeps running, as
it does at a red light. A website from before the trains answers without
them, and the app offers the bike ways as it always did.

**The turns, shown and said.** The website says where the way turns, and
under the numbers a row shows the next corner: an arrow, how far, what to
do and the street it is onto. A voice says the same, since the phone is in
a pocket — "In 200 metres, turn right" about two hundred metres before, and
"Turn right" at the corner — over music, which is turned down for the
second it takes, and with the screen locked. The speaker in the row
switches it off and on, and the phone remembers. The voice is the owner's,
recorded: ten phrases in each language, listed in `docs/voice.md`,
which is why it says no street names and no distance but the one.
Azerbaijani and English are recorded, all but the two said off the way;
Estonian and Russian are not yet.
Until a phrase is recorded the phone's own voice reads it, in Russian;
iOS has no Estonian or Azerbaijani voice. A roundabout is in the row and
is not said: a bike is mostly on the path beside one. A ride with nowhere
to go has no row and no voice (`Core/Guide.swift`).

**Off the way, a new one.** It says first, and only then recalculates, at
the owner's word. More than sixty metres from the way for two points in a
row, the row says "You're off the way · 80 m from it" in place of the next
turn, and the voice says it once; riding the way backwards for forty
metres, it says "Going the wrong way". A few dozen metres off is often on
purpose — a shop, a shortcut, a closed path — so nothing more happens yet,
and back on the way the turns come back. Once the rider is plainly going
wrong — 150 m from the way, 150 m ridden backwards along it, or 250 m
ridden since it was said — the app asks the website for a new way from
where they are, by itself and with no button, since the phone is in a
pocket. The new way takes the old one's place and its first turn is said
as any way's is. With no signal the row says "No new way yet" and it asks
again thirty seconds later. The website's route knows nothing of which way
the rider is facing, so a new way can still begin "Turn around" where that
really is the shortest (`Store.follow`).

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

English, Estonian, Russian and Azerbaijani, following the one chosen under Account, or
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

### Only the riding is sent

Start is pressed at one door and Finish at the next, and in between the
bike may be pushed up a hill, walked through a market or put in a car.
Those stretches are not bike routes, so they are set aside, on the phone,
before anything is sent: kept and drawn, but never counted as riding. `Core/Motion.swift` does it, and it is cheap on
purpose:

- **Nothing listens while riding.** The iPhone's motion coprocessor notes
  all day whether it is walking, running, cycling, in a car or still, and
  keeps a week of it. At Finish the app asks it once what it noted between
  Start and now — one question a ride — and then shows the save card. A ride
  whose app was killed half way is covered too.
- **What is set aside**: a stretch the phone was at least fairly sure was
  walking, running or driving, and not cycling, for a minute or more. Still
  and unknown count as riding, so a red light never cuts a ride. A "walk"
  whose points went by faster than 10 km/h was a ride the coprocessor
  misread, and is kept.
- **What is kept** is all of it, on the phone. The stretches set aside are
  drawn on the ride's map as a faint dotted line, so the rider sees the
  whole of where they went, and the solid line of the riding is broken
  where they are. They are not in the distance, the times or the speeds.
- **What is sent** is what was always sent, with fewer points: the riding
  only. The server never hears what the rider was doing, nor the points
  set aside. Where a
  stretch set aside is longer than 250 m, the server's `GAP`, it cuts the
  line there and keeps each side as a ride of its own; a shorter one is
  joined by a straight step, as a lost signal is. The ride's `seconds` are
  the **active time** — the riding time less the stretches set aside — so the
  server's speed check and the time it shares out between pieces are about
  riding.
- **The save card** then shows distance ridden, active time and total time
  apart, the average over the active time, and *"1.2 km on foot or by car
  — dotted on the map, kept on this phone, not sent as riding"*. While riding, the numbers stay over the whole time: they are
  corrected at Finish, not live. A ride with nothing set aside looks as it
  always did.
- **Motion & Fitness** is asked for at the first Start. Refused, or on a
  phone without a coprocessor, no walk is set aside. A train and a stop
  still are: those are read off the points, below.

### A ride is the session it was

The owner rode twelve rides on 2026-11-17 and 18 and read them back out of
the database, and two things were wrong. A quarter of an hour inside a shop
was half a kilometre of riding that never happened: indoors the fix wanders
fifteen or twenty metres, the recorder keeps a point every twelve, and the
stop was thirty-two points zigzagging over a patch fifty metres by eighty —
in the distance, halving the average, and sent as a knot of lines where
somebody had stood. And a train was nothing at all: every point of it was
dropped as too fast, so the ride began at the far station. The owner's
words: keep the movement, and show what happened. `Core/Timeline.swift`
does, and a ride's page lists it under **Part by part**: riding, on foot,
by train or car, waiting, stopped — each with when it began, how far, how
long, and the speed where it moved.

- **A train is carried, not dropped.** A point too fast for a bike (over
  60 km/h from the last one kept), or on the rails of a way by train, goes
  into `Ride.carried`, one every 50 m. At Finish the carried points are
  gathered into the journeys they were — cut where two are more than two
  minutes apart, and only runs of four points and 300 m, since less is the
  fix jumping — and each goes to `Ride.aside` marked `vehicle` in
  `Ride.asideKinds`, beside what the coprocessor said was driven. Dashed on
  the ride's map, where a walk is dotted.
- **A stop is where the rider arrived, where they left, and the time
  between.** At Finish, where a run of points stayed within 60 m of its own
  middle for two minutes or more and went at least three times further
  than it got, only its first and last points are kept
  (`Timeline.settled`). Three times further than it got is what tells
  wandering from a long red light, whose points go straight through. What
  is left is one leg that took a long time and went nowhere, and that is
  what a stop is everywhere else in the app: `Insight` already counts it as
  standing, and the page draws a dot there.
- **Standing is not stored.** A leg slower than 1 m/s that took thirty
  seconds is waiting, and one that took two minutes is a stop; both are
  read off the points each time the page opens. So a ride recorded before
  this was written has its parts too, though its stops still have their
  wandering in them.
- **A stop comes off the active time; a wait does not.** A red light is
  part of a ride, as it always was. Two minutes standing is not, and
  thirteen of them made a 12 km/h ride read 5.8. The active time is the
  riding time less the stretches set aside and the stops, counted once
  where they overlap and less whatever fell in a pause.
- **None of it is sent but the riding.** Fewer points and a shorter time,
  never a label, never a point of a walk, a train or a stop. The website
  keeps bike routes; the session is the rider's and stays on the phone.
- **What it does not do yet.** The numbers while riding are still over the
  whole time, corrected at Finish. A walk with no coprocessor to say so is
  still riding, slowly. And *by train or car* is one word, because nothing
  on the phone tells a bus from a train.

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
| `GET /api/rides/<id>` | one saved ride, to the account it is under: `ride` with `meters` and `line`, the stored `[lat, lng]` pairs with the ends off. Asked when a saved ride's page opens signed in, and drawn over the phone's line; `not-found` and `signed-out` draw nothing. The rest of the answer, `insight`, is worked out on the phone instead |
| `GET /api/places` | the whole roll, with no query, once a week: the copy Where to? answers the first letters from and a tap on the map is matched against, keeping `id`, `name`, `lat`, `lng` and `map` |
| `GET /api/places?q=&near=&limit=` | the search: the website's places and the city's venues, reading `id`, `name`, `address`, `category`, `lat`, `lng` and `map` |
| `GET /api/geocode?q=` | streets, addresses and districts: `results` with `label`, `where`, `lat`, `lng` |
| `GET /api/lookup`, `POST /api/lookup` | **Look for it on Google Maps**: `ready`, then `{ q }` answered by `ok`, `why` and `places` in the search's rows. The button goes away on `why: "no-key"` and says it is resting on any other refusal |
| `GET /api/v1/route?from=&to=&mode=bike` | asked first: everything `/api/route` answers below, with `version: 1`, and `trains` — each `seconds`, `meters`, `leave`, and `legs`, a ride (`kind: "bike"`, `meters`, `seconds`, `line`, `steps`) or the train (`kind: "train"`, `name`, `from`, `to`, `at`, `until`, `meters`, `line`). An answer without `version`, or none, and `/api/route` is asked instead |
| `GET /api/route?from=&to=&mode=bike` | the suggested way: `meters`, `seconds`, `line`, and `others`, up to two more ways in the same three fields; and for each way `steps`, where it turns — `at`, `turn`, `name`, and `exit` on a roundabout. The words of `turn` are `left`, `right`, `keep-left`, `keep-right`, `straight`, `around`, `roundabout` and `arrive`; one the app does not know is left out |
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
in the four languages; the ones the website has too (`ride*`, `account*`)
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
            Motion.swift        which stretches were walked or driven, asked once at Finish
            Timeline.swift      the ride part by part: a train carried, a stop settled, what is listed
            Ride.swift          a ride, a point, and the sums
            Insight.swift       a ride's kilometres and speeds, and what the website kept of it
            Store.swift         every ride on the phone, and sending them
            Search.swift        places, streets, Google, and the way there and its turns
            Guide.swift         the voice that says the turns
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
            StatsCard.swift     how far today, this week, this month, in all
            RideView.swift      one ride, opened
            AccountView.swift   the Account tab, the colours, deleting an account
            SignIn.swift        the username form and the Apple and Google buttons
            Theme.swift         the website's colours
  Seed/     strings.json        every string, in en, et, ru and az
  Voice/    <lang>-<clip>.m4a   the turns, recorded: Azerbaijani and English so far
  *.lproj/  InfoPlist.strings   the location and motion questions, in each language
  PrivacyInfo.xcprivacy         the privacy manifest
Config/     Info.plist          the two background modes and the languages
            Rattatee.entitlements  Sign in with Apple, Release only
docs/       icon.html           the icon, drawn
            voice.md            the phrases to record, and where they go
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

**A build on GitHub, when asked**, `.github/workflows/ios.yml` — Actions →
build → Run workflow, on the branch to check. Since 2026-11-18 a push no
longer starts it, since twenty minutes of a macOS runner a push was failing
once in sixty. It checks the strings
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
- **The motion purpose string** is `NSMotionUsageDescription`, the same
  two places. Motion activity never leaves the phone, so it is not a data
  type under App Privacy.
- **Background location** has to be justified in the review notes. In one
  line: *the app records a bike ride the user starts with a button, with the
  screen locked, until they press Finish; nothing is recorded otherwise.* A
  screen recording of a ride being started and the phone locked is what
  reviewers ask for when they ask.
- **Background audio** is the second background mode, and review asks what
  plays. In one line: *short spoken directions — "turn right" — on the way
  to a place the user chose, while a ride is being recorded; nothing plays
  otherwise.*
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

`docs/icon.html` is the icon as a page: the owner's own blue single-speed
with its red mudguard, leant on the parapet at Toompea with the Old Town
behind it. Photograph it at 1024 × 1024 into
`Rattatee/Assets.xcassets/AppIcon.appiconset/icon-1024.png` with any
headless browser, and save it as RGB with no alpha channel — App Store
Connect refuses an icon that has one, even a fully opaque one.

## Done when

- A ride recorded on a real iPhone with the screen locked for the whole
  ride saves and comes back from `GET /api/rides?bbox=`.
- Killing the app mid-ride, or losing signal at Save, does not lose the
  ride.
- The project archives for TestFlight with the permission texts and the
  privacy details above.

None of the three can be checked from a cloud session. CI proves the app
compiles and draws its screens; the ride itself needs a phone and a bike.
