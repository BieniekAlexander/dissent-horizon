#!/usr/bin/env python3
"""Fetch the stock-photo PLACEHOLDER icons for every unit and structure.

The authored source is `placeholder_subjects.json`: piece id -> [common name, scientific
name] and, optionally, a pinned Wikimedia Commons file title as a third element. Units are
animals and structures are trees, one distinct species each. This script turns that into
`assets/icons/pieces/<piece_id>.png` plus `CREDITS.md` beside them, so the downloaded images
are a generated artifact of the subject list rather than something edited by hand.

Images come from Wikimedia Commons. The subject being RIGHT comes first, so sources are tried
in order of how reliably they show it: a Commons Quality Image filed under the species, then
the species' own Wikidata image, then a plain search. Within whichever source answers, the
most permissive licence wins: public domain or CC0 first, then CC BY, then CC BY-SA. Every
image's author, licence and source page are written to CREDITS.md whatever the licence, so
the placeholders never carry an obligation nobody recorded. A subject the sources still get
wrong is fixed by pinning a file title as its third element.

Usage:
    python3 tools/piece_icons/fetch_placeholder_icons.py            # fetch every missing icon
    python3 tools/piece_icons/fetch_placeholder_icons.py --force    # refetch all
    python3 tools/piece_icons/fetch_placeholder_icons.py --only an_barracks cl_tech1
    python3 tools/piece_icons/fetch_placeholder_icons.py --candidates cl_tech1 --sheet /tmp/c.png

`--candidates` fetches nothing into the project: it draws a numbered contact sheet of the
usable images for each named piece, with each file title printed beside its number, so a wrong
pick can be replaced by pinning one of them in the subject list.
"""

from __future__ import annotations

import argparse
import html
import io
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw

ROOT: Path = Path(__file__).resolve().parents[2]
SUBJECTS_PATH: Path = Path(__file__).with_name("placeholder_subjects.json")
OUTPUT_DIR: Path = ROOT / "assets" / "icons" / "pieces"
CREDITS_JSON: Path = OUTPUT_DIR / "credits.json"
CREDITS_MD: Path = OUTPUT_DIR / "CREDITS.md"

API: str = "https://commons.wikimedia.org/w/api.php"
WIKIDATA_API: str = "https://www.wikidata.org/w/api.php"
# Wikimedia's API policy requires a descriptive agent; requests without one are throttled.
USER_AGENT: str = "DissentHorizonIconFetcher/1.0 (bieniekalexander@gmail.com)"

# Square edge of a stored icon. The HUD scales it down per button, so this only has to be
# comfortably larger than the biggest card it is drawn on.
ICON_EDGE_PIXELS: int = 128
# Thumbnail width requested from Commons before cropping — enough to downsample cleanly.
FETCH_WIDTH_PIXELS: int = 400
MIN_SOURCE_WIDTH_PIXELS: int = 500
# A wider or taller frame than this loses the subject to the square crop.
MAX_ASPECT_RATIO: float = 2.0
SEARCH_LIMIT: int = 40
# Commons asks clients to keep request rates modest.
REQUEST_PAUSE_SECONDS: float = 0.5

# Most permissive first; anything not matched is unusable.
LICENCE_TIERS: list[tuple[str, re.Pattern[str]]] = [
    (
        "public-domain",
        re.compile(r"public domain|^pd\b|cc0|no restrictions", re.IGNORECASE),
    ),
    ("cc-by", re.compile(r"^cc[ -]by(?![ -]sa)", re.IGNORECASE)),
    ("cc-by-sa", re.compile(r"^cc[ -]by[ -]sa", re.IGNORECASE)),
]
# File titles that are almost never a photograph of the living subject.
REJECT_TITLE: re.Pattern[str] = re.compile(
    r"map|range|distribution|skeleton|skull|illustrat|drawing|plate|stamp|herbarium|"
    r"specimen|sketch|diagram|logo|coin|museum|taxiderm|botanical|engraving|painting|"
    r"heritage library|\bbook\b|\bpage\b|\bp\.\s?\d|kunstformen|haeckel|thom[eé]|"
    r"k[oö]hler|lithograph|woodcut|\bplanche\b|tafel|wappen|coat of arms|"
    r"\.svg|\.gif|\.tif",
    re.IGNORECASE,
)
# A tree's icon is the TREE: a close-up of one organ says nothing at the size of a button.
REJECT_TREE_PART: re.Pattern[str] = re.compile(
    r"\bseeds?\b|\bwood\b|bark|leaf|leaves|flower|blossom|fruit|\bcones?\b|needles|"
    r"catkin|twig|\bnuts?\b|acorn|bud\b|buds\b|pollen|gall|trunk|stump|section",
    re.IGNORECASE,
)


