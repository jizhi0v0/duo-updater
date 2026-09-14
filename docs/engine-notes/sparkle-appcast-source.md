# `SparkleAppcastSource.swift` — engine notes

Source: `DuoUpdaterCore/Sources/DuoUpdaterCore/Sources/SparkleAppcastSource.swift`

## §1 Namespaces: what Foundation's `XMLParser` actually does

Background for issue #641. Sparkle's vocabulary is the namespace
`http://www.andymatuschak.org/xml-namespaces/sparkle`; the `sparkle:` prefix
conventionally bound to it is the vendor's choice, not part of the format. The
parser used to recognise the prefix and nothing else, so a feed that bound the
same namespace to another prefix — or made it the document default — parsed with
the whole vocabulary missing. For `sparkle:maximumSystemVersion` that fails
OPEN: the vendor's "not for an OS this new" disappears and the item is offered
to the very Mac it was capped away from.

Everything below is a **one-time measurement, not a tracked metric**, taken
2026-09-15 on macOS 26 (Darwin 25.6.0) with a standalone `swiftc` probe against
`Foundation.XMLParser`. None of it is in Apple's documentation in this form,
and each line of it decided a line of the implementation.

### §1.1 `shouldProcessNamespaces = true`

* **Elements** arrive split: `elementName` is the LOCAL name, `namespaceURI`
  carries the URI, `qualifiedName` keeps the original `prefix:local` spelling.
* An element in NO namespace reports `namespaceURI` as the **empty string**, not
  nil. Code that tests `namespaceURI == nil` to mean "unnamespaced" is wrong on
  this platform.
* **Attribute keys stay QUALIFIED.** `sparkle:version` arrives as the literal
  key `"sparkle:version"`, and so does `s:version`. There is no attribute
  namespace URI anywhere in the delegate API.
* **`xmlns:*` declarations are REMOVED from the attribute dictionary.** So the
  one place a prefix→URI binding could have been read incidentally is gone
  precisely when it is needed.
* `xml:lang` is unaffected in both modes — the `xml` prefix is bound implicitly
  by the XML spec, never declared, and the key stays `"xml:lang"`.

### §1.2 `shouldReportNamespacePrefixes = true`

Required, separately, to get `didStartMappingPrefix(_:toURI:)` /
`didEndMappingPrefix(_:)` at all: with only `shouldProcessNamespaces` set,
**neither callback ever fires**. Measured directly — a document declaring
`xmlns:s` produced zero mapping callbacks under the first flag alone. Those
callbacks are therefore the only way to resolve an ATTRIBUTE's prefix, which is
why both flags are set in `parse`.

Firing order is nesting-exact: `MAPSTART` immediately before the declaring
element's start tag, `MAPEND` immediately after its end tag, innermost first.
A stack per prefix is therefore sufficient and correct for rebinding.

### §1.3 An undeclared prefix does not fail the parse

`<sparkle:version>` with no `xmlns:sparkle` anywhere: libxml2 recovers rather
than erroring. `parse()` returns true and the element arrives as local name
`version` with an **empty** namespace URI and qualified name
`sparkle:version`. Without a literal-prefix fallback, turning namespace
processing on would therefore have silently emptied the vocabulary of every
such feed — a new bug of the same shape as the one being fixed.

### §1.4 Why the literal-prefix fallback is unconditional

The fallback matches a `sparkle:` qualified name **whatever that prefix is or
is not bound to**, rather than only when it is bound to nothing. The reason is
the likelier accident: a vendor who declares the namespace and typos the URI.
Under a "bound to nothing" rule that feed would go from parsing fine to losing
everything. Unconditional keeps the change a strict superset of the old
behaviour, at the pre-existing price that a different vocabulary which picked
the same short prefix is read as Sparkle's — exactly as it was before.

### §1.5 What the fallback is NOT justified by

The issue proposed keeping the literal path "for feeds that declare no
namespace at all (some do)". Measured over this checkout the same day
(`git ls-files`, every `<rss …>…</rss>` block in `.swift`/`.xml`/`.json`/`.md`):
**47 appcast bodies; 40 use a `sparkle:` name; all 40 declare `xmlns:sparkle`.
Zero declare none. Zero bind the URI to a non-`sparkle` prefix.** So no body in
this repo needs the fallback, and "some do" is unverified as written — the live
feeds are read off installed bundles' `SUFeedURL` and are not stored here, so
the population the sentence is about was not measured at all. What justifies
the fallback is §1.3 and §1.4, not an observed feed.

### §1.6 Turning namespaces on widens the RSS switch too — the trap

The half of this change that is easy to miss: the RSS switch (`item`,
`enclosure`, `description`, `markdownDescription`, `pubDate`) matched
`elementName`, and `elementName` silently changed meaning from the QUALIFIED
name to the bare LOCAL name. Left alone it therefore began matching those names
in **every** namespace. Both halves were measured on the first draft, and both
are now regression tests:

* A `<dc:description>` placed ahead of the real one inside an `<item>` became a
  `description` language variant. Both untagged, so both count as `"en"` and the
  first wins — the release notes became the foreign element's text.
* An `<x:item>` nested inside `<item>` hit `case "item"`: it reset `current`,
  wiped the collected variants, appended an empty item and set `current = nil`.
  The real `<enclosure>` that followed applied to nil and the genuine release
  was never appended — parsed result: one item, no version at all.

The fix is **not** to gate on `namespaceURI`, which fails the other way, also
measured: a feed whose DEFAULT namespace is somebody else's (RSS 1.0's URI)
parses today and would have had every one of its elements stop matching. The
rule that is right in both directions is the one the pre-namespace parser
already had — **the RSS switch accepts a name only when its qualified name
carries no prefix**. A feed that makes SPARKLE the default namespace still works
because it spells those elements unprefixed too.

Elements and attributes also have to resolve in the same ORDER: the properly
bound prefix first, the literal `sparkle:` one as the fallback. Checking the
literal key first (the first draft, again) lets a feed that bound `sparkle` to a
foreign vocabulary and Sparkle's real URI to `s` have its elements read from one
vendor and its attributes from the other.

### §1.7 Unprefixed attributes are never Sparkle's

Per XML Namespaces §6.2 an unprefixed attribute is in no namespace even under a
default `xmlns`. A feed that makes Sparkle the document default therefore
**cannot** express `<enclosure version="…">` as a Sparkle attribute; it must
still bind a prefix for its attributes. The fixture in
`SparkleAppcastNamespaceTests` is written that way for this reason, and
`anUnprefixedEnclosureAttributeIsNotSparkles` pins that a bare `version` on
`<enclosure>` does not overwrite the `<sparkle:version>` child.
