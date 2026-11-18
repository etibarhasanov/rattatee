# Working on Rattatee

Rattatee has no server of its own. It saves rides, searches places and asks
for routes through tallinntastebuds.ee, and that site's `CLAUDE.md`
(`etibarhasanov/tallinntastebuds`) is the authority on what its routes answer
— **What the app reads** there has a section for this app listing every route,
field and error word it depends on. A route this app starts reading is added
there the same week, and an error word it has no sentence for is decided
there first.

## Every request has a price

The site runs on Cloudflare's free plan. Its database bills every row a
request reads, and past five million rows in a UTC day every read on the
account fails until midnight — for the website, the map app and every copy of
this one at once. On 2026-11-18 the website alone did that before noon.

An app multiplies whatever it does by every phone it is on, so a request is
designed with its frequency in mind before it is written:

1. **Say how often it runs.** Per ride, per foreground, per network change,
   per keystroke, per minute while riding — and multiply by a thousand
   riders.
2. **Nothing retries without a wait that grows.** A waiting ride or list add
   that fails is put off by `Store.retryWait`, a minute doubling to six
   hours — A RIDE THAT FAILS WAITS LONGER EACH TIME in `Core/Store.swift`.
   The app coming to the front and the network coming back happen many times
   a day; before that wait, each sent every waiting ride again. Save, Try now
   and signing in are a person asking and go past it, never past `often`.
3. **A refusal sending again cannot change is final.** `short`, `fast` and
   `malformed` today. A new one is added to that list and to the site's
   section together, or an installed app sends that ride for ever — slowly
   now, but for ever.
4. **Typing is debounced and has a floor**: 300 ms and three letters, as
   Where to? is.
5. **Keep what does not change.** The places roll is kept a week in
   `venues.json`, and a failed fetch of it waits `Store.retryWait` like
   everything else.
6. **Rerouting is bounded by distance and, after a miss, by time** —
   `rerouteEvery` in `Core/Store.swift`. A new rule that asks more often
   says how often, in requests per ridden hour.

The site's side of the same rule is **Every read has a price, set before it
is written** in its `CLAUDE.md`; `/admin/stats` there shows the day's reads by
table, which is where a change here that made the site dearer shows up.
