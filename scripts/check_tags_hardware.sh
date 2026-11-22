#!/bin/sh
f="$1"
printf "  Tag  <label> Transmit Power: "
grep -o '<label class="control-label">Transmit Power</label>' "$f" | wc -l
printf "  Tag  <label> No of BSS:      "
grep -o '<label class="control-label">No of BSS</label>' "$f" | wc -l
printf "  Raw  'Transmit Power':       "
grep -o 'Transmit Power' "$f" | wc -l
printf "  Raw  'No of BSS':            "
grep -o 'No of BSS' "$f" | wc -l
