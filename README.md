# Rattatee

Record a bike ride in Tallinn with the phone in your pocket. The iPhone app
that sends rides to [Tallinn Tastebuds](https://tallinntastebuds.ee), where
they are counted into what the site knows of how each street rides, per
street and per direction — and kept there too, for whoever is signed in.

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

**Nobody has to sign in, and then the ride is theirs alone.** People ride,
press Save, and that is it: the ride stays on the phone, and the website
counts the streets it went down and keeps nothing of it — since
2026-11-20, when the owner drew that line; for three days before it such a
ride was kept there with no account on it. The save card says so before
Save is pressed, and that saving rides wants an account. Signing in is
there for whoever wants that, on the **Account** tab: a ride saved signed in
is kept on the website under the account, listed on the account page there
and drawn on its page here, and added up with the account's others on My
rides. Nothing tells the two kinds apart on the phone beyond that,
and nothing offers to move a ride to an account afterwards.

## What it does

Three tabs.

- **Record.** A map and a card at its foot, which is one of:
  - *Ready* — one big **Start** and nothing to read. **Where to?** over
    the map is optional, before a ride or during one: see **Search and
    go** below.
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
  and waiting rides count; a ride Not kept does not. Today, Week and Month
  are added up on the phone from the rides already there, so they ask the
  website for nothing and work with no signal — the server could not say
  them better anyway, since a ride saved with no account is not there at
  all. **All**, signed in, is the account's instead, once the website has
  answered: every ride saved to it from any phone, with the time stopped,
  the average, the top speed, the fastest kilometre and the longest ride
  under it, and *From every phone on your account, since 14 Nov 2026.* at
  the foot (**All, on the account**, below). Signed out, and until that
  answer comes, All is the phone's, as the other three are. The two are not
  meant to agree, and the foot line is what says which All is showing. A
  phone with no ride on it shows only that it has none, signed in or not.

  **A ride, opened.** A row opens its ride on a page of its own
  (`Views/RideView.swift`): the map framed to it, the riding solid, a walk
  set aside dotted and a train or a drive dashed, a small grey dot where
  the rider stopped, a ring where it began and a dot where it ended; the
  save card's numbers; the ride **part by part** (below); the fastest kilometre and how long was
  spent standing; the speed along the way as a line; and each kilometre's
  time, with a bar for its speed and the fastest one in full colour. The
  map on the page stays still, so a thumb on it scrolls the page; a tap
  opens it over the whole screen, where it moves and zooms like any map,
  anywhere along the ride, and **Whole ride** frames it again. Until
  2026-11-21 the page's map could only zoom, and a map that cannot move
  zooms only on its middle. A part of the ride opens a map of its own
  (below). All of
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
  account was never kept, so there is nothing to ask for and its page says
  nothing of the website: the line is the phone's own. Waiting and Not
  kept are in the pill under the title.
  **Remove from this phone** is at the foot, as the swipe is, and never for
  a ride still waiting.
- **Account.** **Create account** or **Sign in** with a username and a
  password, as in Kohuke, or continue with Apple or Google where the
  website offers them — the same accounts as the site and Kohuke, made on
  the spot the first time — or, signed in, sign out and delete the
  account, whose rides add up on My rides. **Language**: the phone's, or
  English, Eesti or Русский for this app alone, switched at once. Under
  **Look**, the colour, one of the website's four (Red, Green, Blue, Plum),
  and the background: **Like the phone**, which is where a new install
  starts, **Light** or **Dark**. Then Privacy.

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

Or touch the map. A tap on a place Apple's map names is somewhere to go
under that name — and if the phone's copy of the website's places has it
within a street's width, it is the website's place, under the website's id.
A hold anywhere, half a second with the finger still, drops a pin there,
with a knock as it lands, whose street the phone works out for itself.
Neither asks Google or the website for anything but the way there. A tap on
bare map does nothing: until 2026-11-19 it dropped the pin, which left a tap
on one of the ways drawn nothing to mean but a new pin on top of it, and
asked the website for a way at every stray touch (`Views/RideMap.swift`, A
HOLD IS A PIN, AND A TAP IS A CHOICE).

**Somewhere chosen is harder to move.** With a pin on the map and its ways
drawn, a tap chooses a way and nothing else: a named place is not chosen by
a tap, and the hold that moves the pin is a whole second, not half of one.
The ways run down the streets and the named places stand along them, so a
finger wider than a line kept landing on the Prisma beside it, which moved
the pin there and threw the ways away. Moving the pin is the one touch that
loses something, so it is the one that has to be meant. To go somewhere
else by name, let the first go with its cross and tap the place, or ask
Where to? (SOMEWHERE CHOSEN IS HARDER TO MOVE, in the same file).

**Mid-ride, too.** Nothing has to be paused or finished to choose somewhere
to go: **Where to?** stays over the map while riding, under the numbers, and
a place chosen there, or a touch on the map, is somewhere to go exactly as
before a ride. The recording goes on underneath; the way is asked for from
where the rider is and setting off the way they are going (`heading`, as a
new way off the old one is), and as soon as it arrives the blue line is
under the ridden one, the card says how much is left and the turns are shown
and said. The website's first way is taken, with no choice of others, since
the rider is moving. A touch chooses only while there is nowhere to go yet —
a hand resting on the screen should not throw away a way being followed — so
a destination already chosen is changed through Where to?, or let go with
its cross, which leaves the ride going with nowhere to go. On the save card
and after it, a touch does nothing.

A pin leaves the map where it was: it lands under the finger, and a
dotted straight line runs to it from the rider while the website is asked
for the way. When the way arrives the map moves once, to the whole of it,
from where the rider is to the pin. A place chosen in the search that is
off the screen is framed straight away instead, rider and place.

Where the website finds more than one way — up to five — the card has a
small button for each, *9 min · 2.1 km*, as the website's own route bar
does. The one chosen is the solid line and the others are faint under it;
pressing another, or tapping its faint line on the map, changes which is
solid, and the map stays where it is. A line is taken for tapped within a
finger's half-width of it. Where the lines run together, as they do at both
ends, the solid one is on top and a tap there changes nothing.
**Go** starts with the one chosen, and how much is left while riding is
measured along it. The buttons say how long and how far and nothing about
which is nicer, because the router does not say.

The one exception is the way people have ridden. Where riders have been
along one of the ways, in the direction it goes and at their own pace, the
website puts it first and marks it `ridden: true`, and its button starts
with the word: *Ridden · 14 min · 4.0 km*, as on the website's own bar.
For a day from 2026-11-19 the website named every way — *Fastest*,
*Safest*, *Quietest* and *Shortest* too — in a field called `style`, and
then took the names back. The app still reads `style`, though nothing sends
it now, and until 2026-11-22 it read nothing else, so the ridden way came
first with no name. The row of buttons still slides sideways here; on the
website it wraps.

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
drawn as any way by bike is, in the colour chosen under Account, and the
rail is not: it is orange, as Elron's trains are, a solid line a little
thicker than a ride with a darker edge, the way Google's map draws a train
among its blue lines. While the way is on offer its rail is a faint orange
among the faint lines, and its button is filled orange when it is the one
chosen (`Theme.train` in `Views/Theme.swift`, and THE RAIL IS ORANGE, AND
THE RIDES ARE NOT in `Views/RideMap.swift`). While riding, the station is a corner
like any other, with a train in the row in place of an arrow — *Train RE34
at 09:31 to Kitseküla* — and said once on the platform, *Your train leaves
from here*, since no recording can say which train. On the train nothing is recorded: a
point on the rail stretch of the way is not kept, so a saved ride is never
a railway, and it goes on from the far station. The clock keeps running, as
it does at a red light. A website from before the trains answers without
them, and the app offers the bike ways as it always did.

**The turns, shown and said.** The website says where the way turns, and
under the numbers a row shows the next corner: an arrow, how far, what to
do and the street it is onto. A voice says the same, since the phone is in
a pocket — "In 200 metres, turn right" about two hundred metres before, and
"Turn right" at the corner — over music, which is turned down for the
second it takes, and with the screen locked. A button at the foot of the
riding screen, at the end of the radio's row, switches it off and on, and
the phone remembers: a speaker and *Voice*, or a struck-through speaker and
*Off*. It is there from the moment somewhere to go is chosen and not
before, since a ride with nowhere to go hears nothing from it but the
greeting at Start; until 2026-11-22 it was a small speaker at the end of the
turn row, where it was easy to miss. The voice is the owner's,
recorded: sixteen phrases in each language, listed in `docs/voice.md`,
which is why it says no street names and no distance but the one.
Azerbaijani, English and Estonian are recorded, all but the train;
Russian is not yet, and until a phrase is the phone's own voice reads it,
in English and Russian, and nothing does in Estonian or Azerbaijani,
which iOS has no voice for. A roundabout is in the row and
is not said: a bike is mostly on the path beside one. A tunnel is said
at its entrance, "Enter the tunnel", and with the turn before it where it
starts just past one, as the Veerenni path under the railway does. A ride
with nowhere to go has no row and no voice (`Core/Guide.swift`).

**A radio, under the voice.** At the foot of the riding screen, over Pause
and Finish, a row says **📻 Play radio** — the whole width with nowhere to
go, and beside the voice's button where there is somewhere, so the music and
the voice are two buttons side by side and either can be had without the
other. A tap plays a station: Raadio
Tallinn in Estonian, Radio Paradise in English, Наше Радио in Russian and
Baku Retro FM in Azerbaijani, until the rider chooses another. Playing, the
row is the station's name between two buttons, the next station and the one
before, as a car's seek buttons go; a tap on the name stops it, and a longer
press opens every station — twenty, `Seed/stations.json` — to choose from.
The phone remembers the station, and whether the radio was on: a ride
starts with it if the last one ended with it, after the greeting, so the
first time is always a press. It never starts over something the rider is
already listening to, and it stops at Finish.

When a turn is said the radio goes under it and comes back after, which
iOS does for other apps' sound and an app has to do for its own. The lock
screen has the station's name, play and pause, and next and previous for
the station, as a pair of headphones' buttons do.

The sound comes straight from each broadcaster, the address a media player
would take, and never through the website: it costs the site nothing and
the rider about sixty megabytes of mobile data an hour. A stream that drops
is joined again, and after three tries the row says **No signal** and keeps
trying every half minute; a tap tries at once (`Core/Radio.swift`,
`Views/RadioRow.swift`).

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
again thirty seconds later. The question carries which way the rider is
going — `heading`, worked out from the last thirty metres of the ride —
and the website answers a way that sets off that way, so somebody who
rode on past "Going the wrong way" is taken on from where they are headed
and not told to turn around a second time (`Store.follow`,
`Store.reroute`).

**And where there is more than one, the bike chooses.** The website may
answer a new way with up to two others beside it — often it has none, since
a way that must set off the way the rider is going leaves the router few —
and all of them are offered, every time the rider leaves the way, and
without a word. The first is the way, solid, its turns shown and said; the
others are faint beside it, and the buttons of the card before a ride,
*9 min · 2.4 km*, sit under the turn. A press chooses one, as does a tap on
its faint line. So does riding it: two points in a row on one of the ways and
off the other two, and that one is the way, its turns said from there on,
and the buttons and faint lines go. Riding one of the others is not "off the
way" while it lasts. Still on the first after 800 m, or off all three, the
choice is over and the way is followed as any way is. Ways by train are not
offered here: a station is not something to turn towards mid-ride unasked
(`Store.pick`, `Views/RecordTab.swift`'s `WayChips`).

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
kept on the phone, as the website keeps its style in the browser. Some
things read the same whatever the colour: saved, waiting and not kept, and
the rail of a way by train, which is orange.

### Bike paths on the map

The bicycle button at the foot of the record map draws where the bike paths
are, over Apple's map: OpenStreetMap's cycle tracks, lanes and shared paths
as [CyclOSM](https://www.cyclosm.org) draws them — its `cyclosm-lite` layer,
which is the paths and nothing else. It is off on a new install and
remembered once switched on. The way the website suggests already prefers
those paths; this is so the rider can see them.

The pictures come from OpenStreetMap France's servers, not from the website,
so they read nothing from its database. They are asked only while the
button is on, only for what is on the screen, never from zoomed out further
than a district, two at a time, and once: 64 MB of them are kept on the
phone. A screen is about a dozen; riding with the map following, some two
hundred an hour the first time along a street and none the second.
`BikePaths` in `Views/RideMap.swift` says the rest. While they show, the map
says whose they are: *© OpenStreetMap · CyclOSM · OSM France*.

It is why the record map is an `MKMapView` and not SwiftUI's `Map`, which
draws nothing of anybody else's.

### All, on the account

Since 2026-11-22 a signed-in rider's rides add up on the website, and My
rides shows the sum as **All** on the card at the top, in place of the
phone's. It was a section of its own under the card, *On your account*,
for most of that day, and under the signed-in rows of the Account tab for
the few hours before; the owner's word was that it is part of All. Every
save carries the ride in a few numbers the phone has already worked out
(`Ride.summary` in `Core/Ride.swift`): the distance ridden, the active
time and the time Start to Finish, the time stopped, the top speed and the
fastest kilometre, and where the kept line would begin and end — the
first point 200 m in from each end, so no door is in it. They are the whole ride, not the line that is sent: a ride that went
out past the four cities adds every kilometre of it, and one that never
came near them is sent with no line at all, for its numbers alone —
*Saved*, with *It was outside the cities, so it is not a bike route, but
it is added up on your account* where a ride kept as a route says it is
one. The website keeps them with the account and adds them to its
totals; with nobody signed in it ignores them, and a rider with no
account gets nothing new and has nothing more kept.

All reads `GET /api/rides?totals=1` (`Core/AccountTotals.swift`): the
distance large, as the other spans have it, and *12 rides · 9 h 43 min
riding* under it; then, a row each, the time stopped, the average, the top
speed and the fastest kilometre where there are any, and the longest ride;
and *From every phone on your account, since 14 Nov 2026.* at the foot.
There are no bars, as All never had. Every figure carries its unit —
*9 h 43 min*, *43 min*, *2 min 17 s*, *13.1 km/h*, *8.6 km* — the hours,
minutes and seconds in the chosen language, since a 9:43 on a line of its
own, as it read at first, could be anything; a ride's own row keeps its
*34 min* and *1:12*, and so does the phone's own line on the card. It asks
when My rides appears signed in, whichever span is chosen, and when who
is signed in changes, and not again for the same account within a minute
— never in the background and never on a timer, one row read on the
website each time. The last answer is kept on the phone for the account it
was, so All opens on the account's numbers; with no signal they stay, with
*As of Sun 22 Nov 17:08 — the site could not be reached.* at the foot.
Before the first answer, and for an account with nothing added up yet,
All is the phone's own sum, as it is signed out — numbers either way, and
no spinner. Signing out or deleting the account forgets the numbers on the
phone.

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
- **A part shows where it was.** A tap on a part opens a still map under
  its row, framed to it: riding bold over the rest of the ride drawn
  faint, a walk or a train bold in its dots or dashes, a wait or a stop a
  ringed dot where the rider stood, with the streets round it. One part is
  open at a time; a tap on its row again puts it away, and a tap on its
  map opens it over the whole screen on the same part, where **Whole
  ride** frames the rest. The page's own map could not do it: by the time
  the list is on the screen, that map has scrolled away above it. The
  part's points are picked out by its times (`Timeline.points(of:in:)`),
  so nothing more is stored and nothing is asked of the website.
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
- **Nothing of it is in the four cities**: saved with nobody signed in, it
  is *Not kept · outside the cities* and never sent, as ever. Saved signed
  in, it is sent with an empty line for its numbers alone, which the
  account adds up (**All, on the account**, above), and is *Saved*; a
  session the website no longer honours answers `signed-out`, and it is
  Not kept after all.

- **The answer is lost on the way back**: from the phone that is the same as
  a save that never arrived, and the ride is sent again — and the website
  does it again, counted a second time signed out and kept as a second ride
  signed in. That is the one known gap, and it is accepted: for an hour on
  2026-11-20 every save carried `request`, the ride's own id, for the
  website to know a repeat by, and the owner took it out the same day
  rather than have the website remember an id for every ride it says it
  keeps nothing of.

A ride saved with nobody signed in is marked so on the phone
(`Ride.phoneOnly`) and is sent with no session even if somebody signs in
before it has gone, so what its save card said — it stays on this phone —
is what happens.

## What it asks the website for

All of it is in `Rattatee/Core/API.swift`, `Store.swift` and
`Account.swift`. These are promises the website keeps to an installed app
that cannot be updated in a day, and they are listed in the website
repository's `CLAUDE.md` under **What the app reads**.

| | |
|---|---|
| `POST /api/rides` | `{ action: "save", anon: true, name, seconds, line }`, answered `{ ride: { id, meters, seconds } }` signed in, where the ride is kept, and `{ counted: true }` with no `ride` signed out, where it is counted and not kept. `line` is `[lat, lng, t, acc]` a point: five decimals, whole seconds since the ride began, whole metres — and `[lat, lng, t, acc, alt]`, from 2026-11-18, where the fix had a height, whole metres above the sea. `anon` is what lets a save with no session through; with a session the ride is on the account. Since 2026-11-22 every save carries `summary`, the whole ride in numbers, which a signed-in account adds up and the website otherwise ignores: `meters`, `seconds` (the active time), `total`, `stopped`, and where there are any `top` (km/h to one decimal), `fastest` (seconds) and `start` and `end` (`[lat, lng]`, 200 m in from each end). A ride with nothing inside the four cities, saved signed in, goes with `line: []` and no `anon`, answered `{ counted: true }`, or `signed-out` with no session, which marks it Not kept |
| `GET /api/rides?totals=1` | what the signed-in account's rides add up to, for **All** on My rides: `{ ready, user, totals }`, `totals` null before any ride is added up, or `rides`, `meters`, `seconds`, `stopped`, `top` (km/h, or null), `fastest` (seconds, or null), `longest` (metres) and `since` (milliseconds since 1970). Asked when My rides appears signed in and when who is signed in changes, once a minute at most |
| `GET /api/rides/<id>` | one saved ride, to the account it is under: `ride` with `meters` and `line`, the stored `[lat, lng]` pairs with the ends off. Asked when a saved ride's page opens signed in, and drawn over the phone's line; `not-found` and `signed-out` draw nothing. The rest of the answer, `insight`, is worked out on the phone instead |
| `GET /api/places` | the whole roll, with no query, once a week: the copy Where to? answers the first letters from and a tap on the map is matched against, keeping `id`, `name`, `lat`, `lng` and `map` |
| `GET /api/places?q=&near=&limit=` | the search: the website's places and the city's venues, reading `id`, `name`, `address`, `category`, `lat`, `lng` and `map` |
| `GET /api/geocode?q=` | streets, addresses and districts: `results` with `label`, `where`, `lat`, `lng` |
| `GET /api/lookup`, `POST /api/lookup` | **Look for it on Google Maps**: `ready`, then `{ q }` answered by `ok`, `why` and `places` in the search's rows. The button goes away on `why: "no-key"` and says it is resting on any other refusal |
| `GET /api/v1/route?from=&to=&mode=bike` | asked first: everything `/api/route` answers below, with `version: 1`, and `trains` — each `seconds`, `meters`, `leave`, and `legs`, a ride (`kind: "bike"`, `meters`, `seconds`, `line`, `steps`) or the train (`kind: "train"`, `name`, `from`, `to`, `at`, `until`, `meters`, `line`). An answer without `version`, or none, and `/api/route` is asked instead |
| `GET /api/route?from=&to=&mode=bike` | the suggested way: `meters`, `seconds`, `line`, and `others`, up to two more ways in the same three fields — and `ridden: true` on the way people have ridden, which the website puts first and the card names on its button (`style`, a name on every way, was sent for a day from 2026-11-19 and taken back; it is still read, and a word this build does not know is a button with no name); and for each way `steps`, where it turns — `at`, `turn`, `name`, and `exit` on a roundabout. The words of `turn` are `left`, `right`, `keep-left`, `keep-right`, `straight`, `around`, `roundabout`, `arrive` and `tunnel`, where the way goes into one; one the app does not know is left out |
| `GET /api/lists` | the signed-in rider's lists: `lists` with `id`, `title` and `n` |
| `POST /api/lists` | `create` (`title`, answered `id`), `place` (`name`, `address`, `lat`, `lng`, answered `place.id`) and `add` (`id`, `place`), and the errors `signed-out`, `full`, `too-many` and `title` |
| `GET /api/account` | who the session is, and `appGoogle` / `appApple`, which draw the two sign-in buttons |
| `POST /api/account` | `create` and `login` with `username` and `password`, answered with `user` or the errors `taken`, `username`, `password`, `no-match` and `slow-down`; `ticket`, `logout`, `delete` |
| `GET /api/google?app=<challenge>` | the Google round trip, ending at `tallinntastebuds://signin` |
| `POST /api/apple` | Apple's token and its nonce, answered as a sign-in |

A line longer than 3,500 points, about forty kilometres, is thinned evenly
before it is sent, and points outside the four boxes the server counts rides in — Tallinn, Tartu,
Pärnu and Narva, fourteen kilometres round each — are left out (`Geo.line` in `Core/Ride.swift`).
The `summary` beside it is worked out over every point, so the account's
totals are the whole ride whatever the line leaves out.

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

- **The server's list in My rides.** `GET /api/rides?mine=1` answers a
  signed-in account's rides; the app lists only what is on the phone, so
  rides do not follow an account to a new phone yet.
- **Everybody's rides on the map.** `GET /api/rides?bbox=` answers them; the
  record map does not draw them yet.
- **The radio's stations.** They are compiled in, so a station that moves
  its address is silent until a new build. The website already keeps a
  station a language in its `data/radio.json`; a list there that the app
  asks for when it opens, with this file as what it falls back on, would
  mend one without a release — and would be a promise, a station's `id`,
  `name` and `url` at the least, written into the website's **What the app
  reads**.

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
            Ride.swift          a ride, a point, the sums, and the summary sent with it
            Insight.swift       a ride's kilometres and speeds, and what the website kept of it
            Store.swift         every ride on the phone, and sending them
            AccountTotals.swift what the account's rides add up to, from the website
            Search.swift        places, streets, Google, and the way there and its turns
            Guide.swift         the voice that says the turns
            Radio.swift         the radio on a ride, and going under that voice
            Venues.swift        the places kept on the phone, a name and a pin each
            Recents.swift       where the rider has gone before, newest first
            Lists.swift         the rider's lists, and adds waiting for signal
            Account.swift       signing in and out
            SocialSignIn.swift  Google and Apple, Kohuke's file unchanged
            Disk.swift          the ride files, and where the other copies live
            Strings.swift       the words, the language chosen, and how a distance is said
  Views/    RecordTab.swift     Where to?, Ready, Recording, Paused
            RideMap.swift       the map, its lines, its taps and holds, and the bike paths
            SearchSheet.swift   Where to?
            ListPicker.swift    Add to a list
            RadioRow.swift      the radio's row while riding, and the list of stations
            FinishCards.swift   Save, Too short, and what came of it
            RidesTab.swift      My rides
            StatsCard.swift     how far today, this week, this month, and in all, the account's signed in
            RideView.swift      one ride, opened
            AccountView.swift   the Account tab, the colours, deleting an account
            SignIn.swift        the username form and the Apple and Google buttons
            Theme.swift         the website's colours
  Seed/     strings.json        every string, in en, et, ru and az
            stations.json       the radio's stations
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
  - *Precise Location* — collected, for App Functionality, linked, not
    used for tracking. That is the ride of somebody signed in, which the
    website keeps under their account, its numbers added up there with
    the account's others (**All, on the account**) — derived from the
    same points, so no new kind of data. A ride saved with nobody signed in
    is sent, counted and let go, which is not collecting it; the answer
    stays *collected* because the app does both.
  - *User ID* — collected only when signed in, for App Functionality,
    linked, not used for tracking.
  - Nothing else: no analytics, no advertising, no third-party code. What
    is typed into the search, and where the phone is when a way is asked
    for, go to the website to be answered and are not kept with anything
    that says who asked.
- **Required-reason APIs**, also in `PrivacyInfo.xcprivacy`: UserDefaults
  for the app's own settings (`CA92.1`), and a file's modification date
  (`C617.1`), which `Core/Venues.swift` reads to tell when its copy of the
  places is a week old. Code that starts reading a file's date, the disk's
  free space, the time since boot or the keyboards needs its line there
  too, or App Store Connect refuses the build.
- **Privacy policy URL**: `https://tallinntastebuds.ee/privacy`, which says
  what is kept of a ride, and that one saved with no account is not kept.
- **Account deletion** is in the app, under Account, as review requires of
  an app that can make an account.
- **Sign-in is optional**, so review needs no demo account.

### The icon

`docs/icon.html` is the icon as a page: the owner's own blue single-speed
with its red mudguard, on the Estonian flag, the top of the black band cut
into the Old Town as it stands seen from the harbour. Photograph it at 1024 × 1024 into
`Rattatee/Assets.xcassets/AppIcon.appiconset/icon-1024.png` with any
headless browser, and save it as RGB with no alpha channel — App Store
Connect refuses an icon that has one, even a fully opaque one.

## Done when

- A ride recorded on a real iPhone with the screen locked for the whole
  ride saves — and, saved signed in, comes back from `GET
  /api/rides?bbox=`; saved signed out it is answered `counted` and comes
  back from nowhere.
- Killing the app mid-ride, or losing signal at Save, does not lose the
  ride.
- The project archives for TestFlight with the permission texts and the
  privacy details above.

None of the three can be checked from a cloud session. CI proves the app
compiles and draws its screens; the ride itself needs a phone and a bike.
