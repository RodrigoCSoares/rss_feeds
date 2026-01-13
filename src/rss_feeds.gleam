import gleam/bit_array
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type FeedConfig {
  FeedConfig(
    id: String,
    title: String,
    link: String,
    description: String,
    ical_url: String,
    output: String,
  )
}

type FeedDraft {
  FeedDraft(
    id: String,
    title: String,
    link: String,
    description: String,
    ical_url: String,
    output: String,
  )
}

type Event {
  Event(
    summary: String,
    description: String,
    location: String,
    url: String,
    dtstart: String,
  )
}

type EventDraft {
  EventDraft(
    summary: String,
    description: String,
    location: String,
    url: String,
    dtstart: String,
  )
}

pub fn main() -> Nil {
  case read_file("feeds.toml") {
    Ok(body) ->
      case bit_array.to_string(body) {
        Ok(toml) ->
          case parse_feeds(toml) {
            Ok(feeds) -> run_feeds(feeds)
            Error(reason) ->
              io.println("Failed to parse feeds.toml: " <> reason)
          }
        Error(_) -> io.println("Failed to decode feeds.toml.")
      }
    Error(reason) -> io.println("Failed to read feeds.toml: " <> reason)
  }
}

fn run_feeds(feeds: List(FeedConfig)) -> Nil {
  list.each(feeds, fn(feed) {
    case generate_feed(feed) {
      Ok(_) -> Nil
      Error(reason) -> io.println(reason)
    }
  })
}

fn generate_feed(feed: FeedConfig) -> Result(Nil, String) {
  let FeedConfig(id, _, _, _, ical_url, output) = feed
  case http_get(ical_url) {
    Ok(body) ->
      case bit_array.to_string(body) {
        Ok(ics) -> {
          let rss = build_rss(ics, feed)
          let contents = bit_array.from_string(rss)
          case write_file(output, contents) {
            Ok(_) -> Ok(Nil)
            Error(reason) ->
              Error(
                "Failed to write " <> output <> " for " <> id <> ": " <> reason,
              )
          }
        }
        Error(_) ->
          Error("Failed to decode iCal response body for " <> id <> ".")
      }
    Error(reason) ->
      Error("Failed to fetch iCal feed for " <> id <> ": " <> reason)
  }
}

@external(erlang, "rss_feeds_http", "get")
fn http_get(url: String) -> Result(BitArray, String)

@external(erlang, "rss_feeds_fs", "read_file")
fn read_file(path: String) -> Result(BitArray, String)

@external(erlang, "rss_feeds_fs", "write_file")
fn write_file(path: String, contents: BitArray) -> Result(Nil, String)

pub fn parse_feeds(toml: String) -> Result(List(FeedConfig), String) {
  let normalized = string.replace(toml, "\r\n", "\n")
  let lines = string.split(normalized, "\n")
  parse_feed_lines(lines, [], FeedDraft("", "", "", "", "", ""), False)
  |> result_map(list.reverse)
}