def api_get(params: dict[str, str], endpoint: str = API) -> dict:
    query: str = urllib.parse.urlencode({**params, "format": "json"})
    request = urllib.request.Request(
        f"{endpoint}?{query}", headers={"User-Agent": USER_AGENT}
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        time.sleep(REQUEST_PAUSE_SECONDS)
        return json.load(response)


def fetch_bytes(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        time.sleep(REQUEST_PAUSE_SECONDS)
        return response.read()


def licence_tier(licence_name: str) -> int:
    """Index into LICENCE_TIERS, or -1 when the licence is not one we accept."""
    return next(
        (
            index
            for index, (_, pattern) in enumerate(LICENCE_TIERS)
            if pattern.search(licence_name)
        ),
        -1,
    )


def strip_html(text: str) -> str:
    return html.unescape(re.sub(r"<[^>]+>", "", text)).strip()


def describe(page: dict) -> dict | None:
    """A candidate's facts, or None when it cannot be used at all."""
    info: list = page.get("imageinfo", [])
    if not info:
        return None
    image: dict = info[0]
    meta: dict = image.get("extmetadata", {})
    licence: str = meta.get("LicenseShortName", {}).get("value", "")
    width: int = image.get("width", 0)
    height: int = image.get("height", 0)
    if (
        image.get("mime") not in ("image/jpeg", "image/png")
        or width < MIN_SOURCE_WIDTH_PIXELS
        or height == 0
        or max(width / height, height / width) > MAX_ASPECT_RATIO
        or licence_tier(licence) < 0
    ):
        return None
    return {
        "title": page["title"],
        "tier": licence_tier(licence),
        "licence": licence,
        "licence_url": meta.get("LicenseUrl", {}).get("value", ""),
        "author": strip_html(meta.get("Artist", {}).get("value", "unknown"))
        or "unknown",
        "page_url": image.get("descriptionurl", ""),
        "thumb_url": image.get("thumburl", image.get("url", "")),
    }


def image_info_params() -> dict[str, str]:
    return {
        "action": "query",
        "prop": "imageinfo",
        "iiprop": "url|extmetadata|size|mime",
        "iiurlwidth": str(FETCH_WIDTH_PIXELS),
    }


def pinned_candidate(file_title: str) -> dict | None:
    data: dict = api_get({**image_info_params(), "titles": file_title})
    pages: list = list(data.get("query", {}).get("pages", {}).values())
    return describe(pages[0]) if pages else None


def best_of(pages: list, is_tree: bool) -> dict | None:
    """The best-licensed usable photo among `pages`, keeping their order within a tier."""
    usable: list[dict] = [
        described
        for described in (
            describe(page)
            for page in pages
            if not REJECT_TITLE.search(page["title"])
            and not (is_tree and REJECT_TREE_PART.search(page["title"]))
        )
        if described is not None
    ]
    return min(usable, key=lambda c: c["tier"]) if usable else None


def search_pages(search: str) -> list:
    data: dict = api_get(
        {
            **image_info_params(),
            "generator": "search",
            "gsrsearch": f"{search} filetype:bitmap",
            "gsrnamespace": "6",
            "gsrlimit": str(SEARCH_LIMIT),
        }
    )
    return sorted(
        data.get("query", {}).get("pages", {}).values(), key=lambda p: p["index"]
    )


def wikidata_pages(scientific_name: str) -> list:
    """The species' Wikidata image (P18), as Commons pages — a curated representative photo."""
    found: dict = api_get(
        {
            "action": "wbsearchentities",
            "search": scientific_name,
            "language": "en",
            "limit": "1",
        },
        WIKIDATA_API,
    )
    if not found.get("search"):
        return []
    entity_id: str = found["search"][0]["id"]
    claims: dict = api_get(
        {"action": "wbgetclaims", "entity": entity_id, "property": "P18"}, WIKIDATA_API
    ).get("claims", {})
    titles: list[str] = [
        "File:" + claim["mainsnak"]["datavalue"]["value"]
        for claim in claims.get("P18", [])
        if "datavalue" in claim["mainsnak"]
    ]
    if not titles:
        return []
    data: dict = api_get({**image_info_params(), "titles": "|".join(titles)})
    return list(data.get("query", {}).get("pages", {}).values())


def search_candidate(scientific_name: str, is_tree: bool) -> dict | None:
    """The first source, most reliable first, that offers a usable photo of the subject."""
    sources = [
        lambda: search_pages(
            f'incategory:"{scientific_name}" incategory:"Quality_images"'
        ),
        lambda: wikidata_pages(scientific_name),
        lambda: search_pages(f'"{scientific_name}"' + (" tree" if is_tree else "")),
    ]
    for source in sources:
        found: dict | None = best_of(source(), is_tree)
        if found is not None:
            return found
    return None


# How many options a contact sheet offers per piece.
CANDIDATES_PER_PIECE: int = 10
SHEET_CELL_PIXELS: int = 120


def all_candidates(common_name: str, scientific_name: str, is_tree: bool) -> list[dict]:
    """Every usable image any source offers, deduplicated, most permissive licence first."""
    suffix: str = " tree" if is_tree else ""
    sources: list = [
        search_pages(f'incategory:"{scientific_name}" incategory:"Quality_images"'),
        wikidata_pages(scientific_name),
        search_pages(f'"{scientific_name}"{suffix}'),
        search_pages(f'"{common_name}"{suffix}'),
    ]
    seen: set[str] = set()
    found: list[dict] = []
    for pages in sources:
        for page in pages:
            if page["title"] in seen or REJECT_TITLE.search(page["title"]):
                continue
            if is_tree and REJECT_TREE_PART.search(page["title"]):
                continue
            seen.add(page["title"])
            described: dict | None = describe(page)
            if described is not None:
                found.append(described)
    return sorted(found, key=lambda c: c["tier"])[:CANDIDATES_PER_PIECE]


def candidate_sheet(
    piece_ids: list[str], subjects: dict[str, list], trees: set[str], path: str
) -> None:
    rows: list[tuple[str, list[dict]]] = [
        (
            piece_id,
            all_candidates(
                subjects[piece_id][0], subjects[piece_id][1], piece_id in trees
            ),
        )
        for piece_id in piece_ids
    ]
    cell: int = SHEET_CELL_PIXELS
    sheet = Image.new(
        "RGB", (cell * CANDIDATES_PER_PIECE, (cell + 14) * len(rows)), "white"
    )
    draw = ImageDraw.Draw(sheet)
    for row, (piece_id, candidates) in enumerate(rows):
        print(f"\n{piece_id} ({subjects[piece_id][0]}):")
        for column, candidate in enumerate(candidates):
            print(f"  {column}: {candidate['licence']:<14} {candidate['title']}")
            thumb: Image.Image = square_icon(
                fetch_bytes(candidate["thumb_url"])
            ).resize((cell - 4, cell - 4))
            sheet.paste(thumb, (column * cell + 2, row * (cell + 14)))
            draw.text(
                (column * cell + 2, row * (cell + 14) + cell - 2),
                f"{piece_id[:12]} {column}",
                fill="black",
            )
    sheet.save(path)


def square_icon(raw: bytes) -> Image.Image:
    image: Image.Image = Image.open(io.BytesIO(raw)).convert("RGB")
    edge: int = min(image.size)
    left: int = (image.width - edge) // 2
    top: int = (image.height - edge) // 2
    cropped: Image.Image = image.crop((left, top, left + edge, top + edge))
    return cropped.resize((ICON_EDGE_PIXELS, ICON_EDGE_PIXELS), Image.LANCZOS)


def write_credits(credits: dict[str, dict], subjects: dict[str, dict]) -> None:
    CREDITS_JSON.write_text(json.dumps(credits, indent="\t", sort_keys=True) + "\n")
    lines: list[str] = [
        "# Piece icon credits",
        "",
        "PLACEHOLDER art: stock photographs standing in for real piece icons — an animal per",
        "unit, a tree per structure. Generated by `tools/piece_icons/fetch_placeholder_icons.py`",
        "from `tools/piece_icons/placeholder_subjects.json`; do not edit by hand.",
        "",
        "| Piece | Subject | Author | Licence | Source |",
        "|---|---|---|---|---|",
    ]
    for piece_id in sorted(credits):
        credit: dict = credits[piece_id]
        common, scientific = subjects[piece_id][:2]
        author: str = credit["author"].replace("|", "/").replace("\n", " ")
        licence: str = (
            f"[{credit['licence']}]({credit['licence_url']})"
            if credit["licence_url"]
            else credit["licence"]
        )
        lines.append(
            f"| `{piece_id}` | {common} (*{scientific}*) | {author} | {licence} "
            f"| [{credit['title']}]({credit['page_url']}) |"
        )
    CREDITS_MD.write_text("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--force", action="store_true", help="refetch icons that already exist"
    )
    parser.add_argument(
        "--only", nargs="*", default=None, help="piece ids to (re)fetch"
    )
    parser.add_argument(
        "--candidates", nargs="*", default=None, help="piece ids to offer options for"
    )
    parser.add_argument(
        "--sheet", default="candidates.png", help="where --candidates draws its sheet"
    )
    args = parser.parse_args()

    groups: dict = json.loads(SUBJECTS_PATH.read_text())
    subjects: dict[str, list] = {**groups["units"], **groups["structures"]}
    trees: set[str] = set(groups["structures"])
    if args.candidates:
        candidate_sheet(args.candidates, subjects, trees, args.sheet)
        return 0
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    credits: dict[str, dict] = (
        json.loads(CREDITS_JSON.read_text()) if CREDITS_JSON.exists() else {}
    )
    # A piece removed from the subject list takes its credit with it.
    credits = {
        piece_id: credit for piece_id, credit in credits.items() if piece_id in subjects
    }

    wanted: list[str] = args.only if args.only else sorted(subjects)
    failures: list[str] = []
    for piece_id in wanted:
        target: Path = OUTPUT_DIR / f"{piece_id}.png"
        if target.exists() and piece_id in credits and not args.force and not args.only:
            continue
        subject: list = subjects[piece_id]
        try:
            candidate = (
                pinned_candidate(subject[2])
                if len(subject) > 2
                else search_candidate(subject[1], piece_id in trees)
            )
            if candidate is None:
                failures.append(piece_id)
                print(f"NO IMAGE  {piece_id}: {subject[1]}")
                continue
            square_icon(fetch_bytes(candidate["thumb_url"])).save(target, optimize=True)
            credits[piece_id] = {
                key: candidate[key]
                for key in ("title", "licence", "licence_url", "author", "page_url")
            }
            print(
                f"ok        {piece_id}: {candidate['licence']:<14} {candidate['title']}"
            )
        except Exception as error:  # noqa: BLE001 — one bad subject must not lose the batch
            failures.append(piece_id)
            print(f"FAILED    {piece_id}: {error}")
        write_credits(credits, subjects)

    write_credits(credits, subjects)
    print(f"\n{len(credits)} credited, {len(failures)} failed: {' '.join(failures)}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
