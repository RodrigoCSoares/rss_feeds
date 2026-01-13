# rss_feeds

Generate an RSS feed from Meetup.

Source:
`https://www.meetup.com/<group>/events/ical/`

Output:
`rss.xml` at the repo root.

## Development

```sh
gleam run   # Generate RSS to stdout
gleam test  # Run the tests
```

To write the file locally:

```sh
gleam run > rss.xml
```

## Automation

GitHub Actions runs the generator daily and commits `rss.xml` to `main`.