fn parse_feed_lines(
  lines: List(String),
  feeds: List(FeedConfig),
  current: FeedDraft,
  in_feed: Bool,
) -> Result(List(FeedConfig), String) {
  case lines {
    [] ->
      case finalize_feed(current, in_feed) {
        Ok(Some(feed)) -> Ok([feed, ..feeds])
        Ok(None) -> Ok(feeds)
        Error(reason) -> Error(reason)
      }
    [line, ..rest] -> {
      let trimmed = string.trim(line)
      case trimmed == "" || string.starts_with(trimmed, "#") {
        True -> parse_feed_lines(rest, feeds, current, in_feed)
        False ->
          case trimmed {
            "[[feed]]" ->
              case finalize_feed(current, in_feed) {
                Ok(Some(feed)) ->
                  parse_feed_lines(
                    rest,
                    [feed, ..feeds],
                    FeedDraft("", "", "", "", "", ""),
                    True,
                  )
                Ok(None) ->
                  parse_feed_lines(
                    rest,
                    feeds,
                    FeedDraft("", "", "", "", "", ""),
                    True,
                  )
                Error(reason) -> Error(reason)
              }
            _ ->
              case in_feed {
                False -> Error("Found feed fields before [[feed]]: " <> trimmed)
                True ->
                  case parse_key_value(trimmed) {
                    Ok(#(key, value)) ->
                      case apply_feed_value(current, key, value) {
                        Ok(updated) ->
                          parse_feed_lines(rest, feeds, updated, in_feed)
                        Error(reason) -> Error(reason)
                      }
                    Error(reason) -> Error(reason)
                  }
              }
          }
      }
    }
  }
}

fn finalize_feed(
  draft: FeedDraft,
  in_feed: Bool,
) -> Result(Option(FeedConfig), String) {
  case in_feed || draft_has_content(draft) {
    False -> Ok(None)
    True ->
      case draft_to_config(draft) {
        Ok(feed) -> Ok(Some(feed))
        Error(reason) -> Error(reason)
      }
  }
}

fn draft_has_content(draft: FeedDraft) -> Bool {
  let FeedDraft(id, title, link, description, ical_url, output) = draft
  id != ""
  || title != ""
  || link != ""
  || description != ""
  || ical_url != ""
  || output != ""
}

fn draft_to_config(draft: FeedDraft) -> Result(FeedConfig, String) {
  let FeedDraft(id, title, link, description, ical_url, output) = draft
  case id == "" {
    True -> Error("Feed is missing id.")
    False ->
      case title == "" {
        True -> Error("Feed " <> id <> " is missing title.")
        False ->
          case link == "" {
            True -> Error("Feed " <> id <> " is missing link.")
            False ->
              case description == "" {
                True -> Error("Feed " <> id <> " is missing description.")
                False ->
                  case ical_url == "" {
                    True -> Error("Feed " <> id <> " is missing ical_url.")
                    False -> {
                      let output = case output == "" {
                        True -> "rss/" <> id <> ".xml"
                        False -> output
                      }
                      Ok(FeedConfig(
                        id,
                        title,
                        link,
                        description,
                        ical_url,
                        output,
                      ))
                    }
                  }
              }
          }
      }
  }
}

fn parse_key_value(line: String) -> Result(#(String, String), String) {
  case string.split(line, "=") {
    [left, right, ..rest] -> {
      let key = string.trim(left)
      let value = string.trim(join_with(right, rest, "="))
      Ok(#(key, parse_toml_value(value)))
    }
    _ -> Error("Invalid feed line: " <> line)
  }
}

fn parse_toml_value(value: String) -> String {
  let trimmed = string.trim(value)
  case string.starts_with(trimmed, "\"") && string.ends_with(trimmed, "\"") {
    True ->
      trimmed
      |> string.drop_start(1)
      |> string.drop_end(1)
      |> unescape_toml_string
    False -> trimmed
  }
}

fn unescape_toml_string(value: String) -> String {
  value
  |> string.replace("\\\"", "\"")
  |> string.replace("\\\\", "\\")
  |> string.replace("\\n", "\n")
}

fn apply_feed_value(
  draft: FeedDraft,
  key: String,
  value: String,
) -> Result(FeedDraft, String) {
  let FeedDraft(id, title, link, description, ical_url, output) = draft
  case key {
    "id" -> Ok(FeedDraft(value, title, link, description, ical_url, output))
    "title" -> Ok(FeedDraft(id, value, link, description, ical_url, output))
    "link" -> Ok(FeedDraft(id, title, value, description, ical_url, output))
    "description" -> Ok(FeedDraft(id, title, link, value, ical_url, output))
    "ical_url" -> Ok(FeedDraft(id, title, link, description, value, output))
    "output" -> Ok(FeedDraft(id, title, link, description, ical_url, value))
    _ -> Ok(draft)
  }
}

fn build_rss(ics: String, feed: FeedConfig) -> String {
  let FeedConfig(_, title, link, description, _, _) = feed
  let lines = unfold_lines(ics)
  let events = parse_events(lines)
  let items = list.map(events, fn(event) { render_item(event, link) })
  let items_text = join_lines(items, "\n")

  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
  <> "<rss version=\"2.0\">\n"
  <> "  <channel>\n"
  <> "    <title>"
  <> xml_escape(title)
  <> "</title>\n"
  <> "    <link>"
  <> xml_escape(link)
  <> "</link>\n"
  <> "    <description>"
  <> xml_escape(description)
  <> "</description>\n"
  <> items_text
  <> "\n"
  <> "  </channel>\n"
  <> "</rss>\n"
}

fn unfold_lines(ics: String) -> List(String) {
  let normalized = string.replace(ics, "\r\n", "\n")
  let lines = string.split(normalized, "\n")
  let folded =
    list.fold(lines, [], fn(acc, line) {
      case acc {
        [] -> [line]
        [prev, ..rest] ->
          case is_folded_line(line) {
            True -> {
              let continued = prev <> drop_first_char(line)
              [continued, ..rest]
            }
            False -> [line, ..acc]
          }
      }
    })
  list.reverse(folded)
}

fn is_folded_line(line: String) -> Bool {
  string.starts_with(line, " ") || string.starts_with(line, "\t")
}

fn drop_first_char(line: String) -> String {
  let length = string.length(line)
  case length <= 1 {
    True -> ""
    False -> string.slice(line, 1, length)
  }
}

fn parse_events(lines: List(String)) -> List(Event) {
  let #(events, _, _) =
    list.fold(lines, #([], False, []), fn(state, line) {
      let #(events, in_event, current) = state
      case line {
        "BEGIN:VEVENT" -> #(events, True, [])
        "END:VEVENT" -> {
          let event = build_event(list.reverse(current))
          let events = case event {
            Some(event) -> [event, ..events]
            None -> events
          }
          #(events, False, [])
        }
        _ ->
          case in_event {
            True -> #(events, True, [line, ..current])
            False -> #(events, False, current)
          }
      }
    })
  list.reverse(events)
}

fn build_event(lines: List(String)) -> Option(Event) {
  let EventDraft(summary, description, location, url, dtstart) =
    list.fold(lines, EventDraft("", "", "", "", ""), fn(draft, line) {
      apply_line(draft, line)
    })

  case summary == "" {
    True -> None
    False -> Some(Event(summary, description, location, url, dtstart))
  }
}

fn apply_line(draft: EventDraft, line: String) -> EventDraft {
  let EventDraft(summary, description, location, url, dtstart) = draft
  case parse_line(line) {
    Some(#(key, value)) ->
      case key {
        "SUMMARY" -> EventDraft(value, description, location, url, dtstart)
        "DESCRIPTION" -> EventDraft(summary, value, location, url, dtstart)
        "LOCATION" -> EventDraft(summary, description, value, url, dtstart)
        "URL" -> EventDraft(summary, description, location, value, dtstart)
        "DTSTART" -> EventDraft(summary, description, location, url, value)
        _ -> draft
      }
    None -> draft
  }
}

fn parse_line(line: String) -> Option(#(String, String)) {
  case string.split(line, ":") {
    [left, right, ..rest] -> {
      let value = unescape_ical(join_with(right, rest, ":"))
      let key = case string.split(left, ";") {
        [key, ..] -> key
        _ -> left
      }
      Some(#(key, value))
    }
    _ -> None
  }
}

fn unescape_ical(value: String) -> String {
  value
  |> string.replace("\\\\", "\\")
  |> string.replace("\\n", "\n")
  |> string.replace("\\N", "\n")
  |> string.replace("\\,", ",")
  |> string.replace("\\;", ";")
}

fn render_item(event: Event, feed_link: String) -> String {
  let Event(summary, description, location, url, dtstart) = event
  let link = case url == "" {
    True -> feed_link
    False -> url
  }
  let description =
    build_description(description, location, format_dtstart(dtstart))

  "    <item>\n"
  <> "      <title>"
  <> xml_escape(summary)
  <> "</title>\n"
  <> "      <link>"
  <> xml_escape(link)
  <> "</link>\n"
  <> "      <guid>"
  <> xml_escape(link)
  <> "</guid>\n"
  <> "      <description><![CDATA["
  <> escape_cdata(description)
  <> "]]></description>\n"
  <> "    </item>"
}

fn build_description(
  description: String,
  location: String,
  date: String,
) -> String {
  let with_date = case date {
    "" -> description
    _ -> description <> "\n\nDate: " <> date
  }

  case location {
    "" -> with_date
    _ -> with_date <> "\n\nLocation: " <> location
  }
}

fn format_dtstart(raw: String) -> String {
  case string.length(raw) < 8 {
    True -> raw
    False -> {
      let year = string.slice(raw, 0, 4)
      let month = string.slice(raw, 4, 6)
      let day = string.slice(raw, 6, 8)
      let date = year <> "-" <> month <> "-" <> day

      case string.split(raw, "T") {
        [_, time_raw] -> {
          let time_clean = case string.ends_with(time_raw, "Z") {
            True -> string.slice(time_raw, 0, string.length(time_raw) - 1)
            False -> time_raw
          }

          let hh = case string.length(time_clean) >= 2 {
            True -> string.slice(time_clean, 0, 2)
            False -> "00"
          }
          let mm = case string.length(time_clean) >= 4 {
            True -> string.slice(time_clean, 2, 4)
            False -> "00"
          }
          let ss = case string.length(time_clean) >= 6 {
            True -> string.slice(time_clean, 4, 6)
            False -> "00"
          }
          let tz = case string.ends_with(time_raw, "Z") {
            True -> "Z"
            False -> ""
          }
          date <> "T" <> hh <> ":" <> mm <> ":" <> ss <> tz
        }
        _ -> date
      }
    }
  }
}

fn xml_escape(value: String) -> String {
  value
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
  |> string.replace("\"", "&quot;")
  |> string.replace("'", "&apos;")
}

fn escape_cdata(value: String) -> String {
  string.replace(value, "]]>", "]]]]><![CDATA[>")
}

fn join_with(first: String, rest: List(String), sep: String) -> String {
  list.fold(rest, first, fn(acc, part) { acc <> sep <> part })
}

fn join_lines(lines: List(String), sep: String) -> String {
  case lines {
    [] -> ""
    [first, ..rest] -> join_with(first, rest, sep)
  }
}

fn result_map(result: Result(a, b), f: fn(a) -> c) -> Result(c, b) {
  case result {
    Ok(value) -> Ok(f(value))
    Error(reason) -> Error(reason)
  }
}
