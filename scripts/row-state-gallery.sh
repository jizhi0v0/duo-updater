#!/bin/bash
# Render every RowActionState to verify/row-states/*.png.
#
# The reference images are COMMITTED: after a change to how a row is drawn,
# re-run this and read the image diff. A state that starts drawing nothing —
# the failure this exists to catch, and one no assertion about the state itself
# can see — fails the run.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Per checkout, and the dead ones reclaimed — see scripts/derived_data_path.py
# for why a fixed path is a trap here. `GALLERY_DD` still overrides.
DD="${GALLERY_DD:-$(python3 "$REPO/scripts/derived_data_path.py" gallery "$REPO")}"

# Must be exported before xcodegen, exactly as install.sh/notarize.sh do it: the
# spec reads $DUO_TEAM_ID for DEVELOPMENT_TEAM, and regenerating without it writes
# an EMPTY team into the project — which does not break this (unsigned) gallery,
# it breaks the next `make install` with "requires a development team". A fork
# sets its own.
TEAM="${DUO_TEAM_ID:-RS59HDH7Y3}"
export DUO_TEAM_ID="$TEAM"

cd "$REPO"
xcodegen generate --spec App/project.yml --project App >/dev/null

xcodebuild -project App/DuoUpdater.xcodeproj \
           -scheme RowStateGallery -configuration Debug \
           -derivedDataPath "$DD" build >/dev/null

# Wipe first, so a renamed or deleted state does not leave its PNG behind. The
# renderer only ever writes; without this, `verify/row-states/` accumulates images
# for states that no longer exist and the committed sheet quietly stops matching
# the enum. Renumbering the App Store cases left 8 orphans exactly this way.
rm -rf "$REPO/verify/row-states"

# Pin what the picture depends on besides the code. `ImageRenderer` renders in the
# host's appearance and language, so a run in dark mode or a non-English locale
# rewrites all 60 files with a diff that says nothing about the change under review.
export AppleLanguages='(en)'
export AppleLocale='en_US'
"$DD/Build/Products/Debug/RowStateGallery" -AppleInterfaceStyle Light
