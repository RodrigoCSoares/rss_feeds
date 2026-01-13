# rss_feeds

Generate RSS feeds from one or more Meetup iCal feeds.

Sources are configured in `feeds.toml` as a list of feeds.

Output:
`rss/{id}.xml` for each feed.

Example `feeds.toml`:

```toml
[[feed]]
id = "cruquiusweg-fun-group"
title = "Cruquiusweg Fun Group"
link = "https://www.meetup.com/cruquiusweg-fun-group/"
description = "Meetup events feed"
ical_url = "https://www.meetup.com/cruquiusweg-fun-group/events/ical/"
```

## Feeds

- Cruquiusweg Fun Group — feed: `rss/cruquiusweg-fun-group.xml` — source: https://www.meetup.com/cruquiusweg-fun-group/events/ical/

Keep this list in sync with `feeds.toml` when adding new feeds.

## Development

```sh
gleam run   # Generate RSS files into rss/
gleam test  # Run the tests
```

## Automation

GitHub Actions runs the generator daily and commits files in `rss/` to `main`.
