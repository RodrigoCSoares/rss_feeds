import gleeunit
import rss_feeds

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn parse_feeds_default_output_test() {
  let toml =
    "[[feed]]\n"
    <> "id = \"one\"\n"
    <> "title = \"One\"\n"
    <> "link = \"https://example.com\"\n"
    <> "description = \"Example feed\"\n"
    <> "ical_url = \"https://example.com/ical\"\n"

  let result = rss_feeds.parse_feeds(toml)

  assert result
    == Ok([
      rss_feeds.FeedConfig(
        "one",
        "One",
        "https://example.com",
        "Example feed",
        "https://example.com/ical",
        "rss/one.xml",
      ),
    ])
}

pub fn parse_feeds_missing_id_test() {
  let toml =
    "[[feed]]\n"
    <> "title = \"One\"\n"
    <> "link = \"https://example.com\"\n"
    <> "description = \"Example feed\"\n"
    <> "ical_url = \"https://example.com/ical\"\n"

  let result = rss_feeds.parse_feeds(toml)

  assert case result {
    Error(_) -> True
    _ -> False
  }
}
