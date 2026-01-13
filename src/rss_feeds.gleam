import gleam/io
import gleam/bit_array
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

const ical_url = "https://www.meetup.com/cruquiusweg-fun-group/events/ical/"
const feed_title = "Cruquiusweg Fun Group"
const feed_link = "https://www.meetup.com/cruquiusweg-fun-group/"
const feed_description = "Meetup events feed"

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
  case http_get(ical_url) {
    Ok(body) ->
      case bit_array.to_string(body) {
        Ok(ics) -> io.println(build_rss(ics))
        Error(_) -> io.println("Failed to decode iCal response body.")
      }
    Error(reason) -> io.println("Failed to fetch iCal feed: " <> reason)
  }
}

@external(erlang, "rss_feeds_http", "get")
fn http_get(url: String) -> Result(BitArray, String)

fn build_rss(ics: String) -> String {
  let lines = unfold_lines(ics)
  let events = parse_events(lines)
  let items = list.map(events, fn(event) { render_item(event) })
  let items_text = join_lines(items, "\n")

  "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" <>
  "<rss version=\"2.0\">\n" <>
  "  <channel>\n" <>
  "    <title>" <> xml_escape(feed_title) <> "</title>\n" <>
  "    <link>" <> xml_escape(feed_link) <> "</link>\n" <>
  "    <description>" <> xml_escape(feed_description) <> "</description>\n" <>
  items_text <> "\n" <>
  "  </channel>\n" <>
  "</rss>\n"
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
          let events =
            case event {
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
      let key =
        case string.split(left, ";") {
          [key, .._] -> key
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

fn render_item(event: Event) -> String {
  let Event(summary, description, location, url, dtstart) = event
  let link =
    case url == "" {
      True -> feed_link
      False -> url
    }
  let description = build_description(description, location, format_dtstart(dtstart))

  "    <item>\n" <>
  "      <title>" <> xml_escape(summary) <> "</title>\n" <>
  "      <link>" <> xml_escape(link) <> "</link>\n" <>
  "      <guid>" <> xml_escape(link) <> "</guid>\n" <>
  "      <description><![CDATA[" <> escape_cdata(description) <> "]]></description>\n" <>
  "    </item>"
}

fn build_description(description: String, location: String, date: String) -> String {
  let with_date =
    case date {
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
          let time_clean =
            case string.ends_with(time_raw, "Z") {
              True -> string.slice(time_raw, 0, string.length(time_raw) - 1)
              False -> time_raw
            }

          let hh =
            case string.length(time_clean) >= 2 {
              True -> string.slice(time_clean, 0, 2)
              False -> "00"
            }
          let mm =
            case string.length(time_clean) >= 4 {
              True -> string.slice(time_clean, 2, 4)
              False -> "00"
            }
          let ss =
            case string.length(time_clean) >= 6 {
              True -> string.slice(time_clean, 4, 6)
              False -> "00"
            }
          let tz =
            case string.ends_with(time_raw, "Z") {
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
